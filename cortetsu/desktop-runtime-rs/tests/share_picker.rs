//! End to end against a fake shell: the helper must print exactly one xdph
//! selection line for a valid answer, hand over to the fallback picker when no
//! shell answers, and give up with a non-zero code when nobody chooses.
use std::{
    fs,
    io::{BufRead, BufReader, Write},
    os::unix::{fs::PermissionsExt, net::UnixStream},
    path::Path,
    process::{Command, Output},
    thread,
    time::{Duration, Instant},
};

const LIST: &str = "12[HC>]firefox[HT>]Docs[HE>]94046512345680[HA>]";

fn script(path: &Path, body: &str) {
    fs::write(path, format!("#!/bin/sh\n{body}\n")).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}

fn run(dir: &Path, qs_body: &str, timeout_ms: &str) -> std::process::Child {
    let qs = dir.join("qs");
    script(&qs, qs_body);
    let fallback = dir.join("fallback");
    script(&fallback, "echo '[SELECTION]/screen:FALLBACK'");
    Command::new(env!("CARGO_BIN_EXE_cortetsu-desktop-runtime"))
        .arg("cortetsu-share-picker")
        .env("XDG_RUNTIME_DIR", dir)
        .env("XDPH_WINDOW_SHARING_LIST", LIST)
        .env("CORTETSU_QS_BIN", &qs)
        .env("CORTETSU_SHELL_PATH", dir)
        .env("CORTETSU_SHARE_PICKER_FALLBACK", &fallback)
        .env("CORTETSU_SHARE_PICKER_TIMEOUT_MS", timeout_ms)
        .stdout(std::process::Stdio::piped())
        .spawn()
        .unwrap()
}

/// Waits for the fake qs to record "<socket> <token>" and answers like the shell.
fn answer(dir: &Path, reply: impl Fn(&serde_json::Value) -> String) {
    let args = dir.join("args");
    let start = Instant::now();
    while !args.exists() {
        assert!(start.elapsed() < Duration::from_secs(5), "helper never asked the shell");
        thread::sleep(Duration::from_millis(10));
    }
    let text = fs::read_to_string(&args).unwrap();
    let fields: Vec<_> = text.split_whitespace().collect();
    let (socket, token) = (fields[fields.len() - 2], fields[fields.len() - 1]);
    let mode = fs::metadata(socket).unwrap().permissions().mode() & 0o777;
    assert_eq!(mode, 0o600, "socket must be private");
    let mut stream = UnixStream::connect(socket).unwrap();
    let mut line = String::new();
    BufReader::new(&stream).read_line(&mut line).unwrap();
    let request: serde_json::Value = serde_json::from_str(&line).unwrap();
    assert_eq!(request["token"], token);
    assert_eq!(request["windows"][0]["address"], "5588e8f5f250");
    stream.write_all(reply(&request).as_bytes()).unwrap();
}

fn finish(child: std::process::Child) -> Output {
    child.wait_with_output().unwrap()
}

#[test]
fn prints_one_selection_for_the_shell_answer() {
    let dir = tempfile::tempdir().unwrap();
    let child = run(dir.path(), &format!("echo \"$@\" > {}/args", dir.path().display()), "5000");
    answer(dir.path(), |r| {
        format!("{{\"token\":\"{}\",\"type\":\"window\",\"handle\":12,\"remember\":true}}\n", r["token"].as_str().unwrap())
    });
    let out = finish(child);
    assert!(out.status.success());
    assert_eq!(String::from_utf8_lossy(&out.stdout), "[SELECTION]r/window:12\n");
    let leftovers: Vec<_> = fs::read_dir(dir.path().join("cortetsu")).unwrap().collect();
    assert!(leftovers.is_empty(), "socket must be removed");
}

#[test]
fn cancel_prints_nothing_and_fails() {
    let dir = tempfile::tempdir().unwrap();
    let child = run(dir.path(), &format!("echo \"$@\" > {}/args", dir.path().display()), "5000");
    answer(dir.path(), |r| format!("{{\"token\":\"{}\",\"type\":\"cancel\"}}\n", r["token"].as_str().unwrap()));
    let out = finish(child);
    assert!(!out.status.success());
    assert!(out.stdout.is_empty());
}

#[test]
fn without_a_shell_the_fallback_picker_answers() {
    let dir = tempfile::tempdir().unwrap();
    let out = finish(run(dir.path(), "exit 1", "5000"));
    assert!(out.status.success());
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "[SELECTION]/screen:FALLBACK");
}

#[test]
fn nobody_choosing_times_out() {
    let dir = tempfile::tempdir().unwrap();
    let start = Instant::now();
    let out = finish(run(dir.path(), "exit 0", "300"));
    assert!(!out.status.success());
    assert!(out.stdout.is_empty());
    assert!(start.elapsed() < Duration::from_secs(3));
}

#[test]
fn a_hung_shell_call_falls_back_instead_of_blocking() {
    let dir = tempfile::tempdir().unwrap();
    let start = Instant::now();
    let out = finish(run(dir.path(), "exec sleep 30", "60000"));
    assert!(out.status.success());
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "[SELECTION]/screen:FALLBACK");
    assert!(start.elapsed() < Duration::from_secs(10));
}
