//! What the visual editor adds to the legacy commands: a preview that writes
//! nothing, the configuration version it was computed from, and writes that
//! only go ahead if that version is still current.
//!
//! Every writing command takes an exclusive lock next to the store, so the
//! version check and the write cannot interleave with another helper.

use crate::legacy::{self, Refusal};
use crate::protocol::Error;
use crate::store::{Paths, Result};
use serde::Serialize;
use serde_json::{Value, json};
use std::fs::{self, File, OpenOptions};
use std::path::Path;

const WRITES: [&str; 4] = ["set", "delete", "reset", "add-app"];
const STALE: &str = "La configuración cambió desde la vista previa; revisa el cambio otra vez";

/// A digest of every file the editor's answers are computed from.
pub fn version(paths: &Paths) -> String {
    let read = |path: &Path| fs::read_to_string(path).unwrap_or_default();
    let parts = [read(&paths.store), read(&paths.defaults), read(&paths.first_party), read(&paths.user)];
    legacy::digest(&parts.iter().map(String::as_str).collect::<Vec<_>>())
}

#[derive(Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Preview {
    pub id: String,
    pub label: String,
    pub before: String,
    pub after: String,
    pub valid: bool,
    /// The chord is fine but another action holds it.
    pub conflict: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub problem: Option<String>,
    pub version: String,
}

/// What `set ID CHORD` (with `identifier`) or `add-app … CHORD` would do.
pub fn preview(paths: &Paths, identifier: Option<&str>, raw_chord: &str) -> std::result::Result<Preview, Error> {
    let version = version(paths);
    let items = legacy::list_bindings(paths).map_err(|e| Error::new("config", e))?;
    let entry = identifier.and_then(|id| items.iter().find(|e| e.id == id));
    // A row that does not exist is an error of the request, not a refusal
    // of the chord: the surface asked about something it should not list.
    if let (Some(id), None) = (identifier, entry) {
        return Err(Error::new("unknown-binding", format!("{}: {id}", legacy::GONE)));
    }
    let planned = match identifier {
        Some(id) => legacy::plan_set(&items, id, raw_chord).map(|(chord, _)| chord),
        None => legacy::plan_add(&items, raw_chord),
    };
    let (after, problem) = match &planned {
        Ok(chord) => (chord.clone(), None),
        // A taken chord is still a valid one: show it as it would be stored.
        Err(refusal) => (legacy::validate_chord(raw_chord).unwrap_or_else(|_| raw_chord.to_owned()), Some(refusal)),
    };
    Ok(Preview {
        id: identifier.unwrap_or("").to_owned(),
        label: entry.map(|e| e.label.clone()).unwrap_or_default(),
        before: entry.map(|e| e.chord.clone()).unwrap_or_default(),
        after,
        valid: planned.is_ok(),
        conflict: matches!(problem, Some(Refusal::Taken(_))),
        problem: problem.map(|p| p.message().to_owned()),
        version,
    })
}

/// Hold the editor lock for as long as the returned file lives.
fn lock(paths: &Paths) -> Result<File> {
    let path = paths.store.with_extension("lock");
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let file = OpenOptions::new().create(true).truncate(false).write(true).open(&path).map_err(|e| e.to_string())?;
    file.lock().map_err(|e| e.to_string())?;
    Ok(file)
}

/// A legacy command, optionally prefixed by `--expect VERSION`. Writes run
/// under the lock; a stale version is refused with `stale: true`. None when
/// `args` is not an editor command.
pub fn dispatch(args: &[String]) -> Option<(Value, i32)> {
    let (expected, command) = match args {
        [flag, version, rest @ ..] if flag == "--expect" => (Some(version.as_str()), rest),
        _ => (None, args),
    };
    let writes = command.first().is_some_and(|c| WRITES.contains(&c.as_str()));
    if expected.is_some() && !writes {
        return Some((json!({ "ok": false, "error": "Argumentos incorrectos" }), 2));
    }
    if !writes {
        return legacy::dispatch(command);
    }
    let paths = Paths::from_env();
    let _held = match lock(&paths) {
        Ok(file) => file,
        Err(error) => {
            return Some((
                json!({ "ok": false, "error": format!("No se pudo bloquear la configuración: {error}") }),
                1,
            ));
        }
    };
    if expected.is_some_and(|v| v != version(&paths)) {
        return Some((json!({ "ok": false, "error": STALE, "stale": true }), 1));
    }
    legacy::dispatch(command)
}
