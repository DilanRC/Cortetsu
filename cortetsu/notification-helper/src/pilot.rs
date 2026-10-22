//! Transactional DND pilot confined to a private XDG fixture in F3.
//!
//! This module deliberately has no installed CLI route. Both Notifs.qml and
//! CortetsuNotifications.qml currently write the same status file without a
//! shared lock. Real cutover requires removing that duplicate writer first.
//! The following journal/readback/recovery logic is exercised only by Rust
//! unit tests in a disposable fixture directory.
use super::{Failure, Result, atomic_write, lock, status_path, sync_directory};
use serde_json::{Map, Value, json};
use std::fs;
use std::path::{Path, PathBuf};

const SCHEMA: u32 = 1;
const MAX_STATUS: usize = 16 * 1024;

struct PilotJournal {
    schema: u32,
    domain: String,
    before: Option<Vec<u8>>,
    after: Vec<u8>,
}

fn pilot_journal(root: &Path) -> PathBuf {
    root.join("cortetsu/dnd-pilot-journal.json")
}

fn validate_bytes(raw: &[u8]) -> Result<Map<String, Value>> {
    if raw.len() > MAX_STATUS {
        return Err(Failure::io());
    }
    match serde_json::from_slice::<Value>(raw) {
        Ok(Value::Object(object)) => Ok(object),
        _ => Err(Failure::io()),
    }
}

fn read_before(path: &Path) -> Result<Option<Vec<u8>>> {
    match fs::read(path) {
        Ok(raw) => {
            validate_bytes(&raw)?;
            Ok(Some(raw))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(_) => Err(Failure::io()),
    }
}

fn journal_load(path: &Path) -> Result<PilotJournal> {
    let raw = fs::read(path).map_err(|_| Failure::io())?;
    if raw.len() > MAX_STATUS * 10 {
        return Err(Failure::io());
    }
    let value: Value = serde_json::from_slice(&raw).map_err(|_| Failure::io())?;
    let object = value.as_object().ok_or_else(Failure::io)?;
    if object.len() != 4 || object.get("schema").and_then(Value::as_u64) != Some(SCHEMA as u64)
        || object.get("domain").and_then(Value::as_str) != Some("notifications.dnd") {
        return Err(Failure::io());
    }
    let before = match object.get("before") {
        Some(Value::Null) => None,
        Some(raw) => Some(serde_json::from_value::<Vec<u8>>(raw.clone()).map_err(|_| Failure::io())?),
        None => return Err(Failure::io()),
    };
    let after = serde_json::from_value::<Vec<u8>>(object.get("after").ok_or_else(Failure::io)?.clone())
        .map_err(|_| Failure::io())?;
    let journal = PilotJournal { schema: SCHEMA, domain: "notifications.dnd".into(), before, after };
    validate_bytes(&journal.after)?;
    if let Some(ref previous) = journal.before { validate_bytes(previous)?; }
    Ok(journal)
}

// Single-owner, readback-verified apply in a disposable HOME. The journal is
// synced before writing, and an uncertain result remains recovery-required.
fn apply(root: &Path, enabled: bool, after_write: impl FnOnce()) -> Result<()> {
    let _lock = lock(root)?;
    let state_path = status_path(root);
    let journal_path = pilot_journal(root);
    if fs::symlink_metadata(&journal_path).is_ok() {
        return Err(Failure::io());
    }
    let previous = read_before(&state_path)?;
    let mut state = if let Some(ref raw) = previous {
        validate_bytes(raw)?
    } else {
        Map::new()
    };
    state.insert("dnd".into(), Value::Bool(enabled));
    let mut after = serde_json::to_vec(&state).map_err(|_| Failure::io())?;
    after.push(b'\n');
    let journal = PilotJournal {
        schema: SCHEMA,
        domain: "notifications.dnd".into(),
        before: previous,
        after: after.clone(),
    };
    let mut encoded = serde_json::to_vec(&json!({
        "schema": journal.schema, "domain": journal.domain,
        "before": journal.before, "after": journal.after,
    })).map_err(|_| Failure::io())?;
    encoded.push(b'\n');
    atomic_write(&journal_path, &encoded)?;
    atomic_write(&state_path, &after)?;
    after_write();
    if fs::read(&state_path).map_err(|_| Failure::io())? != after {
        return Err(Failure::io());
    }
    fs::remove_file(&journal_path).map_err(|_| Failure::io())?;
    sync_directory(journal_path.parent().ok_or_else(Failure::io)?)
}

fn recover(root: &Path) -> Result<bool> {
    let _lock = lock(root)?;
    let path = pilot_journal(root);
    let journal = match journal_load(&path) {
        Ok(value) => value,
        Err(_) if !path.exists() => return Ok(false),
        Err(e) => return Err(e),
    };
    let state_path = status_path(root);
    let now = fs::read(&state_path).ok();
    // An unrelated writer may have edited the same XDG file. Refuse to erase
    // its update; preserve the journal and require explicit manual recovery.
    if now.as_deref() != Some(journal.after.as_slice()) && now != journal.before {
        return Err(Failure::io());
    }
    if now.as_deref() == Some(journal.after.as_slice()) {
        if let Some(before) = journal.before {
            atomic_write(&state_path, &before)?;
        } else {
            fs::remove_file(&state_path).map_err(|_| Failure::io())?;
            sync_directory(state_path.parent().ok_or_else(Failure::io)?)?;
        }
    }
    fs::remove_file(&path).map_err(|_| Failure::io())?;
    sync_directory(path.parent().ok_or_else(Failure::io)?)?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    static N: AtomicU64 = AtomicU64::new(0);
    struct Sandbox(PathBuf);
    impl Sandbox {
        fn new() -> Self {
            let temp = std::env::temp_dir().join(format!(
                "cortetsu-dnd-pilot-{}-{}",
                std::process::id(), N.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&temp).unwrap();
            Self(temp)
        }
    }
    impl Drop for Sandbox {
        fn drop(&mut self) { let _ = fs::remove_dir_all(&self.0); }
    }

    #[test]
    fn pilot_readback_preserves_unknown_fields() {
        let sandbox = Sandbox::new();
        fs::create_dir_all(sandbox.0.join("cortetsu")).unwrap();
        let original = br#"{"dnd":false,"custom":"keep"}"#;
        fs::write(status_path(&sandbox.0), original).unwrap();
        apply(&sandbox.0, true, || {}).unwrap();
        let value: Value = serde_json::from_slice(&fs::read(status_path(&sandbox.0)).unwrap()).unwrap();
        assert_eq!(value["dnd"], true);
        assert_eq!(value["custom"], "keep");
        assert!(!pilot_journal(&sandbox.0).exists());
    }

    #[test]
    fn recovers_interrupted_write_without_erasing_previous_bytes() {
        let sandbox = Sandbox::new();
        fs::create_dir_all(sandbox.0.join("cortetsu")).unwrap();
        let before = br#"{"dnd":false,"custom":"unaltered"}"#;
        fs::write(status_path(&sandbox.0), before).unwrap();
        let crash = std::panic::catch_unwind(|| {
            let _ = apply(&sandbox.0, true, || panic!("simulated abrupt termination"));
        });
        assert!(crash.is_err());
        assert!(pilot_journal(&sandbox.0).exists());
        assert!(recover(&sandbox.0).unwrap());
        assert_eq!(fs::read(status_path(&sandbox.0)).unwrap(), before);
        assert!(!pilot_journal(&sandbox.0).exists());
    }

    #[test]
    fn refuses_recovery_that_would_erase_external_writer() {
        let sandbox = Sandbox::new();
        fs::create_dir_all(sandbox.0.join("cortetsu")).unwrap();
        fs::write(status_path(&sandbox.0), br#"{"dnd":false}"#).unwrap();
        let _ = std::panic::catch_unwind(|| {
            let _ = apply(&sandbox.0, true, || panic!("crash"));
        });
        let external = br#"{"dnd":true,"external":999}"#;
        fs::write(status_path(&sandbox.0), external).unwrap();
        assert!(recover(&sandbox.0).is_err());
        assert_eq!(fs::read(status_path(&sandbox.0)).unwrap(), external);
        assert!(pilot_journal(&sandbox.0).exists());
    }

    #[test]
    fn refuses_unreadable_state_without_writing() {
        let sandbox = Sandbox::new();
        fs::create_dir_all(sandbox.0.join("cortetsu")).unwrap();
        fs::write(status_path(&sandbox.0), "{invalid json").unwrap();
        assert!(apply(&sandbox.0, true, || {}).is_err());
        assert!(!pilot_journal(&sandbox.0).exists());
    }
}
