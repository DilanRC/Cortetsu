//! First cross-language `cortetsu.exec/1` adapter: read-only system.verify.
//!
//! The Go validator allows the same operation. This adapter intentionally
//! supports no mutating operation, command arrays, arbitrary paths or shells.
use super::{Roots, current};
use serde::Deserialize;
use serde_json::{Value, json};

const MAX_REQUEST: usize = 64 * 1024;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Version {
    major: u32,
    minor: u32,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct EmptyArguments {}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    protocol: String,
    version: Version,
    request_id: String,
    operation: String,
    deadline_ms: u32,
    arguments: EmptyArguments,
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
    if input.len() > MAX_REQUEST {
        return reject("", "FRAME_TOO_LARGE");
    }
    // serde_json's default struct deserializer accepts duplicate keys in
    // nested `arguments`; Go explicitly rejects them, so preflight the full
    // payload before interpreting any operation or constructing a response.
    if super::strict_json::validate(input).is_err() {
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
    if request.operation != "system.verify" {
        return reject(&request.request_id, "UNSUPPORTED_CAPABILITY");
    }
    let _ = request.arguments;
    match current(roots) {
        Ok(state) => json!({
            "protocol":"cortetsu.exec",
            "version":{"major":1,"minor":0},
            "request_id":request.request_id,
            "outcome":"read",
            "verified":true,
            "error":null,
            "body":{"system":state.system,"shell":state.shell,"dotfiles":state.dotfiles,"revision":state.revision},
        }),
        Err(_) => reject(&request.request_id, "OWNER_UNAVAILABLE"),
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
