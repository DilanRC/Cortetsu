//! Strict `cortetsu.exec/1` adapter for generation verification and typed owners.
//! Executables and arguments are fixed to the same helper generation; request
//! bytes never select an executable, environment, arbitrary argv, or shell.
use super::{Roots, current};
use cortetsu_notifications_rs::{owner, state_home};
use serde::Deserialize;
use serde_json::{Value, json};
use std::time::{Duration, Instant};

const MAX_REQUEST: usize = 64 * 1024;

fn cancellation_flag() -> Option<&'static std::sync::Arc<std::sync::atomic::AtomicBool>> {
    use std::sync::{Arc, OnceLock, atomic::AtomicBool};
    static CANCELLED: OnceLock<Option<Arc<AtomicBool>>> = OnceLock::new();
    CANCELLED
        .get_or_init(|| {
            let cancelled = Arc::new(AtomicBool::new(false));
            for signal in [signal_hook::consts::SIGTERM, signal_hook::consts::SIGINT] {
                if signal_hook::flag::register(signal, cancelled.clone()).is_err() {
                    return None;
                }
            }
            Some(cancelled)
        })
        .as_ref()
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Version {
    major: u32,
    minor: u32,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    protocol: String,
    version: Version,
    request_id: String,
    operation: String,
    deadline_ms: u32,
    arguments: Value,
    expected_revision: Option<u64>,
    idempotency_key: Option<String>,
}

fn valid_uuid(value: &str) -> bool {
    if value.len() != 36 {
        return false;
    }
    value.bytes().enumerate().all(|(i, b)| {
        if [8, 13, 18, 23].contains(&i) {
            b == b'-'
        } else {
            b.is_ascii_hexdigit()
        }
    })
}

fn reject(request_id: &str, code: &str) -> Value {
    json!({
        "protocol":"cortetsu.exec",
        "version":{"major":1,"minor":0},
        "request_id":request_id,
        "outcome":"rejected",
        "verified":false,
        "error":{"code":code,"retryable":false},
        "body":{},
    })
}

pub fn handle(input: &[u8], roots: &Roots) -> Value {
    let started = Instant::now();
    if input.len() > MAX_REQUEST {
        return reject("", "FRAME_TOO_LARGE");
    }
    // serde_json's default struct deserializer accepts duplicate keys in
    // nested `arguments`; Go explicitly rejects them, so preflight the full
    // payload before interpreting any operation or constructing a response.
    if !super::strict_json::validate(input) {
        return reject("", "INVALID_REQUEST");
    }
    let request: Request = match serde_json::from_slice(input) {
        Ok(value) => value,
        Err(_) => return reject("", "INVALID_REQUEST"),
    };
    if !valid_uuid(&request.request_id) || request.deadline_ms == 0 || request.deadline_ms > 60_000
    {
        return reject("", "INVALID_REQUEST");
    }
    if request.protocol != "cortetsu.exec" || request.version.major != 1 {
        return reject(&request.request_id, "INCOMPATIBLE_PROTOCOL");
    }
    if request.version.minor != 0 {
        return reject(&request.request_id, "UNSUPPORTED_CAPABILITY");
    }
    let Some(arguments) = request.arguments.as_object() else {
        return reject(&request.request_id, "INVALID_REQUEST");
    };
    if request
        .expected_revision
        .is_some_and(|v| v > 9_007_199_254_740_991)
        || request
            .idempotency_key
            .as_ref()
            .is_some_and(|k| !valid_uuid(k))
    {
        return reject(&request.request_id, "INVALID_REQUEST");
    }
    let mutation = match request.operation.as_str() {
        "system.verify"
        | "gamemode.status"
        | "power.status"
        | "display.status"
        | "notifications.status" => {
            if !arguments.is_empty() {
                return reject(&request.request_id, "INVALID_REQUEST");
            }
            false
        }
        "gamemode.set" | "notifications.dnd.set" => {
            if arguments.len() != 1 || !request.arguments["enabled"].is_boolean() {
                return reject(&request.request_id, "INVALID_REQUEST");
            }
            true
        }
        "power.profile.set" => {
            if arguments.len() != 1
                || !matches!(
                    request.arguments["profile"].as_str(),
                    Some("balanced" | "power-saver" | "performance")
                )
            {
                return reject(&request.request_id, "INVALID_REQUEST");
            }
            true
        }
        "display.profile.preview" => {
            if arguments.len() != 2
                || ["monitor", "profile"].iter().any(|k| {
                    request.arguments[*k].as_str().is_none_or(|s| {
                        s.is_empty() || s.len() > 128 || s.chars().any(char::is_control)
                    })
                })
            {
                return reject(&request.request_id, "INVALID_REQUEST");
            }
            true
        }
        _ => return reject(&request.request_id, "UNSUPPORTED_CAPABILITY"),
    };
    if mutation && (request.expected_revision.is_none() || request.idempotency_key.is_none()) {
        return reject(&request.request_id, "INVALID_REQUEST");
    }
    if matches!(
        request.operation.as_str(),
        "notifications.status" | "notifications.dnd.set"
    ) {
        let remaining =
            Duration::from_millis(request.deadline_ms as u64).saturating_sub(started.elapsed());
        if remaining.is_zero() {
            return reject(&request.request_id, "DEADLINE_EXCEEDED");
        }
        let result = state_home().and_then(|root| {
            if mutation {
                owner::set_with_timeout(
                    &root,
                    request.expected_revision.unwrap(),
                    request.idempotency_key.as_deref().unwrap(),
                    request.arguments["enabled"] == true,
                    remaining,
                )
            } else {
                owner::snapshot_with_timeout(&root, remaining)
            }
        });
        return match result {
            Ok(body) => json!({"protocol":"cortetsu.exec","version":{"major":1,"minor":0},
                "request_id":request.request_id,"outcome":if mutation {"applied"} else {"read"},
                "verified":true,"body":body}),
            Err(e) => {
                let code = match e.message.as_str() {
                    "INVALID_REQUEST"
                    | "FRAME_TOO_LARGE"
                    | "RATE_LIMITED"
                    | "STATE_STALE"
                    | "PERMISSION_DENIED"
                    | "IDEMPOTENCY_CONFLICT"
                    | "APPLY_VERIFICATION_FAILED"
                    | "RECOVERY_REQUIRED"
                    | "DEADLINE_EXCEEDED"
                    | "USER_CONFIRMATION_REQUIRED" => e.message.as_str(),
                    _ => "OWNER_UNAVAILABLE",
                };
                reject(&request.request_id, code)
            }
        };
    }
    if request.operation != "system.verify" {
        return hardware(input, &request, started);
    }
    match current(roots) {
        Ok(state) => json!({
            "protocol":"cortetsu.exec",
            "version":{"major":1,"minor":0},
            "request_id":request.request_id,
            "outcome":"read",
            "verified":true,
            "body":{"system":state.system,"shell":state.shell,"dotfiles":state.dotfiles,"revision":state.revision},
        }),
        Err(_) => reject(&request.request_id, "OWNER_UNAVAILABLE"),
    }
}

/// Resolve the owner in the same immutable helper generation. Neither the
/// request nor environment can select the executable or its arguments.
fn hardware(input: &[u8], request: &Request, started: Instant) -> Value {
    let binary = match std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.join("cortetsu-hardware-runtime")))
    {
        Some(path) => path,
        None => return reject(&request.request_id, "OWNER_UNAVAILABLE"),
    };
    forward_owner(&binary, input, request, started)
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Response {
    protocol: String,
    version: Version,
    request_id: String,
    outcome: String,
    verified: bool,
    transaction_id: Option<String>,
    error: Option<Failure>,
    body: Value,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Failure {
    code: String,
    retryable: bool,
}

fn known_error(code: &str) -> bool {
    matches!(
        code,
        "INCOMPATIBLE_PROTOCOL"
            | "UNSUPPORTED_CAPABILITY"
            | "INVALID_REQUEST"
            | "FRAME_TOO_LARGE"
            | "RATE_LIMITED"
            | "STATE_STALE"
            | "SESSION_MISMATCH"
            | "POLICY_CONFLICT"
            | "USER_CONFIRMATION_REQUIRED"
            | "OWNER_UNAVAILABLE"
            | "PERMISSION_DENIED"
            | "DEADLINE_EXCEEDED"
            | "IDEMPOTENCY_CONFLICT"
            | "APPLY_FAILED"
            | "APPLY_VERIFICATION_FAILED"
            | "ROLLBACK_FAILED"
            | "RECOVERY_REQUIRED"
            | "SECRET_TRANSPORT_DENIED"
            | "INTERNAL_REDACTED"
    )
}
fn valid_body(body: &Value, request: &Request) -> bool {
    let Some(object) = body.as_object() else {
        return false;
    };
    if body["revision"]
        .as_u64()
        .is_none_or(|n| n > 9_007_199_254_740_991)
        || body["manual_override_until_unix_ms"]
            .as_u64()
            .is_none_or(|n| n > 9_007_199_254_740_991)
    {
        return false;
    }
    let fields: &[&str] = match request.operation.split('.').next() {
        Some("power") => &["revision", "manual_override_until_unix_ms", "profile"],
        Some("gamemode") => &[
            "revision",
            "manual_override_until_unix_ms",
            "state",
            "enabled",
            "options",
        ],
        Some("display") => &[
            "revision",
            "manual_override_until_unix_ms",
            "outputs",
            "preview",
        ],
        _ => return false,
    };
    if object.len() != fields.len() || object.keys().any(|k| !fields.contains(&k.as_str())) {
        return false;
    }
    match request.operation.as_str() {
        "power.status" | "power.profile.set" => {
            matches!(
                body["profile"].as_str(),
                Some("balanced" | "power-saver" | "performance")
            ) && (request.operation == "power.status"
                || body["profile"] == request.arguments["profile"])
        }
        "gamemode.status" | "gamemode.set" => {
            matches!(
                body["state"].as_str(),
                Some("INACTIVE" | "APPLYING" | "ACTIVE" | "RESTORING" | "RECOVERY_REQUIRED")
            ) && body["enabled"].is_boolean()
                && (body["enabled"] == true) == (body["state"] == "ACTIVE")
                && body["options"].is_object()
                && (request.operation == "gamemode.status"
                    || body["enabled"] == request.arguments["enabled"])
        }
        "display.status" | "display.profile.preview" => {
            body["outputs"]
                .as_array()
                .is_some_and(|a| !a.is_empty() && a.len() <= 128 && a.iter().all(|v| v.is_object()))
                && body["preview"].is_object()
                && body["preview"]["active"].is_boolean()
                && (request.operation == "display.status"
                    || (body["preview"]["active"] == true
                        && body["preview"]["candidate"]["outputs"]
                            .as_array()
                            .is_some_and(|a| {
                                a.len() == 1 && a[0]["name"] == request.arguments["monitor"]
                            })))
        }
        _ => false,
    }
}
fn checked_response(raw: &[u8], request: &Request, successful_exit: bool) -> Value {
    let invalid = || reject(&request.request_id, "APPLY_VERIFICATION_FAILED");
    if raw.len() > MAX_REQUEST || !super::strict_json::validate(raw) {
        return invalid();
    }
    let response: Response = match serde_json::from_slice(raw) {
        Ok(v) => v,
        Err(_) => return invalid(),
    };
    let value: Value = match serde_json::from_slice(raw) {
        Ok(v) => v,
        Err(_) => return invalid(),
    };
    if response.protocol != "cortetsu.exec"
        || response.version.major != 1
        || response.version.minor != 0
        || response.request_id != request.request_id
        || !response.body.is_object()
        || response
            .transaction_id
            .as_ref()
            .is_some_and(|s| !valid_uuid(s))
        || (value.get("transaction_id").is_some() && response.transaction_id.is_none())
    {
        return invalid();
    }
    let mutation = !request.operation.ends_with(".status");
    let expected = if mutation { "applied" } else { "read" };
    if response.outcome == expected
        && response.verified
        && successful_exit
        && response.error.is_none()
        && value.get("error").is_none()
        && valid_body(&response.body, request)
    {
        return value;
    }
    if matches!(response.outcome.as_str(), "rejected" | "unknown")
        && !response.verified
        && response.body.as_object().is_some_and(|b| b.is_empty())
        && let Some(error) = response.error
        && known_error(&error.code)
    {
        let mut result = reject(&request.request_id, &error.code);
        result["outcome"] = json!(response.outcome);
        result["error"]["retryable"] = json!(error.retryable);
        return result;
    }
    invalid()
}

/// A bounded, nonblocking exchange. No pipe-reader threads may outlive this
/// request. SIGTERM gives a native owner time to reap its own process groups;
/// SIGKILL and wait finish cleanup after a fixed grace period.
fn forward_owner(
    binary: &std::path::Path,
    input: &[u8],
    request: &Request,
    started: Instant,
) -> Value {
    use nix::fcntl::{FcntlArg, OFlag, fcntl};
    use nix::{
        sys::signal::{Signal, killpg},
        unistd::{Pid, geteuid},
    };
    use std::io::{ErrorKind, Read, Write};
    use std::os::unix::{fs::MetadataExt, process::CommandExt};
    use std::process::{Child, Command, Stdio};
    fn signal(child: &Child, signal: Signal) {
        let _ = killpg(Pid::from_raw(child.id() as i32), signal);
    }
    fn terminate(child: &mut Child) {
        signal(child, Signal::SIGTERM);
        let end = Instant::now() + Duration::from_millis(100);
        while Instant::now() < end {
            if child.try_wait().ok().flatten().is_some() {
                break;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        signal(child, Signal::SIGKILL);
        let _ = child.wait();
    }
    let unavailable = || reject(&request.request_id, "OWNER_UNAVAILABLE");
    let Some(cancelled) = cancellation_flag() else {
        return unavailable();
    };
    let deadline = started + Duration::from_millis(request.deadline_ms as u64);
    if Instant::now() >= deadline || cancelled.load(std::sync::atomic::Ordering::Relaxed) {
        return reject(&request.request_id, "DEADLINE_EXCEEDED");
    }
    let safe = std::fs::symlink_metadata(binary).is_ok_and(|m| {
        m.is_file()
            && !m.file_type().is_symlink()
            && m.mode() & 0o022 == 0
            && m.mode() & 0o111 != 0
            && (m.uid() == 0 || m.uid() == geteuid().as_raw())
    });
    if !safe || !binary.is_absolute() {
        return unavailable();
    }
    let mut child = match Command::new(binary)
        .arg("exec")
        .process_group(0)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => return unavailable(),
    };
    let writer = child.stdin.take().unwrap();
    let mut reader = child.stdout.take().unwrap();
    fn nonblocking(fd: &impl std::os::fd::AsFd) -> bool {
        fcntl(fd, FcntlArg::F_GETFL)
            .and_then(|flags| {
                fcntl(
                    fd,
                    FcntlArg::F_SETFL(OFlag::from_bits_retain(flags) | OFlag::O_NONBLOCK),
                )
            })
            .is_ok()
    }
    if !nonblocking(&writer) || !nonblocking(&reader) {
        terminate(&mut child);
        return unavailable();
    }
    let mut writer = Some(writer);
    let mut sent = 0;
    let mut input_closed = false;
    let mut raw = Vec::new();
    let mut eof = false;
    let mut exit = None;
    loop {
        if Instant::now() >= deadline || cancelled.load(std::sync::atomic::Ordering::Relaxed) {
            terminate(&mut child);
            return reject(&request.request_id, "DEADLINE_EXCEEDED");
        }
        if !input_closed {
            match writer.as_mut().unwrap().write(&input[sent..]) {
                Ok(n) => sent += n,
                Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::Interrupted) => {}
                Err(_) => {
                    terminate(&mut child);
                    return reject(&request.request_id, "APPLY_VERIFICATION_FAILED");
                }
            }
            if sent == input.len() {
                drop(writer.take());
                input_closed = true;
            }
        }
        let mut chunk = [0_u8; 8192];
        loop {
            match reader.read(&mut chunk) {
                Ok(0) => {
                    eof = true;
                    break;
                }
                Ok(n) => {
                    raw.extend_from_slice(&chunk[..n]);
                    if raw.len() > MAX_REQUEST {
                        terminate(&mut child);
                        return reject(&request.request_id, "APPLY_VERIFICATION_FAILED");
                    }
                }
                Err(e) if e.kind() == ErrorKind::WouldBlock => break,
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(_) => {
                    terminate(&mut child);
                    return reject(&request.request_id, "APPLY_VERIFICATION_FAILED");
                }
            }
        }
        if exit.is_none() {
            match child.try_wait() {
                Ok(Some(status)) => {
                    exit = Some(status);
                    // A helper may have left descendants holding its stdout open.
                    signal(&child, Signal::SIGKILL);
                }
                Ok(None) => {}
                Err(_) => {
                    terminate(&mut child);
                    return unavailable();
                }
            }
        }
        if let Some(status) = exit
            && eof
        {
            return checked_response(&raw, request, status.success() && input_closed);
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn malformed_protocols_and_mutations_are_rejected() {
        let roots = Roots {
            data: "/this/path/does/not/exist".into(),
            runtime: "/no".into(),
        };
        let req = br#"{"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"00000000-0000-0000-0000-000000000001","operation":"gamemode.set","deadline_ms":5000,"arguments":{"enabled":true}}"#;
        assert_eq!(handle(req, &roots)["error"]["code"], "INVALID_REQUEST");
        let req = include_bytes!("../../contracts/exec/v1/fixtures/system-verify.json");
        assert_eq!(handle(req, &roots)["error"]["code"], "OWNER_UNAVAILABLE");
        let duplicate = br#"{"protocol":"cortetsu.exec","protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"00000000-0000-0000-0000-000000000001","operation":"system.verify","deadline_ms":5000,"arguments":{}}"#;
        assert_eq!(
            handle(duplicate, &roots)["error"]["code"],
            "INVALID_REQUEST"
        );
        let nested = br#"{"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"00000000-0000-0000-0000-000000000001","operation":"system.verify","deadline_ms":5000,"arguments":{"a":1,"a":2}}"#;
        assert_eq!(handle(nested, &roots)["error"]["code"], "INVALID_REQUEST");
        let negative = br#"{"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"00000000-0000-0000-0000-000000000001","operation":"system.verify","deadline_ms":5000,"arguments":{"a":-0}}"#;
        assert_eq!(handle(negative, &roots)["error"]["code"], "INVALID_REQUEST");
    }
}

#[cfg(test)]
#[path = "exec_forward_tests.rs"]
mod forward_tests;
