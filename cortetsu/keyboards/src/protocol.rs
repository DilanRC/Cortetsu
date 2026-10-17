//! The JSON protocol QML reads.
//!
//! Version 2 (inventory, keys, watch…) wraps every answer in an envelope:
//!   {"protocol": 2, "kind": "<kind>", "ok": true, …payload}
//!   {"protocol": 2, "kind": "<kind>", "ok": false, "error": {"code", "message"}}
//! `code` is stable and meant for the UI to branch on; `message` is Spanish
//! text for a person. The legacy commands (list, set, delete, reset, add-app)
//! keep the version 1 shape of the Python helper unchanged.

use serde::Serialize;
use serde_json::{Map, Value, json};

pub const VERSION: u32 = 2;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error {
    pub code: &'static str,
    pub message: String,
}

impl Error {
    pub fn new(code: &'static str, message: impl Into<String>) -> Self {
        Error { code, message: message.into() }
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

/// `payload` must serialize to an object; its fields join the envelope.
pub fn ok(kind: &str, payload: impl Serialize) -> Value {
    let mut object = Map::new();
    object.insert("protocol".into(), json!(VERSION));
    object.insert("kind".into(), json!(kind));
    object.insert("ok".into(), json!(true));
    match serde_json::to_value(payload) {
        Ok(Value::Object(fields)) => object.extend(fields),
        other => debug_assert!(false, "protocol payload is not an object: {other:?}"),
    }
    Value::Object(object)
}

pub fn failure(kind: &str, error: &Error) -> Value {
    json!({
        "protocol": VERSION,
        "kind": kind,
        "ok": false,
        "error": {"code": error.code, "message": error.message},
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn envelope_carries_version_kind_and_payload() {
        let value = ok("inventory", json!({"keyboards": []}));
        assert_eq!(value, json!({"protocol": 2, "kind": "inventory", "ok": true, "keyboards": []}));
    }

    #[test]
    fn errors_have_a_stable_code_and_a_message() {
        let value = failure("keys", &Error::new("unknown-device", "Ese teclado ya no está conectado"));
        assert_eq!(value["error"]["code"], "unknown-device");
        assert_eq!(value["ok"], false);
    }
}
