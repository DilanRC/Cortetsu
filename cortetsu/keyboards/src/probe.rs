//! `probe begin DEVICE MS | status | end`: the key test of «Teclas por
//! aprovechar», the only way a key becomes VERIFIED.
//!
//! A declared key is only what the driver could send. To prove a key exists,
//! the editor asks the user to press it: hyprland/keybinds.lua binds every
//! spare key of one keyboard, by keycode and on that keyboard alone, to a
//! function that records the press and does nothing else
//! (`cortetsu_probe_begin`). `end` removes the binds and remembers the codes
//! pressed for that keyboard model in ~/.config/cortetsu/keyboards.json;
//! `keys` reads them back. The binds also go on a timer and with a reload,
//! so a dead editor never leaves keys swallowed.

use crate::inventory::{self, Keyboard};
use crate::protocol::Error;
use crate::store::{Paths, atomic_write, refuse_symlink};
use crate::{hypr, keymap, keys, lua};
use serde::Serialize;
use serde_json::{Map, Value, json};
use std::collections::BTreeSet;
use std::fs;
use std::path::PathBuf;
use std::time::Duration;

const TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    pub active: bool,
    /// Codes pressed during the current (or just ended) test.
    pub hits: Vec<u16>,
    /// Codes under test; only `begin` knows them.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub codes: Vec<u16>,
    /// Every code verified for this keyboard model so far; `end` only.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verified: Option<Vec<u16>>,
}

/// `A=1 H=140,148`, what the Lua side answers.
fn parse_report(text: &str) -> Option<(bool, Vec<u16>)> {
    let (active, hits) = text.trim().split_once(' ')?;
    let active = match active {
        "A=1" => true,
        "A=0" => false,
        _ => return None,
    };
    let hits = hits.strip_prefix("H=")?;
    let codes = hits.split(',').filter(|c| !c.is_empty()).map(|c| c.parse().ok()).collect::<Option<Vec<u16>>>()?;
    Some((active, codes))
}

fn call(code: &str) -> Result<(bool, Vec<u16>), Error> {
    let text = hypr::run(&["repl", code], TIMEOUT)
        .ok_or_else(|| Error::new("hyprland-unavailable", "No se pudo hablar con Hyprland"))?;
    parse_report(&text).ok_or_else(|| {
        Error::new(
            "probe-unavailable",
            format!("La configuración cargada no admite la prueba de teclas; recarga Hyprland ({})", text.trim()),
        )
    })
}

/// Where verified keys are remembered, next to the keybind store.
fn prefs_path() -> PathBuf {
    Paths::from_env().store.with_file_name("keyboards.json")
}

fn codes_of(data: &Map<String, Value>, model: &str) -> BTreeSet<u16> {
    let codes = data.get("verified").and_then(|models| models.get(model)).and_then(Value::as_array);
    codes.into_iter().flatten().filter_map(Value::as_u64).filter_map(|c| u16::try_from(c).ok()).collect()
}

fn read_prefs() -> Option<Map<String, Value>> {
    match serde_json::from_str(&fs::read_to_string(prefs_path()).ok()?) {
        Ok(Value::Object(data)) => Some(data),
        _ => None,
    }
}

/// Codes verified for a keyboard model (`Keyboard::model`): a key exists on
/// every keyboard of the model, whatever port it is plugged into.
pub fn verified(model: &str) -> BTreeSet<u16> {
    read_prefs().map(|data| codes_of(&data, model)).unwrap_or_default()
}

/// Add `hits` to the model's verified codes; other fields are kept.
fn remember(model: &str, hits: &[u16]) -> Result<Vec<u16>, Error> {
    let path = prefs_path();
    let failed = |e: String| Error::new("prefs", format!("No se pudo guardar la prueba: {e}"));
    let mut data = match read_prefs() {
        Some(data) => data,
        None if path.exists() => return Err(failed(format!("{} no es JSON válido", path.display()))),
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
    refuse_symlink(&path).map_err(failed)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| failed(e.to_string()))?;
    }
    let text = serde_json::to_string_pretty(&Value::Object(data)).map_err(|e| failed(e.to_string()))?;
    atomic_write(&path, &(text + "\n")).map_err(failed)?;
    Ok(all)
}

fn keyboard(id: &str) -> Result<Keyboard, Error> {
    inventory::now()
        .keyboards
        .into_iter()
        .find(|k| k.id == id)
        .ok_or_else(|| Error::new("unknown-device", format!("El teclado {id} no está conectado")))
}

/// The keys a test asks for: the keyboard's spare keys, which have no
/// action to swallow while the test binds them.
pub fn testable(keyboard: &Keyboard) -> Vec<u16> {
    let keymap = keyboard.interfaces.iter().find_map(|i| i.layout.clone()).and_then(|l| keymap::compile(&l));
    let binds = hypr::binds();
    keys::classify(keyboard, keymap.as_ref(), binds.as_deref(), &BTreeSet::new())
        .into_iter()
        .filter(|k| k.has(keys::State::Candidate))
        .map(|k| k.code)
        .collect()
}

pub fn begin(device: &str, timeout_ms: u32) -> Result<Status, Error> {
    let keyboard = keyboard(device)?;
    let names = keyboard.hyprland_names();
    if !keyboard.hyprland_linked || names.is_empty() {
        return Err(Error::new(
            "not-linked",
            "Hyprland no distingue este teclado de otro igual; desconecta uno para probarlo",
        ));
    }
    let codes = testable(&keyboard);
    if codes.is_empty() {
        return Err(Error::new("nothing-to-test", "Este teclado no tiene teclas por aprovechar que probar"));
    }
    let names: Vec<String> = names.iter().map(|n| lua::quote(n)).collect();
    let list: Vec<String> = codes.iter().map(u16::to_string).collect();
    let code =
        format!("return cortetsu_probe_begin({{ {} }}, {{ {} }}, {timeout_ms})", names.join(", "), list.join(", "));
    let (active, hits) = call(&code)?;
    if !active {
        return Err(Error::new("probe-failed", "Hyprland no empezó la prueba de teclas"));
    }
    Ok(Status { active, hits, codes, verified: None })
}

pub fn status() -> Result<Status, Error> {
    let (active, hits) = call("return cortetsu_probe_status()")?;
    Ok(Status { active, hits, codes: Vec::new(), verified: None })
}

/// End the test and remember what was pressed for `device`'s model.
pub fn end(device: &str) -> Result<Status, Error> {
    let (active, hits) = call("return cortetsu_probe_end()")?;
    if active {
        return Err(Error::new("probe-failed", "Hyprland sigue con la prueba de teclas"));
    }
    let keyboard = keyboard(device)?;
    // Only codes this keyboard declares: a stale report cannot verify keys
    // of another model.
    let declared = keyboard.codes();
    let hits: Vec<u16> = hits.into_iter().filter(|c| declared.contains(c)).collect();
    let verified = remember(&keyboard.model, &hits)?;
    Ok(Status { active, hits, codes: Vec::new(), verified: Some(verified) })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_lua_report() {
        assert_eq!(parse_report("A=1 H=\n"), Some((true, vec![])));
        assert_eq!(parse_report("A=0 H=140,148"), Some((false, vec![140, 148])));
        assert_eq!(parse_report("error: attempt to call a nil value"), None);
        assert_eq!(parse_report("A=1 H=x"), None);
    }
}
