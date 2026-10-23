use serde_json::{Value, json};
use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Output},
};
use tempfile::TempDir;

fn exe(path: &Path, content: &str) {
    fs::write(path, content).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}
fn setup() -> TempDir {
    let t = tempfile::tempdir().unwrap();
    fs::create_dir(t.path().join("bin")).unwrap();
    fs::create_dir(t.path().join("run")).unwrap();
    fs::create_dir_all(t.path().join("sys/class/drm")).unwrap();
    exe(
        &t.path().join("bin/systemctl"),
        "#!/bin/sh\ncase \"$2\" in is-active) echo inactive; exit 3;; is-enabled) echo disabled; exit 1;; esac\n",
    );
    t
}
fn run(t: &TempDir, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_cortetsu-hardware-runtime"))
        .args(args)
        .env("HOME", t.path())
        .env("XDG_CONFIG_HOME", t.path().join(".config"))
        .env("XDG_STATE_HOME", t.path().join(".local/state"))
        .env("XDG_RUNTIME_DIR", t.path().join("run"))
        .env("CORTETSU_SYSFS_ROOT", t.path().join("sys"))
        .env("CORTETSU_DRM_ROOT", t.path().join("sys/class/drm"))
        .env("HYPRLAND_INSTANCE_SIGNATURE", "test")
        .env(
            "PATH",
            format!("{}:/usr/bin:/bin", t.path().join("bin").display()),
        )
        .output()
        .unwrap()
}
fn output(out: Output) -> Value {
    assert!(
        out.status.success(),
        "status={} stderr={} stdout={}",
        out.status,
        String::from_utf8_lossy(&out.stderr),
        String::from_utf8_lossy(&out.stdout)
    );
    serde_json::from_slice(&out.stdout).unwrap()
}
#[test]
fn display_plan_never_writes_and_rejects_unproven_capabilities() {
    let t = setup();
    exe(
        &t.path().join("bin/hyprctl"),
        "#!/bin/sh\ncase \"$*\" in '-j monitors all') echo '[{\"name\":\"eDP-1\",\"width\":1920,\"height\":1080,\"refreshRate\":60,\"scale\":1,\"x\":0,\"y\":0,\"transform\":0,\"availableModes\":[\"1920x1080@60Hz\"],\"currentFormat\":\"XRGB8888\"}]';; '-j workspaces') echo '[]';; *) echo mutation >&2; exit 77;; esac\n",
    );
    let c = json!({"outputs":[{"name":"eDP-1","mode":"1920x1080@60Hz"}]}).to_string();
    let p = output(run(&t, &["cortetsu-display-plan", "--candidate", &c]));
    assert_eq!(p["applied"], false);
    assert_eq!(p["candidate"]["outputs"][0]["cm"], "srgb");
    let c=json!({"outputs":[{"name":"eDP-1","mode":"1920x1080@60Hz","bitdepth":10,"cm":"hdr","vrr":1}]}).to_string();
    let r = run(&t, &["cortetsu-display-plan", "--candidate", &c]);
    assert_eq!(r.status.code(), Some(3));
    let p: Value = serde_json::from_slice(&r.stdout).unwrap();
    assert!(p["errors"].as_array().unwrap().len() >= 3);
    assert_eq!(p["commands"], json!([]));
}
#[test]
fn corrupt_game_journal_is_never_overwritten() {
    let t = setup();
    let path = t.path().join("run/cortetsu-gamemode-test.json");
    fs::write(&path, "{broken").unwrap();
    let p = output(run(&t, &["cortetsu-gamemode", "status"]));
    assert_eq!(p["state"], "UNKNOWN");
    assert!(!run(&t, &["cortetsu-gamemode", "enable"]).status.success());
    assert_eq!(fs::read_to_string(path).unwrap(), "{broken");
}
#[test]
fn nvibrant_status_never_executes_the_writer() {
    let t = setup();
    let d = t.path().join("sys/class/drm");
    fs::create_dir_all(d.join("card1/device")).unwrap();
    fs::write(d.join("card1/device/vendor"), "0x10de\n").unwrap();
    fs::create_dir_all(d.join("card1-HDMI-A-1")).unwrap();
    fs::write(d.join("card1-HDMI-A-1/connector_id"), "80\n").unwrap();
    fs::write(d.join("card1-HDMI-A-1/status"), "connected\n").unwrap();
    exe(
        &t.path().join("bin/nvibrant"),
        "#!/bin/sh\ntouch \"$HOME/writer-called\"\nexit 77\n",
    );
    let p = output(run(&t, &["cortetsu-nvibrant", "status"]));
    assert_eq!(p["outputs"][0]["connector"], "HDMI-A-1");
    assert!(!t.path().join("writer-called").exists());
}
#[test]
fn power_configuration_is_normalized_and_saved() {
    let t = setup();
    let p = output(run(
        &t,
        &["cortetsu-power-auto-control", "set-threshold", "100"],
    ));
    assert_eq!(p["config"]["low_battery_threshold"], 80);
    let p = output(run(
        &t,
        &[
            "cortetsu-power-auto-control",
            "set-profile",
            "battery",
            "power-saver",
        ],
    ));
    assert_eq!(p["config"]["battery_profile"], "power-saver");
    assert!(t.path().join(".config/cortetsu/power-auto.json").exists());
}
#[test]
fn suspended_nvidia_is_reported_without_nvidia_smi() {
    let t = setup();
    let d = t.path().join("sys/bus/pci/devices/0000:01:00.0");
    fs::create_dir_all(d.join("power")).unwrap();
    fs::write(d.join("vendor"), "0x10de\n").unwrap();
    fs::write(d.join("class"), "0x030000\n").unwrap();
    fs::write(d.join("device"), "0x25a2\n").unwrap();
    fs::write(d.join("power/runtime_status"), "suspended\n").unwrap();
    exe(
        &t.path().join("bin/nvidia-smi"),
        "#!/bin/sh\ntouch \"$HOME/gpu-woken\"\nexit 77\n",
    );
    let p = output(run(&t, &["cortetsu-hardware-probe", "--gpus"]));
    assert_eq!(p["gpus"][0]["state"], "suspended");
    assert!(!t.path().join("gpu-woken").exists());
}

fn request(
    t: &TempDir,
    operation: &str,
    args: Value,
    revision: Option<u64>,
    key: Option<&str>,
) -> Value {
    use std::io::Write;
    use std::process::Stdio;
    let mut value = json!({"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"00000000-0000-0000-0000-000000000001","operation":operation,"deadline_ms":5000,"arguments":args});
    if let Some(n) = revision {
        value["expected_revision"] = json!(n)
    }
    if let Some(k) = key {
        value["idempotency_key"] = json!(k)
    }
    let mut child = Command::new(env!("CARGO_BIN_EXE_cortetsu-hardware-runtime"))
        .arg("exec")
        .env("HOME", t.path())
        .env("XDG_CONFIG_HOME", t.path().join(".config"))
        .env("XDG_STATE_HOME", t.path().join(".local/state"))
        .env("XDG_RUNTIME_DIR", t.path().join("run"))
        .env("HYPRLAND_INSTANCE_SIGNATURE", "test")
        .env(
            "PATH",
            format!("{}:/usr/bin:/bin", t.path().join("bin").display()),
        )
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(value.to_string().as_bytes())
        .unwrap();
    let output = child.wait_with_output().unwrap();
    serde_json::from_slice(&output.stdout).unwrap()
}
fn fake_power(t: &TempDir) {
    fs::write(t.path().join("profile"), "balanced\n").unwrap();
    exe(
        &t.path().join("bin/powerprofilesctl"),
        "#!/bin/sh\ncase \"$1\" in get) cat \"$HOME/profile\";; set) echo \"$2\" > \"$HOME/profile\"; echo \"$2\" >> \"$HOME/writes\";; list) echo 'balanced:';echo 'performance:';echo 'power-saver:';; esac\n",
    );
}
#[test]
fn typed_owner_cas_replay_and_manual_override() {
    let t = setup();
    fake_power(&t);
    let s = request(&t, "power.status", json!({}), None, None);
    assert_eq!(s["outcome"], "read");
    let revision = s["body"]["revision"].as_u64().unwrap();
    let key = "00000000-0000-0000-0000-000000000002";
    let p = request(
        &t,
        "power.profile.set",
        json!({"profile":"performance"}),
        Some(revision),
        Some(key),
    );
    assert_eq!(p["outcome"], "applied", "{p}");
    assert!(p.get("error").is_none());
    let duplicate = request(
        &t,
        "power.profile.set",
        json!({"profile":"performance"}),
        Some(revision),
        Some(key),
    );
    assert_eq!(duplicate["outcome"], "applied");
    assert_eq!(
        fs::read_to_string(t.path().join("writes"))
            .unwrap()
            .lines()
            .count(),
        1
    );
    output(run(
        &t,
        &["cortetsu-hardware-power", "set-profile", "power-saver"],
    ));
    let s = request(&t, "power.status", json!({}), None, None);
    assert_eq!(s["body"]["profile"], "power-saver");
    assert!(s["body"]["revision"].as_u64().unwrap() > revision);
    let p = request(
        &t,
        "power.profile.set",
        json!({"profile":"performance"}),
        Some(s["body"]["revision"].as_u64().unwrap()),
        Some("00000000-0000-0000-0000-000000000003"),
    );
    assert_eq!(p["error"]["code"], "USER_CONFIRMATION_REQUIRED");
    assert_eq!(
        fs::read_to_string(t.path().join("profile")).unwrap().trim(),
        "power-saver"
    );
    let replay = request(
        &t,
        "power.profile.set",
        json!({"profile":"performance"}),
        Some(revision),
        Some(key),
    );
    assert_eq!(replay["error"]["code"], "STATE_STALE");
}
#[test]
fn typed_owner_detects_external_edits_before_cas() {
    let t = setup();
    fake_power(&t);
    let s = request(&t, "power.status", json!({}), None, None);
    let revision = s["body"]["revision"].as_u64().unwrap();
    fs::write(t.path().join("profile"), "power-saver\n").unwrap();
    let p = request(
        &t,
        "power.profile.set",
        json!({"profile":"performance"}),
        Some(revision),
        Some("00000000-0000-0000-0000-000000000004"),
    );
    assert_eq!(p["error"]["code"], "STATE_STALE");
    assert!(!t.path().join("writes").exists());
}

#[test]
fn expired_idempotency_record_remains_a_terminal_tombstone() {
    let t = setup();
    fake_power(&t);
    let revision = request(&t, "power.status", json!({}), None, None)["body"]["revision"]
        .as_u64()
        .unwrap();
    let key = "00000000-0000-0000-0000-000000000006";
    let args = json!({"profile":"performance"});
    assert_eq!(
        request(
            &t,
            "power.profile.set",
            args.clone(),
            Some(revision),
            Some(key)
        )["outcome"],
        "applied"
    );
    let path = t
        .path()
        .join(".local/state/cortetsu/hardware-owners/power.json");
    let mut state: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    state["entries"][key]["expires_at_unix_ms"] = json!(1);
    fs::write(&path, state.to_string()).unwrap();
    let replay = request(&t, "power.profile.set", args, Some(revision), Some(key));
    assert_eq!(replay["error"]["code"], "STATE_STALE");
    let state: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    assert_eq!(state["entries"][key]["state"], "COMMITTED");
    assert_eq!(
        fs::read_to_string(t.path().join("writes"))
            .unwrap()
            .lines()
            .count(),
        1
    );
}

#[test]
fn cancellation_terminates_spawned_process_group() {
    use nix::{
        sys::signal::{Signal, kill},
        unistd::Pid,
    };
    use std::{
        thread,
        time::{Duration, Instant},
    };
    let t = setup();
    exe(
        &t.path().join("bin/nvidia-smi"),
        "#!/bin/sh\necho $$ > \"$HOME/child-pid\"\nsleep 30\n",
    );
    let mut child = Command::new(env!("CARGO_BIN_EXE_cortetsu-hardware-runtime"))
        .args(["cortetsu-hardware-probe", "--gpus"])
        .env("HOME", t.path())
        .env("CORTETSU_SYSFS_ROOT", t.path().join("sys"))
        .env(
            "PATH",
            format!("{}:/usr/bin:/bin", t.path().join("bin").display()),
        )
        .spawn()
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(2);
    let path = t.path().join("child-pid");
    while !path.exists() {
        assert!(Instant::now() < deadline);
        thread::sleep(Duration::from_millis(5));
    }
    let pid = fs::read_to_string(path)
        .unwrap()
        .trim()
        .parse::<i32>()
        .unwrap();
    kill(Pid::from_raw(child.id() as i32), Signal::SIGTERM).unwrap();
    let _ = child.wait();
    let proc = fs::read_to_string(format!("/proc/{pid}/stat")).unwrap_or_default();
    assert!(
        proc.is_empty()
            || proc
                .split_once(") ")
                .is_some_and(|(_, s)| s.starts_with('Z')),
        "child still running after cancellation: {proc}"
    );
}

#[test]
fn failed_display_rollback_preserves_the_original_journal() {
    let t = setup();
    exe(
        &t.path().join("bin/hyprctl"),
        "#!/bin/sh\ncase \"$*\" in '-j monitors all') echo '[{\"name\":\"eDP-1\",\"width\":1920,\"height\":1080,\"refreshRate\":60,\"scale\":1,\"x\":0,\"y\":0,\"transform\":0,\"availableModes\":[\"1920x1080@60Hz\"],\"currentFormat\":\"XRGB8888\"}]';; '-j workspaces') echo '[]';; *) echo 'injected failure' >&2;exit 1;; esac\n",
    );
    let candidate = json!({"outputs":[{"name":"eDP-1","mode":"1920x1080@60Hz"}]}).to_string();
    let result = run(
        &t,
        &[
            "cortetsu-display-transaction",
            "preview",
            "--candidate",
            &candidate,
            "--timeout",
            "8",
        ],
    );
    assert!(!result.status.success());
    let p: Value = serde_json::from_slice(&result.stdout).unwrap();
    assert_eq!(p["reverted"], false);
    assert_eq!(p["recovery_required"], true);
    let state: Value = serde_json::from_slice(
        &fs::read(t.path().join("run/cortetsu-display-preview.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(state["original"]["outputs"][0]["name"], "eDP-1");
    assert_eq!(state["active"], true);
}
#[test]
fn typed_failure_after_side_effect_never_reexecutes() {
    let t = setup();
    fake_power(&t);
    let s = request(&t, "power.status", json!({}), None, None);
    let revision = s["body"]["revision"].as_u64().unwrap();
    exe(
        &t.path().join("bin/powerprofilesctl"),
        "#!/bin/sh\ncase \"$1\" in get) cat \"$HOME/profile\";; set) echo \"$2\" > \"$HOME/profile\";echo called >> \"$HOME/writes\";exit 1;; esac\n",
    );
    let key = "00000000-0000-0000-0000-000000000005";
    for _ in 0..2 {
        let p = request(
            &t,
            "power.profile.set",
            json!({"profile":"performance"}),
            Some(revision),
            Some(key),
        );
        assert_eq!(p["error"]["code"], "RECOVERY_REQUIRED");
    }
    assert_eq!(
        fs::read_to_string(t.path().join("writes"))
            .unwrap()
            .lines()
            .count(),
        1
    );
    let current = request(&t, "power.status", json!({}), None, None)["body"]["revision"]
        .as_u64()
        .unwrap();
    let fresh = request(
        &t,
        "power.profile.set",
        json!({"profile":"balanced"}),
        Some(current),
        Some("00000000-0000-0000-0000-000000000099"),
    );
    assert_eq!(
        fresh["error"]["code"], "RECOVERY_REQUIRED",
        "a new key cannot bypass an unresolved transaction"
    );
    fake_power(&t);
    output(run(
        &t,
        &["cortetsu-hardware-power", "set-profile", "balanced"],
    ));
    let state: Value = serde_json::from_slice(
        &fs::read(
            t.path()
                .join(".local/state/cortetsu/hardware-owners/power.json"),
        )
        .unwrap(),
    )
    .unwrap();
    assert_eq!(state["entries"][key]["state"], "RECONCILED_MANUAL");
}
#[test]
fn native_power_loop_keeps_manual_changes_until_rule_transition() {
    use std::{
        process::Stdio,
        thread,
        time::{Duration, Instant},
    };
    let t = setup();
    fake_power(&t);
    let ac = t.path().join("sys/class/power_supply/AC");
    fs::create_dir_all(&ac).unwrap();
    fs::write(ac.join("type"), "Mains\n").unwrap();
    fs::write(ac.join("online"), "1\n").unwrap();
    let conf = t.path().join(".config/cortetsu");
    fs::create_dir_all(&conf).unwrap();
    fs::write(conf.join("power-auto.json"),json!({"enabled":true,"ac_profile":"performance","battery_profile":"balanced","poll_seconds":2}).to_string()).unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_cortetsu-hardware-runtime"))
        .arg("cortetsu-power-auto")
        .env("HOME", t.path())
        .env("XDG_STATE_HOME", t.path().join(".local/state"))
        .env("XDG_RUNTIME_DIR", t.path().join("run"))
        .env("CORTETSU_SYSFS_ROOT", t.path().join("sys"))
        .env(
            "PATH",
            format!("{}:/usr/bin:/bin", t.path().join("bin").display()),
        )
        .stdout(Stdio::null())
        .spawn()
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(3);
    while !t
        .path()
        .join(".local/state/cortetsu/hardware-owners/power.json")
        .exists()
    {
        assert!(Instant::now() < deadline);
        thread::sleep(Duration::from_millis(10));
    }
    assert_eq!(
        fs::read_to_string(t.path().join("profile")).unwrap().trim(),
        "performance"
    );
    fs::write(t.path().join("profile"), "power-saver\n").unwrap();
    thread::sleep(Duration::from_millis(2200));
    assert_eq!(
        fs::read_to_string(t.path().join("profile")).unwrap().trim(),
        "power-saver"
    );
    assert_eq!(
        fs::read_to_string(t.path().join("writes"))
            .unwrap()
            .lines()
            .count(),
        1
    );
    fs::write(ac.join("online"), "0\n").unwrap();
    let deadline = Instant::now() + Duration::from_secs(3);
    while fs::read_to_string(t.path().join("profile")).unwrap().trim() != "balanced" {
        assert!(Instant::now() < deadline);
        thread::sleep(Duration::from_millis(10));
    }
    nix::sys::signal::kill(
        nix::unistd::Pid::from_raw(child.id() as i32),
        nix::sys::signal::Signal::SIGTERM,
    )
    .unwrap();
    child.wait().unwrap();
}

#[test]
fn display_preview_rejects_ignored_mode_and_transform() {
    let t = setup();
    exe(
        &t.path().join("bin/hyprctl"),
        "#!/bin/sh\ncase \"$*\" in '-j monitors all') echo '[{\"name\":\"eDP-1\",\"width\":1280,\"height\":720,\"refreshRate\":60,\"scale\":1,\"x\":0,\"y\":0,\"transform\":0,\"availableModes\":[\"1280x720@60Hz\",\"1920x1080@60Hz\"],\"currentFormat\":\"XRGB8888\"}]';; '-j workspaces') echo '[]';; *) echo ok;; esac\n",
    );
    let candidate =
        json!({"outputs":[{"name":"eDP-1","mode":"1920x1080@60Hz","transform":2}]}).to_string();
    let response = run(
        &t,
        &[
            "cortetsu-display-transaction",
            "preview",
            "--candidate",
            &candidate,
        ],
    );
    assert!(
        !response.status.success(),
        "a zero exit code from hyprctl cannot verify a mode change"
    );
    let value: Value = serde_json::from_slice(&response.stdout).unwrap();
    assert_eq!(value["ok"], false);
    assert_eq!(value["reverted"], true);
}
#[test]
fn rollback_refuses_to_overwrite_external_monitor_changes() {
    let t = setup();
    exe(
        &t.path().join("bin/hyprctl"),
        "#!/bin/sh\ncase \"$*\" in '-j monitors all') echo '[{\"name\":\"eDP-1\",\"width\":1920,\"height\":1080,\"refreshRate\":60,\"scale\":1,\"x\":200,\"y\":0,\"transform\":0,\"availableModes\":[\"1920x1080@60Hz\"],\"currentFormat\":\"XRGB8888\"}]';; '-j workspaces') echo '[]';; *) touch \"$HOME/overwritten\";echo ok;; esac\n",
    );
    let original = json!({"outputs":[{"name":"eDP-1","enabled":true,"mode":"1920x1080@60Hz","x":0,"y":0,"scale":1,"transform":0,"bitdepth":8,"cm":"srgb","vrr":0}]});
    let mut candidate = original.clone();
    candidate["outputs"][0]["x"] = json!(100);
    fs::write(t.path().join("run/cortetsu-display-preview.json"), json!({"active":true,"token":"fixture","instance":"test","deadline":0,"original":original,"candidate":candidate}).to_string()).unwrap();
    let response = run(&t, &["cortetsu-display-transaction", "revert"]);
    assert!(!response.status.success());
    assert!(
        !t.path().join("overwritten").exists(),
        "rollback must not erase an external position change"
    );
    assert!(t.path().join("run/cortetsu-display-preview.json").exists());
}

#[test]
fn rollback_preserves_external_color_policy_even_with_unchanged_config() {
    let t = setup();
    exe(
        &t.path().join("bin/hyprctl"),
        "#!/bin/sh\ncase \"$*\" in '-j monitors all') echo '[{\"name\":\"eDP-1\",\"width\":1920,\"height\":1080,\"refreshRate\":60,\"scale\":1,\"x\":0,\"y\":0,\"transform\":0,\"availableModes\":[\"1920x1080@60Hz\"],\"currentFormat\":\"XRGB8888\",\"colorManagementPreset\":\"wide\"}]';; '-j workspaces') echo '[]';; *) touch \"$HOME/overwritten\";echo ok;; esac\n",
    );
    let original = json!({"outputs":[{"name":"eDP-1","enabled":true,"mode":"1920x1080@60Hz","x":0,"y":0,"scale":1.0,"transform":0,"bitdepth":8,"cm":"srgb","vrr":0,"observed_cm":"srgb","observed_bitdepth":8,"observed_vrr":false}]});
    let mut applied = original.clone();
    applied["outputs"][0]["cm"] = json!("dcip3");
    applied["outputs"][0]["observed_cm"] = json!("dcip3");
    fs::write(t.path().join("run/cortetsu-display-preview.json"), json!({"active":true,"token":"fixture","instance":"test","deadline":0,"original":original,"candidate":applied,"applied":applied}).to_string()).unwrap();
    let response = run(&t, &["cortetsu-display-transaction", "revert"]);
    assert!(!response.status.success());
    assert!(
        !t.path().join("overwritten").exists(),
        "rollback cannot overwrite color changed directly through the compositor"
    );
    let journal: Value = serde_json::from_slice(
        &fs::read(t.path().join("run/cortetsu-display-preview.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(journal["recovery_required"], true);
}
#[test]
fn cpu_temp_reads_only_the_cpu_sensor_like_the_hardware_center() {
    let t = setup();
    let hwmon = |n: &str, name: &str, temps: &[(&str, &str)]| {
        let d = t.path().join("sys/class/hwmon").join(n);
        fs::create_dir_all(&d).unwrap();
        fs::write(d.join("name"), format!("{name}\n")).unwrap();
        for (file, v) in temps {
            fs::write(d.join(file), v).unwrap();
        }
    };
    // The ACPI zone is hotter here; the dashboard used to show it as "CPU".
    hwmon("hwmon0", "acpitz", &[("temp1_input", "88000\n")]);
    hwmon(
        "hwmon1",
        "k10temp",
        &[("temp1_input", "54250\n"), ("temp3_input", "51000\n")],
    );
    assert_eq!(
        output(run(&t, &["cortetsu-hardware-probe", "--cpu-temp"])),
        json!({"temp_c": 54.3})
    );
    fs::remove_dir_all(t.path().join("sys/class/hwmon/hwmon1")).unwrap();
    assert_eq!(
        output(run(&t, &["cortetsu-hardware-probe", "--cpu-temp"])),
        json!({"temp_c": null})
    );
}
