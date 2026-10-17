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
use crate::store::{Paths, Result, Store, chord_parts, commit, load_store, split_chord, text};
use crate::{hypr, sha256};
use serde::Serialize;
use serde_json::{Map, Value, json};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

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

// --- chords -----------------------------------------------------------------

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

pub fn digest(parts: &[&str]) -> String {
    sha256::hex(parts.join("\0").as_bytes())[..16].to_owned()
}

pub const GONE: &str = "Ese atajo ya no existe";

/// One row of `list`. Optional fields are absent from the JSON, exactly where
/// the Python helper left them out of its dicts.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Binding {
    pub id: String,
    pub label: String,
    pub chord: String,
    pub group: &'static str,
    pub description: String,
    pub command: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub app_query: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub app_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub app_id: Option<String>,
    pub origin: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub variable: Option<String>,
    pub editable: bool,
    pub deletable: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resettable: Option<bool>,
    pub active: bool,
    /// hypr-user binds only: `{"exec"}`/`{"global"}`, or null for Lua logic.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub action: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reserved: Option<bool>,
    pub conflicts: Vec<String>,
}

impl Binding {
    fn new(id: String, label: String, chord: String, group: &'static str, origin: &'static str) -> Self {
        Binding {
            id,
            label,
            chord,
            group,
            description: String::new(),
            command: String::new(),
            app_query: None,
            app_name: None,
            app_id: None,
            origin,
            variable: None,
            editable: false,
            deletable: false,
            resettable: None,
            active: true,
            action: None,
            note: None,
            reserved: None,
            conflicts: Vec::new(),
        }
    }
}

fn first_nonempty<'a>(values: &[&'a str]) -> Option<&'a str> {
    values.iter().copied().find(|value| !value.is_empty())
}

fn global_label(target: &str) -> String {
    target.replace("cortetsu:", "Cortetsu · ")
}

fn user_bindings(paths: &Paths, store: &Store) -> Vec<Binding> {
    let Ok(text) = fs::read_to_string(&paths.user) else { return Vec::new() };
    let removed: Vec<String> = store.unbind.iter().map(|chord| normalise(chord)).collect();
    let mut result = Vec::new();
    for block in lua::binding_blocks(&text) {
        let action = lua::simple_action(&block.body);
        let (target, command) = match &action {
            Some(Action::Global(name)) => (name.as_str(), ""),
            Some(Action::Exec(command)) => ("", command.as_str()),
            None => ("", ""),
        };
        let app = lua::generated_app(&text, block.start);
        let label = match &app {
            Some((name, _)) => name.clone(),
            None => first_nonempty(&[&global_label(target), command]).unwrap_or("Acción Lua").to_owned(),
        };
        let mut entry = Binding::new(
            format!("user:{}", digest(&[&block.chord, &block.body])),
            label,
            block.chord.clone(),
            if app.is_some() { "Application" } else { "Custom" },
            "user",
        );
        entry.description = first_nonempty(&[command, target]).unwrap_or("Acción Lua de hypr-user.lua").to_owned();
        entry.command = command.to_owned();
        entry.editable = action.is_some();
        entry.deletable = true;
        entry.active = !removed.contains(&normalise(&block.chord));
        entry.resettable = Some(!entry.active);
        entry.action = Some(match &action {
            Some(Action::Global(name)) => json!({ "global": name }),
            Some(Action::Exec(command)) => json!({ "exec": command }),
            None => Value::Null,
        });
        if let Some((name, id)) = app {
            entry.app_name = Some(name);
            entry.app_id = Some(id);
        }
        if action.is_none() {
            entry.note = Some("Acción Lua: se cambia en hypr-user.lua".into());
        }
        result.push(entry);
    }
    result
}

const GLOBAL_CALL: &str = "hl.dsp.global(\"";
const EXEC_CALL: &str = "hl.dsp.exec_cmd(";

/// Binds keybinds.lua writes with a fixed chord: hardware keys and the like.
fn first_party_literals(paths: &Paths) -> Vec<Binding> {
    let Ok(text) = fs::read_to_string(&paths.first_party) else { return Vec::new() };
    let mut result = Vec::new();
    for (chords, action) in lua::literal_binds(&text) {
        let target = action
            .split_once(GLOBAL_CALL)
            .and_then(|(_, rest)| rest.find('"').filter(|&end| end > 0).map(|end| rest[..end].to_owned()));
        let command = action
            .split_once(EXEC_CALL)
            .filter(|(_, rest)| rest.starts_with('"'))
            .map(|(_, rest)| lua::strings(rest).into_iter().next().unwrap_or_default());
        for chord in chords {
            let hardware = chord.to_uppercase().starts_with("XF86");
            let label = match (&target, &command) {
                (Some(target), _) => global_label(target),
                (None, Some(command)) => command.clone(),
                (None, None) => chord.clone(),
            };
            let mut entry = Binding::new(
                format!("fixed:{}", digest(&[&chord])),
                label,
                chord,
                if hardware { "Hardware" } else { "Cortetsu" },
                "fixed",
            );
            entry.description = if hardware { "Tecla del equipo" } else { "Atajo fijo de Cortetsu" }.into();
            entry.reserved = Some(true);
            result.push(entry);
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

/// A variable's chords: the edit if there is one, else the default.
fn variable_slot(store: &Store, defaults: &[(String, Vec<String>)], name: &str) -> Vec<String> {
    store.variables.get(name).cloned().unwrap_or_else(|| default_of(defaults, name))
}

pub fn list_bindings(paths: &Paths) -> Result<Vec<Binding>> {
    let store = load_store(&paths.store)?;
    let defaults = defaults(paths)?;
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
            .and_then(|(_, command)| variable_slot(&store, &defaults, command).into_iter().next())
            .unwrap_or_default();
        let app_query = if name == "kbTerminal" {
            "kitty".to_owned()
        } else {
            // Path(first).name: the last component, a trailing slash ignored.
            let first = command.split_whitespace().next().unwrap_or("").trim_end_matches('/');
            first.rsplit('/').next().unwrap_or(first).to_owned()
        };
        let group = if command.is_empty() { "Cortetsu" } else { "Application" };
        for (index, chord) in current.iter().enumerate() {
            let mut entry = Binding::new(
                format!("var:{name}:{index}"),
                title(name),
                chord.clone(),
                group,
                if edited { "edited" } else { "default" },
            );
            entry.description = if command.is_empty() { title(name) } else { command.clone() };
            entry.command = command.clone();
            entry.app_query = Some(app_query.clone());
            entry.variable = Some(name.clone());
            entry.editable = true;
            entry.deletable = true;
            entry.resettable = Some(edited);
            result.push(entry);
        }
        if edited && current.is_empty() {
            let mut entry = Binding::new(format!("var:{name}:-"), title(name), String::new(), "Cortetsu", "edited");
            entry.description = "Sin combinación".into();
            entry.command = command.clone();
            entry.variable = Some(name.clone());
            entry.resettable = Some(true);
            entry.active = false;
            result.push(entry);
        }
    }
    result.extend(user_bindings(paths, &store));
    for bind in &store.binds {
        let global = text(bind, "global").unwrap_or("");
        let exec = text(bind, "exec").unwrap_or("");
        let name = text(bind, "name").unwrap_or("");
        let app_id = text(bind, "appId").unwrap_or("");
        let mut entry = Binding::new(
            text(bind, "id").unwrap_or("").to_owned(),
            first_nonempty(&[name, &global_label(global), exec]).unwrap_or("").to_owned(),
            text(bind, "chord").unwrap_or("").to_owned(),
            if app_id.is_empty() { "Custom" } else { "Application" },
            "edited",
        );
        entry.description = first_nonempty(&[exec, global]).unwrap_or("").to_owned();
        entry.command = exec.to_owned();
        entry.app_name = Some(name.to_owned());
        entry.app_id = Some(app_id.to_owned());
        entry.editable = true;
        entry.deletable = true;
        entry.resettable = Some(text(bind, "replaces").is_some_and(|r| !r.is_empty()));
        result.push(entry);
    }
    result.extend(first_party_literals(paths));

    let mut owners: BTreeMap<String, Vec<(String, String)>> = BTreeMap::new();
    for entry in result.iter().filter(|e| e.active && !e.chord.is_empty()) {
        owners.entry(normalise(&entry.chord)).or_default().push((entry.id.clone(), entry.label.clone()));
    }
    for entry in result.iter_mut().filter(|e| e.active) {
        entry.conflicts = owners
            .get(&normalise(&entry.chord))
            .into_iter()
            .flatten()
            .filter(|(id, _)| *id != entry.id)
            .map(|(_, label)| label.clone())
            .collect();
    }
    result.sort_by(|a, b| (a.group, &a.label, &a.chord).cmp(&(b.group, &b.label, &b.chord)));
    Ok(result)
}

/// Live binds on the same modmask and key as `chord`.
fn live_on(chord: &str) -> Vec<hypr::Bind> {
    let (mask, key) = chord_parts(chord);
    hypr::binds().unwrap_or_default().into_iter().filter(|b| b.modmask == mask && b.key.to_uppercase() == key).collect()
}

fn ensure_free(chord: &str, own: &[String], items: &[Binding]) -> Result<()> {
    let wanted = normalise(chord);
    for entry in items.iter().filter(|e| e.active && !e.chord.is_empty()) {
        let other = normalise(&entry.chord);
        if other == wanted && !own.contains(&other) {
            return Err(format!("{chord} ya es «{}»", entry.label));
        }
    }
    if own.contains(&wanted) {
        return Ok(());
    }
    // Workspace binds are generated in Lua and only Hyprland knows them all.
    if !live_on(chord).is_empty() {
        return Err(format!("{chord} ya lo usa otra acción de Hyprland"));
    }
    Ok(())
}

// --- commands ---------------------------------------------------------------

fn parse_var_id(identifier: &str) -> Result<(String, Option<usize>)> {
    let rest = identifier.split_once(':').map_or("", |(_, rest)| rest);
    let (name, raw) = rest.split_once(':').unwrap_or((rest, ""));
    if raw == "-" {
        return Ok((name.to_owned(), None));
    }
    raw.parse().map(|index| (name.to_owned(), Some(index))).map_err(|_| GONE.into())
}

fn find(identifier: &str, items: Vec<Binding>) -> Result<(Binding, Vec<Binding>)> {
    let entry = items.iter().find(|entry| entry.id == identifier).cloned().ok_or(GONE)?;
    Ok((entry, items))
}

/// The old chord, when moving away from it should leave it unbound.
fn vacated(entry: &Binding, chord: &str) -> Vec<String> {
    if !entry.conflicts.is_empty() || normalise(&entry.chord) == normalise(chord) {
        Vec::new()
    } else {
        vec![entry.chord.clone()]
    }
}

/// Give a hypr-user chord back: drop its removal and any edit replacing it.
fn unrestricted(store: &mut Store, chord: &str) {
    let wanted = normalise(chord);
    store.unbind.retain(|other| normalise(other) != wanted);
    store.binds.retain(|bind| normalise(text(bind, "replaces").unwrap_or("")) != wanted);
}

fn saved_reply(saved: &Path, extra: Value) -> Value {
    let mut reply = Map::new();
    reply.insert("ok".into(), json!(true));
    reply.insert("snapshot".into(), json!(saved.display().to_string()));
    if let Value::Object(fields) = extra {
        reply.extend(fields);
    }
    Value::Object(reply)
}

fn bind_object(value: Value) -> Map<String, Value> {
    match value {
        Value::Object(map) => map,
        _ => unreachable!("bind literals are objects"),
    }
}

/// Why a chord cannot be written. The message is the one the Python helper
/// gave; the kind tells a preview whether another action holds the chord.
#[derive(Debug, Clone, PartialEq)]
pub enum Refusal {
    /// Not a chord Hyprland and the editor accept.
    Invalid(String),
    /// The shortcut is fixed or no longer exists.
    Locked(String),
    /// Another action holds the chord.
    Taken(String),
}

impl Refusal {
    pub fn message(&self) -> &str {
        match self {
            Refusal::Invalid(m) | Refusal::Locked(m) | Refusal::Taken(m) => m,
        }
    }
}

impl From<Refusal> for String {
    fn from(refusal: Refusal) -> String {
        refusal.message().to_owned()
    }
}

/// Every check `set` makes before it writes, against the rows already read:
/// the chord as stored and the row it changes.
pub fn plan_set(
    items: &[Binding],
    identifier: &str,
    raw_chord: &str,
) -> std::result::Result<(String, Binding), Refusal> {
    let chord = validate_chord(raw_chord).map_err(Refusal::Invalid)?;
    let entry = items.iter().find(|e| e.id == identifier).cloned().ok_or_else(|| Refusal::Locked(GONE.into()))?;
    if !entry.editable {
        return Err(Refusal::Locked(
            entry.note.clone().unwrap_or_else(|| "Este atajo no se puede cambiar desde aquí".into()),
        ));
    }
    ensure_free(&chord, &[normalise(&entry.chord)], items).map_err(Refusal::Taken)?;
    if identifier.starts_with("user:") && (!entry.conflicts.is_empty() || live_on(&entry.chord).len() > 1) {
        return Err(Refusal::Taken(format!("{} también lo usa otra acción; cámbiala primero", entry.chord)));
    }
    Ok((chord, entry))
}

pub fn set_binding(paths: &Paths, identifier: &str, raw_chord: &str) -> Result<Value> {
    let (chord, entry) = plan_set(&list_bindings(paths)?, identifier, raw_chord)?;
    let mut store = load_store(&paths.store)?;
    let saved = if identifier.starts_with("var:") {
        let (name, index) = parse_var_id(identifier)?;
        let mut current = variable_slot(&store, &defaults(paths)?, &name);
        *index.and_then(|i| current.get_mut(i)).ok_or(GONE)? = chord.clone();
        store.variables.insert(name.clone(), current);
        commit(paths, &store, &[(chord.clone(), format!("{VAR_TAG}{name}"))], &vacated(&entry, &chord))?
    } else if identifier.starts_with("user:") {
        // Keyed by the chord it replaces, which is also what unbind stores, so
        // an edit of the line in hypr-user.lua does not orphan it.
        let replacement = format!("edit:{}", digest(&[&normalise(&entry.chord)]));
        unrestricted(&mut store, &entry.chord);
        store.unbind.push(entry.chord.clone());
        let name = first_nonempty(&[entry.app_name.as_deref().unwrap_or(""), &entry.label]).unwrap_or("");
        let mut bind = bind_object(json!({
            "id": replacement,
            "chord": chord,
            "replaces": entry.chord,
            "name": name,
            "appId": entry.app_id.as_deref().unwrap_or(""),
        }));
        if let Some(Value::Object(action)) = &entry.action {
            bind.extend(action.clone());
        }
        store.binds.push(bind);
        commit(
            paths,
            &store,
            &[(chord.clone(), format!("{EDIT_TAG}{replacement}"))],
            std::slice::from_ref(&entry.chord),
        )?
    } else {
        for bind in store.binds.iter_mut().filter(|bind| text(bind, "id") == Some(identifier)) {
            bind.insert("chord".into(), json!(chord));
        }
        commit(paths, &store, &[(chord.clone(), format!("{EDIT_TAG}{identifier}"))], &vacated(&entry, &chord))?
    };
    Ok(saved_reply(&saved, json!({ "chord": chord, "message": format!("Guardado · {chord}") })))
}

pub fn delete_binding(paths: &Paths, identifier: &str) -> Result<Value> {
    let (entry, _) = find(identifier, list_bindings(paths)?)?;
    if !entry.deletable {
        return Err("Este atajo no se puede eliminar desde aquí".into());
    }
    let mut store = load_store(&paths.store)?;
    if identifier.starts_with("var:") {
        let (name, index) = parse_var_id(identifier)?;
        let mut current = variable_slot(&store, &defaults(paths)?, &name);
        let index = index.filter(|&i| i < current.len()).ok_or(GONE)?;
        current.remove(index);
        store.variables.insert(name, current);
    } else if identifier.starts_with("user:") {
        if !entry.conflicts.is_empty() || live_on(&entry.chord).len() > 1 {
            return Err(format!("{} también lo usa otra acción; quitarlo las borraría todas", entry.chord));
        }
        store.unbind.push(entry.chord.clone());
    } else {
        // Deleting the edit of a hypr-user bind leaves the original removed;
        // resetting the original brings it back.
        store.binds.retain(|bind| text(bind, "id") != Some(identifier));
    }
    let absent = if entry.conflicts.is_empty() { vec![entry.chord.clone()] } else { Vec::new() };
    let saved = commit(paths, &store, &[], &absent)?;
    Ok(saved_reply(&saved, json!({ "message": format!("Eliminado · {}", entry.label) })))
}

pub fn reset_binding(paths: &Paths, identifier: &str) -> Result<Value> {
    let (entry, _) = find(identifier, list_bindings(paths)?)?;
    if entry.resettable != Some(true) {
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
        unrestricted(&mut store, &entry.chord);
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
    Ok(saved_reply(&saved, json!({ "message": format!("Restablecido · {}", entry.label) })))
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

/// The checks `add-app` makes on its chord, against the rows already read.
pub fn plan_add(items: &[Binding], raw_chord: &str) -> std::result::Result<String, Refusal> {
    let chord = validate_chord(raw_chord).map_err(Refusal::Invalid)?;
    ensure_free(&chord, &[], items).map_err(Refusal::Taken)?;
    Ok(chord)
}

pub fn add_app(paths: &Paths, app_id: &str, name: &str, command: &str, raw_chord: &str) -> Result<Value> {
    if app_id.is_empty() || name.is_empty() || command.is_empty() {
        return Err("La aplicación elegida no tiene datos de lanzamiento completos".into());
    }
    let command = without_field_codes(command);
    if command.contains('\n') || command.contains('\0') {
        return Err("El comando de la aplicación no se puede guardar de forma segura".into());
    }
    let chord = plan_add(&list_bindings(paths)?, raw_chord)?;
    let mut store = load_store(&paths.store)?;
    let identifier = format!("app:{}", digest(&[app_id, &chord]));
    store.binds.retain(|bind| text(bind, "id") != Some(identifier.as_str()));
    store
        .binds
        .push(bind_object(json!({ "id": identifier, "chord": chord, "exec": command, "name": name, "appId": app_id })));
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
