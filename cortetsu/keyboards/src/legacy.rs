//! The keybind editor's version 1 commands, ported from the Python helper
//! (`cortetsu/bin/cortetsu-keybinds` at 6e3fdaf) with the same contract:
//! `list`, `set ID CHORD`, `delete ID`, `reset ID`,
//! `add-app APP_ID NAME COMMAND CHORD`, answering `{"ok": …}` JSON.
//!
//! The defaults (variables.lua, hyprland/keybinds.lua) and the user layer
//! (hypr-user.lua) belong to the promoted dotfiles generation and are read
//! only. Edits live in ~/.config/cortetsu/keybinds.json and are compiled into
//! ~/.config/hypr/cortetsu-keybinds.lua, plain data that hyprland.lua applies
//! on every load. Every change is a transaction: snapshot, atomic write, luac
//! check, reload, then a check of `hyprctl binds -j` by bind description,
//! rolling back if Hyprland does not show the expected result.

use crate::lua::{self, Action};
use crate::store::{Store, commit, load_store, text};
use crate::{hypr, sha256};
use serde_json::{Map, Value, json};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

pub type Result<T> = std::result::Result<T, String>;

/// Bind descriptions shared with the Lua side: keybinds.lua tags kb* binds
/// with "cortetsu:<variable>", hyprland.lua tags edits "cortetsu-keybinds:<id>".
pub const VAR_TAG: &str = "cortetsu:";
pub const EDIT_TAG: &str = "cortetsu-keybinds:";

const MODIFIERS: [&str; 7] = ["SHIFT", "CTRL", "CONTROL", "ALT", "SUPER", "WIN", "MOD4"];
const APP_COMMANDS: [(&str, &str); 5] = [
    ("kbTerminal", "terminal"),
    ("kbBrowser", "browser"),
    ("kbEditor", "editor"),
    ("kbFileExplorer", "fileExplorer"),
    ("kbAudioSettings", "audioSettings"),
];
const NAMED_KEYS: [&str; 33] = [
    "Return",
    "Space",
    "Tab",
    "Backspace",
    "Delete",
    "Insert",
    "Home",
    "End",
    "Page_Up",
    "Page_Down",
    "Left",
    "Right",
    "Up",
    "Down",
    "Print",
    "Pause",
    "Escape",
    "Comma",
    "Period",
    "Slash",
    "Backslash",
    "Minus",
    "Equal",
    "Semicolon",
    "Apostrophe",
    "Grave",
    "BracketLeft",
    "BracketRight",
    "Menu",
    "SUPER_L",
    "SUPER_R",
    "mouse_up",
    "mouse_down",
];

pub struct Paths {
    pub defaults: PathBuf,
    pub first_party: PathBuf,
    pub user: PathBuf,
    pub store: PathBuf,
    pub compiled: PathBuf,
    pub snapshots: PathBuf,
}

impl Paths {
    pub fn from_env() -> Self {
        let home = PathBuf::from(crate::env_or("HOME", "/"));
        let config = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|| home.join(".config"));
        let hypr = home.join(".config/hypr");
        Paths {
            defaults: hypr.join("variables.lua"),
            first_party: hypr.join("hyprland/keybinds.lua"),
            user: hypr.join("hypr-user.lua"),
            store: config.join("cortetsu/keybinds.json"),
            compiled: hypr.join("cortetsu-keybinds.lua"),
            snapshots: home.join(".local/share/cortetsu/snapshots/keybinds"),
        }
    }
}

// --- chords -----------------------------------------------------------------

fn split_chord(chord: &str) -> Vec<&str> {
    chord.split('+').map(str::trim).filter(|part| !part.is_empty()).collect()
}

pub fn normalise(chord: &str) -> String {
    let parts: Vec<String> = split_chord(chord).iter().map(|part| part.to_uppercase()).collect();
    let Some((key, mods)) = parts.split_last() else { return String::new() };
    let mut mods: Vec<String> = mods
        .iter()
        .map(|part| match part.as_str() {
            "CONTROL" => "CTRL".to_owned(),
            "WIN" | "MOD4" => "SUPER".to_owned(),
            _ => part.clone(),
        })
        .collect();
    mods.sort();
    mods.dedup();
    mods.push(key.clone());
    mods.join("+")
}

/// (modmask, KEY) as `hyprctl binds -j` reports them; unknown modifiers add nothing.
pub fn chord_parts(chord: &str) -> (u32, String) {
    let parts = split_chord(chord);
    let Some((key, mods)) = parts.split_last() else { return (0, String::new()) };
    let mask = mods.iter().map(|m| mod_bit(m).unwrap_or(0)).fold(0, |a, b| a | b);
    (mask, key.to_uppercase())
}

fn mod_bit(name: &str) -> Option<u32> {
    Some(match name.to_ascii_uppercase().as_str() {
        "SHIFT" => hypr::MOD_SHIFT,
        "CAPS" => 2,
        "CTRL" | "CONTROL" => hypr::MOD_CTRL,
        "ALT" => hypr::MOD_ALT,
        "MOD2" => 16,
        "MOD3" => 32,
        "SUPER" | "WIN" | "MOD4" => hypr::MOD_SUPER,
        "MOD5" => hypr::MOD_MOD5,
        _ => return None,
    })
}

fn only_modifiers(chord: &str) -> bool {
    split_chord(chord).iter().all(|part| MODIFIERS.contains(&part.to_uppercase().as_str()))
}

fn digits(text: &str) -> bool {
    !text.is_empty() && text.bytes().all(|b| b.is_ascii_digit())
}

fn alnum(text: &str) -> bool {
    !text.is_empty() && text.bytes().all(|b| b.is_ascii_alphanumeric())
}

/// A key name Hyprland accepts (case-insensitive, like the Python regex).
fn key_name_ok(key: &str) -> bool {
    let upper = key.to_ascii_uppercase();
    let function_number =
        |rest: &str| rest.parse::<u8>().is_ok_and(|n| (1..=24).contains(&n)) && !rest.starts_with('0');
    (key.len() == 1 && key.bytes().all(|b| b.is_ascii_alphanumeric()))
        || upper.strip_prefix('F').is_some_and(function_number)
        || upper
            .strip_prefix("KP_")
            .is_some_and(|rest| !rest.is_empty() && rest.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_'))
        || upper.strip_prefix("XF86").is_some_and(alnum)
        || upper.strip_prefix("CODE:").is_some_and(digits)
        || upper.strip_prefix("MOUSE:").is_some_and(digits)
        || NAMED_KEYS.iter().any(|name| name.eq_ignore_ascii_case(key))
}

/// Keys pressed alone by design: dedicated hardware and spare F-keys.
fn solo_key(key: &str) -> bool {
    let upper = key.to_ascii_uppercase();
    upper.strip_prefix("XF86").is_some_and(alnum)
        || upper == "PRINT"
        || upper
            .strip_prefix('F')
            .and_then(|n| n.parse::<u8>().ok().filter(|_| !n.starts_with('0')))
            .is_some_and(|n| (13..=24).contains(&n))
}

/// The chord as stored, or an error a person can act on.
pub fn validate_chord(chord: &str) -> Result<String> {
    let parts = split_chord(chord);
    let Some((key, mods)) = parts.split_last() else {
        return Err("Hace falta una combinación de teclas".into());
    };
    for modifier in mods {
        let upper = modifier.to_uppercase();
        if ["MOD5", "ALTGR", "ISO_LEVEL3_SHIFT"].contains(&upper.as_str()) {
            return Err("AltGr escribe caracteres en la distribución latam; no se puede usar en atajos".into());
        }
        if !MODIFIERS.contains(&upper.as_str()) {
            return Err(format!("{modifier} no es un modificador (Super, Ctrl, Alt o Shift)"));
        }
    }
    if MODIFIERS.contains(&key.to_uppercase().as_str()) || !key_name_ok(key) {
        return Err(format!("{key} no es una tecla que Hyprland reconozca"));
    }
    let upper: Vec<String> = mods.iter().map(|m| m.to_uppercase()).collect();
    let has = |name: &str| upper.iter().any(|m| m == name);
    if mods.is_empty() && !solo_key(key) {
        return Err("Una tecla sola interceptaría la escritura; añade Super".into());
    }
    let super_held = has("SUPER") || has("WIN") || has("MOD4");
    if !mods.is_empty() && !super_held && !solo_key(key) && !(has("CTRL") && has("ALT")) {
        // CTRL + End, CTRL + Down: the navigation the old app shortcuts stole.
        return Err("Sin Super la combinación pertenece a las aplicaciones; usa Super o Ctrl + Alt".into());
    }
    Ok(upper.iter().map(String::as_str).chain([*key]).collect::<Vec<_>>().join(" + "))
}

// --- what Hyprland ends up with ---------------------------------------------

fn title(name: &str) -> String {
    let bare = name.strip_prefix("kb").unwrap_or(name);
    let mut spaced = String::new();
    let mut previous: Option<char> = None;
    for c in bare.chars() {
        if previous.is_some_and(|p| p.is_ascii_lowercase()) && c.is_ascii_uppercase() {
            spaced.push(' ');
        }
        spaced.push(c);
        previous = Some(c);
    }
    let replaced = spaced.replace("Ws", "workspace");
    // str.title(): a letter after a non-letter starts a word.
    let mut out = String::new();
    let mut after_letter = false;
    for c in replaced.trim().chars() {
        if c.is_alphabetic() {
            if after_letter {
                out.extend(c.to_lowercase());
            } else {
                out.extend(c.to_uppercase());
            }
            after_letter = true;
        } else {
            out.push(c);
            after_letter = false;
        }
    }
    out
}

fn digest(parts: &[&str]) -> String {
    sha256::hex(parts.join("\0").as_bytes())[..16].to_owned()
}

type Item = Map<String, Value>;

fn item(value: Value) -> Item {
    match value {
        Value::Object(map) => map,
        _ => Map::new(),
    }
}

fn s<'a>(item: &'a Item, field: &str) -> &'a str {
    item.get(field).and_then(Value::as_str).unwrap_or("")
}

fn flag(item: &Item, field: &str) -> bool {
    item.get(field).and_then(Value::as_bool).unwrap_or(false)
}

fn user_bindings(paths: &Paths, store: &Store) -> Vec<Item> {
    let Ok(text) = fs::read_to_string(&paths.user) else { return Vec::new() };
    let removed: Vec<String> = store.unbind.iter().map(|chord| normalise(chord)).collect();
    let mut result = Vec::new();
    for block in lua::binding_blocks(&text) {
        let action = lua::simple_action(&block.body);
        let (target, command) = match &action {
            Some(Action::Global(name)) => (name.clone(), String::new()),
            Some(Action::Exec(command)) => (String::new(), command.clone()),
            None => (String::new(), String::new()),
        };
        let app = lua::generated_app(&text, block.start);
        let label = match &app {
            Some((name, _)) => name.clone(),
            None => [target.replace("cortetsu:", "Cortetsu · "), command.clone()]
                .into_iter()
                .find(|value| !value.is_empty())
                .unwrap_or_else(|| "Acción Lua".into()),
        };
        let description = [command.clone(), target.clone()]
            .into_iter()
            .find(|value| !value.is_empty())
            .unwrap_or_else(|| "Acción Lua de hypr-user.lua".into());
        let action_json = match &action {
            Some(Action::Global(name)) => json!({ "global": name }),
            Some(Action::Exec(command)) => json!({ "exec": command }),
            None => Value::Null,
        };
        let mut entry = item(json!({
            "id": format!("user:{}", digest(&[&block.chord, &block.body])),
            "label": label,
            "chord": block.chord,
            "group": if app.is_some() { "Application" } else { "Custom" },
            "description": description,
            "command": command,
            "origin": "user",
            "editable": action.is_some(),
            "action": action_json,
            "deletable": true,
            "active": !removed.contains(&normalise(&block.chord)),
        }));
        if let Some((name, id)) = app {
            entry.insert("appName".into(), json!(name));
            entry.insert("appId".into(), json!(id));
        }
        if action.is_none() {
            entry.insert("note".into(), json!("Acción Lua: se cambia en hypr-user.lua"));
        }
        result.push(entry);
    }
    result
}

/// Binds keybinds.lua writes with a fixed chord: hardware keys and the like.
fn first_party_literals(paths: &Paths) -> Vec<Item> {
    let Ok(text) = fs::read_to_string(&paths.first_party) else { return Vec::new() };
    let mut result = Vec::new();
    for (chords, action) in lua::literal_binds(&text) {
        let target = action
            .find("hl.dsp.global(\"")
            .map(|at| &action[at + "hl.dsp.global(\"".len()..])
            .and_then(|rest| rest.find('"').filter(|&end| end > 0).map(|end| rest[..end].to_owned()));
        let command = action.find("hl.dsp.exec_cmd(\"").map(|at| {
            let rest = &action[at + "hl.dsp.exec_cmd(".len()..];
            lua::strings(rest).into_iter().next().unwrap_or_default()
        });
        for chord in chords {
            let hardware = chord.to_uppercase().starts_with("XF86");
            let label = match (&target, &command) {
                (Some(target), _) => target.replace("cortetsu:", "Cortetsu · "),
                (None, Some(command)) => command.clone(),
                (None, None) => chord.clone(),
            };
            result.push(item(json!({
                "id": format!("fixed:{}", digest(&[&chord])),
                "label": label,
                "chord": chord,
                "group": if hardware { "Hardware" } else { "Cortetsu" },
                "description": if hardware { "Tecla del equipo" } else { "Atajo fijo de Cortetsu" },
                "command": "",
                "origin": "fixed",
                "editable": false,
                "deletable": false,
                "active": true,
                "reserved": true,
            })));
        }
    }
    result
}

fn defaults(paths: &Paths) -> Result<Vec<(String, Vec<String>)>> {
    fs::read_to_string(&paths.defaults)
        .map(|text| lua::entries(&text))
        .map_err(|e| format!("{}: {e}", paths.defaults.display()))
}

fn default_of(defaults: &[(String, Vec<String>)], name: &str) -> Vec<String> {
    defaults.iter().find(|(n, _)| n == name).map(|(_, v)| v.clone()).unwrap_or_default()
}

pub fn list_bindings(paths: &Paths) -> Result<Vec<Item>> {
    let store = load_store(&paths.store)?;
    let defaults = defaults(paths)?;
    let effective = |name: &str| store.variables.get(name).cloned().unwrap_or_else(|| default_of(&defaults, name));
    let first_party = fs::read_to_string(&paths.first_party).unwrap_or_default();
    // Only variables the Lua actually binds; a defined but unused kb* would
    // list a shortcut that never exists.
    let used = lua::used_variables(&first_party);
    let mut result = Vec::new();
    for (name, default_values) in &defaults {
        if !used.contains(name) || (!default_values.is_empty() && default_values.iter().all(|c| only_modifiers(c))) {
            continue;
        }
        let edited = store.variables.contains_key(name);
        let current = store.variables.get(name).unwrap_or(default_values);
        let command = APP_COMMANDS
            .iter()
            .find(|(variable, _)| variable == name)
            .and_then(|(_, command)| effective(command).into_iter().next())
            .unwrap_or_default();
        let app_query = if name == "kbTerminal" {
            "kitty".to_owned()
        } else {
            // Path(first).name: the last component, a trailing slash ignored.
            let first = command.split_whitespace().next().unwrap_or("").trim_end_matches('/');
            first.rsplit('/').next().unwrap_or(first).to_owned()
        };
        for (index, chord) in current.iter().enumerate() {
            result.push(item(json!({
                "id": format!("var:{name}:{index}"), "label": title(name), "chord": chord,
                "group": if command.is_empty() { "Cortetsu" } else { "Application" },
                "description": if command.is_empty() { title(name) } else { command.clone() },
                "command": command, "appQuery": app_query,
                "origin": if edited { "edited" } else { "default" }, "variable": name,
                "editable": true, "deletable": true, "resettable": edited, "active": true,
            })));
        }
        if edited && current.is_empty() {
            result.push(item(json!({
                "id": format!("var:{name}:-"), "label": title(name), "chord": "", "group": "Cortetsu",
                "description": "Sin combinación", "command": command, "origin": "edited", "variable": name,
                "editable": false, "deletable": false, "resettable": true, "active": false,
            })));
        }
    }
    for mut entry in user_bindings(paths, &store) {
        let active = flag(&entry, "active");
        entry.insert("resettable".into(), json!(!active));
        result.push(entry);
    }
    for bind in &store.binds {
        let global = text(bind, "global").unwrap_or("");
        let exec = text(bind, "exec").unwrap_or("");
        let name = text(bind, "name").unwrap_or("");
        let label = [name.to_owned(), global.replace("cortetsu:", "Cortetsu · "), exec.to_owned()]
            .into_iter()
            .find(|value| !value.is_empty())
            .unwrap_or_default();
        let app_id = text(bind, "appId").unwrap_or("");
        result.push(item(json!({
            "id": text(bind, "id"), "label": label, "chord": text(bind, "chord"),
            "group": if app_id.is_empty() { "Custom" } else { "Application" },
            "description": if exec.is_empty() { global } else { exec }, "command": exec,
            "appName": name, "appId": app_id, "origin": "edited",
            "editable": true, "deletable": true,
            "resettable": text(bind, "replaces").is_some_and(|r| !r.is_empty()), "active": true,
        })));
    }
    result.extend(first_party_literals(paths));

    let mut owners: BTreeMap<String, Vec<(String, String)>> = BTreeMap::new();
    for entry in &result {
        if flag(entry, "active") && !s(entry, "chord").is_empty() {
            owners
                .entry(normalise(s(entry, "chord")))
                .or_default()
                .push((s(entry, "id").into(), s(entry, "label").into()));
        }
    }
    for entry in &mut result {
        let conflicts: Vec<String> = if flag(entry, "active") {
            owners
                .get(&normalise(s(entry, "chord")))
                .into_iter()
                .flatten()
                .filter(|(id, _)| id != s(entry, "id"))
                .map(|(_, label)| label.clone())
                .collect()
        } else {
            Vec::new()
        };
        entry.insert("conflicts".into(), json!(conflicts));
    }
    result.sort_by(|a, b| {
        (s(a, "group"), s(a, "label"), s(a, "chord")).cmp(&(s(b, "group"), s(b, "label"), s(b, "chord")))
    });
    Ok(result)
}

pub(crate) fn live_binds() -> Option<Vec<hypr::Bind>> {
    hypr::run(&["binds", "-j"], Duration::from_secs(10)).and_then(|text| serde_json::from_str(&text).ok())
}

fn binds_on(chord: &str) -> usize {
    let (mask, key) = chord_parts(chord);
    live_binds().unwrap_or_default().iter().filter(|b| b.modmask == mask && b.key.to_uppercase() == key).count()
}

fn ensure_free(chord: &str, own: &[String], items: &[Item]) -> Result<()> {
    let wanted = normalise(chord);
    for entry in items {
        let other = normalise(s(entry, "chord"));
        if flag(entry, "active") && !s(entry, "chord").is_empty() && other == wanted && !own.contains(&other) {
            return Err(format!("{chord} ya es «{}»", s(entry, "label")));
        }
    }
    if own.contains(&wanted) {
        return Ok(());
    }
    // Workspace binds are generated in Lua and only Hyprland knows them all.
    let (mask, key) = chord_parts(chord);
    if live_binds().unwrap_or_default().iter().any(|b| b.modmask == mask && b.key.to_uppercase() == key) {
        return Err(format!("{chord} ya lo usa otra acción de Hyprland"));
    }
    Ok(())
}

// --- commands ---------------------------------------------------------------

fn parse_var_id(identifier: &str) -> Result<(String, Option<usize>)> {
    let mut parts = identifier.splitn(3, ':');
    let (_, name, raw) = (parts.next(), parts.next().unwrap_or(""), parts.next().unwrap_or(""));
    if raw == "-" {
        return Ok((name.to_owned(), None));
    }
    raw.parse().map(|index| (name.to_owned(), Some(index))).map_err(|_| "Ese atajo ya no existe".into())
}

fn find<'a>(identifier: &str, items: &'a [Item]) -> Result<&'a Item> {
    items.iter().find(|entry| s(entry, "id") == identifier).ok_or_else(|| "Ese atajo ya no existe".into())
}

fn has_conflicts(entry: &Item) -> bool {
    entry.get("conflicts").and_then(Value::as_array).is_some_and(|c| !c.is_empty())
}

/// The old chord, when moving away from it should leave it unbound.
fn vacated(entry: &Item, chord: &str) -> Vec<String> {
    if has_conflicts(entry) || normalise(s(entry, "chord")) == normalise(chord) {
        Vec::new()
    } else {
        vec![s(entry, "chord").to_owned()]
    }
}

/// Give a hypr-user chord back: drop its removal and any edit replacing it.
fn unrestricted(store: &mut Store, chord: &str) {
    let wanted = normalise(chord);
    store.unbind.retain(|other| normalise(other) != wanted);
    store.binds.retain(|bind| normalise(text(bind, "replaces").unwrap_or("")) != wanted);
}

fn variable_slot(store: &Store, defaults: &[(String, Vec<String>)], name: &str) -> Vec<String> {
    store.variables.get(name).cloned().unwrap_or_else(|| default_of(defaults, name))
}

fn saved_reply(saved: &Path, extra: Value) -> Value {
    let mut reply = item(json!({ "ok": true, "snapshot": saved.display().to_string() }));
    if let Value::Object(fields) = extra {
        reply.extend(fields);
    }
    Value::Object(reply)
}

pub fn set_binding(paths: &Paths, identifier: &str, raw_chord: &str) -> Result<Value> {
    let chord = validate_chord(raw_chord)?;
    let items = list_bindings(paths)?;
    let entry = find(identifier, &items)?;
    if !flag(entry, "editable") {
        let note = s(entry, "note");
        return Err(if note.is_empty() { "Este atajo no se puede cambiar desde aquí".into() } else { note.into() });
    }
    let mut store = load_store(&paths.store)?;
    let current_chord = s(entry, "chord").to_owned();
    ensure_free(&chord, &[normalise(&current_chord)], &items)?;
    let saved = if identifier.starts_with("var:") {
        let (name, index) = parse_var_id(identifier)?;
        let mut current = variable_slot(&store, &defaults(paths)?, &name);
        let slot = index.and_then(|i| current.get_mut(i)).ok_or("Ese atajo ya no existe")?;
        *slot = chord.clone();
        store.variables.insert(name.clone(), current);
        commit(paths, &store, &[(chord.clone(), format!("{VAR_TAG}{name}"))], &vacated(entry, &chord))?
    } else if identifier.starts_with("user:") {
        if has_conflicts(entry) || binds_on(&current_chord) > 1 {
            return Err(format!("{current_chord} también lo usa otra acción; cámbiala primero"));
        }
        // Keyed by the chord it replaces, which is also what unbind stores, so
        // an edit of the line in hypr-user.lua does not orphan it.
        let replacement = format!("edit:{}", digest(&[&normalise(&current_chord)]));
        unrestricted(&mut store, &current_chord);
        store.unbind.push(current_chord.clone());
        let name = [s(entry, "appName"), s(entry, "label")].into_iter().find(|v| !v.is_empty()).unwrap_or("");
        let mut bind = item(json!({
            "id": replacement, "chord": chord, "replaces": current_chord, "name": name, "appId": s(entry, "appId"),
        }));
        if let Some(Value::Object(action)) = entry.get("action") {
            bind.extend(action.clone());
        }
        store.binds.push(bind);
        commit(paths, &store, &[(chord.clone(), format!("{EDIT_TAG}{replacement}"))], &[current_chord])?
    } else {
        for bind in &mut store.binds {
            if text(bind, "id") == Some(identifier) {
                bind.insert("chord".into(), json!(chord));
            }
        }
        commit(paths, &store, &[(chord.clone(), format!("{EDIT_TAG}{identifier}"))], &vacated(entry, &chord))?
    };
    Ok(saved_reply(&saved, json!({ "chord": chord, "message": format!("Guardado · {chord}") })))
}

pub fn delete_binding(paths: &Paths, identifier: &str) -> Result<Value> {
    let items = list_bindings(paths)?;
    let entry = find(identifier, &items)?;
    if !flag(entry, "deletable") {
        return Err("Este atajo no se puede eliminar desde aquí".into());
    }
    let mut store = load_store(&paths.store)?;
    let chord = s(entry, "chord").to_owned();
    if identifier.starts_with("var:") {
        let (name, index) = parse_var_id(identifier)?;
        let mut current = variable_slot(&store, &defaults(paths)?, &name);
        match index.filter(|&i| i < current.len()) {
            Some(i) => current.remove(i),
            None => return Err("Ese atajo ya no existe".into()),
        };
        store.variables.insert(name, current);
    } else if identifier.starts_with("user:") {
        if has_conflicts(entry) || binds_on(&chord) > 1 {
            return Err(format!("{chord} también lo usa otra acción; quitarlo las borraría todas"));
        }
        store.unbind.push(chord.clone());
    } else {
        // Deleting the edit of a hypr-user bind leaves the original removed;
        // resetting the original brings it back.
        store.binds.retain(|bind| text(bind, "id") != Some(identifier));
    }
    let absent = if has_conflicts(entry) { Vec::new() } else { vec![chord] };
    let saved = commit(paths, &store, &[], &absent)?;
    Ok(saved_reply(&saved, json!({ "message": format!("Eliminado · {}", s(entry, "label")) })))
}

pub fn reset_binding(paths: &Paths, identifier: &str) -> Result<Value> {
    let items = list_bindings(paths)?;
    let entry = find(identifier, &items)?;
    if !flag(entry, "resettable") {
        return Err("Este atajo no tiene cambios que deshacer".into());
    }
    let mut store = load_store(&paths.store)?;
    let mut present = Vec::new();
    if identifier.starts_with("var:") {
        let (name, _) = parse_var_id(identifier)?;
        store.variables.remove(&name);
        present =
            default_of(&defaults(paths)?, &name).into_iter().map(|chord| (chord, format!("{VAR_TAG}{name}"))).collect();
    } else if identifier.starts_with("user:") {
        unrestricted(&mut store, s(entry, "chord"));
    } else {
        let replaces = store
            .binds
            .iter()
            .find(|bind| text(bind, "id") == Some(identifier))
            .and_then(|bind| text(bind, "replaces"))
            .filter(|r| !r.is_empty())
            .map(str::to_owned)
            .ok_or("Este atajo no tiene cambios que deshacer")?;
        unrestricted(&mut store, &replaces);
    }
    let saved = commit(paths, &store, &present, &[])?;
    Ok(saved_reply(&saved, json!({ "message": format!("Restablecido · {}", s(entry, "label")) })))
}

/// The Exec line without desktop-entry field codes (%U, %f…).
fn without_field_codes(command: &str) -> String {
    let chars: Vec<char> = command.chars().collect();
    let mut out = String::new();
    let mut i = 0;
    while i < chars.len() {
        if chars[i].is_whitespace() {
            let mut j = i;
            while j < chars.len() && chars[j].is_whitespace() {
                j += 1;
            }
            if j + 1 < chars.len() && chars[j] == '%' && "fFuUdDnNickvm".contains(chars[j + 1]) {
                i = j + 2;
                continue;
            }
            out.extend(&chars[i..j]);
            i = j;
            continue;
        }
        out.push(chars[i]);
        i += 1;
    }
    out.replace("%%", "%").trim().to_owned()
}

pub fn add_app(paths: &Paths, app_id: &str, name: &str, command: &str, raw_chord: &str) -> Result<Value> {
    if app_id.is_empty() || name.is_empty() || command.is_empty() {
        return Err("La aplicación elegida no tiene datos de lanzamiento completos".into());
    }
    let command = without_field_codes(command);
    if command.contains('\n') || command.contains('\0') {
        return Err("El comando de la aplicación no se puede guardar de forma segura".into());
    }
    let chord = validate_chord(raw_chord)?;
    ensure_free(&chord, &[], &list_bindings(paths)?)?;
    let mut store = load_store(&paths.store)?;
    let identifier = format!("app:{}", digest(&[app_id, &chord]));
    store.binds.retain(|bind| text(bind, "id") != Some(identifier.as_str()));
    store.binds.push(item(json!({ "id": identifier, "chord": chord, "exec": command, "name": name, "appId": app_id })));
    let saved = commit(paths, &store, &[(chord.clone(), format!("{EDIT_TAG}{identifier}"))], &[])?;
    Ok(saved_reply(&saved, json!({ "chord": chord, "message": format!("Guardado · {chord}") })))
}

/// Run one legacy command; None when `args` is not one of them.
pub fn dispatch(args: &[String]) -> Option<(Value, i32)> {
    let paths = Paths::from_env();
    let arg = |i: usize| args[i].as_str();
    let result = match (args.first()?.as_str(), args.len()) {
        ("list", 1) => list_bindings(&paths).map(|items| json!({ "ok": true, "bindings": items })),
        ("set", 3) => set_binding(&paths, arg(1), arg(2)),
        ("delete", 2) => delete_binding(&paths, arg(1)),
        ("reset", 2) => reset_binding(&paths, arg(1)),
        ("add-app", 5) => add_app(&paths, arg(1), arg(2), arg(3), arg(4)),
        ("list" | "set" | "delete" | "reset" | "add-app", _) => {
            return Some((json!({ "ok": false, "error": "Argumentos incorrectos" }), 2));
        }
        _ => return None,
    };
    Some(match result {
        Ok(value) => (value, 0),
        Err(error) => {
            let error = if error.is_empty() { "El atajo no se pudo cambiar".to_owned() } else { error };
            (json!({ "ok": false, "error": error }), 1)
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validation_matches_the_python_rules() {
        for (chord, words) in [
            ("CTRL + End", "aplicaciones"),
            ("F5", "tecla sola"),
            ("Q", "tecla sola"),
            ("SUPER + Ñ", "no es una tecla"),
            ("HYPER + A", "no es un modificador"),
            ("MOD5 + Q", "AltGr"),
            ("ALTGR + Q", "AltGr"),
            ("SUPER + SHIFT", "no es una tecla"),
            ("", "Hace falta"),
            ("SUPER + F0", "no es una tecla"),
            ("SUPER + F25", "no es una tecla"),
        ] {
            let error = validate_chord(chord).unwrap_err();
            assert!(error.contains(words), "{chord}: {error}");
        }
        for (chord, stored) in [
            ("XF86Calculator", "XF86Calculator"),
            ("super + shift + f23", "SUPER + SHIFT + f23"),
            ("CTRL + ALT + T", "CTRL + ALT + T"),
            ("SUPER + KP_1", "SUPER + KP_1"),
            ("F13", "F13"),
            ("Print", "Print"),
            ("SUPER + code:10", "SUPER + code:10"),
        ] {
            assert_eq!(validate_chord(chord).unwrap(), stored);
        }
    }

    #[test]
    fn normalise_sorts_and_aliases_modifiers() {
        assert_eq!(normalise("super + control + q"), "CTRL+SUPER+Q");
        assert_eq!(normalise("WIN + MOD4 + Q"), "SUPER+Q");
        assert_eq!(chord_parts("SUPER + SHIFT + q"), (65, "Q".into()));
    }

    #[test]
    fn titles_like_python_str_title() {
        assert_eq!(title("kbMoveWinToWsNext"), "Move Win To Workspace Next");
        assert_eq!(title("kbShowPanels"), "Show Panels");
        assert_eq!(title("kbF13x"), "F13X");
    }

    #[test]
    fn desktop_field_codes_are_dropped() {
        assert_eq!(without_field_codes("example --open %U"), "example --open");
        assert_eq!(without_field_codes("a  %f %U"), "a");
        assert_eq!(without_field_codes("app 100%% %u"), "app 100%");
        assert_eq!(without_field_codes("%U app"), "%U app");
    }

}
