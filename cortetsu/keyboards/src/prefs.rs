//! ~/.config/cortetsu/keyboards.json: what the key test verified, by
//! keyboard model. Fields this version does not know are kept.

use crate::store::{Paths, Result, atomic_write, refuse_symlink};
use serde_json::{Map, Value, json};
use std::collections::BTreeSet;
use std::fs;

fn codes_of(data: &Map<String, Value>, model: &str) -> BTreeSet<u16> {
    let codes = data.get("verified").and_then(|models| models.get(model)).and_then(Value::as_array);
    codes.into_iter().flatten().filter_map(Value::as_u64).filter_map(|c| u16::try_from(c).ok()).collect()
}

fn read(paths: &Paths) -> Option<Map<String, Value>> {
    match serde_json::from_str(&fs::read_to_string(&paths.keyboards).ok()?) {
        Ok(Value::Object(data)) => Some(data),
        _ => None,
    }
}

/// Codes verified for a keyboard model (`Keyboard::model`): a key exists on
/// every keyboard of the model, whatever port it is plugged into.
pub fn verified(paths: &Paths, model: &str) -> BTreeSet<u16> {
    read(paths).map(|data| codes_of(&data, model)).unwrap_or_default()
}

/// Add `hits` to the model's verified codes and return them all. An
/// unreadable file is refused, not replaced.
pub fn remember(paths: &Paths, model: &str, hits: &[u16]) -> Result<Vec<u16>> {
    let path = &paths.keyboards;
    let mut data = match read(paths) {
        Some(data) => data,
        None if path.exists() => return Err(format!("{} no es JSON válido", path.display())),
        None => Map::new(),
    };
    let mut all = codes_of(&data, model);
    all.extend(hits.iter().copied());
    let all: Vec<u16> = all.into_iter().collect();
    if hits.is_empty() {
        return Ok(all);
    }
    data.insert("schema".into(), json!(1));
    let models = data.entry("verified").or_insert_with(|| json!({}));
    if !models.is_object() {
        *models = json!({});
    }
    models[model] = json!(all);
    refuse_symlink(path)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let text = serde_json::to_string_pretty(&Value::Object(data)).map_err(|e| e.to_string())?;
    atomic_write(path, &(text + "\n"))?;
    Ok(all)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn paths(name: &str) -> Paths {
        let root = std::env::temp_dir().join(format!("cortetsu-prefs-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let mut paths = Paths::from_env();
        paths.keyboards = root.join("cortetsu/keyboards.json");
        paths
    }

    #[test]
    fn remembers_by_model_and_keeps_other_fields() {
        let paths = paths("keep");
        fs::create_dir_all(paths.keyboards.parent().unwrap()).unwrap();
        fs::write(&paths.keyboards, r#"{"other": 1, "verified": {"m2": [5]}}"#).unwrap();
        assert_eq!(remember(&paths, "m1", &[148, 140]).unwrap(), vec![140, 148]);
        assert_eq!(remember(&paths, "m1", &[140]).unwrap(), vec![140, 148]);
        assert_eq!(verified(&paths, "m1"), BTreeSet::from([140, 148]));
        assert_eq!(verified(&paths, "m2"), BTreeSet::from([5]));
        let data: Value = serde_json::from_str(&fs::read_to_string(&paths.keyboards).unwrap()).unwrap();
        assert_eq!(data["other"], 1);
        let _ = fs::remove_dir_all(paths.keyboards.parent().unwrap().parent().unwrap());
    }

    #[test]
    fn an_unreadable_file_is_not_replaced() {
        let paths = paths("broken");
        fs::create_dir_all(paths.keyboards.parent().unwrap()).unwrap();
        fs::write(&paths.keyboards, "{not json").unwrap();
        assert!(remember(&paths, "m1", &[140]).is_err());
        assert_eq!(fs::read_to_string(&paths.keyboards).unwrap(), "{not json");
        let _ = fs::remove_dir_all(paths.keyboards.parent().unwrap().parent().unwrap());
    }
}
