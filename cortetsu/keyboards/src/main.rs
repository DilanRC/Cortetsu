//! cortetsu-keybinds: keyboards, keys and keybinds for «Atajos y teclados».
//!
//! Runs on demand and exits; `watch` lives only while the editor keeps it
//! open. Nothing here reads key presses.
//!
//!   inventory               keyboards present now (protocol 2)
//!   keys [--device ID]      every declared key with its states (protocol 2)
//!   watch                   inventory again on every keyboard hotplug

mod bitmap;
mod hypr;
mod inventory;
mod keycodes;
mod keymap;
mod keys;
mod protocol;
mod watch;

use protocol::Error;
use serde::Serialize;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::time::Instant;

pub fn sysfs_root() -> PathBuf {
    std::env::var_os("CORTETSU_SYSFS").map(PathBuf::from).unwrap_or_else(|| "/sys".into())
}

pub fn udev_data_root() -> PathBuf {
    std::env::var_os("CORTETSU_UDEV_DATA").map(PathBuf::from).unwrap_or_else(|| "/run/udev/data".into())
}

pub fn inventory_now() -> inventory::Inventory {
    let hyprland = hypr::keyboards();
    inventory::scan(&sysfs_root(), &udev_data_root(), hyprland.as_deref())
}

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

/// Lower sorts first in «Teclas por aprovechar».
fn spare_rank(key: &keys::Key) -> (u8, u8, u16) {
    use keys::Category::*;
    let category = match key.category {
        Programmable => 0,
        Launch => 1,
        Media => 2,
        ExtraFunction => 3,
        _ => 4,
    };
    (u8::from(!key.has(keys::State::Verified)), category, key.code)
}

fn keys_command(device: Option<&str>) -> Result<Value, Error> {
    let started = Instant::now();
    let inventory = inventory_now();
    let binds = hypr::binds();
    let mut keymaps: BTreeMap<inventory::Layout, Option<keymap::Keymap>> = BTreeMap::new();
    let selected: Vec<&inventory::Keyboard> =
        inventory.keyboards.iter().filter(|k| device.is_none_or(|id| k.id == id)).collect();
    if let (Some(id), true) = (device, selected.is_empty()) {
        return Err(Error::new("unknown-device", format!("El teclado {id} no está conectado")));
    }
    let mut devices = Vec::new();
    let mut spare = Vec::new();
    for keyboard in selected {
        // One keyboard, one layout: Hyprland gives all its nodes the same one.
        let layout = keyboard.interfaces.iter().find_map(|i| i.layout.clone());
        let keymap =
            layout.map(|layout| keymaps.entry(layout.clone()).or_insert_with(|| keymap::compile(&layout)).clone());
        let device_keys = keys::classify(keyboard, keymap.flatten().as_ref(), binds.as_deref(), &BTreeSet::new());
        for key in device_keys.iter().filter(|k| k.has(keys::State::Candidate)) {
            spare.push(Spare { device: keyboard.id.clone(), device_label: keyboard.label.clone(), key: key.clone() });
        }
        devices.push(DeviceKeys { device: keyboard, keys: device_keys });
    }
    spare.sort_by_key(|s| spare_rank(&s.key));
    Ok(protocol::ok(
        "keys",
        serde_json::json!({
            "devices": devices,
            "spare": spare,
            "bindsAvailable": binds.is_some(),
            "hyprlandAvailable": inventory.hyprland_available,
            "fingerprint": inventory.fingerprint,
            "elapsedMs": started.elapsed().as_millis() as u64,
        }),
    ))
}

fn inventory_command() -> Value {
    let started = Instant::now();
    let inventory = inventory_now();
    let mut value = protocol::ok("inventory", &inventory);
    value["elapsedMs"] = serde_json::json!(started.elapsed().as_millis() as u64);
    value
}

const USAGE: &str = "uso: cortetsu-keybinds inventory | keys [--device ID] | watch";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let command = args.first().map(String::as_str).unwrap_or("");
    let result = match command {
        "inventory" => Ok(inventory_command()),
        "keys" => match args.get(1..).unwrap_or_default() {
            [] => keys_command(None),
            [flag, id] if flag == "--device" => keys_command(Some(id)),
            _ => Err(Error::new("usage", USAGE)),
        },
        "watch" => {
            watch::run();
            return;
        }
        _ => Err(Error::new("usage", USAGE)),
    };
    let (value, success) = match result {
        Ok(value) => (value, true),
        Err(error) => (protocol::failure(if command.is_empty() { "usage" } else { command }, &error), false),
    };
    println!("{value}");
    std::process::exit(if success { 0 } else { 1 });
}
