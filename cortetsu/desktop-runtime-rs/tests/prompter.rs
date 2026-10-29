//! End to end against a real gnome-keyring on a private bus, with a fake
//! shell answering over the helper's socket. gnome-keyring is the gcr client
//! here, so a wrong `sx-aes-1` implementation shows up as a keyring that
//! never unlocks. Creating a keyring, a wrong then right unlock password, a
//! cancel and the no-shell fallback are covered.
use serde_json::{Value, json};
use std::{
    fs,
    io::{BufRead, BufReader, Write},
    os::unix::{fs::PermissionsExt, net::UnixStream},
    path::{Path, PathBuf},
    process::{Child, Command, Output, Stdio},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

fn script(path: &Path, body: &str) {
    fs::write(path, format!("#!/bin/sh\n{body}\n")).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}

fn wait_for(what: &str, limit: Duration, mut ready: impl FnMut() -> bool) {
    let start = Instant::now();
    while !ready() {
        assert!(start.elapsed() < limit, "timed out waiting for {what}");
        thread::sleep(Duration::from_millis(20));
    }
}

struct Session {
    dir: tempfile::TempDir,
    address: String,
    children: Vec<Child>,
}

impl Drop for Session {
    fn drop(&mut self) {
        for child in self.children.iter_mut().rev() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

impl Session {
    /// A private session bus with nothing activatable, so no system service
    /// can stand in for the helper under test.
    fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        for sub in ["home", "run", "services"] {
            fs::create_dir_all(dir.path().join(sub)).unwrap();
        }
        fs::set_permissions(dir.path().join("run"), fs::Permissions::from_mode(0o700)).unwrap();
        let socket = dir.path().join("bus");
        let config = dir.path().join("bus.conf");
        fs::write(
            &config,
            format!(
                r#"<busconfig><type>session</type><listen>unix:path={}</listen>
<auth>EXTERNAL</auth><servicedir>{}</servicedir>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow receive_sender="*"/><allow own="*"/></policy></busconfig>"#,
                socket.display(),
                dir.path().join("services").display()
            ),
        )
        .unwrap();
        let bus = Command::new("dbus-daemon")
            .arg(format!("--config-file={}", config.display()))
            .arg("--nofork")
            .stdout(Stdio::null())
            .spawn()
            .unwrap();
        wait_for("the bus", Duration::from_secs(5), || socket.exists());
        let address = format!("unix:path={}", socket.display());
        Self {
            dir,
            address,
            children: vec![bus],
        }
    }

    fn path(&self, sub: &str) -> PathBuf {
        self.dir.path().join(sub)
    }

    fn command(&self, program: impl AsRef<std::ffi::OsStr>) -> Command {
        let mut c = Command::new(program);
        c.env_clear()
            .env("PATH", std::env::var_os("PATH").unwrap())
            .env("DBUS_SESSION_BUS_ADDRESS", &self.address)
            .env("HOME", self.path("home"))
            .env("XDG_RUNTIME_DIR", self.path("run"))
            .env("XDG_DATA_HOME", self.path("home/.local/share"))
            .env("XDG_CONFIG_HOME", self.path("home/.config"));
        c
    }

    fn has_owner(&self, name: &str) -> bool {
        Command::new("dbus-send")
            .arg(format!("--bus={}", self.address))
            .args([
                "--print-reply",
                "--dest=org.freedesktop.DBus",
                "/org/freedesktop/DBus",
            ])
            .args([
                "org.freedesktop.DBus.NameHasOwner",
                &format!("string:{name}"),
            ])
            .output()
            .is_ok_and(|o| String::from_utf8_lossy(&o.stdout).contains("boolean true"))
    }

    fn start(&mut self, mut command: Command, name: &str) {
        self.children
            .push(command.stdout(Stdio::null()).spawn().unwrap());
        wait_for(name, Duration::from_secs(10), || self.has_owner(name));
    }

    /// The prompter with a fake `qs` that records each request.
    fn prompter(&mut self) {
        let qs = self.path("qs");
        script(
            &qs,
            &format!(
                "[ \"$6\" = ping ] && echo ok\n[ \"$6\" = request ] && echo \"$7 $8\" >> {}/requests\nexit 0",
                self.dir.path().display()
            ),
        );
        let mut c = self.command(env!("CARGO_BIN_EXE_cortetsu-desktop-runtime"));
        c.arg("cortetsu-prompter")
            .env("CORTETSU_QS_BIN", &qs)
            .env("CORTETSU_SHELL_PATH", self.dir.path())
            .env("CORTETSU_PROMPTER_IDLE_MS", "60000");
        self.start(c, "org.gnome.keyring.SystemPrompter");
    }

    fn keyring(&mut self) {
        let mut c = self.command("gnome-keyring-daemon");
        c.args(["--foreground", "--components=secrets"])
            .arg(format!(
                "--control-directory={}",
                self.path("run/keyring").display()
            ))
            .env("G_MESSAGES_DEBUG", "Gcr")
            .stderr(fs::File::create(self.path("keyring.log")).unwrap());
        self.start(c, "org.freedesktop.secrets");
    }

    fn secret_tool(&self, args: &[&str], input: &str) -> Output {
        let mut child = self
            .command("secret-tool")
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(input.as_bytes())
            .unwrap();
        child.wait_with_output().unwrap()
    }
}

/// Plays the shell: for each dialog the helper opens, answers its prompts in
/// order with `answers` and reports every prompt it saw.
fn fake_shell(dir: PathBuf, answers: Vec<Vec<Option<&'static str>>>) -> mpsc::Receiver<Vec<Value>> {
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        let requests = dir.join("requests");
        for (n, dialog) in answers.into_iter().enumerate() {
            wait_for("a dialog request", Duration::from_secs(20), || {
                fs::read_to_string(&requests).is_ok_and(|t| t.lines().count() > n)
            });
            let line = fs::read_to_string(&requests)
                .unwrap()
                .lines()
                .nth(n)
                .unwrap()
                .to_owned();
            let (socket, token) = line.split_once(' ').unwrap();
            let mode = fs::metadata(socket).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode, 0o600, "socket must be private");
            let mut stream = UnixStream::connect(socket).unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut seen = Vec::new();
            for answer in dialog {
                let mut line = String::new();
                reader.read_line(&mut line).unwrap();
                let prompt: Value = serde_json::from_str(&line).unwrap();
                assert_eq!(prompt["token"], token);
                seen.push(prompt);
                let reply = match answer {
                    Some(pw) => {
                        json!({"token": token, "reply": "yes", "password": pw, "choice": false})
                    }
                    None => json!({"token": token, "reply": "no"}),
                };
                stream.write_all(format!("{reply}\n").as_bytes()).unwrap();
            }
            // The helper closes the dialog when the client stops prompting.
            let mut rest = String::new();
            let _ = reader.read_line(&mut rest);
            assert!(
                rest.is_empty(),
                "no prompt expected after the last answer: {rest}"
            );
            tx.send(seen).unwrap();
        }
    });
    rx
}

#[test]
fn creates_and_unlocks_a_real_keyring() {
    let mut s = Session::new();
    s.prompter();
    s.keyring();
    let shell = fake_shell(
        s.dir.path().to_owned(),
        vec![
            vec![Some("pw-one")],
            vec![Some("wrong"), Some("pw-one")],
            vec![None],
        ],
    );

    let stored = s.secret_tool(
        &["store", "--label=Prueba", "service", "cortetsu-test"],
        "s3cret",
    );
    assert!(
        stored.status.success(),
        "store: {}\n{}",
        String::from_utf8_lossy(&stored.stderr),
        fs::read_to_string(s.path("keyring.log")).unwrap_or_default()
    );
    let created = shell.recv_timeout(Duration::from_secs(20)).unwrap();
    assert_eq!(created[0]["kind"], "password");
    assert_eq!(
        created[0]["passwordNew"], true,
        "a new keyring asks for a new password"
    );

    assert!(s.secret_tool(&["lock"], "").status.success());
    let found = s.secret_tool(&["lookup", "service", "cortetsu-test"], "");
    assert_eq!(String::from_utf8_lossy(&found.stdout), "s3cret");
    let unlock = shell.recv_timeout(Duration::from_secs(20)).unwrap();
    assert_eq!(unlock.len(), 2);
    assert_eq!(unlock[0]["passwordNew"], false);
    assert_eq!(unlock[0]["warning"], "");
    assert_ne!(
        unlock[1]["warning"], "",
        "a wrong password is reported on the next prompt"
    );

    assert!(s.secret_tool(&["lock"], "").status.success());
    let refused = s.secret_tool(&["lookup", "service", "cortetsu-test"], "");
    assert!(
        refused.stdout.is_empty(),
        "a cancelled unlock reveals nothing"
    );
    shell.recv_timeout(Duration::from_secs(20)).unwrap();

    // `secret-tool lock` alone makes gnome-keyring 51.1 log a gkm_session
    // CRITICAL; only what concerns the prompter protocol is checked.
    let log = fs::read_to_string(s.path("keyring.log")).unwrap();
    for bad in [
        "Gcr-WARNING",
        "Gcr-CRITICAL",
        "GLib-CRITICAL",
        "invalid secret exchange",
    ] {
        assert!(!log.contains(bad), "gcr complained ({bad}):\n{log}");
    }
}

#[test]
fn gpg_asks_through_pinentry_gnome3() {
    let mut s = Session::new();
    s.prompter();
    let gnupg = s.path("home/.gnupg");
    fs::create_dir_all(&gnupg).unwrap();
    fs::set_permissions(&gnupg, fs::Permissions::from_mode(0o700)).unwrap();
    fs::write(
        gnupg.join("gpg-agent.conf"),
        "pinentry-program /usr/bin/pinentry-gnome3\n",
    )
    .unwrap();
    let gpg = |args: &[&str]| {
        let mut c = s.command("gpg");
        c.env("GNUPGHOME", &gnupg)
            .env("WAYLAND_DISPLAY", "wayland-test")
            .args(["--batch", "--no-tty"])
            .args(args);
        c
    };
    let made = gpg(&["--pinentry-mode", "loopback", "--passphrase", "frase-gpg"])
        .args([
            "--quick-gen-key",
            "prueba@cortetsu.invalid",
            "ed25519",
            "sign",
            "never",
        ])
        .output()
        .unwrap();
    assert!(
        made.status.success(),
        "{}",
        String::from_utf8_lossy(&made.stderr)
    );

    let shell = fake_shell(s.dir.path().to_owned(), vec![vec![Some("frase-gpg")]]);
    let signed = gpg(&["--clearsign"]).stdin(Stdio::null()).output().unwrap();
    let mut kill = s.command("gpgconf");
    let _ = kill
        .env("GNUPGHOME", &gnupg)
        .args(["--kill", "gpg-agent"])
        .status();
    assert!(
        signed.status.success(),
        "{}",
        String::from_utf8_lossy(&signed.stderr)
    );
    assert!(String::from_utf8_lossy(&signed.stdout).contains("BEGIN PGP SIGNATURE"));
    let seen = shell.recv_timeout(Duration::from_secs(20)).unwrap();
    assert_eq!(seen[0]["kind"], "password");
    assert!(
        seen[0]["description"]
            .as_str()
            .unwrap()
            .contains("prueba@cortetsu.invalid")
    );
}

/// No shell at all, and a shell generation without the `secretprompt`
/// target: `qs` exits 0 there and only prints "Target not found.".
#[test]
fn becomes_the_fallback_prompter_without_a_shell() {
    for qs_body in ["exit 1", "echo 'Target not found.'\nexit 0"] {
        let s = Session::new();
        let qs = s.path("qs");
        script(&qs, qs_body);
        let fallback = s.path("fallback");
        script(&fallback, "echo fallback-ran");
        let out = s
            .command(env!("CARGO_BIN_EXE_cortetsu-desktop-runtime"))
            .arg("cortetsu-prompter")
            .env("CORTETSU_QS_BIN", &qs)
            .env("CORTETSU_SHELL_PATH", s.dir.path())
            .env("CORTETSU_PROMPTER_FALLBACK", &fallback)
            .output()
            .unwrap();
        assert!(out.status.success(), "{qs_body}");
        assert_eq!(
            String::from_utf8_lossy(&out.stdout),
            "fallback-ran\n",
            "{qs_body}"
        );
        assert!(
            !s.has_owner("org.gnome.keyring.SystemPrompter"),
            "the name is left to the fallback"
        );
    }
}
