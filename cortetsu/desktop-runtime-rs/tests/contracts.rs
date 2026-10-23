use serde_json::{Value, json};
use std::{fs, os::unix::fs::PermissionsExt, process::Command};
use tempfile::TempDir;

fn command(home: &TempDir, helper: &str, args: &[&str]) -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_cortetsu-desktop-runtime"));
    c.arg(helper)
        .args(args)
        .env("HOME", home.path())
        .env("XDG_STATE_HOME", home.path().join("state"))
        .env("XDG_CONFIG_HOME", home.path().join("config"))
        .env("XDG_CACHE_HOME", home.path().join("cache"))
        .env("XDG_CONFIG_DIRS", home.path().join("system-config"))
        .env(
            "CORTETSU_REPO_ROOT",
            concat!(env!("CARGO_MANIFEST_DIR"), "/../.."),
        );
    c
}
fn payload(mut c: Command) -> Value {
    let o = c.output().unwrap();
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    serde_json::from_slice(&o.stdout).unwrap()
}

#[test]
fn pomodoro_default_reset_and_state_mode() {
    let home = TempDir::new().unwrap();
    let initial = payload(command(&home, "cortetsu-pomodoro", &["status"]));
    assert_eq!(initial["phase"], "IDLE");
    assert_eq!(initial["schema"], 2);
    let path = home.path().join("state/cortetsu/pomodoro.json");
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(&path,json!({"phase":"PAUSED","pausedPhase":"LONG_BREAK","pausedRemainingMs":111,"focusMinutes":45,"completedSessions":8}).to_string()).unwrap();
    let reset = payload(command(&home, "cortetsu-pomodoro", &["reset"]));
    assert_eq!(reset["phase"], "IDLE");
    assert_eq!(reset["focusMinutes"], 45);
    assert_eq!(reset["completedSessions"], 0);
    assert_eq!(
        fs::metadata(path).unwrap().permissions().mode() & 0o777,
        0o600
    );
}

#[test]
fn expired_pomodoro_announces_only_once() {
    let home = TempDir::new().unwrap();
    let dir = home.path().join("state/cortetsu");
    fs::create_dir_all(&dir).unwrap();
    fs::write(
        dir.join("pomodoro.json"),
        r#"{"phase":"FOCUS","targetEndTimestamp":1,"completedSessions":3}"#,
    )
    .unwrap();
    assert_eq!(
        payload(command(&home, "cortetsu-pomodoro", &["status"]))["phase"],
        "LONG_BREAK"
    );
    let event = fs::read(dir.join("pomodoro-notification.json")).unwrap();
    payload(command(&home, "cortetsu-pomodoro", &["status"]));
    assert_eq!(
        event,
        fs::read(dir.join("pomodoro-notification.json")).unwrap()
    );
}

#[test]
fn calendar_selection_and_no_credentials() {
    let home = TempDir::new().unwrap();
    let v = payload(command(&home, "cortetsu-calendar", &["status"]));
    assert_eq!(v["status"], "auth_required");
    assert_eq!(v["eventCount"], 0);
    payload(command(
        &home,
        "cortetsu-calendar",
        &["set-selection", "private-id", "true"],
    ));
    let v = payload(command(
        &home,
        "cortetsu-calendar",
        &["set-selection", "z", "true"],
    ));
    assert_eq!(v["enabled"], json!(["private-id", "z"]));
    let o = command(&home, "cortetsu-calendar", &["sync"])
        .output()
        .unwrap();
    assert_eq!(o.status.code(), Some(2));
    assert_eq!(
        serde_json::from_slice::<Value>(&o.stdout).unwrap()["status"],
        "auth_required"
    );
}

#[test]
fn scheme_catalog_contains_shipped_colours() {
    let home = TempDir::new().unwrap();
    let v = payload(command(&home, "cortetsu-scheme", &["list"]));
    assert!(v.as_object().unwrap().len() > 1);
    let (name, flavours) = v.as_object().unwrap().iter().next().unwrap();
    let flavour = flavours.as_object().unwrap().keys().next().unwrap();
    assert!(
        command(&home, "cortetsu-scheme", &["set", "-n", name, flavour])
            .status()
            .unwrap()
            .success()
    );
    let state: Value =
        serde_json::from_slice(&fs::read(home.path().join("state/cortetsu/scheme.json")).unwrap())
            .unwrap();
    assert_eq!(state["colours"], flavours[flavour]);
}

#[test]
fn kitty_colours_stay_outside_sealed_generations() {
    use std::os::unix::fs::MetadataExt;
    let home = TempDir::new().unwrap();
    let v = payload(command(&home, "cortetsu-scheme", &["list"]));
    let (name, flavours) = v.as_object().unwrap().iter().next().unwrap();
    let flavour = flavours.as_object().unwrap().keys().next().unwrap();
    let set = |home: &TempDir| {
        assert!(
            command(home, "cortetsu-scheme", &["set", "-n", name, flavour])
                .status()
                .unwrap()
                .success()
        )
    };
    let sync = |home: &TempDir| {
        command(home, "cortetsu-scheme", &["sync-kitty"])
            .status()
            .unwrap()
    };
    // A stale symlink into a sealed generation must be replaced, never written through.
    let sealed = home.path().join("dotfiles/builds/g1/kitty.conf");
    fs::create_dir_all(sealed.parent().unwrap()).unwrap();
    fs::write(&sealed, "include cortetsu-theme.conf\n").unwrap();
    let kitty = home.path().join("state/cortetsu/kitty-colors.conf");
    fs::create_dir_all(kitty.parent().unwrap()).unwrap();
    std::os::unix::fs::symlink(&sealed, &kitty).unwrap();
    set(&home);
    assert_eq!(
        fs::read_to_string(&sealed).unwrap(),
        "include cortetsu-theme.conf\n"
    );
    assert!(!kitty.is_symlink());
    let first = fs::read_to_string(&kitty).unwrap();
    let expected = &flavours[flavour]["term15"].as_str().unwrap();
    assert!(first.contains(&format!(
        "color15 #{}",
        expected.trim_start_matches('#').to_lowercase()
    )));
    assert!(!first.contains("include"));
    let inode = fs::metadata(&kitty).unwrap().ino();
    for _ in 0..3 {
        set(&home);
        assert!(sync(&home).success());
    }
    assert_eq!(fs::read_to_string(&kitty).unwrap(), first);
    assert_eq!(
        fs::metadata(&kitty).unwrap().ino(),
        inode,
        "unchanged colours must not rewrite"
    );
    let scheme = home.path().join("state/cortetsu/scheme.json");
    let good = fs::read(&scheme).unwrap();
    fs::write(&scheme, r#"{"name":"broken","colours":{"surface":"zz"}}"#).unwrap();
    assert!(!sync(&home).success());
    assert_eq!(
        fs::read_to_string(&kitty).unwrap(),
        first,
        "a failed sync keeps the valid file"
    );
    fs::write(&scheme, good).unwrap();
    fs::remove_file(&kitty).unwrap();
    assert!(sync(&home).success());
    assert_eq!(fs::read_to_string(&kitty).unwrap(), first);
    assert_eq!(fs::metadata(&kitty).unwrap().mode() & 0o777, 0o644);
}

#[test]
fn emoji_dump_is_byte_exact() {
    let home = TempDir::new().unwrap();
    let path = home.path().join("emoji.txt");
    fs::write(&path, "😀 feliz\n¯\\_(ツ)_/¯ shrug\n").unwrap();
    let o = command(&home, "cortetsu-emoji", &[])
        .env("CORTETSU_EMOJI_DATA", &path)
        .output()
        .unwrap();
    assert!(o.status.success());
    assert_eq!(o.stdout, fs::read(path).unwrap());
}

#[test]
fn startup_toggle_preserves_desktop_file_and_has_readback() {
    let home = TempDir::new().unwrap();
    let dir = home.path().join("config/autostart");
    fs::create_dir_all(&dir).unwrap();
    let path = dir.join("example.desktop");
    fs::write(&path,"# keep me\n[Desktop Entry]\nName=Example\nExec=/bin/true\nHidden=false\n[X-Test]\nKey=Value\n").unwrap();
    let v = payload(command(
        &home,
        "cortetsu-startup",
        &["set", "xdg:example.desktop", "disable"],
    ));
    assert_eq!(v["entry"]["configured"], false);
    let t = fs::read_to_string(&path).unwrap();
    assert!(t.contains("# keep me"));
    assert!(t.contains("[X-Test]\nKey=Value"));
    assert!(t.contains("Hidden=true"));
    assert!(
        fs::read_dir(home.path().join("state/cortetsu/startup/backups"))
            .unwrap()
            .next()
            .is_some()
    );
}

#[test]
fn credential_rejects_bad_uuid_without_echoing_secret() {
    use std::io::Write;
    let home = TempDir::new().unwrap();
    let mut child = command(&home, "cortetsu-connectivity-secret", &["not-a-uuid"])
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(b"super-secret-value")
        .unwrap();
    let o = child.wait_with_output().unwrap();
    assert_eq!(o.status.code(), Some(2));
    assert_eq!(String::from_utf8_lossy(&o.stderr).trim(), "profile-invalid");
    assert!(o.stdout.is_empty());
}

#[test]
fn immutable_generation_resources_win_over_mutable_checkout() {
    let home = TempDir::new().unwrap();
    let resource = home.path().join("generation");
    let palette = resource.join("data/schemes/cortetsu-pack/frozen/default");
    fs::create_dir_all(&palette).unwrap();
    fs::write(
        resource.join("data/schemes/palettes.json"),
        r#"{"frozen/default":{}}"#,
    )
    .unwrap();
    fs::write(palette.join("dark.txt"), "primary 123456\n").unwrap();
    let v = payload({
        let mut c = command(&home, "cortetsu-scheme", &["list"]);
        c.env("CORTETSU_RESOURCE_ROOT", &resource);
        c
    });
    assert_eq!(v, json!({"frozen":{"default":{"primary":"123456"}}}));
    let o = command(&home, "cortetsu-scheme", &["list"])
        .env(
            "CORTETSU_RESOURCE_ROOT",
            home.path().join("missing-generation"),
        )
        .output()
        .unwrap();
    assert!(
        !o.status.success(),
        "silently fell back to mutable checkout"
    );
}

fn script(home: &TempDir, name: &str, body: &str) {
    let dir = home.path().join("bin");
    fs::create_dir_all(&dir).unwrap();
    let path = dir.join(name);
    fs::write(&path, format!("#!/bin/sh\n{body}\n")).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}
fn isolated(home: &TempDir, helper: &str, args: &[&str]) -> Command {
    let mut c = command(home, helper, args);
    c.env(
        "PATH",
        format!("{}:/usr/bin:/bin", home.path().join("bin").display()),
    );
    c
}
struct ChildGuard(std::process::Child);
impl Drop for ChildGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}
fn wait_until(mut check: impl FnMut() -> bool) {
    let until = std::time::Instant::now() + std::time::Duration::from_secs(5);
    while !check() {
        assert!(
            std::time::Instant::now() < until,
            "condition did not become true"
        );
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
}

#[test]
fn daemon_is_idle_and_wakes_once_for_deadline() {
    let home = TempDir::new().unwrap();
    let dir = home.path().join("state/cortetsu");
    fs::create_dir_all(&dir).unwrap();
    let state = payload(command(&home, "cortetsu-pomodoro", &["reset"]));
    let daemon = ChildGuard(
        command(&home, "cortetsu-pomodoro", &["daemon"])
            .spawn()
            .unwrap(),
    );
    wait_until(|| {
        fs::read_to_string(dir.join("pomodoro-daemon.lock"))
            .is_ok_and(|v| v.trim() == daemon.0.id().to_string())
    });
    let switches = || {
        fs::read_to_string(format!("/proc/{}/status", daemon.0.id()))
            .unwrap()
            .lines()
            .find(|l| l.starts_with("voluntary_ctxt_switches:"))
            .unwrap()
            .split_whitespace()
            .last()
            .unwrap()
            .parse::<u64>()
            .unwrap()
    };
    let before = switches();
    std::thread::sleep(std::time::Duration::from_millis(500));
    assert!(switches() - before <= 1, "idle daemon polls");
    let mut expiring = state;
    expiring["phase"] = json!("FOCUS");
    expiring["targetEndTimestamp"] = json!(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs_f64()
            + 0.2
    );
    fs::write(dir.join("pomodoro.json"), expiring.to_string()).unwrap();
    nix::sys::signal::kill(
        nix::unistd::Pid::from_raw(daemon.0.id() as i32),
        nix::sys::signal::Signal::SIGUSR1,
    )
    .unwrap();
    wait_until(|| {
        fs::read(dir.join("pomodoro-notification.json"))
            .ok()
            .and_then(|b| serde_json::from_slice::<Value>(&b).ok())
            .is_some_and(|v| v["title"] == "Sesión de concentración completada")
    });
    let event = fs::read(dir.join("pomodoro-notification.json")).unwrap();
    assert_eq!(
        payload(command(&home, "cortetsu-pomodoro", &["status"]))["phase"],
        "BREAK"
    );
    assert_eq!(
        event,
        fs::read(dir.join("pomodoro-notification.json")).unwrap()
    );
    let second = command(&home, "cortetsu-pomodoro", &["daemon"])
        .status()
        .unwrap();
    assert!(second.success());
}

#[test]
fn calendar_cache_force_and_invalid_desktop_client() {
    let home = TempDir::new().unwrap();
    let cfg = home.path().join("config/cortetsu");
    let cache = home.path().join("cache/cortetsu");
    fs::create_dir_all(&cfg).unwrap();
    fs::create_dir_all(&cache).unwrap();
    fs::write(
        cfg.join("calendar-client.json"),
        r#"{"web":{"client_id":"wrong-client-type"}}"#,
    )
    .unwrap();
    fs::write(cache.join("calendar-events.json"),json!({"fetchedAt":std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64(),"events":[{"title":"kept"}]}).to_string()).unwrap();
    let v = payload(command(&home, "cortetsu-calendar", &["sync"]));
    assert_eq!(v["status"], "cached");
    assert_eq!(v["eventCount"], 1);
    let out = command(&home, "cortetsu-calendar", &["sync", "--force"])
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(2));
    assert_eq!(
        serde_json::from_slice::<Value>(&out.stdout).unwrap()["status"],
        "credential_error"
    );
    assert!(
        fs::read_to_string(cache.join("calendar-events.json"))
            .unwrap()
            .contains("kept")
    );
}

#[test]
fn area_capture_uses_argv_and_always_removes_temporary_image() {
    let home = TempDir::new().unwrap();
    script(&home, "grim", "printf 'PNG' > \"$3\"");
    script(&home, "wl-copy", "cat > \"$HOME/copied\"");
    script(&home, "notify-send", "exit 0");
    let path = home.path().join("image ; $(touch injected).png");
    let out = isolated(
        &home,
        "cortetsu-area-capture",
        &["-10,20 100x200", path.to_str().unwrap(), "--clipboard"],
    )
    .output()
    .unwrap();
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(!path.exists());
    assert_eq!(fs::read(home.path().join("copied")).unwrap(), b"PNG");
    assert!(!home.path().join("injected").exists());
    fs::write(&path, "retain-on-invalid-request").unwrap();
    let out = isolated(
        &home,
        "cortetsu-area-capture",
        &["0,0 10x10; false", path.to_str().unwrap()],
    )
    .output()
    .unwrap();
    assert_eq!(out.status.code(), Some(2));
    assert!(path.exists());
}

#[test]
fn wallpaper_watcher_only_applies_on_change_and_skips_running_engine() {
    let home = TempDir::new().unwrap();
    let state = home.path().join("state/cortetsu/wallpaper");
    fs::create_dir_all(&state).unwrap();
    let image = home.path().join("wall.png");
    fs::write(&image, "pixels").unwrap();
    fs::write(state.join("path.txt"), format!("{}\n", image.display())).unwrap();
    let bin = home.path().join(".local/bin");
    fs::create_dir_all(&bin).unwrap();
    let apply = bin.join("cortetsu-apply-wallpaper-colors");
    fs::write(
        &apply,
        "#!/bin/sh\nprintf 'apply\\n' >> \"$HOME/applied\"\n",
    )
    .unwrap();
    fs::set_permissions(&apply, fs::Permissions::from_mode(0o755)).unwrap();
    let proc = home.path().join("proc");
    fs::create_dir_all(&proc).unwrap();
    let run = || {
        command(&home, "cortetsu-wallpaper-color-daemon", &["--once"])
            .env("XDG_RUNTIME_DIR", home.path().join("runtime"))
            .env("CORTETSU_PROC_ROOT", &proc)
            .status()
            .unwrap()
    };
    assert!(run().success());
    assert!(run().success());
    assert_eq!(
        fs::read_to_string(home.path().join("applied")).unwrap(),
        "apply\n"
    );
    fs::create_dir_all(proc.join("12345")).unwrap();
    fs::write(proc.join("12345/cmdline"), b"linux-wallpaperengine\0").unwrap();
    assert!(run().success());
    assert_eq!(
        fs::read_to_string(home.path().join("applied")).unwrap(),
        "apply\n"
    );
}

#[test]
fn recorder_owns_process_and_preserves_output() {
    let home = TempDir::new().unwrap();
    script(
        &home,
        "hyprctl",
        r#"printf '[{"name":"eDP-1","focused":true,"refreshRate":143.9}]'"#,
    );
    script(&home, "notify-send", "printf '42\\n'");
    script(
        &home,
        "gpu-screen-recorder",
        r#"
if [ "$1" = --list-monitors ]; then printf 'eDP-1|1920x1080\n'; exit 0; fi
printf '%s\n' "$@" > "$HOME/recorder-args"
while [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then shift; printf 'recorded-video' > "$1"; break; fi; shift; done
trap 'exit 0' INT TERM
trap ':' USR2
while :; do sleep 0.05; done
"#,
    );
    let out = isolated(&home, "cortetsu-record", &["start", "--sound"])
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let s: Value = serde_json::from_slice(
        &fs::read(home.path().join("state/cortetsu/record/state.json")).unwrap(),
    )
    .unwrap();
    struct SignalCleanup(i32);
    impl Drop for SignalCleanup {
        fn drop(&mut self) {
            let _ = nix::sys::signal::kill(
                nix::unistd::Pid::from_raw(self.0),
                nix::sys::signal::Signal::SIGTERM,
            );
        }
    }
    let _cleanup = SignalCleanup(s["pid"].as_i64().unwrap() as i32);
    assert!(
        isolated(&home, "cortetsu-record", &["status"])
            .status()
            .unwrap()
            .success()
    );
    assert!(
        isolated(&home, "cortetsu-record", &["pause"])
            .status()
            .unwrap()
            .success()
    );
    let out = isolated(&home, "cortetsu-record", &["stop"])
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let p = String::from_utf8(out.stdout).unwrap();
    assert_eq!(fs::read(p.trim()).unwrap(), b"recorded-video");
    assert!(
        !home
            .path()
            .join("state/cortetsu/record/state.json")
            .exists()
    );
}
