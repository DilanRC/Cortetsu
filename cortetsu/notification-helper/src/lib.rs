//! Native owner for `cortetsu/bin/cortetsu-notifications`.
//!
//! All writes are scoped to the user's XDG state
//! and retain the JSON shapes already watched by services/Notifs.qml.
use fs2::FileExt;
pub mod owner;

#[cfg(test)]
mod pilot;
use serde_json::Value;
#[cfg(test)]
use serde_json::{Map, json};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};

const USAGE: &str = "usage: cortetsu-notifications <count|history|dismiss ID|clear|dnd ACTION>";

#[derive(Debug)]
pub struct Failure {
    pub code: u8,
    pub message: String,
}

impl Failure {
    fn unreadable() -> Self {
        Self {
            code: 65,
            message: "cortetsu-notifications: unreadable history, left untouched".into(),
        }
    }
    fn io() -> Self {
        Self {
            code: 2,
            message: "cortetsu-notifications: I/O error".into(),
        }
    }
    fn usage() -> Self {
        Self {
            code: 64,
            message: USAGE.into(),
        }
    }
}

type Result<T> = std::result::Result<T, Failure>;

pub fn state_home() -> Result<PathBuf> {
    let root = if let Some(value) = std::env::var_os("XDG_STATE_HOME") {
        PathBuf::from(value)
    } else if let Some(home) = std::env::var_os("HOME") {
        PathBuf::from(home).join(".local/state")
    } else {
        return Err(Failure::io());
    };
    if !root.is_absolute() {
        return Err(Failure::io());
    }
    Ok(root)
}

fn history_path(root: &Path) -> PathBuf {
    root.join("cortetsu/notifs.json")
}

fn status_path(root: &Path) -> PathBuf {
    root.join("cortetsu/notification-status.json")
}

fn check_history_path(root: &Path) -> Result<()> {
    for (path, directory) in [(root.join("cortetsu"), true), (history_path(root), false)] {
        match fs::symlink_metadata(path) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
            Ok(meta)
                if !meta.file_type().is_symlink()
                    && if directory {
                        meta.is_dir()
                    } else {
                        meta.is_file()
                    } => {}
            _ => return Err(Failure::unreadable()),
        }
    }
    Ok(())
}

fn load_history(root: &Path) -> Result<Vec<Value>> {
    check_history_path(root)?;
    if owner::clear_state(root)?.1 {
        return Ok(Vec::new());
    }
    let bytes = match fs::read(history_path(root)) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(_) => return Err(Failure::unreadable()),
    };
    let value: Value = serde_json::from_slice(&bytes).map_err(|_| Failure::unreadable())?;
    let Value::Array(items) = value else {
        return Err(Failure::unreadable());
    };
    Ok(items)
}

#[cfg(test)]
fn load_status(root: &Path) -> Map<String, Value> {
    match fs::read(status_path(root))
        .ok()
        .and_then(|b| serde_json::from_slice::<Value>(&b).ok())
    {
        Some(Value::Object(data)) => data,
        _ => Map::new(),
    }
}

fn sync_directory(path: &Path) -> Result<()> {
    File::open(path)
        .and_then(|dir| dir.sync_all())
        .map_err(|_| Failure::io())
}

fn atomic_write(path: &Path, bytes: &[u8]) -> Result<()> {
    let parent = path.parent().ok_or_else(Failure::io)?;
    fs::create_dir_all(parent).map_err(|_| Failure::io())?;
    let file_name = path.file_name().ok_or_else(Failure::io)?;
    let partial = parent.join(format!(
        ".{}.{}.tmp",
        file_name.to_string_lossy(),
        std::process::id()
    ));
    let mut f = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&partial)
        .map_err(|_| Failure::io())?;
    let outcome = (|| {
        f.write_all(bytes)
            .and_then(|_| f.sync_all())
            .map_err(|_| Failure::io())?;
        fs::rename(&partial, path).map_err(|_| Failure::io())?;
        sync_directory(parent)
    })();
    if outcome.is_err() {
        let _ = fs::remove_file(&partial);
    }
    outcome
}

fn lock(root: &Path) -> Result<File> {
    lock_with_timeout(root, std::time::Duration::from_secs(5))
}
fn lock_with_timeout(root: &Path, timeout: std::time::Duration) -> Result<File> {
    let started = std::time::Instant::now();
    let parent = root.join("cortetsu");
    if let Ok(meta) = fs::symlink_metadata(&parent)
        && (!meta.is_dir() || meta.file_type().is_symlink())
    {
        return Err(Failure::io());
    }
    fs::create_dir_all(&parent).map_err(|_| Failure::io())?;
    let path = parent.join("notifications-rs.lock");
    if let Ok(meta) = fs::symlink_metadata(&path)
        && (!meta.is_file() || meta.file_type().is_symlink())
    {
        return Err(Failure::io());
    }
    let file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(path)
        .map_err(|_| Failure::io())?;
    loop {
        match file.try_lock_exclusive() {
            Ok(()) => break,
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                if started.elapsed() >= timeout {
                    return Err(Failure {
                        code: 2,
                        message: "DEADLINE_EXCEEDED".into(),
                    });
                }
                std::thread::sleep(
                    std::time::Duration::from_millis(5)
                        .min(timeout.saturating_sub(started.elapsed())),
                );
            }
            Err(_) => return Err(Failure::io()),
        }
    }
    Ok(file)
}

fn save_history(root: &Path, entries: &[Value]) -> Result<()> {
    check_history_path(root)?;
    let mut bytes = serde_json::to_vec(entries).map_err(|_| Failure::io())?;
    bytes.push(b'\n');
    atomic_write(&history_path(root), &bytes)
}

#[cfg(test)]
fn save_status(root: &Path, data: &Map<String, Value>) -> Result<()> {
    let mut bytes = serde_json::to_vec(data).map_err(|_| Failure::io())?;
    bytes.push(b'\n');
    atomic_write(&status_path(root), &bytes)
}

fn python_string(value: Option<&Value>) -> String {
    match value {
        None | Some(Value::Null) => "None".into(),
        Some(Value::Bool(true)) => "True".into(),
        Some(Value::Bool(false)) => "False".into(),
        Some(Value::String(text)) => text.clone(),
        Some(Value::Number(n)) => n.to_string(),
        Some(Value::Array(_)) => "[]".into(),
        Some(Value::Object(_)) => "{}".into(),
    }
}

fn entry_id(entry: &Value) -> String {
    match entry {
        Value::Object(fields) => {
            python_string(fields.get("notificationId").or_else(|| fields.get("id")))
        }
        _ => "None".into(),
    }
}

/// Equivalent stdout/exit contract to the Python helper, with atomic writes.
/// This function is designed to be tested with a private XDG_STATE_HOME.
pub fn run(args: &[String], root: &Path) -> Result<String> {
    if !root.is_absolute() {
        return Err(Failure::io());
    }
    match args {
        [action] if action == "count" => Ok(load_history(root)?.len().to_string()),
        [action] if action == "history" => {
            serde_json::to_string(&load_history(root)?).map_err(|_| Failure::io())
        }
        [action, id] if action == "dismiss" => {
            let _guard = lock(root)?;
            let mut entries = load_history(root)?;
            entries.retain(|entry| entry_id(entry) != *id);
            save_history(root, &entries)?;
            Ok(entries.len().to_string())
        }
        [action] if action == "clear" => {
            let _guard = lock(root)?;
            owner::clear_locked(root)?;
            Ok("0".into())
        }
        [action, mode] if action == "dnd" && mode == "snapshot" => {
            Ok(owner::snapshot(root)?.to_string())
        }
        [action, mode] if action == "dnd" && mode == "ensure" => {
            owner::ensure(root)?;
            Ok(owner::snapshot(root)?.to_string())
        }
        [action, mode] if action == "dnd" && mode == "recover" => {
            owner::recover(root)?;
            Ok(owner::snapshot(root)?.to_string())
        }
        [
            action,
            mode,
            expected_flag,
            expected,
            key_flag,
            key,
            enabled_flag,
            enabled,
        ] if action == "dnd"
            && mode == "set"
            && expected_flag == "--expected-revision"
            && key_flag == "--idempotency-key"
            && enabled_flag == "--enabled" =>
        {
            let revision = expected.parse::<u64>().map_err(|_| Failure::usage())?;
            let enabled = enabled.parse::<bool>().map_err(|_| Failure::usage())?;
            Ok(owner::set(root, revision, key, enabled)?.to_string())
        }
        [action, mode] if action == "dnd" => {
            if !matches!(mode.as_str(), "status" | "on" | "off" | "toggle") {
                return Err(Failure::usage());
            }
            let state = if mode == "status" {
                owner::snapshot(root)?["dnd"] == true
            } else {
                owner::manual(root, mode)?["dnd"] == true
            };
            Ok(if state { "on".into() } else { "off".into() })
        }
        _ => Err(Failure::usage()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    static N: AtomicU64 = AtomicU64::new(0);
    struct Temp(PathBuf);
    impl Temp {
        fn new() -> Self {
            let p = std::env::temp_dir().join(format!(
                "cortetsu-notif-{}-{}",
                std::process::id(),
                N.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&p).unwrap();
            Self(p)
        }
    }
    impl Drop for Temp {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    fn call(dir: &Path, args: &[&str]) -> Result<String> {
        run(&args.iter().map(|s| s.to_string()).collect::<Vec<_>>(), dir)
    }
    #[test]
    fn missing_history_and_status_are_read_only() {
        let f = Temp::new();
        assert_eq!(call(&f.0, &["count"]).unwrap(), "0");
        assert_eq!(call(&f.0, &["history"]).unwrap(), "[]");
        assert_eq!(call(&f.0, &["dnd", "status"]).unwrap(), "off");
        assert!(!f.0.join("cortetsu").exists());
    }
    #[test]
    fn corrupt_history_remains_untouched() {
        let f = Temp::new();
        fs::create_dir_all(f.0.join("cortetsu")).unwrap();
        fs::write(history_path(&f.0), "{not json").unwrap();
        let before = fs::read(history_path(&f.0)).unwrap();
        assert_eq!(call(&f.0, &["clear"]).unwrap(), "0"); // clear never reads corrupt content (Python parity).
        assert_ne!(fs::read(history_path(&f.0)).unwrap(), before);
        fs::write(history_path(&f.0), "{not json").unwrap();
        let err = call(&f.0, &["count"]).unwrap_err();
        assert_eq!(err.code, 65);
        assert_eq!(fs::read(history_path(&f.0)).unwrap(), before);
    }
    #[test]
    fn dismiss_uses_notification_id_then_id_without_erasing_unknown_fields() {
        let f = Temp::new();
        fs::create_dir_all(f.0.join("cortetsu")).unwrap();
        fs::write(
            history_path(&f.0),
            r#"[{"id":5,"message":"original"},{"id":8,"notificationId":42,"message":"private"}]"#,
        )
        .unwrap();
        assert_eq!(call(&f.0, &["dismiss", "42"]).unwrap(), "1");
        let hist = load_history(&f.0).unwrap();
        assert_eq!(hist.len(), 1);
        assert_eq!(hist[0]["message"], "original");
    }
    #[test]
    fn dnd_preserves_unknown_status_keys() {
        let f = Temp::new();
        assert_eq!(call(&f.0, &["dnd", "on"]).unwrap(), "on");
        let state = load_status(&f.0);
        assert_eq!(state.get("dnd"), Some(&Value::Bool(true)));
        let status = status_path(&f.0);
        let mut object = load_status(&f.0);
        object.insert("version".into(), json!(42));
        save_status(&f.0, &object).unwrap();
        assert_eq!(call(&f.0, &["dnd", "toggle"]).unwrap(), "off");
        assert_eq!(load_status(&f.0)["version"], 42);
        let before = fs::read(&status).unwrap();
        assert_eq!(call(&f.0, &["dnd", "status"]).unwrap(), "off");
        assert_eq!(before, fs::read(&status).unwrap());
    }
    #[test]
    fn invalid_usage_returns_64() {
        let f = Temp::new();
        assert_eq!(call(&f.0, &["dnd", "invalid"]).unwrap_err().code, 64);
        assert_eq!(call(&f.0, &["unknown"]).unwrap_err().code, 64);
    }
}
