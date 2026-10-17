//! cortetsu-keybinds: keyboards, keys and keybinds for «Atajos y teclados».
//!
//! Runs on demand and exits; `watch` lives only while the editor keeps it
//! open. Nothing here reads key presses.
//!
//! The commands are listed once, in `USAGE`.

use cortetsu_keyboards::protocol::{self, Error};
use cortetsu_keyboards::{capture, editor, hypr, inventory, keymap, keys, legacy, store, watch};
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};
use std::time::Instant;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DeviceKeys<'a> {
    device: &'a inventory::Keyboard,
    keys: Vec<keys::Key>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Spare {
    device: String,
    device_label: String,
    #[serde(flatten)]
    key: keys::Key,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct KeysPayload<'a> {
    devices: Vec<DeviceKeys<'a>>,
    /// «Teclas por aprovechar»: every CANDIDATE, best first.
    spare: Vec<Spare>,
    binds_available: bool,
    hyprland_available: bool,
    fingerprint: &'a str,
    elapsed_ms: u128,
}

/// Lower sorts first in «Teclas por aprovechar».
fn spare_rank(key: &keys::Key) -> (keys::Confidence, u8, u16) {
    use keys::Category::*;
    let category = match key.category {
        Programmable => 0,
        Launch => 1,
        Media => 2,
        ExtraFunction => 3,
        _ => 4,
    };
    (key.confidence, category, key.code)
}

fn keys_command(device: Option<&str>) -> Result<serde_json::Value, Error> {
    let started = Instant::now();
    let inventory = inventory::now();
    let binds = hypr::binds();
    let selected: Vec<&inventory::Keyboard> =
        inventory.keyboards.iter().filter(|k| device.is_none_or(|id| k.id == id)).collect();
    if let (Some(id), true) = (device, selected.is_empty()) {
        return Err(Error::new("unknown-device", format!("El teclado {id} no está conectado")));
    }
    let mut keymaps: BTreeMap<inventory::Layout, Option<keymap::Keymap>> = BTreeMap::new();
    let mut devices = Vec::new();
    let mut spare = Vec::new();
    for keyboard in selected {
        // Hyprland gives every node of a keyboard the same layout.
        let keymap = keyboard
            .interfaces
            .iter()
            .find_map(|i| i.layout.clone())
            .and_then(|layout| keymaps.entry(layout.clone()).or_insert_with(|| keymap::compile(&layout)).clone());
        // ponytail: no key is VERIFIED until the explicit key test lands with
        // the per-device editor; the parameter is already threaded through.
        let device_keys = keys::classify(keyboard, keymap.as_ref(), binds.as_deref(), &BTreeSet::new());
        for key in device_keys.iter().filter(|k| k.has(keys::State::Candidate)) {
            spare.push(Spare { device: keyboard.id.clone(), device_label: keyboard.label.clone(), key: key.clone() });
        }
        devices.push(DeviceKeys { device: keyboard, keys: device_keys });
    }
    spare.sort_by_key(|s| spare_rank(&s.key));
    Ok(protocol::ok(
        "keys",
        KeysPayload {
            devices,
            spare,
            binds_available: binds.is_some(),
            hyprland_available: inventory.hyprland_available,
            fingerprint: &inventory.fingerprint,
            elapsed_ms: started.elapsed().as_millis(),
        },
    ))
}

fn inventory_command() -> serde_json::Value {
    let started = Instant::now();
    let mut value = protocol::ok("inventory", inventory::now());
    value["elapsedMs"] = serde_json::json!(started.elapsed().as_millis() as u64);
    value
}

fn bindings_command() -> Result<serde_json::Value, Error> {
    let paths = store::Paths::from_env();
    let bindings = legacy::list_bindings(&paths).map_err(|e| Error::new("config", e))?;
    Ok(protocol::ok("bindings", serde_json::json!({ "bindings": bindings, "version": editor::version(&paths) })))
}

fn preview_command(verb: &str, rest: &[String]) -> Result<serde_json::Value, Error> {
    let paths = store::Paths::from_env();
    let preview = match (verb, rest) {
        ("set", [id, chord]) => editor::preview(&paths, Some(id), chord),
        ("add-app", [chord]) => editor::preview(&paths, None, chord),
        _ => return Err(Error::new("usage", USAGE)),
    }?;
    Ok(protocol::ok("preview", preview))
}

fn capture_command(verb: &str, rest: &[String]) -> Result<serde_json::Value, Error> {
    let status = match (verb, rest) {
        ("begin", [ms]) => capture::begin(ms.parse().map_err(|_| Error::new("usage", USAGE))?),
        ("end", []) => capture::end(),
        ("status", []) => capture::status(),
        _ => return Err(Error::new("usage", USAGE)),
    }?;
    Ok(protocol::ok("capture", status))
}

const USAGE: &str = "\
uso: cortetsu-keybinds COMANDO
  list | set ID CHORD | delete ID | reset ID | add-app APP_ID NAME COMMAND CHORD
                          el editor de atajos (protocolo 1)
  [--expect VERSION] set|delete|reset|add-app …
                          rechaza el cambio si la configuración cambió
  inventory               teclados conectados ahora
  keys [--device ID]      cada tecla declarada con sus estados
  watch                   el inventario otra vez en cada conexión
  bindings                las filas del editor y la versión de la configuración
  preview set ID CHORD | preview add-app CHORD
                          lo que haría un cambio, sin escribir
  capture begin MS | capture end | capture status
                          el submapa que retiene los atajos mientras se graba";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let Some((value, code)) = editor::dispatch(&args) {
        println!("{value}");
        std::process::exit(code);
    }
    let command = args.first().map(String::as_str).unwrap_or("");
    let result = match (command, args.get(1..).unwrap_or_default()) {
        ("inventory", []) => Ok(inventory_command()),
        ("keys", []) => keys_command(None),
        ("keys", [flag, id]) if flag == "--device" => keys_command(Some(id)),
        ("watch", []) => watch::run(),
        ("capture", [verb, rest @ ..]) => capture_command(verb, rest),
        ("bindings", []) => bindings_command(),
        ("preview", [verb, rest @ ..]) => preview_command(verb, rest),
        _ => Err(Error::new("usage", USAGE)),
    };
    let (value, code) = match result {
        Ok(value) => (value, 0),
        Err(error) => (protocol::failure(if command.is_empty() { "usage" } else { command }, &error), 1),
    };
    if !value.is_null() {
        println!("{value}");
    }
    std::process::exit(code);
}
