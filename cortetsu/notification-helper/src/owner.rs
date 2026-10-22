//! Single DND owner. All writers (CLI, QML and Go) share the same lock,
//! durable intent, revision compare-and-swap and live readback.
use super::{
    Failure, Result, atomic_write, history_path, load_history, lock, lock_with_timeout,
    save_history, status_path, sync_directory,
};
use serde_json::{Value, json};
use std::{
    fs,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

const MAX_REVISION: u64 = 9_007_199_254_740_991;
const MAX_STATE: u64 = 16 * 1024;
const MAX_RECORDS: usize = 4096;
const RETENTION_SECS: u64 = 7 * 86400;

fn fail(code: &str) -> Failure {
    Failure {
        code: 2,
        message: code.into(),
    }
}
fn uuid(s: &str) -> bool {
    s.len() == 36
        && s.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_hexdigit()
            }
        })
}
fn now() -> Result<u64> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .map_err(|_| fail("INTERNAL_REDACTED"))
}
fn read_optional(path: &Path, limit: u64) -> Result<Option<Vec<u8>>> {
    let meta = match fs::symlink_metadata(path) {
        Ok(m) => m,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err(fail("OWNER_UNAVAILABLE")),
    };
    if !meta.is_file() || meta.file_type().is_symlink() || meta.len() > limit {
        return Err(fail("OWNER_UNAVAILABLE"));
    }
    fs::read(path)
        .map(Some)
        .map_err(|_| fail("OWNER_UNAVAILABLE"))
}
fn decode(bytes: Option<&[u8]>) -> Result<Value> {
    let state = match bytes {
        None => json!({"dnd":false,"revision":0}),
        Some(b) => serde_json::from_slice::<Value>(b).map_err(|_| fail("OWNER_UNAVAILABLE"))?,
    };
    if !state.is_object()
        || state.get("dnd").is_some_and(|v| !v.is_boolean())
        || state
            .get("revision")
            .is_some_and(|v| v.as_u64().is_none_or(|r| r > MAX_REVISION))
        || state
            .get("manual_override_until_unix_ms")
            .is_some_and(|v| v.as_u64().is_none_or(|r| r > MAX_REVISION))
    {
        return Err(fail("OWNER_UNAVAILABLE"));
    }
    Ok(state)
}
fn state(root: &Path) -> Result<(Option<Vec<u8>>, Value)> {
    let bytes = read_optional(&status_path(root), MAX_STATE)?;
    let value = decode(bytes.as_deref())?;
    Ok((bytes, value))
}
fn view(s: &Value) -> Value {
    let mut result = json!({"dnd":s["dnd"].as_bool().unwrap_or(false),"revision":s["revision"].as_u64().unwrap_or(0)});
    if let Some(until) = s["manual_override_until_unix_ms"].as_u64() {
        result["manual_override_until_unix_ms"] = json!(until);
    }
    result
}
fn anchor_path(root: &Path) -> PathBuf {
    root.join("cortetsu/dnd-observed.json")
}
fn anchor(root: &Path, bytes: &[u8], s: &Value) -> Result<()> {
    save(
        &anchor_path(root),
        &json!({"schema":1,"bytes":bytes,"revision":s["revision"].as_u64().unwrap_or(0)}),
    )
}
fn manual_until() -> Result<u64> {
    let seconds = std::env::var("CORTETSU_MANUAL_OVERRIDE_SECONDS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(3600)
        .min(86400);
    Ok((now()? + seconds) * 1000)
}
fn observe_locked(root: &Path) -> Result<(Option<Vec<u8>>, Value)> {
    let (mut bytes, mut s) = state(root)?;
    let recorded = read_optional(&anchor_path(root), MAX_STATE * 12)?;
    if let Some(raw) = recorded {
        let a: Value = serde_json::from_slice(&raw).map_err(|_| fail("RECOVERY_REQUIRED"))?;
        let previous: Vec<u8> =
            serde_json::from_value(a["bytes"].clone()).map_err(|_| fail("RECOVERY_REQUIRED"))?;
        let revision = a["revision"]
            .as_u64()
            .filter(|r| *r < MAX_REVISION)
            .ok_or_else(|| fail("RECOVERY_REQUIRED"))?;
        if a["schema"] != 1 {
            return Err(fail("RECOVERY_REQUIRED"));
        }
        if bytes.as_deref() != Some(previous.as_slice()) {
            let next = revision
                .max(s["revision"].as_u64().unwrap_or(0))
                .checked_add(1)
                .filter(|r| *r <= MAX_REVISION)
                .ok_or_else(|| fail("STATE_STALE"))?;
            s["revision"] = json!(next);
            s["manual_override_until_unix_ms"] = json!(manual_until()?);
            let new = serde_json::to_vec(&s).map_err(|_| Failure::io())?;
            atomic_write(&status_path(root), &new)?;
            anchor(root, &new, &s)?;
            bytes = Some(new);
        }
    } else if let Some(ref raw) = bytes {
        // Adopt the previous runtime's existing choice without changing it.
        // Future edits outside this owner become explicit manual overrides.
        anchor(root, raw, &s)?;
    }
    Ok((bytes, s))
}
pub fn snapshot(root: &Path) -> Result<Value> {
    snapshot_with_timeout(root, std::time::Duration::from_secs(5))
}
pub fn snapshot_with_timeout(root: &Path, timeout: std::time::Duration) -> Result<Value> {
    if !root.join("cortetsu").exists() {
        return Ok(view(&state(root)?.1));
    }
    let _guard = lock_with_timeout(root, timeout)?;
    recover_locked(root)?;
    Ok(view(&observe_locked(root)?.1))
}
pub fn ensure(root: &Path) -> Result<()> {
    let _guard = lock(root)?;
    recover_locked(root)?;
    // The QML watcher needs a durable initial token. Snapshot alone remains
    // read-only when no owner state exists; malformed evidence is retained.
    clear_state(root)?;
    if read_optional(&clear_path(root), MAX_STATE)?.is_none() {
        save(&clear_path(root), &json!({"revision":0,"pending":false}))?;
    }
    let (before, s) = state(root)?;
    if before.is_none() {
        save(&status_path(root), &s)?;
    }
    observe_locked(root)?;
    Ok(())
}
fn journal(root: &Path) -> PathBuf {
    root.join("cortetsu/dnd-journal.json")
}
fn records(root: &Path) -> Result<PathBuf> {
    use std::os::unix::fs::PermissionsExt;
    let dir = root.join("cortetsu/dnd-requests");
    match fs::symlink_metadata(&dir) {
        Ok(m)
            if !m.is_dir() || m.file_type().is_symlink() || m.permissions().mode() & 0o077 != 0 =>
        {
            return Err(fail("PERMISSION_DENIED"));
        }
        Ok(_) => (),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            use std::os::unix::fs::DirBuilderExt;
            fs::DirBuilder::new()
                .mode(0o700)
                .create(&dir)
                .map_err(|_| fail("PERMISSION_DENIED"))?;
        }
        Err(_) => return Err(fail("PERMISSION_DENIED")),
    }
    Ok(dir)
}
fn save(path: &Path, value: &Value) -> Result<()> {
    let b = serde_json::to_vec(value).map_err(|_| fail("INTERNAL_REDACTED"))?;
    atomic_write(path, &b)
}
fn remove_synced(path: &Path) -> Result<()> {
    fs::remove_file(path).map_err(|_| fail("RECOVERY_REQUIRED"))?;
    sync_directory(path.parent().ok_or_else(Failure::io)?)
}
fn recover_locked(root: &Path) -> Result<bool> {
    let path = journal(root);
    let Some(bytes) = read_optional(&path, MAX_STATE * 12)? else {
        return Ok(false);
    };
    let mut j: Value = serde_json::from_slice(&bytes).map_err(|_| fail("RECOVERY_REQUIRED"))?;
    let key = j["key"]
        .as_str()
        .filter(|k| uuid(k))
        .ok_or_else(|| fail("RECOVERY_REQUIRED"))?
        .to_string();
    if j["schema"] != 1 {
        return Err(fail("RECOVERY_REQUIRED"));
    }
    let before: Option<Vec<u8>> =
        serde_json::from_value(j["before"].clone()).map_err(|_| fail("RECOVERY_REQUIRED"))?;
    let after: Vec<u8> =
        serde_json::from_value(j["after"].clone()).map_err(|_| fail("RECOVERY_REQUIRED"))?;
    decode(before.as_deref())?;
    decode(Some(&after))?;
    let current = read_optional(&status_path(root), MAX_STATE)?;
    let receipt_path = records(root)?.join(format!("{key}.json"));
    if let Some(receipt) = read_optional(&receipt_path, MAX_STATE * 12)? {
        let receipt: Value =
            serde_json::from_slice(&receipt).map_err(|_| fail("RECOVERY_REQUIRED"))?;
        if receipt["phase"] == "VERIFIED" && receipt["after"] == j["after"] {
            // Commit is durable; cleanup only. A later manual write is never undone.
            // The receipt is persisted before the observation anchor. Repair
            // that crash window so our own commit is not classified as manual.
            anchor(root, &after, &decode(Some(&after))?)?;
            remove_synced(&path)?;
            return Ok(true);
        }
    }
    if current.as_deref() != Some(after.as_slice()) && current != before {
        return Err(fail("RECOVERY_REQUIRED"));
    }
    if current != before {
        match &before {
            Some(b) => atomic_write(&status_path(root), b)?,
            None => remove_synced(&status_path(root))?,
        }
    }
    j["phase"] = json!("ABORTED");
    save(&receipt_path, &j)?;
    remove_synced(&path)?;
    Ok(true)
}
pub fn recover(root: &Path) -> Result<bool> {
    let _guard = lock(root)?;
    recover_locked(root)
}

fn apply_locked(
    root: &Path,
    expected: u64,
    key: &str,
    enabled: bool,
    manual: bool,
    after_write: impl FnOnce(),
) -> Result<Value> {
    if !uuid(key) || expected >= MAX_REVISION {
        return Err(fail("INVALID_REQUEST"));
    }
    recover_locked(root)?;
    let dir = records(root)?;
    let receipt = dir.join(format!("{key}.json"));
    let (before, mut s) = observe_locked(root)?;
    if let Some(bytes) = read_optional(&receipt, MAX_STATE * 12)? {
        let r: Value = serde_json::from_slice(&bytes).map_err(|_| fail("RECOVERY_REQUIRED"))?;
        if r["expected"] != expected || r["enabled"] != enabled {
            return Err(fail("IDEMPOTENCY_CONFLICT"));
        }
        if r["phase"] != "VERIFIED" {
            return Err(fail("RECOVERY_REQUIRED"));
        }
        let expires = r["expires"]
            .as_u64()
            .ok_or_else(|| fail("RECOVERY_REQUIRED"))?;
        if now()? > expires {
            return Err(fail("STATE_STALE"));
        }
        let after: Vec<u8> =
            serde_json::from_value(r["after"].clone()).map_err(|_| fail("RECOVERY_REQUIRED"))?;
        if before.as_deref() != Some(&after) {
            return Err(fail("STATE_STALE"));
        }
        return Ok(view(&s));
    }
    if s["revision"].as_u64().unwrap_or(0) != expected {
        return Err(fail("STATE_STALE"));
    }
    if !manual && s["manual_override_until_unix_ms"].as_u64().unwrap_or(0) > now()? * 1000 {
        return Err(fail("USER_CONFIRMATION_REQUIRED"));
    }
    if !manual
        && fs::read_dir(&dir)
            .map_err(|_| fail("OWNER_UNAVAILABLE"))?
            .count()
            >= MAX_RECORDS
    {
        return Err(fail("RATE_LIMITED"));
    }
    s["dnd"] = json!(enabled);
    s["revision"] = json!(expected + 1);
    if manual {
        s["manual_override_until_unix_ms"] = json!(manual_until()?);
    }
    let after = serde_json::to_vec(&s).map_err(|_| Failure::io())?;
    if after.len() as u64 > MAX_STATE {
        return Err(fail("FRAME_TOO_LARGE"));
    }
    let mut j = json!({"schema":1,"key":key,"expected":expected,"enabled":enabled,
        "before":before,"after":after,"phase":"PREPARED","expires":now()? + RETENTION_SECS});
    save(&journal(root), &j)?;
    atomic_write(&status_path(root), &after)?;
    after_write();
    if read_optional(&status_path(root), MAX_STATE)?.as_deref() != Some(&after) {
        return Err(fail("APPLY_VERIFICATION_FAILED"));
    }
    j["phase"] = json!("VERIFIED");
    save(&receipt, &j)?;
    anchor(root, &after, &s)?;
    remove_synced(&journal(root))?;
    Ok(view(&s))
}
pub fn set(root: &Path, expected: u64, key: &str, enabled: bool) -> Result<Value> {
    set_with_timeout(
        root,
        expected,
        key,
        enabled,
        std::time::Duration::from_secs(5),
    )
}
pub fn set_with_timeout(
    root: &Path,
    expected: u64,
    key: &str,
    enabled: bool,
    timeout: std::time::Duration,
) -> Result<Value> {
    let _guard = lock_with_timeout(root, timeout)?;
    apply_locked(root, expected, key, enabled, false, || {})
}
pub fn manual(root: &Path, mode: &str) -> Result<Value> {
    use std::io::Read;
    let _guard = lock(root)?;
    recover_locked(root)?;
    let s = view(&observe_locked(root)?.1);
    let enabled = match mode {
        "on" => true,
        "off" => false,
        "toggle" => s["dnd"] != true,
        _ => return Err(Failure::usage()),
    };
    let mut random = [0u8; 16];
    fs::File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut random))
        .map_err(|_| fail("INTERNAL_REDACTED"))?;
    random[6] = (random[6] & 15) | 64;
    random[8] = (random[8] & 63) | 128;
    let hex: String = random.iter().map(|b| format!("{b:02x}")).collect();
    let key = format!(
        "{}-{}-{}-{}-{}",
        &hex[..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..]
    );
    let result = apply_locked(
        root,
        s["revision"].as_u64().unwrap_or(0),
        &key,
        enabled,
        true,
        || {},
    )?;
    // Manual one-shot commands have no externally replayable idempotency key.
    // Their completed receipts need not consume the bounded automation ledger.
    remove_synced(&records(root)?.join(format!("{key}.json")))?;
    Ok(result)
}

/// QML submits its previous ids and current snapshot under the same lock as
/// dismiss/clear. Entries already removed by another writer stay removed.
fn clear_path(root: &Path) -> PathBuf {
    root.join("cortetsu/notifs-clear.json")
}
pub(crate) fn clear_state(root: &Path) -> Result<(u64, bool)> {
    let Some(bytes) = read_optional(&clear_path(root), MAX_STATE)? else {
        return Ok((0, false));
    };
    let value: Value = serde_json::from_slice(&bytes).map_err(|_| fail("RECOVERY_REQUIRED"))?;
    let revision = value["revision"]
        .as_u64()
        .filter(|r| *r <= MAX_REVISION)
        .ok_or_else(|| fail("RECOVERY_REQUIRED"))?;
    let pending = value["pending"]
        .as_bool()
        .ok_or_else(|| fail("RECOVERY_REQUIRED"))?;
    Ok((revision, pending))
}
pub(crate) fn clear_locked(root: &Path) -> Result<()> {
    super::check_history_path(root)?;
    let revision = clear_state(root)?
        .0
        .checked_add(1)
        .filter(|r| *r <= MAX_REVISION)
        .ok_or_else(|| fail("STATE_STALE"))?;
    save(
        &clear_path(root),
        &json!({"revision": revision, "pending": true}),
    )?;
    save_history(root, &[])?;
    save(
        &clear_path(root),
        &json!({"revision": revision, "pending": false}),
    )
}
pub fn merge(root: &Path, input: &[u8]) -> Result<Value> {
    if input.len() > 1024 * 1024 {
        return Err(fail("FRAME_TOO_LARGE"));
    }
    let request: Value = serde_json::from_slice(input).map_err(|_| fail("INVALID_REQUEST"))?;
    let entries = request["entries"]
        .as_array()
        .ok_or_else(|| fail("INVALID_REQUEST"))?;
    let base = request["base_ids"]
        .as_array()
        .ok_or_else(|| fail("INVALID_REQUEST"))?;
    let expected_clear = match request.get("clear_revision") {
        Some(value) => Some(
            value
                .as_u64()
                .filter(|r| *r <= MAX_REVISION)
                .ok_or_else(|| fail("INVALID_REQUEST"))?,
        ),
        None => None,
    };
    if entries.len() > 2048
        || base.len() > 2048
        || base.iter().any(|id| !id.is_string())
        || entries
            .iter()
            .any(|v| !v.is_object() || !v["id"].is_string())
    {
        return Err(fail("INVALID_REQUEST"));
    }
    let _guard = lock(root)?;
    let (revision, pending) = clear_state(root)?;
    if pending {
        save_history(root, &[])?;
        save(
            &clear_path(root),
            &json!({"revision": revision, "pending": false}),
        )?;
    }
    let current = load_history(root)?;
    if expected_clear.is_some_and(|expected| expected != revision) {
        return Ok(json!(current));
    }
    let mut merged = Vec::new();
    for item in entries {
        if !base.contains(&item["id"]) || current.iter().any(|old| old["id"] == item["id"]) {
            merged.push(item.clone());
        }
    }
    for item in current {
        if !base.contains(&item["id"]) && !merged.iter().any(|entry| entry["id"] == item["id"]) {
            merged.push(item);
        }
    }
    save_history(root, &merged)?;
    let readback: Value =
        serde_json::from_slice(&fs::read(history_path(root)).map_err(|_| Failure::io())?)
            .map_err(|_| Failure::io())?;
    if readback != json!(merged) {
        return Err(fail("APPLY_VERIFICATION_FAILED"));
    }
    Ok(readback)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn interrupted_apply_restores_bytes_and_does_not_reexecute_key() {
        let root = std::env::temp_dir().join(format!("dnd-recovery-{}", std::process::id()));
        fs::create_dir_all(root.join("cortetsu")).unwrap();
        let before = br#"{"dnd":false,"custom":"keep"}"#;
        fs::write(status_path(&root), before).unwrap();
        let key = "00000000-0000-4000-8000-000000000099";
        let interrupted = std::panic::catch_unwind(|| {
            let _guard = lock(&root).unwrap();
            apply_locked(&root, 0, key, true, false, || {
                panic!("interrupted before receipt")
            })
            .unwrap();
        });
        assert!(interrupted.is_err());
        assert!(recover(&root).unwrap());
        assert_eq!(fs::read(status_path(&root)).unwrap(), before);
        assert_eq!(
            set(&root, 0, key, true).unwrap_err().message,
            "RECOVERY_REQUIRED"
        );
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn contended_owner_respects_request_deadline() {
        let root = std::env::temp_dir().join(format!("dnd-deadline-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let guard = lock(&root).unwrap();
        let start = std::time::Instant::now();
        let err = set_with_timeout(
            &root,
            0,
            "00000000-0000-4000-8000-000000000001",
            true,
            std::time::Duration::from_millis(25),
        )
        .unwrap_err();
        assert_eq!(err.message, "DEADLINE_EXCEEDED");
        assert!(start.elapsed() < std::time::Duration::from_millis(250));
        assert!(!status_path(&root).exists());
        drop(guard);
        fs::remove_dir_all(root).unwrap();
    }
}
