//! Revisioned, durable typed hardware ownership shared with the manual CLI.
//! A PREPARED record is never retried. Replays can only return verified state.
use crate::{display, gamemode, power, util::*};
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};
use std::{
    env,
    fs::{self, File},
    io::Read,
    os::unix::fs::{DirBuilderExt, MetadataExt},
    path::PathBuf,
};
#[path = "../../rescue/src/strict_json.rs"]
mod strict_json;
const MAX_REV: u64 = 9_007_199_254_740_991;
const MAX_LEDGER: usize = 4096;
const RETENTION_MS: u64 = 7 * 24 * 3600 * 1000;
fn uuid(s: &str) -> bool {
    s.len() == 36
        && s.bytes().enumerate().all(|(i, c)| {
            if [8, 13, 18, 23].contains(&i) {
                c == b'-'
            } else {
                c.is_ascii_hexdigit()
            }
        })
}
fn canonical(v: &Value) -> Value {
    match v {
        Value::Object(m) => {
            let mut keys = m.keys().collect::<Vec<_>>();
            keys.sort();
            let mut out = Map::new();
            for k in keys {
                out.insert(k.clone(), canonical(&m[k]));
            }
            Value::Object(out)
        }
        Value::Array(a) => Value::Array(a.iter().map(canonical).collect()),
        v => v.clone(),
    }
}
fn digest(v: &Value) -> String {
    format!("{:x}", Sha256::digest(canonical(v).to_string().as_bytes()))
}
fn millis() -> u64 {
    (now() * 1000.) as u64
}
fn override_until() -> u64 {
    let seconds = env::var("CORTETSU_MANUAL_OVERRIDE_SECONDS")
        .ok()
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(3600)
        .min(86400);
    millis().saturating_add(seconds * 1000)
}
fn scope(domain: &str) -> String {
    if domain == "power" {
        return "power".into();
    }
    let session = env::var("HYPRLAND_INSTANCE_SIGNATURE").unwrap_or_default();
    format!("{domain}-{}", &digest(&json!(session))[..24])
}
fn directory() -> Result<PathBuf> {
    let parent = state_home().join("cortetsu");
    fs::create_dir_all(&parent).map_err(|_| "PERMISSION_DENIED")?;
    let dir = parent.join("hardware-owners");
    if let Err(e) = fs::DirBuilder::new().mode(0o700).create(&dir)
        && e.kind() != std::io::ErrorKind::AlreadyExists
    {
        return Err("PERMISSION_DENIED".into());
    }
    let meta = fs::symlink_metadata(&dir).map_err(|_| "PERMISSION_DENIED")?;
    if !meta.is_dir()
        || meta.uid() != nix::unistd::Uid::current().as_raw()
        || meta.mode() & 0o077 != 0
    {
        return Err("PERMISSION_DENIED".into());
    }
    Ok(dir)
}
fn path(domain: &str) -> Result<PathBuf> {
    Ok(directory()?.join(format!("{}.json", scope(domain))))
}
pub fn domain_lock(domain: &str) -> Result<File> {
    lock(&directory()?.join(format!("{}.lock", scope(domain))))
        .map_err(|_| "PERMISSION_DENIED".into())
}
fn load(domain: &str) -> Result<Value> {
    let p = path(domain)?;
    let meta = match fs::symlink_metadata(&p) {
        Ok(m) => m,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            return Ok(
                json!({"schema":1,"revision":0,"fingerprint":null,"snapshot":{},"manual_override_until_unix_ms":0,"entries":{}}),
            );
        }
        Err(_) => return Err("PERMISSION_DENIED".into()),
    };
    if !meta.is_file()
        || meta.uid() != nix::unistd::Uid::current().as_raw()
        || meta.mode() & 0o077 != 0
        || meta.len() > 4 * 1024 * 1024
    {
        return Err("PERMISSION_DENIED".into());
    }
    let raw = fs::read(&p).map_err(|_| "OWNER_UNAVAILABLE")?;
    if !strict_json::validate(&raw) {
        return Err("RECOVERY_REQUIRED".into());
    }
    let state: Value = serde_json::from_slice(&raw).map_err(|_| "RECOVERY_REQUIRED")?;
    if state["schema"] != 1
        || state["revision"].as_u64().is_none_or(|n| n > MAX_REV)
        || !state["entries"].is_object()
        || !state["snapshot"].is_object()
    {
        return Err("RECOVERY_REQUIRED".into());
    }
    Ok(state)
}
fn save(domain: &str, state: &Value) -> Result<()> {
    atomic_json(&path(domain)?, state).map_err(|_| "OWNER_UNAVAILABLE".into())
}
fn pending(state: &Value) -> bool {
    state["entries"]
        .as_object()
        .is_some_and(|entries| entries.values().any(|entry| entry["state"] == "PREPARED"))
}
/// Keep the key as a terminal tombstone after explicit, verified manual recovery.
/// Its original effect remains uncertain and must never be executed again.
fn reconcile_manual(state: &mut Value) {
    if let Some(entries) = state["entries"].as_object_mut() {
        for entry in entries.values_mut() {
            if entry["state"] == "PREPARED" {
                entry["state"] = json!("RECONCILED_MANUAL");
            }
        }
    }
}
fn snapshot(domain: &str) -> Result<Value> {
    match domain {
        "gamemode" => gamemode::owner_snapshot(),
        "power" => {
            let profile = power::current_profile();
            if !["balanced", "power-saver", "performance"].contains(&profile.as_str()) {
                Err("OWNER_UNAVAILABLE".into())
            } else {
                Ok(json!({"profile":profile}))
            }
        }
        "display" => display::owner_snapshot(),
        _ => Err("UNSUPPORTED_CAPABILITY".into()),
    }
}
fn advance(state: &mut Value) -> Result<()> {
    let rev = state["revision"].as_u64().ok_or("RECOVERY_REQUIRED")?;
    if rev >= MAX_REV {
        return Err("RECOVERY_REQUIRED".into());
    }
    state["revision"] = json!(rev + 1);
    Ok(())
}
fn reconcile(domain: &str, state: &mut Value, current: &Value, external: bool) -> Result<()> {
    let fp = digest(current);
    if state["fingerprint"] != fp {
        if !state["fingerprint"].is_null() {
            advance(state)?;
            if external {
                state["manual_override_until_unix_ms"] = json!(override_until())
            }
        }
        state["fingerprint"] = json!(fp);
        state["snapshot"] = current.clone();
        save(domain, state)?;
    }
    Ok(())
}
fn body(state: &Value) -> Value {
    let mut b = state["snapshot"].clone();
    b["revision"] = state["revision"].clone();
    b["manual_override_until_unix_ms"] = state["manual_override_until_unix_ms"].clone();
    b
}
fn reject(request_id: &str, code: &str) -> Value {
    let code = if [
        "INCOMPATIBLE_PROTOCOL",
        "UNSUPPORTED_CAPABILITY",
        "INVALID_REQUEST",
        "FRAME_TOO_LARGE",
        "RATE_LIMITED",
        "STATE_STALE",
        "SESSION_MISMATCH",
        "POLICY_CONFLICT",
        "USER_CONFIRMATION_REQUIRED",
        "OWNER_UNAVAILABLE",
        "PERMISSION_DENIED",
        "DEADLINE_EXCEEDED",
        "IDEMPOTENCY_CONFLICT",
        "APPLY_FAILED",
        "APPLY_VERIFICATION_FAILED",
        "ROLLBACK_FAILED",
        "RECOVERY_REQUIRED",
    ]
    .contains(&code)
    {
        code
    } else {
        "INTERNAL_REDACTED"
    };
    json!({"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":request_id,"outcome":"rejected","verified":false,"error":{"code":code,"retryable":false},"body":{}})
}
fn success(id: &str, mutation: bool, state: &Value) -> Value {
    json!({"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":id,"outcome":if mutation{"applied"}else{"read"},"verified":true,"body":body(state)})
}
fn apply(operation: &str, args: &Value) -> Result<()> {
    let (payload, code) = match operation {
        "gamemode.set" => gamemode::main(&[if args["enabled"] == true {
            "enable".into()
        } else {
            "disable".into()
        }]),
        "power.profile.set" => power::hardware(&["set-profile".into(), text(args, "profile", "")]),
        "display.profile.preview" => {
            display::preview_profile(&text(args, "monitor", ""), &text(args, "profile", ""))
        }
        _ => return Err("UNSUPPORTED_CAPABILITY".into()),
    };
    if code != 0 || payload.get("ok") == Some(&Value::Bool(false)) {
        return Err("APPLY_FAILED".into());
    }
    Ok(())
}
fn desired(operation: &str, args: &Value, current: &Value) -> bool {
    match operation {
        "gamemode.set" => {
            current["enabled"] == args["enabled"]
                && ["ACTIVE", "INACTIVE"].contains(&current["state"].as_str().unwrap_or(""))
        }
        "power.profile.set" => current["profile"] == args["profile"],
        "display.profile.preview" => {
            current["preview"]["active"] == true
                && current["preview"]["candidate"]["outputs"]
                    .as_array()
                    .is_some_and(|a| a.len() == 1 && a[0]["name"] == args["monitor"])
        }
        _ => false,
    }
}
fn handle(request: &Value) -> Result<Value> {
    let op = request["operation"].as_str().ok_or("INVALID_REQUEST")?;
    let domain = op.split('.').next().unwrap_or("");
    let args = &request["arguments"];
    let mutation = match op {
        "gamemode.status" | "power.status" | "display.status" => {
            if args.as_object().is_none_or(|a| !a.is_empty()) {
                return Err("INVALID_REQUEST".into());
            }
            false
        }
        "gamemode.set" => {
            if args.as_object().is_none_or(|a| a.len() != 1) || !args["enabled"].is_boolean() {
                return Err("INVALID_REQUEST".into());
            }
            true
        }
        "power.profile.set" => {
            if args.as_object().is_none_or(|a| a.len() != 1)
                || !["balanced", "power-saver", "performance"]
                    .contains(&args["profile"].as_str().unwrap_or(""))
            {
                return Err("INVALID_REQUEST".into());
            }
            true
        }
        "display.profile.preview" => {
            if args.as_object().is_none_or(|a| a.len() != 2)
                || ["monitor", "profile"].iter().any(|k| {
                    args[*k].as_str().is_none_or(|s| {
                        s.is_empty() || s.len() > 128 || s.chars().any(char::is_control)
                    })
                })
            {
                return Err("INVALID_REQUEST".into());
            }
            true
        }
        _ => return Err("UNSUPPORTED_CAPABILITY".into()),
    };
    let id = request["request_id"].as_str().unwrap();
    let _lock = domain_lock(domain)?;
    let mut state = load(domain)?;
    let current = snapshot(domain)?;
    reconcile(domain, &mut state, &current, true)?;
    if !mutation {
        return Ok(success(id, false, &state));
    }
    let expected = request["expected_revision"]
        .as_u64()
        .filter(|r| *r <= MAX_REV)
        .ok_or("INVALID_REQUEST")?;
    let key = request["idempotency_key"]
        .as_str()
        .filter(|s| uuid(s))
        .ok_or("INVALID_REQUEST")?;
    let fp = digest(&json!({"operation":op,"arguments":args,"expected_revision":expected}));
    if let Some(entry) = state["entries"].get(key) {
        if entry["fingerprint"] != fp {
            return Err("IDEMPOTENCY_CONFLICT".into());
        }
        if entry["state"] != "COMMITTED" {
            return Err("RECOVERY_REQUIRED".into());
        }
        if entry["revision"] != state["revision"]
            || entry["state_fingerprint"] != state["fingerprint"]
            || entry["expires_at_unix_ms"]
                .as_u64()
                .is_none_or(|n| n <= millis())
        {
            return Err("STATE_STALE".into());
        }
        return Ok(success(id, true, &state));
    }
    if pending(&state) {
        return Err("RECOVERY_REQUIRED".into());
    }
    if state["revision"] != expected {
        return Err("STATE_STALE".into());
    }
    if state["manual_override_until_unix_ms"].as_u64().unwrap_or(0) > millis() {
        return Err("USER_CONFIRMATION_REQUIRED".into());
    }
    if state["entries"].as_object().unwrap().len() >= MAX_LEDGER {
        return Err("RATE_LIMITED".into());
    }
    if op == "display.profile.preview" {
        display::profile_candidate(&text(args, "monitor", ""), &text(args, "profile", ""))
            .map_err(|e| {
                if e == "UNSUPPORTED_CAPABILITY" {
                    e
                } else {
                    "POLICY_CONFLICT".into()
                }
            })?;
    }
    state["entries"][key] = json!({"state":"PREPARED","fingerprint":fp,"revision_before":expected,"expires_at_unix_ms":millis().saturating_add(RETENTION_MS)});
    save(domain, &state)?;
    if apply(op, args).is_err() {
        return Err("RECOVERY_REQUIRED".into());
    }
    let after = snapshot(domain).map_err(|_| "RECOVERY_REQUIRED")?;
    if !desired(op, args, &after) {
        return Err("APPLY_VERIFICATION_FAILED".into());
    }
    advance(&mut state)?;
    state["snapshot"] = after.clone();
    state["fingerprint"] = json!(digest(&after));
    state["entries"][key]["state"] = json!("COMMITTED");
    state["entries"][key]["revision"] = state["revision"].clone();
    state["entries"][key]["state_fingerprint"] = state["fingerprint"].clone();
    save(domain, &state)?;
    Ok(success(id, true, &state))
}
pub fn exec() -> Value {
    let mut raw = Vec::new();
    if std::io::stdin().take(65537).read_to_end(&mut raw).is_err() {
        return reject("", "INVALID_REQUEST");
    }
    if raw.len() > 65536 {
        return reject("", "FRAME_TOO_LARGE");
    }
    if !strict_json::validate(&raw) {
        return reject("", "INVALID_REQUEST");
    }
    let request: Value = match serde_json::from_slice(&raw) {
        Ok(v) => v,
        Err(_) => return reject("", "INVALID_REQUEST"),
    };
    let id = request["request_id"].as_str().unwrap_or("");
    let allowed = [
        "protocol",
        "version",
        "request_id",
        "operation",
        "deadline_ms",
        "arguments",
        "expected_revision",
        "idempotency_key",
    ];
    if !uuid(id)
        || request
            .as_object()
            .is_none_or(|o| o.keys().any(|k| !allowed.contains(&k.as_str())))
        || request["version"].as_object().is_none_or(|v| v.len() != 2)
        || request["deadline_ms"]
            .as_u64()
            .is_none_or(|n| n == 0 || n > 60_000)
        || !request["arguments"].is_object()
        || request
            .get("expected_revision")
            .is_some_and(|v| v.as_u64().is_none_or(|n| n > MAX_REV))
        || request
            .get("idempotency_key")
            .is_some_and(|v| v.as_str().is_none_or(|s| !uuid(s)))
    {
        return reject(id, "INVALID_REQUEST");
    }
    if request["protocol"] != "cortetsu.exec" || request["version"]["major"] != 1 {
        return reject(id, "INCOMPATIBLE_PROTOCOL");
    }
    if request["version"]["minor"] != 0 {
        return reject(id, "UNSUPPORTED_CAPABILITY");
    }
    set_deadline(request["deadline_ms"].as_u64().unwrap());
    match handle(&request) {
        Ok(v) => v,
        Err(e) => reject(
            id,
            if deadline_expired() && e != "RECOVERY_REQUIRED" {
                "DEADLINE_EXCEEDED"
            } else {
                &e
            },
        ),
    }
}
/// Manual writes use the same owner lock and advance the version before release.
/// A missing compositor never makes a legacy recovery action unavailable.
pub fn manual_cli(domain: &str, action: impl FnOnce() -> (Value, i32)) -> (Value, i32) {
    let _guard = match domain_lock(domain) {
        Ok(g) => g,
        Err(e) => return json_error(e),
    };
    let mut state = match load(domain) {
        Ok(s) => s,
        Err(e) => return json_error(e),
    };
    if let Ok(before) = snapshot(domain)
        && let Err(e) = reconcile(domain, &mut state, &before, true)
    {
        return json_error(e);
    }
    let result = action();
    if result.1 == 0 {
        if let Err(e) = advance(&mut state) {
            return json_error(e);
        }
        if let Ok(after) = snapshot(domain) {
            state["snapshot"] = after.clone();
            state["fingerprint"] = json!(digest(&after));
            reconcile_manual(&mut state);
        } else {
            state["fingerprint"] = Value::Null;
        }
        state["manual_override_until_unix_ms"] = json!(override_until());
        if let Err(e) = save(domain, &state) {
            return json_error(e);
        }
    }
    result
}
/// Called only at an actual legacy automation transition; steady iterations spawn nothing.
pub fn automation_override() -> Result<bool> {
    let state = load("power")?;
    if pending(&state) {
        return Err("RECOVERY_REQUIRED".into());
    }
    Ok(state["manual_override_until_unix_ms"].as_u64().unwrap_or(0) > millis())
}
pub fn automation_finish(profile: &str, manual: bool) -> Result<()> {
    let mut state = load("power")?;
    let after = json!({"profile":profile});
    reconcile("power", &mut state, &after, false)?;
    if manual {
        advance(&mut state)?;
        reconcile_manual(&mut state);
        state["manual_override_until_unix_ms"] = json!(override_until());
        save("power", &state)?;
    }
    Ok(())
}
