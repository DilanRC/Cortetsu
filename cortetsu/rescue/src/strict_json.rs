//! Reject ambiguous JSON before interpreting the versioned IPC envelope.
//!
//! serde_json normally accepts duplicate object members by keeping the last
//! value. The Go exec/1 validator rejects them, including nested duplicates.
//! All first-party Rust adapters must reject the same input before dispatch.
use serde::de::{self, Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use std::collections::HashSet;
use std::fmt;

struct Checked;

impl<'de> Deserialize<'de> for Checked {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        deserializer.deserialize_any(CheckedVisitor)
    }
}

struct CheckedVisitor;

impl<'de> Visitor<'de> for CheckedVisitor {
    type Value = Checked;

    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("a duplicate-free, finite JSON value")
    }

    fn visit_map<M>(self, mut map: M) -> Result<Self::Value, M::Error>
    where
        M: MapAccess<'de>,
    {
        let mut seen = HashSet::new();
        while let Some(key) = map.next_key::<String>()? {
            if !seen.insert(key) {
                return Err(de::Error::custom("duplicate JSON object key"));
            }
            map.next_value::<Checked>()?;
        }
        Ok(Checked)
    }

    fn visit_seq<S>(self, mut seq: S) -> Result<Self::Value, S::Error>
    where
        S: SeqAccess<'de>,
    {
        while seq.next_element::<Checked>()?.is_some() {}
        Ok(Checked)
    }

    fn visit_bool<E: de::Error>(self, _: bool) -> Result<Self::Value, E> {
        Ok(Checked)
    }
    fn visit_i64<E: de::Error>(self, _: i64) -> Result<Self::Value, E> {
        Ok(Checked)
    }
    fn visit_u64<E: de::Error>(self, _: u64) -> Result<Self::Value, E> {
        Ok(Checked)
    }
    fn visit_f64<E: de::Error>(self, value: f64) -> Result<Self::Value, E> {
        if !value.is_finite() || (value == 0.0 && value.is_sign_negative()) {
            return Err(de::Error::custom("non-finite number or negative zero"));
        }
        Ok(Checked)
    }
    fn visit_str<E: de::Error>(self, _: &str) -> Result<Self::Value, E> {
        Ok(Checked)
    }
    fn visit_string<E: de::Error>(self, _: String) -> Result<Self::Value, E> {
        Ok(Checked)
    }
    fn visit_none<E: de::Error>(self) -> Result<Self::Value, E> {
        Ok(Checked)
    }
    fn visit_unit<E: de::Error>(self) -> Result<Self::Value, E> {
        Ok(Checked)
    }
    fn visit_some<D: Deserializer<'de>>(self, d: D) -> Result<Self::Value, D::Error> {
        Checked::deserialize(d)
    }
}

pub fn validate(raw: &[u8]) -> bool {
    if raw.is_empty() || raw.len() > 64 * 1024 {
        return false;
    }
    let mut decoder = serde_json::Deserializer::from_slice(raw);
    if Checked::deserialize(&mut decoder).is_err() {
        return false;
    }
    decoder.end().is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn duplicate_keys_are_rejected_at_every_depth() {
        assert!(!validate(br#"{"a":1,"a":2}"#));
        assert!(!validate(br#"{"x":{"y":1,"y":2}}"#));
        assert!(validate(br#"[{"x":1},{"x":2}]"#));
        assert!(!validate(br#"{"a":1,"\u0061":2}"#));
    }

    #[test]
    fn invalid_unicode_numbers_and_partial_frames_fail_closed() {
        assert!(!validate(br#"{"a":-0}"#));
        assert!(!validate(br#"{"a":-0.0}"#));
        assert!(!validate(br#"{"a":1e999}"#));
        assert!(!validate(br#"{"a":"\uD800"}"#));
        assert!(!validate(b"{} {} "));
        assert!(!validate(br#"{"a": [1,2}"#));
        assert!(validate(br#"{"a":-1.0,"b":true,"c":null}"#));
    }
}
