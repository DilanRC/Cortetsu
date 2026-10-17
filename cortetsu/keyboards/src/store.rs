//! The edit store and its transaction, shared by every editor command.
//!
//! keybinds.json is the only source of truth for edits; cortetsu-keybinds.lua
//! is its compiled, data-only twin that hyprland.lua loads. A change is
//! applied as: snapshot both files, luac-check the Lua, write both
//! atomically, reload Hyprland, check `hyprctl binds -j` by description, and
//! restore the snapshot (and reload again) on any failure.

use crate::legacy::EDIT_TAG;
use crate::scope::Scope;
use crate::{hypr, lua};
use serde::Serialize;
use serde_json::{Map, Value};
use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::time::Duration;

pub type Result<T> = std::result::Result<T, String>;

/// Where the editor reads and writes; HOME and XDG_CONFIG_HOME decide.
pub struct Paths {
    pub defaults: PathBuf,
    pub first_party: PathBuf,
    pub user: PathBuf,
    pub store: PathBuf,
    pub compiled: PathBuf,
    pub snapshots: PathBuf,
    /// Key-test results (`prefs`).
    pub keyboards: PathBuf,
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
            keyboards: config.join("cortetsu/keyboards.json"),
        }
    }
}

pub(crate) fn split_chord(chord: &str) -> Vec<&str> {
    chord.split('+').map(str::trim).filter(|part| !part.is_empty()).collect()
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

#[derive(Debug, Clone, Default, Serialize, PartialEq)]
pub struct Store {
    pub schema: u32,
    pub variables: BTreeMap<String, Vec<String>>,
    pub unbind: Vec<String>,
    /// Kept as JSON objects so fields this version does not know survive.
    pub binds: Vec<Map<String, Value>>,
}

/// Python's str() of a JSON scalar, for values the old helper coerced.
fn py_str(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        Value::Bool(true) => "True".into(),
        Value::Bool(false) => "False".into(),
        Value::Null => "None".into(),
        other => other.to_string(),
    }
}

pub(crate) fn text<'a>(bind: &'a Map<String, Value>, field: &str) -> Option<&'a str> {
    bind.get(field).and_then(Value::as_str)
}

pub(crate) fn refuse_symlink(path: &Path) -> Result<()> {
    if path.is_symlink() {
        return Err(format!("{} es un enlace a otro archivo; no se reemplaza", path.display()));
    }
    Ok(())
}

pub fn load_store(path: &Path) -> Result<Store> {
    let data: Value = match fs::read_to_string(path) {
        Ok(text) => serde_json::from_str(&text).map_err(|e| format!("{} no es JSON válido: {e}", path.display()))?,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Value::Object(Map::new()),
        Err(error) => return Err(error.to_string()),
    };
    let mut store = Store { schema: 1, ..Store::default() };
    let Value::Object(data) = data else { return Ok(store) };
    if let Some(Value::Object(variables)) = data.get("variables") {
        for (name, chords) in variables {
            if let (true, Value::Array(chords)) = (name.starts_with("kb"), chords) {
                store.variables.insert(name.clone(), chords.iter().map(py_str).collect());
            }
        }
    }
    if let Some(Value::Array(unbind)) = data.get("unbind") {
        store.unbind = unbind.iter().filter_map(Value::as_str).map(str::to_owned).collect();
    }
    if let Some(Value::Array(binds)) = data.get("binds") {
        store.binds = binds
            .iter()
            .filter_map(Value::as_object)
            .filter(|b| text(b, "id").is_some() && text(b, "chord").is_some())
            .filter(|b| text(b, "exec").is_some() || text(b, "global").is_some())
            .cloned()
            .collect();
    }
    Ok(store)
}

pub fn compile_store(store: &Store) -> Result<String> {
    let mut lines = vec![
        "-- Generated by cortetsu-keybinds from ~/.config/cortetsu/keybinds.json. Do not edit.".to_owned(),
        "return {".into(),
        "    variables = {".into(),
    ];
    for (name, chords) in &store.variables {
        let valid = name.len() > 2 && name.bytes().skip(2).all(|b| b.is_ascii_alphanumeric() || b == b'_');
        if !valid {
            return Err(format!("Nombre de variable no válido: {name}"));
        }
        let quoted: Vec<String> = chords.iter().map(|chord| lua::quote(chord)).collect();
        lines.push(format!("        {name} = {{ {} }},", quoted.join(", ")));
    }
    lines.extend(["    },".into(), "    unbind = {".into()]);
    lines.extend(store.unbind.iter().map(|chord| format!("        {},", lua::quote(chord))));
    lines.extend(["    },".into(), "    binds = {".into()]);
    for bind in &store.binds {
        let mut fields = vec![
            format!("id = {}", lua::quote(text(bind, "id").unwrap_or(""))),
            format!("chord = {}", lua::quote(text(bind, "chord").unwrap_or(""))),
        ];
        match text(bind, "exec") {
            Some(command) => fields.push(format!("exec = {}", lua::quote(command))),
            None => fields.push(format!("global = {}", lua::quote(text(bind, "global").unwrap_or("")))),
        }
        fields.extend(Scope::of(bind).to_lua());
        lines.push(format!("        {{ {} }},", fields.join(", ")));
    }
    lines.extend(["    },".into(), "}".into(), String::new()]);
    Ok(lines.join("\n"))
}

pub fn atomic_write(path: &Path, contents: &str) -> Result<()> {
    refuse_symlink(path)?;
    let dir = path.parent().ok_or("ruta sin directorio")?;
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let name = path.file_name().unwrap_or_default().to_string_lossy();
    let temp = dir.join(format!(".{name}.{}.{}", std::process::id(), unique()));
    let written = (|| -> std::io::Result<()> {
        let mut file = fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temp)?;
        file.write_all(contents.as_bytes())?;
        file.sync_all()?;
        fs::rename(&temp, path)
    })();
    if written.is_err() {
        let _ = fs::remove_file(&temp);
    }
    written.map_err(|e| e.to_string())
}

fn unique() -> u128 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0)
}

/// UTC, `YYYYmmdd-HHMMSS-micros`, so names sort by time like the Python ones.
fn snapshot_name() -> String {
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
    let (days, secs) = ((now.as_secs() / 86_400) as i64, now.as_secs() % 86_400);
    // Howard Hinnant's civil_from_days.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}{month:02}{day:02}-{:02}{:02}{:02}-{:06}",
        secs / 3600,
        secs / 60 % 60,
        secs % 60,
        now.subsec_micros()
    )
}

fn snapshot(paths: &Paths) -> Result<PathBuf> {
    // The latest 20 are enough to undo by hand; older ones are dropped.
    if let Ok(entries) = fs::read_dir(&paths.snapshots) {
        // Snapshot directories only, like the Python helper's glob("*").
        let mut old: Vec<PathBuf> = entries
            .flatten()
            .filter(|e| !e.file_name().to_string_lossy().starts_with('.') && e.path().is_dir())
            .map(|e| e.path())
            .collect();
        old.sort();
        let excess = old.len().saturating_sub(19);
        for path in &old[..excess] {
            let _ = fs::remove_dir_all(path);
        }
    }
    let target = paths.snapshots.join(snapshot_name());
    fs::create_dir_all(&paths.snapshots).map_err(|e| e.to_string())?;
    fs::create_dir(&target).map_err(|e| e.to_string())?;
    for path in [&paths.store, &paths.compiled] {
        if path.exists() {
            fs::copy(path, target.join(path.file_name().unwrap_or_default())).map_err(|e| e.to_string())?;
        }
    }
    Ok(target)
}

fn reload() -> bool {
    hypr::run(&["reload"], Duration::from_secs(15)).is_some()
}

fn restore(paths: &Paths, saved: &Path) {
    for path in [&paths.store, &paths.compiled] {
        let copy = saved.join(path.file_name().unwrap_or_default());
        if copy.exists() {
            let _ = fs::copy(&copy, path);
        } else if path.exists() && !path.is_symlink() {
            let _ = fs::remove_file(path);
        }
    }
    reload();
}

fn luac_check(compiled: &str) -> Result<()> {
    let Some(luac) = ["luac", "luac5.4"].into_iter().find(|tool| crate::on_path(tool)) else { return Ok(()) };
    let probe = std::env::temp_dir().join(format!("cortetsu-keybinds-{}-{}.lua", std::process::id(), unique()));
    fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&probe)
        .and_then(|mut file| file.write_all(compiled.as_bytes()))
        .map_err(|e| e.to_string())?;
    let output = std::process::Command::new(luac).args(["-p"]).arg(&probe).output();
    let _ = fs::remove_file(&probe);
    match output {
        Ok(output) if output.status.success() => Ok(()),
        Ok(output) => Err(format!(
            "La configuración generada no es Lua válido: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        )),
        Err(error) => Err(error.to_string()),
    }
}

/// Each store bind must listen to the same keyboards in Hyprland as in the
/// store. Without a readable report that is only an error when some bind is
/// limited: a loader that predates the report binds everything everywhere.
fn verify_scopes(store: &Store) -> Result<()> {
    let wanted: Vec<(&str, Scope)> =
        store.binds.iter().filter_map(|bind| Some((text(bind, "id")?, Scope::of(bind)))).collect();
    if wanted.is_empty() {
        return Ok(());
    }
    let limited = wanted.iter().any(|(_, scope)| *scope != Scope::All);
    let live = match hypr::live_scopes() {
        Some(Some(live)) => live,
        _ if !limited => return Ok(()),
        None => return Err("No se pudo leer de Hyprland a qué teclados responde cada atajo".into()),
        Some(None) => {
            return Err(
                "La configuración cargada de Hyprland no admite atajos por teclado; actualiza hyprland.lua".into()
            );
        }
    };
    for (id, scope) in wanted {
        // A bind Hyprland did not take (none in the report) only matters if
        // it was limited: unlimited, it has nothing to leak.
        let held = live.get(id).cloned().or((scope == Scope::All).then_some(Scope::All));
        if held.as_ref() != Some(&scope) {
            return Err(format!("Hyprland no tiene {id} {} tras recargar", scope.describe()));
        }
    }
    Ok(())
}

/// Write the store, reload Hyprland and check the result, or roll back.
/// `present`: (chord, description) pairs that must be bound afterwards.
/// `absent`: chords that must have no bind afterwards.
pub fn commit(paths: &Paths, store: &Store, present: &[(String, String)], absent: &[String]) -> Result<PathBuf> {
    // Before the snapshot: restoring through a symlink would write elsewhere.
    refuse_symlink(&paths.store)?;
    refuse_symlink(&paths.compiled)?;
    let compiled = compile_store(store)?;
    let saved = snapshot(paths)?;
    let applied = (|| -> Result<()> {
        luac_check(&compiled)?;
        let json = serde_json::to_string_pretty(store).map_err(|e| e.to_string())?;
        atomic_write(&paths.store, &(json + "\n"))?;
        atomic_write(&paths.compiled, &compiled)?;
        if !reload() {
            return Err("Hyprland no pudo recargar la configuración".into());
        }
        let active = hypr::binds().ok_or("No se pudo leer la configuración de Hyprland tras recargar")?;
        let mut bound: BTreeMap<(u32, String), Vec<String>> = BTreeMap::new();
        for bind in active {
            bound.entry((bind.modmask, bind.key.to_uppercase())).or_default().push(bind.description);
        }
        for (chord, description) in present {
            if !bound.get(&chord_parts(chord)).is_some_and(|d| d.contains(description)) {
                return Err(format!("Hyprland no muestra {chord} con su acción tras recargar"));
            }
        }
        // Another store bind may keep an absent chord on other keyboards.
        let mut kept: BTreeMap<(u32, String), Vec<String>> = BTreeMap::new();
        for bind in &store.binds {
            if let (Some(chord), Some(id)) = (text(bind, "chord"), text(bind, "id")) {
                kept.entry(chord_parts(chord)).or_default().push(format!("{EDIT_TAG}{id}"));
            }
        }
        for chord in absent {
            let parts = chord_parts(chord);
            let ours = kept.get(&parts).map(Vec::as_slice).unwrap_or_default();
            if bound.get(&parts).is_some_and(|d| d.iter().any(|d| !ours.contains(d))) {
                return Err(format!("{chord} sigue activo tras recargar"));
            }
        }
        verify_scopes(store)
    })();
    match applied {
        Ok(()) => Ok(saved),
        Err(error) => {
            restore(paths, &saved);
            Err(error)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn snapshot_names_sort_by_time() {
        let name = snapshot_name();
        assert_eq!(name.len(), "20261017-123456-123456".len());
        assert!(name.as_str() > "20260101-000000-000000");
    }

    #[test]
    fn store_coerces_like_python_and_keeps_unknown_fields() {
        let dir = crate::testing::FakeSys::new();
        let path = dir.path().join("keybinds.json");
        fs::write(
            &path,
            r#"{"variables": {"kbX": ["SUPER + X", 5], "other": ["no"]}, "unbind": ["A", 3],
                "binds": [{"id": "app:1", "chord": "SUPER + A", "exec": "a", "extra": true}, {"id": "x"}]}"#,
        )
        .unwrap();
        let store = load_store(&path).unwrap();
        assert_eq!(store.variables["kbX"], vec!["SUPER + X", "5"]);
        assert!(!store.variables.contains_key("other"));
        assert_eq!(store.unbind, vec!["A"]);
        assert_eq!(store.binds.len(), 1);
        assert_eq!(store.binds[0]["extra"], json!(true));
        let compiled = compile_store(&store).unwrap();
        assert!(compiled.contains("kbX = { \"SUPER + X\", \"5\" },"));
        assert!(compiled.contains("{ id = \"app:1\", chord = \"SUPER + A\", exec = \"a\" },"));
        assert!(!compiled.contains("function"));
    }

    #[test]
    fn atomic_write_refuses_symlinks_and_leaves_no_temp_files() {
        let dir = crate::testing::FakeSys::new();
        let target = dir.path().join("elsewhere");
        fs::write(&target, "{}").unwrap();
        let link = dir.path().join("keybinds.json");
        std::os::unix::fs::symlink(&target, &link).unwrap();
        assert!(atomic_write(&link, "x").unwrap_err().contains("enlace"));
        assert_eq!(fs::read_to_string(&target).unwrap(), "{}");
        let file = dir.path().join("plain.json");
        atomic_write(&file, "data").unwrap();
        assert_eq!(fs::read_to_string(&file).unwrap(), "data");
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(fs::metadata(&file).unwrap().permissions().mode() & 0o777, 0o600);
        let leftovers: Vec<_> = fs::read_dir(dir.path())
            .unwrap()
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().starts_with('.'))
            .collect();
        assert!(leftovers.is_empty());
    }

    #[test]
    fn retention_keeps_twenty_snapshot_directories_and_ignores_other_entries() {
        let dir = crate::testing::FakeSys::new();
        let root = dir.path();
        let paths = Paths {
            defaults: root.join("variables.lua"),
            first_party: root.join("keybinds.lua"),
            user: root.join("hypr-user.lua"),
            store: root.join("keybinds.json"),
            compiled: root.join("cortetsu-keybinds.lua"),
            snapshots: root.join("snapshots"),
            keyboards: root.join("keyboards.json"),
        };
        fs::write(&paths.store, "{}").unwrap();
        for n in 0..25 {
            fs::create_dir_all(paths.snapshots.join(format!("20260101-0000{n:02}-000000"))).unwrap();
        }
        fs::write(paths.snapshots.join(".hidden"), "").unwrap();
        fs::write(paths.snapshots.join("notes.txt"), "").unwrap();
        let saved = snapshot(&paths).unwrap();
        assert!(saved.join("keybinds.json").is_file());
        let dirs = fs::read_dir(&paths.snapshots).unwrap().flatten().filter(|e| e.path().is_dir()).count();
        assert_eq!(dirs, 20);
        assert!(paths.snapshots.join(".hidden").exists() && paths.snapshots.join("notes.txt").exists());
        assert!(!paths.snapshots.join("20260101-000000-000000").exists(), "the oldest go first");
    }
}
