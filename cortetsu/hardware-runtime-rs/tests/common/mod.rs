// Shared by the integration test files: each spawns the native binary in
// a temporary HOME whose bin/ shadows the system tools it calls.
#![allow(dead_code)]
use serde_json::Value;
use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Output},
};
use tempfile::TempDir;

pub fn exe(path: &Path, content: &str) {
    fs::write(path, content).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}
pub fn setup() -> TempDir {
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
pub fn run(t: &TempDir, args: &[&str]) -> Output {
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
pub fn output(out: Output) -> Value {
    assert!(
        out.status.success(),
        "status={} stderr={} stdout={}",
        out.status,
        String::from_utf8_lossy(&out.stderr),
        String::from_utf8_lossy(&out.stdout)
    );
    serde_json::from_slice(&out.stdout).unwrap()
}
