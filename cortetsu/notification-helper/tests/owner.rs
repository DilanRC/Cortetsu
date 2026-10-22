use serde_json::{Value, json};
use std::{
    fs,
    path::PathBuf,
    process::{Command, Output},
    sync::atomic::{AtomicU64, Ordering},
};

static NEXT: AtomicU64 = AtomicU64::new(0);
const KEY: &str = "00000000-0000-4000-8000-000000000001";
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "cortetsu-owner-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&path).unwrap();
        Self(path)
    }
    fn call(&self, args: &[&str]) -> Output {
        Command::new(env!("CARGO_BIN_EXE_cortetsu-notifications-rs"))
            .env("XDG_STATE_HOME", &self.0)
            .args(args)
            .output()
            .unwrap()
    }
    fn state(&self) -> Value {
        let out = self.call(&["dnd", "snapshot"]);
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        serde_json::from_slice(&out.stdout).unwrap()
    }
    fn set(&self, revision: &str, key: &str, enabled: &str) -> Output {
        self.call(&[
            "dnd",
            "set",
            "--expected-revision",
            revision,
            "--idempotency-key",
            key,
            "--enabled",
            enabled,
        ])
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[test]
fn owner_uses_cas_and_idempotent_live_readback() {
    let f = Fixture::new();
    assert_eq!(f.state(), json!({"dnd": false, "revision": 0}));
    assert!(!f.0.join("cortetsu").exists(), "snapshot must be read only");
    let first = f.set("0", KEY, "true");
    assert!(
        first.status.success(),
        "{}",
        String::from_utf8_lossy(&first.stderr)
    );
    assert_eq!(f.state(), json!({"dnd": true, "revision": 1}));
    assert!(
        f.set("0", KEY, "true").status.success(),
        "same request is a readback, not a second write"
    );
    assert_eq!(f.state()["revision"], 1);
    let stale = f.set("0", "00000000-0000-4000-8000-000000000002", "false");
    assert!(!stale.status.success());
    assert!(String::from_utf8_lossy(&stale.stderr).contains("STATE_STALE"));
    assert!(!f.set("0", KEY, "false").status.success());
    assert_eq!(f.state()["dnd"], true);
    assert!(f.call(&["dnd", "off"]).status.success());
    assert_eq!(f.state()["revision"], 2);
    assert!(
        !f.set("0", KEY, "true").status.success(),
        "replay must not claim success after manual change"
    );
    assert_eq!(f.state()["dnd"], false);
}

#[test]
fn corrupt_and_symlink_status_are_never_replaced() {
    let f = Fixture::new();
    let dir = f.0.join("cortetsu");
    fs::create_dir(&dir).unwrap();
    let path = dir.join("notification-status.json");
    fs::write(&path, "{broken").unwrap();
    assert!(!f.call(&["dnd", "on"]).status.success());
    assert_eq!(fs::read_to_string(&path).unwrap(), "{broken");
    fs::remove_file(&path).unwrap();
    let outside = f.0.join("outside.json");
    fs::write(&outside, "{}").unwrap();
    std::os::unix::fs::symlink(&outside, &path).unwrap();
    assert!(!f.call(&["dnd", "on"]).status.success());
    assert_eq!(fs::read_to_string(outside).unwrap(), "{}");
}

#[test]
fn merge_never_resurrects_a_concurrent_cli_dismissal() {
    use std::io::Write;
    let f = Fixture::new();
    let dir = f.0.join("cortetsu");
    fs::create_dir(&dir).unwrap();
    fs::write(
        dir.join("notifs.json"),
        r#"[{"id":"old","summary":"private"}]"#,
    )
    .unwrap();
    assert!(f.call(&["dismiss", "old"]).status.success());
    let mut child = Command::new(env!("CARGO_BIN_EXE_cortetsu-notifications-rs"))
        .env("XDG_STATE_HOME", &f.0)
        .arg("merge")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(br#"{"base_ids":["old"],"entries":[{"id":"old"},{"id":"new"}]}"#)
        .unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(out.status.success());
    let state: Value = serde_json::from_slice(&fs::read(dir.join("notifs.json")).unwrap()).unwrap();
    assert_eq!(state, json!([{"id":"new"}]));
}

#[test]
fn manual_and_external_changes_block_automation() {
    let f = Fixture::new();
    assert!(f.call(&["dnd", "on"]).status.success());
    let s = f.state();
    assert!(s["manual_override_until_unix_ms"].as_u64().unwrap_or(0) > 0);
    let blocked = f.set("1", KEY, "false");
    assert!(String::from_utf8_lossy(&blocked.stderr).contains("USER_CONFIRMATION_REQUIRED"));
    let mut external: Value =
        serde_json::from_slice(&fs::read(f.0.join("cortetsu/notification-status.json")).unwrap())
            .unwrap();
    external["dnd"] = json!(false);
    fs::write(
        f.0.join("cortetsu/notification-status.json"),
        serde_json::to_vec(&external).unwrap(),
    )
    .unwrap();
    let observed = f.state();
    assert_eq!(observed["revision"], 2);
    assert_eq!(observed["dnd"], false);
    assert_eq!(
        f.state()["revision"],
        2,
        "stable reads must not increment revision"
    );
}

#[test]
fn clear_token_rejects_unsaved_batches_and_recovers_interrupted_clear() {
    let f = Fixture::new();
    let dir = f.0.join("cortetsu");
    fs::create_dir(&dir).unwrap();
    fs::write(dir.join("notifs.json"), r#"[{"id":"old"}]"#).unwrap();
    assert!(f.call(&["clear"]).status.success());
    let token: Value =
        serde_json::from_slice(&fs::read(dir.join("notifs-clear.json")).unwrap()).unwrap();
    assert_eq!(token, json!({"revision":1,"pending":false}));
    let delayed =
        br#"{"base_ids":[],"entries":[{"id":"unsaved-before-clear"}],"clear_revision":0}"#;
    assert_eq!(
        cortetsu_notifications_rs::owner::merge(&f.0, delayed).unwrap(),
        json!([])
    );
    let after = br#"{"base_ids":[],"entries":[{"id":"after-clear"}],"clear_revision":1}"#;
    assert_eq!(
        cortetsu_notifications_rs::owner::merge(&f.0, after).unwrap(),
        json!([{"id":"after-clear"}])
    );
    // The durable token is written before history. A crash in between must
    // never make pre-clear history visible or admit an old pending batch.
    fs::write(
        dir.join("notifs-clear.json"),
        r#"{"revision":2,"pending":true}"#,
    )
    .unwrap();
    assert_eq!(
        String::from_utf8(f.call(&["history"]).stdout)
            .unwrap()
            .trim(),
        "[]"
    );
    assert_eq!(
        cortetsu_notifications_rs::owner::merge(&f.0, after).unwrap(),
        json!([])
    );
    let token: Value =
        serde_json::from_slice(&fs::read(dir.join("notifs-clear.json")).unwrap()).unwrap();
    assert_eq!(token, json!({"revision":2,"pending":false}));
    assert_eq!(
        fs::read_to_string(dir.join("notifs.json")).unwrap().trim(),
        "[]"
    );
}

#[test]
fn committed_recovery_repairs_observation_before_replay() {
    let f = Fixture::new();
    assert!(f.call(&["dnd", "ensure"]).status.success());
    let dir = f.0.join("cortetsu");
    let before_anchor = fs::read(dir.join("dnd-observed.json")).unwrap();
    assert!(f.set("0", KEY, "true").status.success());
    let mut journal: Value = serde_json::from_slice(
        &fs::read(dir.join("dnd-requests").join(format!("{KEY}.json"))).unwrap(),
    )
    .unwrap();
    journal["phase"] = json!("PREPARED");
    fs::write(dir.join("dnd-journal.json"), journal.to_string()).unwrap();
    fs::write(dir.join("dnd-observed.json"), before_anchor).unwrap();
    assert_eq!(f.state(), json!({"dnd":true,"revision":1}));
    assert!(
        f.set("0", KEY, "true").status.success(),
        "committed retry is a readback"
    );
    assert!(!dir.join("dnd-journal.json").exists());
}

#[test]
fn ensure_recovers_pending_intent_before_observing_it() {
    let f = Fixture::new();
    let dir = f.0.join("cortetsu");
    fs::create_dir(&dir).unwrap();
    let after = br#"{"dnd":true,"revision":1}"#;
    fs::write(dir.join("notification-status.json"), after).unwrap();
    fs::write(
        dir.join("dnd-journal.json"),
        json!({
            "schema":1,"key":KEY,"phase":"PREPARED","expected":0,"enabled":true,
            "before":null,"after":after,"expires":4_000_000_000_u64,
        })
        .to_string(),
    )
    .unwrap();
    let ensured = f.call(&["dnd", "ensure"]);
    assert!(
        ensured.status.success(),
        "{}",
        String::from_utf8_lossy(&ensured.stderr)
    );
    assert_eq!(f.state(), json!({"dnd":false,"revision":0}));
    assert!(!f.set("0", KEY, "true").status.success());
}

#[test]
fn full_automation_ledger_cannot_block_manual_choice() {
    use std::os::unix::fs::PermissionsExt;
    let f = Fixture::new();
    let dir = f.0.join("cortetsu/dnd-requests");
    fs::create_dir_all(&dir).unwrap();
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o700)).unwrap();
    for n in 0..4096 {
        fs::write(dir.join(format!("receipt-{n}.json")), b"{}").unwrap();
    }
    let result = f.call(&["dnd", "on"]);
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    assert_eq!(f.state()["dnd"], true);
    assert_eq!(fs::read_dir(dir).unwrap().count(), 4096);
}

#[test]
fn history_symlink_is_not_read_replaced_or_marked_cleared() {
    let f = Fixture::new();
    let dir = f.0.join("cortetsu");
    fs::create_dir(&dir).unwrap();
    let outside = f.0.join("outside.json");
    let original = br#"[{"id":"owned-elsewhere"}]"#;
    fs::write(&outside, original).unwrap();
    let history = dir.join("notifs.json");
    std::os::unix::fs::symlink(&outside, &history).unwrap();
    for args in [
        &["history"][..],
        &["dismiss", "owned-elsewhere"],
        &["clear"],
    ] {
        assert!(
            !f.call(args).status.success(),
            "symlink accepted for {args:?}"
        );
        assert_eq!(fs::read_link(&history).unwrap(), outside);
        assert!(!dir.join("notifs-clear.json").exists());
        assert_eq!(fs::read(&outside).unwrap(), original);
    }
}

#[test]
fn ensure_initializes_clear_watcher_without_overwriting_invalid_token() {
    let f = Fixture::new();
    assert!(f.call(&["dnd", "ensure"]).status.success());
    let token = f.0.join("cortetsu/notifs-clear.json");
    assert_eq!(
        serde_json::from_slice::<Value>(&fs::read(&token).unwrap()).unwrap(),
        json!({"revision":0,"pending":false})
    );
    fs::write(&token, b"{broken").unwrap();
    assert!(!f.call(&["dnd", "ensure"]).status.success());
    assert_eq!(fs::read(&token).unwrap(), b"{broken");
}
