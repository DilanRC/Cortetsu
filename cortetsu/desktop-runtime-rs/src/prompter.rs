//! `cortetsu-prompter`: gcr's system prompter, the dialog gnome-keyring opens
//! to unlock or create a keyring and pinentry-gnome3 opens for GPG.
//!
//! It owns `org.gnome.keyring.SystemPrompter` and speaks the internal
//! `org.gnome.keyring.internal.Prompter` protocol (gcr 3.41,
//! gcr/gcr-system-prompter.c) in single mode: one client prompts at a time,
//! the rest wait. The dialog is the shell's (`modules/SecretPromptHost.qml`):
//! for each client this helper opens a private 0600 socket, asks the shell
//! over `qs ipc` to connect, and exchanges one JSON line per prompt. The
//! password only travels over that socket and, encrypted with the client's
//! `sx-aes-1` key, back over D-Bus.
//!
//! D-Bus activates the helper. If no shell answers then, it becomes
//! gcr-prompter before taking the name, so a prompt never depends on the
//! shell being up. It exits after a few idle seconds, as gcr-prompter does.
use crate::{common::Result, sxaes::Exchange};
use serde_json::{Value, json};
use std::{
    collections::{HashMap, VecDeque},
    env, fs,
    io::{BufRead, BufReader, ErrorKind, Write},
    net::Shutdown,
    os::unix::{
        fs::{DirBuilderExt, PermissionsExt},
        net::{UnixListener, UnixStream},
        process::CommandExt,
    },
    path::PathBuf,
    process::Command,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
        mpsc::{self, RecvTimeoutError, Sender},
    },
    thread,
    time::{Duration, Instant},
};
use zbus::{
    blocking::{Connection, connection::Builder, fdo::DBusProxy},
    fdo,
    message::Header,
    zvariant::{ObjectPath, OwnedValue, Value as Variant},
};
use zeroize::Zeroizing;

const PROMPTER_PATH: &str = "/org/gnome/keyring/Prompter";
const CALLBACK_IFACE: &str = "org.gnome.keyring.internal.Prompter.Callback";

/// A client prompt: the caller's unique bus name and its callback path.
type Client = (String, String);

enum Event {
    Next,
    Perform(Client),
    Stop(Client, bool),
    Answer(u64, Option<Value>),
    Vanished(String),
}

struct Active {
    client: Client,
    exchange: Exchange,
    kind: String,
    props: HashMap<String, Value>,
    busy: bool,
    shell: Option<ShellLink>,
}

#[derive(Default)]
struct State {
    known: Vec<Client>,
    waiting: VecDeque<Client>,
    active: Option<Active>,
}

fn fail(message: &str) -> fdo::Error {
    fdo::Error::Failed(message.to_owned())
}

/// gcr sends GcrPrompt properties as strings, booleans and one int.
fn json_of(value: &OwnedValue) -> Value {
    if let Ok(s) = <&str>::try_from(value) {
        Value::from(s)
    } else if let Ok(b) = bool::try_from(value) {
        Value::from(b)
    } else if let Ok(i) = i32::try_from(value) {
        Value::from(i)
    } else {
        Value::Null
    }
}

struct Prompter {
    state: Arc<Mutex<State>>,
    events: Sender<Event>,
}

#[zbus::interface(name = "org.gnome.keyring.internal.Prompter")]
impl Prompter {
    fn begin_prompting(
        &self,
        #[zbus(header)] header: Header<'_>,
        callback: ObjectPath<'_>,
    ) -> fdo::Result<()> {
        let sender = header
            .sender()
            .ok_or_else(|| fail("no sender"))?
            .to_string();
        let client = (sender, callback.to_string());
        let mut state = self.state.lock().map_err(|_| fail("poisoned"))?;
        if state.known.contains(&client) {
            return Err(fail("Already begun prompting for this prompt callback"));
        }
        state.known.push(client.clone());
        state.waiting.push_back(client);
        let _ = self.events.send(Event::Next);
        Ok(())
    }

    fn perform_prompt(
        &self,
        #[zbus(header)] header: Header<'_>,
        callback: ObjectPath<'_>,
        kind: &str,
        properties: HashMap<String, OwnedValue>,
        exchange: &str,
    ) -> fdo::Result<()> {
        let sender = header
            .sender()
            .ok_or_else(|| fail("no sender"))?
            .to_string();
        let client = (sender, callback.to_string());
        let mut state = self.state.lock().map_err(|_| fail("poisoned"))?;
        let active = match state.active.as_mut() {
            Some(active) if active.client == client => active,
            _ => return Err(fail("Not begun prompting for this prompt callback")),
        };
        if active.busy {
            return Err(fail("Already performing a prompt for this prompt callback"));
        }
        if kind != "password" && kind != "confirm" {
            return Err(fdo::Error::InvalidArgs("Invalid type argument".into()));
        }
        if !active.exchange.receive(exchange) {
            return Err(fdo::Error::InvalidArgs(
                "Invalid secret exchange received".into(),
            ));
        }
        for (name, value) in &properties {
            active.props.insert(name.clone(), json_of(value));
        }
        active.kind = kind.to_owned();
        active.busy = true;
        let _ = self.events.send(Event::Perform(client));
        Ok(())
    }

    fn stop_prompting(
        &self,
        #[zbus(header)] header: Header<'_>,
        callback: ObjectPath<'_>,
    ) -> fdo::Result<()> {
        let sender = header
            .sender()
            .ok_or_else(|| fail("no sender"))?
            .to_string();
        let _ = self
            .events
            .send(Event::Stop((sender, callback.to_string()), true));
        Ok(())
    }
}

// --- shell link ---------------------------------------------------------

// Link ids start at 1; `Worker::answer(0, None)` is the cancel sent when no
// dialog could be opened at all.
static LINKS: AtomicU64 = AtomicU64::new(1);

fn shell_path() -> PathBuf {
    env::var_os("CORTETSU_SHELL_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|| crate::common::config().join("quickshell/cortetsu/current"))
}

/// Runs `qs ipc call secretprompt <args>` and returns its stdout, or None when
/// no shell answers within `limit`, so a wedged shell never holds a prompt.
/// `qs` exits 0 even for a target the shell lacks ("Target not found."), so
/// callers check the output, not only the exit code.
fn qs_ipc(args: &[&std::ffi::OsStr], limit: Duration) -> Option<String> {
    let qs = env::var_os("CORTETSU_QS_BIN").unwrap_or_else(|| "qs".into());
    let mut command = Command::new(qs);
    command
        .arg("-p")
        .arg(shell_path())
        .args(["ipc", "call", "secretprompt"])
        .args(args);
    let out = crate::common::run(&mut command, None, limit).ok()?;
    out.status
        .success()
        .then(|| String::from_utf8_lossy(&out.stdout).trim().to_owned())
}

fn socket_dir() -> Result<PathBuf> {
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .filter(|s| !s.is_empty())
        .ok_or("XDG_RUNTIME_DIR is not set")?;
    let dir = PathBuf::from(runtime).join("cortetsu");
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&dir)?;
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o700))?;
    Ok(dir)
}

/// One shell dialog. Dropping it closes the socket, which closes the dialog.
struct ShellLink {
    id: u64,
    token: String,
    stream: UnixStream,
}

impl Drop for ShellLink {
    fn drop(&mut self) {
        let _ = self.stream.shutdown(Shutdown::Both);
    }
}

fn accept(listener: &UnixListener, deadline: Instant) -> Result<UnixStream> {
    listener.set_nonblocking(true)?;
    loop {
        match listener.accept() {
            Ok((stream, _)) => {
                stream.set_nonblocking(false)?;
                return Ok(stream);
            }
            Err(e) if e.kind() == ErrorKind::WouldBlock && Instant::now() < deadline => {
                thread::sleep(Duration::from_millis(20));
            }
            Err(e) if e.kind() == ErrorKind::WouldBlock => {
                return Err("the shell did not connect".into());
            }
            Err(e) => return Err(e.into()),
        }
    }
}

impl ShellLink {
    fn open(events: Sender<Event>) -> Result<Self> {
        let token: String = crate::sxaes::random(16)?
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect();
        let path = socket_dir()?.join(format!(
            "prompter-{}-{}.sock",
            std::process::id(),
            &token[..8]
        ));
        let _ = fs::remove_file(&path);
        let listener = UnixListener::bind(&path)?;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600))?;
        // `request` returns nothing; a shell that lacks it fails the accept.
        let asked = qs_ipc(
            &["request".as_ref(), path.as_os_str(), token.as_ref()],
            Duration::from_secs(5),
        );
        let stream = if asked.is_some() {
            accept(&listener, Instant::now() + Duration::from_secs(5))
        } else {
            Err("no shell".into())
        };
        let _ = fs::remove_file(&path);
        let stream = stream?;
        let id = LINKS.fetch_add(1, Ordering::Relaxed);
        let reader = stream.try_clone()?;
        thread::spawn(move || {
            for line in BufReader::new(reader).lines() {
                let Ok(line) = line.map(Zeroizing::new) else {
                    break;
                };
                let _ = events.send(Event::Answer(id, serde_json::from_str(&line).ok()));
            }
            let _ = events.send(Event::Answer(id, None));
        });
        Ok(Self { id, token, stream })
    }

    fn send(&mut self, request: &Value) -> bool {
        let line = format!("{request}\n");
        self.stream
            .write_all(line.as_bytes())
            .and_then(|_| self.stream.flush())
            .is_ok()
    }
}

/// What the shell is asked to show, from the accumulated gcr properties.
fn request(token: &str, kind: &str, props: &HashMap<String, Value>) -> Value {
    let s = |k: &str| props.get(k).and_then(Value::as_str).unwrap_or("");
    let b = |k: &str| props.get(k).and_then(Value::as_bool).unwrap_or(false);
    json!({
        "token": token,
        "kind": kind,
        "title": s("title"),
        "message": s("message"),
        "description": s("description"),
        "warning": s("warning"),
        "choiceLabel": s("choice-label"),
        "choiceChosen": b("choice-chosen"),
        "passwordNew": b("password-new"),
        "continueLabel": s("continue-label"),
        "cancelLabel": s("cancel-label"),
    })
}

/// The gcr reply for one shell answer: "yes" with the password for a password
/// prompt, "yes" for a confirmation, "no" for anything else, including an
/// answer carrying the wrong token.
fn reply_of(
    kind: &str,
    token: &str,
    answer: Option<&Value>,
) -> (&'static str, Option<Zeroizing<String>>, bool) {
    let Some(answer) = answer.filter(|a| a["token"].as_str() == Some(token)) else {
        return ("no", None, false);
    };
    let choice = answer["choice"].as_bool().unwrap_or(false);
    if answer["reply"].as_str() != Some("yes") {
        return ("no", None, choice);
    }
    match (kind, answer["password"].as_str()) {
        ("password", Some(password)) => ("yes", Some(Zeroizing::new(password.to_owned())), choice),
        ("password", None) => ("no", None, choice),
        _ => ("yes", None, choice),
    }
}

// --- worker -------------------------------------------------------------

struct Worker {
    conn: Connection,
    state: Arc<Mutex<State>>,
    events: Sender<Event>,
}

impl Worker {
    fn call(
        &self,
        client: &Client,
        method: &str,
        body: &(impl serde::Serialize + zbus::zvariant::DynamicType),
    ) -> bool {
        let Ok(path) = ObjectPath::try_from(client.1.as_str()) else {
            return false;
        };
        self.conn
            .call_method(
                Some(client.0.as_str()),
                path,
                Some(CALLBACK_IFACE),
                method,
                body,
            )
            .is_ok()
    }

    fn ready(
        &self,
        client: &Client,
        reply: &str,
        props: HashMap<&str, Variant<'_>>,
        exchange: &str,
    ) {
        if !self.call(client, "PromptReady", &(reply, props, exchange)) {
            // The client is gone or refused; drop it so the next one can prompt.
            let _ = self.events.send(Event::Stop(client.clone(), false));
        }
    }

    fn next(&self) {
        let (client, begin) = {
            let mut state = self.state.lock().unwrap();
            if state.active.is_some() {
                return;
            }
            let Some(client) = state.waiting.pop_front() else {
                return;
            };
            let Ok(exchange) = Exchange::new() else {
                state.known.retain(|c| *c != client);
                return;
            };
            let begin = exchange.begin();
            state.active = Some(Active {
                client: client.clone(),
                exchange,
                kind: String::new(),
                props: HashMap::new(),
                busy: false,
                shell: None,
            });
            (client, begin)
        };
        self.ready(&client, "", HashMap::new(), &begin);
    }

    fn perform(&self, client: Client) {
        let is_current = |state: &State| {
            state
                .active
                .as_ref()
                .is_some_and(|a| a.client == client && a.busy)
        };
        // Opening a link waits on the shell for up to 10 s; not under the
        // lock, so other clients' D-Bus calls are not held up meanwhile.
        let needs_link = {
            let state = self.state.lock().unwrap();
            if !is_current(&state) {
                return;
            }
            state.active.as_ref().is_some_and(|a| a.shell.is_none())
        };
        let link = needs_link
            .then(|| {
                ShellLink::open(self.events.clone())
                    .inspect_err(|e| eprintln!("cortetsu-prompter: {e}"))
                    .ok()
            })
            .flatten();
        let mut state = self.state.lock().unwrap();
        if !is_current(&state) {
            return;
        }
        let active = state.active.as_mut().expect("checked above");
        if link.is_some() {
            active.shell = link;
        }
        let sent = match active.shell.as_mut() {
            Some(link) => {
                let req = request(&link.token, &active.kind, &active.props);
                link.send(&req)
            }
            None => false,
        };
        if !sent {
            active.shell = None;
            drop(state);
            // No dialog could be shown: answer as a cancel.
            self.answer(0, None);
        }
    }

    fn answer(&self, link: u64, answer: Option<Value>) {
        let (client, reply, props, exchange) = {
            let mut state = self.state.lock().unwrap();
            let Some(active) = state.active.as_mut() else {
                return;
            };
            let current = active.shell.as_ref().map(|l| l.id);
            if link != 0 && current != Some(link) {
                return;
            }
            if answer.is_none() {
                active.shell = None;
            }
            if !active.busy {
                return;
            }
            let token = active
                .shell
                .as_ref()
                .map(|l| l.token.clone())
                .unwrap_or_default();
            let (reply, password, choice) = reply_of(&active.kind, &token, answer.as_ref());
            let Some(exchange) = active
                .exchange
                .send(password.as_deref().map(String::as_str))
            else {
                return;
            };
            let strength = i32::from(password.as_ref().is_some_and(|p| !p.is_empty()));
            active
                .props
                .insert("choice-chosen".into(), Value::from(choice));
            active.busy = false;
            // gcr wraps each value in a second variant in this direction
            // (gcr-system-prompter.c, prompt_build_properties).
            let wrap = |v: Variant<'static>| Variant::Value(Box::new(v));
            let props = HashMap::from([
                ("choice-chosen", wrap(Variant::from(choice))),
                ("password-strength", wrap(Variant::from(strength))),
            ]);
            (
                active.client.clone(),
                reply,
                props,
                Zeroizing::new(exchange),
            )
        };
        self.ready(&client, reply, props, &exchange);
    }

    fn stop(&self, client: Client, send_done: bool) {
        let was_active = {
            let mut state = self.state.lock().unwrap();
            if !state.known.contains(&client) {
                return;
            }
            state.known.retain(|c| *c != client);
            state.waiting.retain(|c| *c != client);
            let was_active = state.active.as_ref().is_some_and(|a| a.client == client);
            if was_active {
                state.active = None;
            }
            was_active
        };
        if send_done {
            self.call(&client, "PromptDone", &());
        }
        if was_active {
            self.next();
        }
    }

    fn vanished(&self, name: &str) {
        let gone: Vec<Client> = self
            .state
            .lock()
            .unwrap()
            .known
            .iter()
            .filter(|c| c.0 == name)
            .cloned()
            .collect();
        for client in gone {
            self.stop(client, false);
        }
    }

    fn idle(&self) -> bool {
        self.state.lock().unwrap().known.is_empty()
    }
}

fn fallback() -> Result<i32> {
    let prompter =
        env::var_os("CORTETSU_PROMPTER_FALLBACK").unwrap_or_else(|| "/usr/lib/gcr-prompter".into());
    // exec only returns on failure; D-Bus waits for the name from the same pid.
    let error = Command::new(&prompter).exec();
    eprintln!("cortetsu-prompter: no shell and no fallback prompter: {error}");
    Ok(1)
}

fn millis(var: &str, default: u64) -> Duration {
    Duration::from_millis(
        env::var(var)
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(default),
    )
}

pub fn main(_args: &[String]) -> Result<i32> {
    if qs_ipc(&["ping".as_ref()], Duration::from_secs(3)).as_deref() != Some("ok") {
        return fallback();
    }
    let name = env::var("CORTETSU_PROMPTER_NAME")
        .unwrap_or_else(|_| "org.gnome.keyring.SystemPrompter".into());
    let idle = millis("CORTETSU_PROMPTER_IDLE_MS", 10_000);
    let (tx, rx) = mpsc::channel();
    let state = Arc::new(Mutex::new(State::default()));
    let conn = Builder::session()?
        .method_timeout(Duration::from_secs(30))
        .serve_at(
            PROMPTER_PATH,
            Prompter {
                state: state.clone(),
                events: tx.clone(),
            },
        )?
        .name(name.as_str())?
        .build()?;

    let watcher = DBusProxy::new(&conn)?;
    let vanished = tx.clone();
    thread::spawn(move || {
        let Ok(signals) = watcher.receive_name_owner_changed() else {
            return;
        };
        for signal in signals {
            if let Ok(args) = signal.args()
                && args.new_owner().is_none()
            {
                let _ = vanished.send(Event::Vanished(args.name().to_string()));
            }
        }
    });

    let worker = Worker {
        conn,
        state,
        events: tx,
    };
    loop {
        match rx.recv_timeout(idle) {
            Ok(Event::Next) => worker.next(),
            Ok(Event::Perform(client)) => worker.perform(client),
            Ok(Event::Answer(link, answer)) => worker.answer(link, answer),
            Ok(Event::Stop(client, done)) => worker.stop(client, done),
            Ok(Event::Vanished(name)) => worker.vanished(&name),
            Err(RecvTimeoutError::Timeout) if worker.idle() => return Ok(0),
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => return Ok(0),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn request_maps_gcr_properties() {
        let props = HashMap::from([
            ("title".to_owned(), Value::from("Unlock")),
            ("password-new".to_owned(), Value::from(true)),
            ("choice-label".to_owned(), Value::from("Auto")),
        ]);
        let r = request("t", "password", &props);
        assert_eq!(r["title"], "Unlock");
        assert_eq!(r["passwordNew"], true);
        assert_eq!(r["choiceLabel"], "Auto");
        assert_eq!(r["choiceChosen"], false);
        assert_eq!(r["warning"], "");
    }

    #[test]
    fn replies_only_to_the_right_token() {
        let ok = json!({"token": "t", "reply": "yes", "password": "pw", "choice": true});
        let (reply, pw, choice) = reply_of("password", "t", Some(&ok));
        assert_eq!(
            (reply, pw.as_deref().map(String::as_str), choice),
            ("yes", Some("pw"), true)
        );
        assert_eq!(reply_of("password", "other", Some(&ok)).0, "no");
        assert_eq!(reply_of("password", "t", None).0, "no");
        let no_pw = json!({"token": "t", "reply": "yes"});
        assert_eq!(reply_of("password", "t", Some(&no_pw)).0, "no");
        assert_eq!(reply_of("confirm", "t", Some(&no_pw)).0, "yes");
        assert_eq!(
            reply_of("confirm", "t", Some(&json!({"token": "t", "reply": "no"}))).0,
            "no"
        );
    }
}
