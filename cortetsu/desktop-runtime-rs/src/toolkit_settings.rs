//! Documented desktop appearance preferences; no libadwaita CSS injection.
use crate::common::*;
use serde_json::{Value, json};
use std::fs;

const SCHEMA: &str = "org.gnome.desktop.interface";
fn get(key: &str) -> Result<Option<String>> {
    if which("gsettings").is_none() {
        return Ok(None);
    }
    let result = call("gsettings", &["get", SCHEMA, key], 5)?;
    if !result.status.success() {
        return Ok(None);
    }
    let value = String::from_utf8(result.stdout)?
        .trim()
        .trim_matches('\'')
        .to_owned();
    if value.is_empty() || !value.bytes().all(|c| c.is_ascii_lowercase() || c == b'-') {
        return Err("invalid desktop appearance value".into());
    }
    Ok(Some(value))
}
fn set(key: &str, value: &str) -> Result<()> {
    let result = call("gsettings", &["set", SCHEMA, key, value], 5)?;
    if !result.status.success() || get(key)?.as_deref() != Some(value) {
        return Err(format!("desktop {key} did not confirm its value").into());
    }
    Ok(())
}
fn persist(value: &Value) -> Result<()> {
    let path = state().join("theme-backups/desktop-appearance.json");
    let encoded = serde_json::to_vec_pretty(value)?;
    if fs::read(&path).ok().as_deref() != Some(encoded.as_slice()) {
        atomic(&path, &encoded, 0o600)?;
    }
    Ok(())
}
pub fn apply(mode: &str, colour: &Value) -> Result<Value> {
    let path = state().join("theme-backups/desktop-appearance.json");
    let mut record = json_object(&path)?;
    let accent = nearest_accent(&crate::theme_sync::hex(colour)?)?;
    let mut results = json!({});
    for (key, next) in [
        (
            "color-scheme",
            if mode == "light" {
                "prefer-light"
            } else {
                "prefer-dark"
            },
        ),
        ("accent-color", accent),
    ] {
        let Some(previous) = get(key)? else {
            results[key] = json!("unavailable");
            continue;
        };
        if record["original"].get(key).is_none() {
            record["original"][key] = json!(previous);
            persist(&record)?;
        }
        let original = record["original"][key].as_str();
        let last = record["last"][key].as_str();
        if Some(previous.as_str()) != original && Some(previous.as_str()) != last {
            results[key] = json!("external-change");
            continue;
        }
        if previous != next
            && let Err(error) = set(key, next)
        {
            let _ = set(key, &previous);
            return Err(error);
        }
        record["last"][key] = json!(next);
        persist(&record)?;
        results[key] = json!("applied");
    }
    Ok(results)
}
pub fn restore() -> Result<()> {
    let path = state().join("theme-backups/desktop-appearance.json");
    let mut record = json_object(&path)?;
    for key in ["color-scheme", "accent-color"] {
        if let Some(previous) = record["original"][key].as_str().map(str::to_owned)
            && get(key)?.as_deref() == record["last"][key].as_str()
        {
            set(key, &previous)?;
            record["last"][key] = json!(previous);
        }
    }
    if !record.as_object().is_some_and(|m| m.is_empty()) {
        persist(&record)?;
    }
    Ok(())
}
fn nearest_accent(hex: &str) -> Result<&'static str> {
    let rgb = (0..3)
        .map(|i| u8::from_str_radix(&hex[1 + i * 2..3 + i * 2], 16).map(|v| v as f64 / 255.0))
        .collect::<std::result::Result<Vec<_>, _>>()?;
    let (r, g, b) = (rgb[0], rgb[1], rgb[2]);
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let delta = max - min;
    if delta < 0.08 {
        return Ok("slate");
    }
    let h = 60.0
        * if max == r {
            ((g - b) / delta).rem_euclid(6.0)
        } else if max == g {
            (b - r) / delta + 2.0
        } else {
            (r - g) / delta + 4.0
        };
    Ok(if h < 15.0 {
        "red"
    } else if h < 45.0 {
        "orange"
    } else if h < 75.0 {
        "yellow"
    } else if h < 160.0 {
        "green"
    } else if h < 200.0 {
        "teal"
    } else if h < 260.0 {
        "blue"
    } else if h < 310.0 {
        "purple"
    } else if h < 345.0 {
        "pink"
    } else {
        "red"
    })
}
