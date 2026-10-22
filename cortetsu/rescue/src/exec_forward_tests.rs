use super::*;
use std::{
    fs,
    os::unix::fs::{PermissionsExt, symlink},
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
    time::{Duration, Instant},
};
static COUNTER: AtomicU64 = AtomicU64::new(0);
struct Fixture(PathBuf);
impl Fixture {
    fn new(script: &str) -> Self {
        let dir = std::env::temp_dir().join(format!(
            "cortetsu-exec-forward-{}-{}-{}",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::SeqCst),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        let executable = dir.join("owner");
        fs::write(&executable, format!("#!/bin/sh\n{script}\n")).unwrap();
        fs::set_permissions(&executable, fs::Permissions::from_mode(0o700)).unwrap();
        Self(dir)
    }
    fn forward(&self, millis: u32) -> Value {
        let input = json!({"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"00000000-0000-0000-0000-000000000001","operation":"power.status","deadline_ms":millis,"arguments":{}}).to_string();
        let request: Request = serde_json::from_str(&input).unwrap();
        forward_owner(
            &self.0.join("owner"),
            input.as_bytes(),
            &request,
            Instant::now(),
        )
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn reply() -> Value {
    json!({"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"00000000-0000-0000-0000-000000000001","outcome":"read","verified":true,"body":{"revision":0,"manual_override_until_unix_ms":0,"profile":"balanced"}})
}
fn echoed(value: &Value) -> Fixture {
    Fixture::new(&format!("cat >/dev/null\nprintf '%s\\n' '{}'", value))
}
#[test]
fn forwards_only_verified_matching_response_shape() {
    assert_eq!(echoed(&reply()).forward(1000), reply());
    let mut wrong = reply();
    wrong["outcome"] = json!("applied");
    assert_eq!(
        echoed(&wrong).forward(1000)["error"]["code"],
        "APPLY_VERIFICATION_FAILED"
    );
    let mut wrong = reply();
    wrong["surprise"] = json!(true);
    assert_eq!(
        echoed(&wrong).forward(1000)["error"]["code"],
        "APPLY_VERIFICATION_FAILED"
    );
    let mut wrong = reply();
    wrong["body"].as_object_mut().unwrap().remove("revision");
    assert_eq!(
        echoed(&wrong).forward(1000)["error"]["code"],
        "APPLY_VERIFICATION_FAILED"
    );
    let mut wrong = reply();
    wrong["body"]["revision"] = json!(9_007_199_254_740_992_u64);
    assert_eq!(
        echoed(&wrong).forward(1000)["error"]["code"],
        "APPLY_VERIFICATION_FAILED"
    );
    let mut wrong = reply();
    wrong["error"] = Value::Null;
    assert_eq!(
        echoed(&wrong).forward(1000)["error"]["code"],
        "APPLY_VERIFICATION_FAILED"
    );
}
#[test]
fn inherited_stdout_cannot_outlive_owner_deadline() {
    let fixture = Fixture::new(&format!(
        "cat >/dev/null\nprintf '%s\\n' '{}'\nsleep 10 &\nexit 0",
        reply()
    ));
    let start = Instant::now();
    assert_eq!(fixture.forward(500), reply());
    assert!(start.elapsed() < Duration::from_millis(500));
}
#[test]
fn timeout_allows_term_cleanup_then_reaps_the_owner() {
    let fixture = Fixture::new(
        r#"trap 'touch "$(dirname "$0")/cleaned"; exit 0' TERM
while :; do sleep 1; done"#,
    );
    let marker = fixture.0.join("cleaned");
    let start = Instant::now();
    assert_eq!(fixture.forward(60)["error"]["code"], "DEADLINE_EXCEEDED");
    assert!(
        marker.exists(),
        "SIGTERM must give the owner a chance to reap its external process groups"
    );
    assert!(start.elapsed() < Duration::from_millis(400));
}
#[test]
fn overlong_response_is_bounded_and_untrusted_executable_refused() {
    let fixture = Fixture::new("dd if=/dev/zero bs=65537 count=1 2>/dev/null");
    assert_eq!(
        fixture.forward(500)["error"]["code"],
        "APPLY_VERIFICATION_FAILED"
    );
    fs::set_permissions(fixture.0.join("owner"), fs::Permissions::from_mode(0o777)).unwrap();
    assert_eq!(fixture.forward(500)["error"]["code"], "OWNER_UNAVAILABLE");
    fs::remove_file(fixture.0.join("owner")).unwrap();
    symlink("/bin/sh", fixture.0.join("owner")).unwrap();
    assert_eq!(fixture.forward(500)["error"]["code"], "OWNER_UNAVAILABLE");
}
#[test]
fn invalid_error_shape_never_escapes_and_manual_override_code_survives() {
    let mut denied = reply();
    denied["verified"] = json!(false);
    denied["outcome"] = json!("rejected");
    denied["body"] = json!({});
    denied["error"] = json!({"code":"USER_CONFIRMATION_REQUIRED","retryable":false});
    assert_eq!(
        echoed(&denied).forward(1000)["error"]["code"],
        "USER_CONFIRMATION_REQUIRED"
    );
    denied["error"]["details"] = json!("secret");
    assert_eq!(
        echoed(&denied).forward(1000)["error"]["code"],
        "APPLY_VERIFICATION_FAILED"
    );
}

#[test]
fn signal_forwarding_child() {
    let Some(binary) = std::env::var_os("CORTETSU_TEST_FORWARD_OWNER") else {
        return;
    };
    let input = json!({"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"00000000-0000-0000-0000-000000000001","operation":"power.status","deadline_ms":5000,"arguments":{}}).to_string();
    let request: Request = serde_json::from_str(&input).unwrap();
    let response = forward_owner(
        std::path::Path::new(&binary),
        input.as_bytes(),
        &request,
        Instant::now(),
    );
    assert_eq!(response["error"]["code"], "DEADLINE_EXCEEDED");
}

#[test]
fn cancellation_signal_reaches_the_separate_owner_process_group() {
    use nix::{
        sys::signal::{Signal, kill, killpg},
        unistd::Pid,
    };
    let fixture = Fixture::new(
        r#"trap 'touch "$(dirname "$0")/cleaned"; exit 0' TERM
echo $$ > "$(dirname "$0")/ready"
while :; do sleep 1; done"#,
    );
    let mut child = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "exec_read::forward_tests::signal_forwarding_child",
            "--nocapture",
        ])
        .env("CORTETSU_TEST_FORWARD_OWNER", fixture.0.join("owner"))
        .stdout(std::process::Stdio::null())
        .spawn()
        .unwrap();
    let ready = fixture.0.join("ready");
    let end = Instant::now() + Duration::from_secs(2);
    while !ready.exists() {
        assert!(Instant::now() < end, "forwarding child did not start");
        std::thread::sleep(Duration::from_millis(5));
    }
    let owner = fs::read_to_string(ready)
        .unwrap()
        .trim()
        .parse::<i32>()
        .unwrap();
    kill(Pid::from_raw(child.id() as i32), Signal::SIGTERM).unwrap();
    let end = Instant::now() + Duration::from_secs(1);
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            break status;
        }
        if Instant::now() >= end {
            let _ = child.kill();
            break child.wait().unwrap();
        }
        std::thread::sleep(Duration::from_millis(5));
    };
    let _ = killpg(Pid::from_raw(owner), Signal::SIGKILL);
    assert!(
        status.success(),
        "the forwarding adapter did not handle cancellation"
    );
    assert!(
        fixture.0.join("cleaned").exists(),
        "owner cleanup was skipped"
    );
}
