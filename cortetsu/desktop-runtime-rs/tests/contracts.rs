use serde_json::{Value, json};
use std::{
    fs,
    io::Write,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};
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
    assert_eq!(state["schema"], 2);
    assert_eq!(state["origin"], "manual");
    assert_eq!(state["lastSelection"]["name"], name.as_str());
    assert_eq!(state["lastSelection"]["flavour"], flavour.as_str());
}

#[test]
fn explicit_scheme_choice_recovers_corrupt_state() {
    let home = TempDir::new().unwrap();
    let state = home.path().join("state/cortetsu");
    fs::create_dir_all(&state).unwrap();
    let scheme = state.join("scheme.json");
    fs::write(&scheme, b"{broken").unwrap();
    let result = command(&home, "cortetsu-scheme", &["set", "-n", "aura", "default"])
        .output()
        .unwrap();
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    let recovered: Value = serde_json::from_slice(&fs::read(scheme).unwrap()).unwrap();
    assert_eq!(recovered["schema"], 2);
    assert_eq!(recovered["origin"], "manual");
    assert_eq!(recovered["name"], "aura");
}

#[test]
fn concurrent_manual_scheme_changes_leave_hypr_projection_at_latest_choice() {
    let home = TempDir::new().unwrap();
    let config = home.path().join("config/hypr/scheme");
    fs::create_dir_all(&config).unwrap();
    fs::write(config.join("current.lua"), "return {}\n").unwrap();
    let state = home.path().join("state/cortetsu/scheme.json");
    let catalog = payload(command(&home, "cortetsu-scheme", &["list"]));
    let latest_primary = catalog["nebula"]["default"]["primary"]
        .as_str()
        .unwrap()
        .trim_start_matches('#')
        .to_owned();
    let fake_bin = home.path().join("fake-bin");
    fs::create_dir_all(&fake_bin).unwrap();
    let started = home.path().join("reload-started");
    let release = home.path().join("release-reload");
    let hyprctl = fake_bin.join("hyprctl");
    fs::write(
        &hyprctl,
        format!(
            "#!/bin/sh\nprintf started > '{}'\nwhile [ ! -e '{}' ]; do sleep 0.01; done\n",
            started.display(),
            release.display()
        ),
    )
    .unwrap();
    fs::set_permissions(&hyprctl, fs::Permissions::from_mode(0o755)).unwrap();
    let path = std::env::var_os("PATH").unwrap_or_default();
    let path = std::iter::once(fake_bin.clone())
        .chain(std::env::split_paths(&path))
        .collect::<Vec<_>>();
    let path = std::env::join_paths(path).unwrap();

    let mut first = command(&home, "cortetsu-scheme", &["set", "-n", "aura", "default"]);
    first.env("PATH", &path);
    let mut first = first.spawn().unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    while !started.exists() && Instant::now() < deadline {
        thread::sleep(Duration::from_millis(10));
    }
    assert!(started.exists(), "first Hyprland projection did not start");

    let mut second = command(
        &home,
        "cortetsu-scheme",
        &["set", "-n", "nebula", "default"],
    );
    second.env("PATH", &path);
    let mut second = second.spawn().unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    while Instant::now() < deadline {
        if fs::read(&state)
            .ok()
            .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
            .is_some_and(|value| value["name"] == "nebula")
        {
            break;
        }
        thread::sleep(Duration::from_millis(10));
    }
    let current: Value = serde_json::from_slice(&fs::read(&state).unwrap()).unwrap();
    assert_eq!(current["name"], "nebula");
    fs::write(&release, b"go").unwrap();
    assert!(first.wait().unwrap().success());
    assert!(second.wait().unwrap().success());
    assert!(
        fs::read_to_string(config.join("current.lua"))
            .unwrap()
            .contains(&format!("primary = \"{latest_primary}\""))
    );
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
fn area_capture_keeps_the_preview_image_and_runs_its_actions() {
    let home = TempDir::new().unwrap();
    script(&home, "grim", "printf 'PNG' > \"$3\"");
    script(&home, "wl-copy", "cat > \"$HOME/copied\"");
    script(&home, "swappy", "printf 'EDITED' > \"$4\"");
    let pictures = home.path().join("Imágenes");
    script(
        &home,
        "xdg-user-dir",
        &format!("printf '%s\\n' '{}'", pictures.display()),
    );
    let run = |args: &[&str]| {
        isolated(&home, "cortetsu-area-capture", args)
            .output()
            .unwrap()
    };
    // The capture lands in a new private directory and stays for the preview.
    let shot = home.path().join("run/cortetsu/cortetsu-shot-1.png");
    let s = shot.to_str().unwrap();
    assert!(run(&["0,0 10x10", s]).status.success());
    assert_eq!(fs::read(&shot).unwrap(), b"PNG");
    let mode = fs::metadata(shot.parent().unwrap())
        .unwrap()
        .permissions()
        .mode();
    assert_eq!(mode & 0o777, 0o700);

    assert!(run(&["--copy", s]).status.success());
    assert_eq!(fs::read(home.path().join("copied")).unwrap(), b"PNG");
    assert!(run(&["--edit", s]).status.success());
    assert_eq!(fs::read(&shot).unwrap(), b"EDITED");

    let out = run(&["--save", s]);
    assert!(out.status.success());
    let dest = PathBuf::from(String::from_utf8(out.stdout).unwrap().trim());
    assert_eq!(dest.parent().unwrap(), pictures.join("Capturas"));
    assert_eq!(fs::read(&dest).unwrap(), b"EDITED");
    assert!(!shot.exists());

    // A second save in the same second gets its own name.
    assert!(run(&["0,0 10x10", s]).status.success());
    let again = PathBuf::from(
        String::from_utf8(run(&["--save", s]).stdout)
            .unwrap()
            .trim(),
    );
    assert_ne!(again, dest);
    assert!(again.is_file() && dest.is_file());

    assert!(run(&["0,0 10x10", s]).status.success());
    assert!(run(&["--discard", s]).status.success());
    assert!(!shot.exists());

    // Actions refuse any file this helper did not capture.
    let other = home.path().join("notes.png");
    fs::write(&other, "keep").unwrap();
    for action in ["--discard", "--save", "--copy", "--edit"] {
        assert_eq!(
            run(&[action, other.to_str().unwrap()]).status.code(),
            Some(2)
        );
    }
    assert_eq!(fs::read(&other).unwrap(), b"keep");

    // A failed capture leaves nothing behind.
    script(&home, "grim", "printf 'partial' > \"$3\"; exit 1");
    assert!(!run(&["0,0 10x10", s]).status.success());
    assert!(!shot.exists());
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
fn wallpaper_watcher_preserves_a_manual_scheme() {
    let home = TempDir::new().unwrap();
    let state = home.path().join("state/cortetsu");
    let wallpaper = state.join("wallpaper");
    fs::create_dir_all(&wallpaper).unwrap();
    let image = home.path().join("wall.png");
    fs::write(&image, "pixels").unwrap();
    fs::write(wallpaper.join("path.txt"), format!("{}\n", image.display())).unwrap();
    fs::write(
        state.join("scheme.json"),
        json!({
            "schema": 2,
            "name": "aura",
            "flavour": "default",
            "origin": "manual",
            "colours": {"primary": "#123456"}
        })
        .to_string(),
    )
    .unwrap();
    let config = home.path().join("config/cortetsu");
    fs::create_dir_all(&config).unwrap();
    fs::write(
        config.join("preferences.json"),
        r#"{"schema":1,"smartScheme":true}"#,
    )
    .unwrap();
    let bin = home.path().join(".local/bin");
    fs::create_dir_all(&bin).unwrap();
    let apply = bin.join("cortetsu-apply-wallpaper-colors");
    fs::write(
        &apply,
        "#!/bin/sh\nprintf '%s\\n' \"$1\" >> \"$HOME/applied\"\n",
    )
    .unwrap();
    fs::set_permissions(&apply, fs::Permissions::from_mode(0o755)).unwrap();
    let proc = home.path().join("proc");
    fs::create_dir_all(&proc).unwrap();

    assert!(
        command(&home, "cortetsu-wallpaper-color-daemon", &["--once"])
            .env("XDG_RUNTIME_DIR", home.path().join("runtime"))
            .env("CORTETSU_PROC_ROOT", &proc)
            .status()
            .unwrap()
            .success()
    );

    assert!(
        !home.path().join("applied").exists(),
        "a new session must not replace an explicitly selected manual scheme"
    );
    let scheme: Value =
        serde_json::from_slice(&fs::read(state.join("scheme.json")).unwrap()).unwrap();
    assert_eq!(scheme["name"], "aura");
    assert_eq!(scheme["colours"]["primary"], "#123456");

    // Upgrade-era files have no schema/origin. A named palette still means
    // that the user picked it manually and must survive the next source change.
    fs::write(
        state.join("scheme.json"),
        r##"{"name":"aura","flavour":"default","colours":{"primary":"#654321"}}"##,
    )
    .unwrap();
    fs::write(&image, "changed wallpaper pixels").unwrap();
    assert!(
        command(&home, "cortetsu-wallpaper-color-daemon", &["--once"])
            .env("XDG_RUNTIME_DIR", home.path().join("runtime"))
            .env("CORTETSU_PROC_ROOT", &proc)
            .status()
            .unwrap()
            .success()
    );
    assert!(!home.path().join("applied").exists());
    let legacy: Value =
        serde_json::from_slice(&fs::read(state.join("scheme.json")).unwrap()).unwrap();
    assert_eq!(legacy["name"], "aura");
    assert_eq!(legacy["colours"]["primary"], "#654321");
}

#[test]
fn wallpaper_palette_writer_rechecks_manual_ownership_at_commit_time() {
    let home = TempDir::new().unwrap();
    let state = home.path().join("state/cortetsu");
    fs::create_dir_all(&state).unwrap();
    let scheme_path = state.join("scheme.json");
    let manual = json!({
        "schema": 2,
        "name": "aura",
        "flavour": "default",
        "origin": "manual",
        "colours": {"primary": "#123456"}
    });
    fs::write(&scheme_path, serde_json::to_vec(&manual).unwrap()).unwrap();
    fs::create_dir_all(home.path().join("config/cortetsu")).unwrap();
    fs::write(
        home.path().join("config/cortetsu/preferences.json"),
        r#"{"smartScheme":true}"#,
    )
    .unwrap();
    let original = fs::read(&scheme_path).unwrap();
    let payload = json!({
        "name": "dynamic",
        "flavour": "default",
        "mode": "dark",
        "variant": "tonal-spot",
        "colours": {"primary": "#abcdef"}
    });
    let mut child = command(&home, "cortetsu-scheme", &["apply-wallpaper-colors"])
        .stdin(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(serde_json::to_string(&payload).unwrap().as_bytes())
        .unwrap();
    assert_eq!(child.wait().unwrap().code(), Some(3));
    assert_eq!(fs::read(scheme_path).unwrap(), original);
}

#[test]
fn wallpaper_watcher_respects_disabled_wallpaper_sync() {
    let home = TempDir::new().unwrap();
    let state = home.path().join("state/cortetsu");
    let wallpaper = state.join("wallpaper");
    fs::create_dir_all(&wallpaper).unwrap();
    let image = home.path().join("wall.png");
    fs::write(&image, "pixels").unwrap();
    fs::write(wallpaper.join("path.txt"), format!("{}\n", image.display())).unwrap();
    fs::write(
        state.join("scheme.json"),
        json!({
            "schema": 2,
            "name": "dynamic",
            "flavour": "default",
            "origin": "wallpaper",
            "colours": {"primary": "#123456"}
        })
        .to_string(),
    )
    .unwrap();
    let config = home.path().join("config/cortetsu");
    fs::create_dir_all(&config).unwrap();
    fs::write(
        config.join("preferences.json"),
        r#"{"schema":1,"smartScheme":false}"#,
    )
    .unwrap();
    let bin = home.path().join(".local/bin");
    fs::create_dir_all(&bin).unwrap();
    let apply = bin.join("cortetsu-apply-wallpaper-colors");
    fs::write(
        &apply,
        "#!/bin/sh\nprintf 'applied\\n' >> \"$HOME/applied\"\n",
    )
    .unwrap();
    fs::set_permissions(&apply, fs::Permissions::from_mode(0o755)).unwrap();
    let proc = home.path().join("proc");
    fs::create_dir_all(&proc).unwrap();

    let runtime = home.path().join("runtime");
    assert!(
        command(&home, "cortetsu-wallpaper-color-daemon", &["--once"])
            .env("XDG_RUNTIME_DIR", &runtime)
            .env("CORTETSU_PROC_ROOT", &proc)
            .status()
            .unwrap()
            .success()
    );
    assert!(!home.path().join("applied").exists());

    fs::write(
        config.join("preferences.json"),
        r#"{"schema":1,"smartScheme":true}"#,
    )
    .unwrap();
    assert!(
        command(&home, "cortetsu-wallpaper-color-daemon", &["--once"])
            .env("XDG_RUNTIME_DIR", runtime)
            .env("CORTETSU_PROC_ROOT", proc)
            .status()
            .unwrap()
            .success()
    );
    assert!(home.path().join("applied").exists());
}

#[test]
fn wallpaper_watcher_fails_closed_on_corrupt_persistent_state() {
    for corrupt_file in ["scheme.json", "preferences.json"] {
        let home = TempDir::new().unwrap();
        let state = home.path().join("state/cortetsu");
        let wallpaper = state.join("wallpaper");
        fs::create_dir_all(&wallpaper).unwrap();
        let image = home.path().join("wall.png");
        fs::write(&image, "pixels").unwrap();
        fs::write(wallpaper.join("path.txt"), format!("{}\n", image.display())).unwrap();
        let scheme = state.join("scheme.json");
        let config = home.path().join("config/cortetsu");
        fs::create_dir_all(&config).unwrap();
        if corrupt_file == "scheme.json" {
            fs::write(&scheme, "{broken").unwrap();
            fs::write(
                config.join("preferences.json"),
                r#"{"schema":1,"smartScheme":true}"#,
            )
            .unwrap();
        } else {
            fs::write(
                &scheme,
                json!({
                    "schema": 2,
                    "name": "dynamic",
                    "origin": "wallpaper",
                    "colours": {"primary": "#123456"}
                })
                .to_string(),
            )
            .unwrap();
            fs::write(config.join("preferences.json"), "{broken").unwrap();
        }
        let original_scheme = fs::read(&scheme).unwrap();
        let original_preferences = fs::read(config.join("preferences.json")).unwrap();
        let bin = home.path().join(".local/bin");
        fs::create_dir_all(&bin).unwrap();
        let apply = bin.join("cortetsu-apply-wallpaper-colors");
        fs::write(
            &apply,
            "#!/bin/sh\nprintf 'applied\\n' >> \"$HOME/applied\"\n",
        )
        .unwrap();
        fs::set_permissions(&apply, fs::Permissions::from_mode(0o755)).unwrap();
        let proc = home.path().join("proc");
        fs::create_dir_all(&proc).unwrap();

        assert!(
            command(&home, "cortetsu-wallpaper-color-daemon", &["--once"])
                .env("XDG_RUNTIME_DIR", home.path().join("runtime"))
                .env("CORTETSU_PROC_ROOT", &proc)
                .status()
                .unwrap()
                .success()
        );
        assert!(!home.path().join("applied").exists(), "{corrupt_file}");
        assert_eq!(fs::read(scheme).unwrap(), original_scheme, "{corrupt_file}");
        assert_eq!(
            fs::read(config.join("preferences.json")).unwrap(),
            original_preferences,
            "{corrupt_file}"
        );
    }
}

#[test]
fn wallpaper_watcher_retries_a_failed_palette_application() {
    let home = TempDir::new().unwrap();
    let state = home.path().join("state/cortetsu");
    let wallpaper = state.join("wallpaper");
    fs::create_dir_all(&wallpaper).unwrap();
    let image = home.path().join("wall.png");
    fs::write(&image, "pixels").unwrap();
    fs::write(wallpaper.join("path.txt"), format!("{}\n", image.display())).unwrap();
    fs::write(
        state.join("scheme.json"),
        json!({
            "schema": 2,
            "name": "dynamic",
            "origin": "wallpaper",
            "colours": {"primary": "#123456"}
        })
        .to_string(),
    )
    .unwrap();
    let config = home.path().join("config/cortetsu");
    fs::create_dir_all(&config).unwrap();
    fs::write(config.join("preferences.json"), r#"{"smartScheme":true}"#).unwrap();
    let bin = home.path().join(".local/bin");
    fs::create_dir_all(&bin).unwrap();
    let apply = bin.join("cortetsu-apply-wallpaper-colors");
    fs::write(
        &apply,
        "#!/bin/sh\ncount=0\n[ ! -f \"$HOME/attempt-count\" ] || count=$(cat \"$HOME/attempt-count\")\ncount=$((count + 1))\nprintf '%s\\n' \"$count\" > \"$HOME/attempt-count\"\n[ \"$count\" -ne 1 ] || exit 1\nprintf 'applied\\n' > \"$HOME/applied\"\n",
    )
    .unwrap();
    fs::set_permissions(&apply, fs::Permissions::from_mode(0o755)).unwrap();
    let proc = home.path().join("proc");
    fs::create_dir_all(&proc).unwrap();
    let runtime = home.path().join("runtime");

    let mut daemon = command(&home, "cortetsu-wallpaper-color-daemon", &["--once"]);
    daemon
        .env("XDG_RUNTIME_DIR", &runtime)
        .env("CORTETSU_PROC_ROOT", &proc);
    assert!(!daemon.status().unwrap().success());
    let failed_state: Value =
        serde_json::from_slice(&fs::read(state.join("scheme.json")).unwrap()).unwrap();
    assert_eq!(failed_state["wallpaperSync"]["status"], "error");

    let mut daemon = command(&home, "cortetsu-wallpaper-color-daemon", &["--once"]);
    daemon
        .env("XDG_RUNTIME_DIR", &runtime)
        .env("CORTETSU_PROC_ROOT", &proc);
    assert!(daemon.status().unwrap().success());

    assert_eq!(
        fs::read_to_string(home.path().join("attempt-count")).unwrap(),
        "2\n"
    );
    assert_eq!(
        fs::read_to_string(home.path().join("applied")).unwrap(),
        "applied\n"
    );
    let applied_state: Value =
        serde_json::from_slice(&fs::read(state.join("scheme.json")).unwrap()).unwrap();
    assert_eq!(applied_state["wallpaperSync"]["status"], "applied");
}

#[test]
fn wallpaper_watcher_does_not_repeat_after_palette_origin_is_written() {
    let home = TempDir::new().unwrap();
    let state = home.path().join("state/cortetsu");
    let wallpaper = state.join("wallpaper");
    fs::create_dir_all(&wallpaper).unwrap();
    let image = home.path().join("wall.png");
    fs::write(&image, "pixels").unwrap();
    fs::write(wallpaper.join("path.txt"), format!("{}\n", image.display())).unwrap();
    let config = home.path().join("config/cortetsu");
    fs::create_dir_all(&config).unwrap();
    fs::write(config.join("preferences.json"), r#"{"smartScheme":true}"#).unwrap();
    let bin = home.path().join(".local/bin");
    fs::create_dir_all(&bin).unwrap();
    let apply = bin.join("cortetsu-apply-wallpaper-colors");
    fs::write(
        &apply,
        "#!/bin/sh\nprintf 'applied\\n' >> \"$HOME/applied\"\nmkdir -p \"$XDG_STATE_HOME/cortetsu\"\nprintf '{\\\"schema\\\":2,\\\"name\\\":\\\"dynamic\\\",\\\"origin\\\":\\\"wallpaper\\\",\\\"colours\\\":{\\\"primary\\\":\\\"#123456\\\"}}\\n' > \"$XDG_STATE_HOME/cortetsu/scheme.json\"\n",
    )
    .unwrap();
    fs::set_permissions(&apply, fs::Permissions::from_mode(0o755)).unwrap();
    let proc = home.path().join("proc");
    fs::create_dir_all(&proc).unwrap();
    let runtime = home.path().join("runtime");

    for _ in 0..2 {
        assert!(
            command(&home, "cortetsu-wallpaper-color-daemon", &["--once"])
                .env("XDG_RUNTIME_DIR", &runtime)
                .env("CORTETSU_PROC_ROOT", &proc)
                .status()
                .unwrap()
                .success()
        );
    }

    assert_eq!(
        fs::read_to_string(home.path().join("applied")).unwrap(),
        "applied\n"
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

#[test]
fn pomodoro_daemon_adopts_a_promoted_helper_on_wake() {
    use std::{
        os::unix::fs::PermissionsExt,
        thread,
        time::{Duration, Instant},
    };
    let home = TempDir::new().unwrap();
    let generation = home.path().join("helpers-new");
    fs::create_dir_all(&generation).unwrap();
    let wrapper = generation.join("cortetsu-pomodoro");
    // The "new" helper records the PID it runs as; exec keeps the daemon's PID.
    fs::write(
        &wrapper,
        "#!/bin/sh\necho $$ > \"$HOME/reexec\"\nexec sleep 30\n",
    )
    .unwrap();
    fs::set_permissions(&wrapper, fs::Permissions::from_mode(0o755)).unwrap();
    fs::create_dir_all(home.path().join(".local/bin")).unwrap();
    let mut daemon = command(&home, "cortetsu-pomodoro", &["daemon"])
        .spawn()
        .unwrap();
    let lock = home.path().join("state/cortetsu/pomodoro-daemon.lock");
    let deadline = Instant::now() + Duration::from_secs(5);
    while fs::read_to_string(&lock)
        .map(|s| s.trim().is_empty())
        .unwrap_or(true)
    {
        assert!(Instant::now() < deadline, "daemon did not start");
        thread::sleep(Duration::from_millis(20));
    }
    std::os::unix::fs::symlink(&wrapper, home.path().join(".local/bin/cortetsu-pomodoro")).unwrap();
    assert!(
        command(&home, "cortetsu-pomodoro", &["wake"])
            .status()
            .unwrap()
            .success()
    );
    let marker = home.path().join("reexec");
    while !marker.exists() {
        if Instant::now() > deadline + Duration::from_secs(5) {
            let _ = daemon.kill();
            panic!("daemon did not re-execute into the promoted helper");
        }
        thread::sleep(Duration::from_millis(20));
    }
    thread::sleep(Duration::from_millis(50));
    let pid: u32 = fs::read_to_string(&marker).unwrap().trim().parse().unwrap();
    assert_eq!(
        pid,
        daemon.id(),
        "re-exec must keep the PID owned by Quickshell"
    );
    let _ = daemon.kill();
    let _ = daemon.wait();
}
