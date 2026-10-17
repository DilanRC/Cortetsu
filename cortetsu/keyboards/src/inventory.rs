//! Keyboards present right now, read from sysfs.
//!
//! Every `eventN` node with EV_KEY codes other than mouse/touchpad buttons is
//! an interface. Interfaces are grouped into physical devices by their nearest
//! USB device ancestor (a USB keyboard's "Keyboard", "Consumer Control" and
//! "System Control" nodes are one keyboard), else their HID device, else the
//! node itself. `eventN` is reported for diagnostics only; identities come
//! from the bus, the vendor/product and the port path, which survive reboots.
//! Serial numbers (`uniq`) are never read, and `phys` is not emitted: for a
//! Bluetooth keyboard it is the adapter's hardware address.

use crate::bitmap;
use crate::hypr;
use crate::keycodes;
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

const BUS_USB: u16 = 0x03;
const BUS_BLUETOOTH: u16 = 0x05;
const BUS_VIRTUAL: u16 = 0x06;
const BUS_I8042: u16 = 0x11;
const BUS_I2C: u16 = 0x18;
const BUS_HOST: u16 = 0x19;

/// Declaration order is priority: a group of nodes takes the first kind any
/// of them has (an HP WMI node next to a USB one would make the group
/// vendor-hotkeys). Keep new variants in that order.
#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "kebab-case")]
pub enum Kind {
    Internal,
    VendorHotkeys,
    Usb,
    Bluetooth,
    Virtual,
    SystemButtons,
    Other,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Interface {
    /// eventN: changes between boots, shown only to help diagnose.
    pub event: String,
    pub name: String,
    #[serde(skip)]
    pub phys: String,
    pub bus: u16,
    pub vendor: u16,
    pub product: u16,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub usb_interface: Option<String>,
    /// The name `hyprctl devices` uses for this node, when it is unambiguous.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hyprland_name: Option<String>,
    /// Every Hyprland name this node could be, when several devices share it.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub hyprland_candidates: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub layout: Option<Layout>,
    #[serde(skip)]
    pub codes: Vec<u16>,
    /// Codes udev's hardware database maps for this model (KEYBOARD_KEY_*):
    /// stronger evidence than the driver's generic bitmap.
    #[serde(skip)]
    pub model_codes: Vec<u16>,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq, PartialOrd, Ord, Default)]
pub struct Layout {
    pub layout: String,
    pub variant: String,
    pub options: String,
    pub model: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Keyboard {
    /// Stable identity: the same keyboard on the same port keeps it.
    pub id: String,
    /// Bus, vendor and product without the port: matches a keyboard moved to
    /// another port only while no other device shares it.
    pub model: String,
    pub kind: Kind,
    pub label: String,
    pub detail: String,
    /// Another connected keyboard has the same identity (two Bluetooth
    /// keyboards of one model): its preferences cannot be told apart, and
    /// `id` carries a `#n` suffix that is only valid while both stay.
    pub ambiguous: bool,
    /// Every interface has a Hyprland name, so a per-device bind can target
    /// it. False with candidates when two identical keyboards share names.
    pub hyprland_linked: bool,
    pub interfaces: Vec<Interface>,
}

impl Keyboard {
    pub fn codes(&self) -> BTreeSet<u16> {
        self.interfaces.iter().flat_map(|i| i.codes.iter().copied()).collect()
    }

    pub fn hyprland_names(&self) -> Vec<String> {
        self.interfaces.iter().filter_map(|i| i.hyprland_name.clone()).collect()
    }

    pub fn is_hp_wmi(&self) -> bool {
        self.kind == Kind::VendorHotkeys && self.interfaces.iter().any(|i| i.name == "HP WMI hotkeys")
    }
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Inventory {
    pub keyboards: Vec<Keyboard>,
    /// Hyprland keyboards with no sysfs node: virtual keyboards of clients
    /// (wtype, ydotool, the nested test seat).
    pub hyprland_only: Vec<String>,
    /// False when `hyprctl devices` could not be read.
    pub hyprland_available: bool,
    /// Changes whenever a keyboard appears, disappears or changes identity.
    pub fingerprint: String,
}

/// The keyboards connected now, as `CORTETSU_SYSFS`/`CORTETSU_UDEV_DATA`
/// (tests) or the real /sys and /run/udev/data show them.
pub fn now() -> Inventory {
    let sys = crate::env_or("CORTETSU_SYSFS", "/sys");
    let udev = crate::env_or("CORTETSU_UDEV_DATA", "/run/udev/data");
    scan(Path::new(&sys), Path::new(&udev), hypr::keyboards().as_deref())
}

struct Node {
    event: String,
    device_dir: PathBuf,
    name: String,
    phys: String,
    bus: u16,
    vendor: u16,
    product: u16,
    codes: Vec<u16>,
    model_codes: Vec<u16>,
}

fn read(path: &Path) -> String {
    fs::read_to_string(path).map(|s| s.trim().to_owned()).unwrap_or_default()
}

fn hex(path: &Path) -> u16 {
    u16::from_str_radix(&read(path), 16).unwrap_or(0)
}

fn is_button(code: u16) -> bool {
    keycodes::name(code).is_some_and(|name| name.starts_with("BTN_"))
}

/// aa:bb:cc:dd:ee:ff, the shape of a Bluetooth address.
fn looks_like_address(text: &str) -> bool {
    let parts: Vec<&str> = text.split(':').collect();
    parts.len() == 6 && parts.iter().all(|p| p.len() == 2 && p.chars().all(|c| c.is_ascii_hexdigit()))
}

/// KEYBOARD_KEY_<scancode>=<name> lines of the node's udev database entry.
/// `!calc` marks a key with a release quirk; the name is what matters.
fn model_codes(udev_data: &Path, event_dir: &Path) -> Vec<u16> {
    let dev = read(&event_dir.join("dev"));
    let Ok(text) = fs::read_to_string(udev_data.join(format!("c{dev}"))) else {
        return Vec::new();
    };
    let mut codes: Vec<u16> = text
        .lines()
        .filter_map(|line| line.strip_prefix("E:KEYBOARD_KEY_"))
        .filter_map(|entry| entry.split_once('=').map(|(_, name)| name.trim_start_matches('!')))
        .filter_map(|name| keycodes::code(&format!("KEY_{}", name.to_ascii_uppercase())))
        .collect();
    codes.sort_unstable();
    codes.dedup();
    codes
}

fn nodes(sys: &Path, udev_data: &Path) -> Vec<Node> {
    let Ok(entries) = fs::read_dir(sys.join("class/input")) else {
        return Vec::new();
    };
    let mut result = Vec::new();
    for entry in entries.flatten() {
        let event = entry.file_name().to_string_lossy().into_owned();
        if !event.starts_with("event") {
            continue;
        }
        let Ok(path) = fs::canonicalize(entry.path()) else { continue };
        let Some(device_dir) = path.parent().map(Path::to_path_buf) else { continue };
        let ev = u64::from_str_radix(&read(&device_dir.join("capabilities/ev")), 16).unwrap_or(0);
        if ev & (1 << 1) == 0 {
            continue; // no EV_KEY
        }
        let text = read(&device_dir.join("capabilities/key"));
        let Ok(codes) = bitmap::parse(&text, bitmap::word_bits_for(&text)) else { continue };
        if codes.iter().all(|&code| is_button(code)) {
            continue; // mice, touchpads, lid and audio jacks
        }
        result.push(Node {
            event,
            name: read(&device_dir.join("name")),
            phys: read(&device_dir.join("phys")),
            bus: hex(&device_dir.join("id/bustype")),
            vendor: hex(&device_dir.join("id/vendor")),
            product: hex(&device_dir.join("id/product")),
            codes,
            model_codes: model_codes(udev_data, &path),
            device_dir,
        });
    }
    result.sort_by(|a, b| a.device_dir.cmp(&b.device_dir));
    result
}

fn is_hid_dir(name: &str) -> bool {
    // 0003:046D:C31C.0001
    let bytes = name.as_bytes();
    bytes.len() == 19
        && bytes[4] == b':'
        && bytes[9] == b':'
        && bytes[14] == b'.'
        && name.chars().enumerate().all(|(i, c)| [4, 9, 14].contains(&i) || c.is_ascii_hexdigit())
}

/// The directory that stands for the physical device, and the USB interface
/// number when there is one.
fn physical(node: &Node, sys: &Path) -> (PathBuf, Option<String>) {
    let devices = sys.join("devices");
    let mut hid = None;
    let mut interface = None;
    let mut cursor = node.device_dir.parent();
    while let Some(dir) = cursor {
        // A Bluetooth keyboard hangs off its adapter, which may be a USB
        // device: climbing past `bluetooth` would merge every BT keyboard.
        if !dir.starts_with(&devices) || dir == devices || dir.file_name().is_some_and(|n| n == "bluetooth") {
            break;
        }
        if dir.join("idVendor").is_file() {
            return (dir.to_path_buf(), interface);
        }
        if interface.is_none() {
            // sysfs prints bInterfaceNumber as two hex digits.
            interface = u8::from_str_radix(&read(&dir.join("bInterfaceNumber")), 16).ok().map(|n| n.to_string());
        }
        if hid.is_none() && dir.file_name().is_some_and(|n| is_hid_dir(&n.to_string_lossy())) {
            hid = Some(dir.to_path_buf());
        }
        cursor = dir.parent();
    }
    (hid.unwrap_or_else(|| node.device_dir.clone()), interface)
}

fn kind_of(node: &Node, sys: &Path) -> Kind {
    let virtual_node = node.device_dir.starts_with(sys.join("devices/virtual"));
    let lower = node.name.to_lowercase();
    if node.phys.starts_with("wmi") || lower.ends_with(" hotkeys") || lower.contains("extra buttons") {
        return Kind::VendorHotkeys;
    }
    match node.bus {
        BUS_USB if !virtual_node => Kind::Usb,
        BUS_BLUETOOTH => Kind::Bluetooth,
        BUS_I8042 => Kind::Internal,
        BUS_I2C if lower.contains("keyboard") => Kind::Internal,
        BUS_HOST
            if ["power button", "sleep button", "video bus", "lid switch"].iter().any(|n| lower.starts_with(n)) =>
        {
            Kind::SystemButtons
        }
        _ if virtual_node || node.bus == BUS_VIRTUAL => Kind::Virtual,
        _ => Kind::Other,
    }
}

fn relative(path: &Path, sys: &Path) -> String {
    path.strip_prefix(sys.join("devices")).unwrap_or(path).to_string_lossy().into_owned()
}

/// (model, id). USB keeps its port in the id. Bluetooth has no port and its
/// address is a serial number in all but name, so its id is the model.
fn identity(kind: Kind, group: &Path, first: &Node, sys: &Path) -> (String, String) {
    let ids = format!("{:04x}:{:04x}", first.vendor, first.product);
    match kind {
        Kind::Usb => (format!("usb:{ids}"), format!("usb:{ids}@{}", relative(group, sys))),
        Kind::Bluetooth => (format!("bluetooth:{ids}"), format!("bluetooth:{ids}")),
        Kind::Virtual => (format!("virtual:{}", first.name), format!("virtual:{}", first.name)),
        _ => {
            let model = format!("{:04x}:{ids}:{}", first.bus, first.name);
            let place = if first.phys.is_empty() || looks_like_address(&first.phys) {
                relative(group, sys)
            } else {
                first.phys.clone()
            };
            (model.clone(), format!("{model}@{place}"))
        }
    }
}

fn labels(kind: Kind, group: &Path, first: &Node) -> (String, String) {
    let usb_name = || {
        let maker = read(&group.join("manufacturer"));
        let product = read(&group.join("product"));
        let joined = format!("{maker} {product}").trim().to_owned();
        if joined.is_empty() { first.name.clone() } else { joined }
    };
    match kind {
        Kind::Internal => ("Teclado integrado".into(), first.name.clone()),
        Kind::VendorHotkeys => {
            let vendor = first.name.split_whitespace().next().unwrap_or("").to_owned();
            (format!("Teclas especiales {vendor}").trim().to_owned(), first.name.clone())
        }
        Kind::Usb => (usb_name(), format!("USB {:04x}:{:04x}", first.vendor, first.product)),
        Kind::Bluetooth => (first.name.clone(), format!("Bluetooth {:04x}:{:04x}", first.vendor, first.product)),
        Kind::Virtual => (first.name.clone(), "Dispositivo virtual".into()),
        Kind::SystemButtons => (first.name.clone(), "Botón del sistema".into()),
        Kind::Other => (first.name.clone(), format!("Bus {:04x}", first.bus)),
    }
}

pub fn scan(sys: &Path, udev_data: &Path, hyprland: Option<&[hypr::Keyboard]>) -> Inventory {
    let mut groups: BTreeMap<PathBuf, Vec<(Node, Option<String>)>> = BTreeMap::new();
    for node in nodes(sys, udev_data) {
        let (group, interface) = physical(&node, sys);
        groups.entry(group).or_default().push((node, interface));
    }

    let mut keyboards = Vec::new();
    for (group, members) in &groups {
        let first = &members[0].0;
        let kind = members.iter().map(|(n, _)| kind_of(n, sys)).min().unwrap_or(Kind::Other);
        let (model, id) = identity(kind, group, first, sys);
        let (label, detail) = labels(kind, group, first);
        let interfaces = members
            .iter()
            .map(|(node, usb_interface)| Interface {
                event: node.event.clone(),
                name: node.name.clone(),
                phys: node.phys.clone(),
                bus: node.bus,
                vendor: node.vendor,
                product: node.product,
                usb_interface: usb_interface.clone(),
                hyprland_name: None,
                hyprland_candidates: Vec::new(),
                layout: None,
                codes: node.codes.clone(),
                model_codes: node.model_codes.clone(),
            })
            .collect();
        keyboards.push(Keyboard {
            id,
            model,
            kind,
            label,
            detail,
            ambiguous: false,
            hyprland_linked: false,
            interfaces,
        });
    }

    // Same id twice: number them so each row is addressable.
    let mut seen: BTreeMap<String, usize> = BTreeMap::new();
    for keyboard in &keyboards {
        *seen.entry(keyboard.id.clone()).or_default() += 1;
    }
    let mut counter: BTreeMap<String, usize> = BTreeMap::new();
    for keyboard in &mut keyboards {
        if seen[&keyboard.id] > 1 {
            let n = counter.entry(keyboard.id.clone()).or_default();
            *n += 1;
            keyboard.id = format!("{}#{n}", keyboard.id);
            keyboard.ambiguous = true;
        }
    }

    let hyprland_only = link_hyprland(&mut keyboards, hyprland);
    let fingerprint = fingerprint(&keyboards);
    keyboards.sort_by(|a, b| (a.kind, &a.label, &a.id).cmp(&(b.kind, &b.label, &b.id)));
    Inventory { keyboards, hyprland_only, hyprland_available: hyprland.is_some(), fingerprint }
}

/// Fill each interface's Hyprland name and layout. Names are assigned only
/// when one physical device owns every node with that base name, and then
/// any order will do (a bind on the device lists them all). Across devices
/// Hyprland numbers duplicates in creation order, which sysfs cannot
/// reproduce, so those nodes get candidates instead of a guess.
fn link_hyprland(keyboards: &mut [Keyboard], hyprland: Option<&[hypr::Keyboard]>) -> Vec<String> {
    let Some(hyprland) = hyprland else {
        return Vec::new();
    };
    // base name -> (owning keyboards, nodes with that name)
    let mut owners: BTreeMap<String, (BTreeSet<usize>, usize)> = BTreeMap::new();
    for (index, keyboard) in keyboards.iter().enumerate() {
        for interface in &keyboard.interfaces {
            let entry = owners.entry(hypr::internal_name(&interface.name)).or_default();
            entry.0.insert(index);
            entry.1 += 1;
        }
    }
    let mut used = BTreeSet::new();
    for keyboard in keyboards.iter_mut() {
        let mut taken: BTreeSet<String> = BTreeSet::new();
        for interface in &mut keyboard.interfaces {
            let base = hypr::internal_name(&interface.name);
            let matches: Vec<&hypr::Keyboard> =
                hyprland.iter().filter(|k| hypr::is_instance_of(&k.name, &base)).collect();
            let (devices, nodes) = &owners[&base];
            let chosen = if devices.len() == 1 && matches.len() == *nodes {
                matches.iter().copied().find(|k| !taken.contains(&k.name))
            } else {
                interface.hyprland_candidates = matches.iter().map(|k| k.name.clone()).collect();
                None
            };
            if let Some(found) = chosen {
                interface.hyprland_name = Some(found.name.clone());
                taken.insert(found.name.clone());
            }
            used.extend(matches.iter().map(|k| k.name.clone()));
            interface.layout = chosen.or(matches.first().copied()).map(|k| Layout {
                layout: k.layout.clone(),
                variant: k.variant.clone(),
                options: k.options.clone(),
                model: k.model.clone(),
            });
        }
        keyboard.hyprland_linked = keyboard.interfaces.iter().all(|i| i.hyprland_name.is_some());
    }
    hyprland.iter().filter(|k| !used.contains(&k.name)).map(|k| k.name.clone()).collect()
}

fn fingerprint(keyboards: &[Keyboard]) -> String {
    // FNV-1a: stable across runs and builds, unlike std's hasher.
    let mut hash: u64 = 0xcbf29ce484222325;
    let mut ids: Vec<String> = keyboards
        .iter()
        .map(|k| {
            let names: Vec<String> = k.interfaces.iter().map(|i| format!("{}={:?}", i.name, i.hyprland_name)).collect();
            format!("{}|{}", k.id, names.join(","))
        })
        .collect();
    ids.sort();
    for byte in ids.join("\n").bytes() {
        hash ^= u64::from(byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::*;

    fn hypr(names: &[&str]) -> Vec<hypr::Keyboard> {
        names
            .iter()
            .map(|n| hypr::Keyboard { name: (*n).into(), layout: "latam".into(), ..Default::default() })
            .collect()
    }

    #[test]
    fn hp_victus_internal_keyboard_and_wmi_hotkeys() {
        let mut sys = FakeSys::new();
        hp_victus(&mut sys);
        let names = hypr(&["at-translated-set-2-keyboard", "hp-wmi-hotkeys", "power-button"]);
        let inventory = scan(sys.path(), &sys.udev_data(), Some(&names));
        let kinds: Vec<(Kind, &str)> = inventory.keyboards.iter().map(|k| (k.kind, k.label.as_str())).collect();
        assert_eq!(
            kinds,
            vec![
                (Kind::Internal, "Teclado integrado"),
                (Kind::VendorHotkeys, "Teclas especiales HP"),
                (Kind::SystemButtons, "Power Button")
            ],
            "the touchpad only declares buttons and is not a keyboard"
        );
        let internal = &inventory.keyboards[0];
        assert_eq!(internal.id, "0011:0001:0001:AT Translated Set 2 keyboard@isa0060/serio0/input0");
        assert_eq!(internal.interfaces[0].hyprland_name.as_deref(), Some("at-translated-set-2-keyboard"));
        assert!(internal.codes().contains(&140), "KEY_CALC is declared by the AT keyboard");
        let wmi = &inventory.keyboards[1];
        assert!(wmi.codes().contains(&149) && wmi.codes().contains(&465), "KEY_PROG2 and KEY_FN_ESC");
        assert!(wmi.hyprland_linked && !wmi.ambiguous);
    }

    #[test]
    fn usb_interfaces_are_one_physical_keyboard() {
        let mut sys = FakeSys::new();
        usb_keyboard(&mut sys, "1-2", "USB Keyboard");
        let names = hypr(&[
            "semico-usb-keyboard",
            "semico-usb-keyboard-consumer-control",
            "semico-usb-keyboard-system-control",
        ]);
        let inventory = scan(sys.path(), &sys.udev_data(), Some(&names));
        assert_eq!(inventory.keyboards.len(), 1);
        let keyboard = &inventory.keyboards[0];
        assert_eq!(keyboard.kind, Kind::Usb);
        assert_eq!(keyboard.label, "SEMICO USB Keyboard");
        assert_eq!(keyboard.id, "usb:1a2c:2124@pci0000:00/0000:00:14.0/usb1/1-2");
        assert_eq!(keyboard.interfaces.len(), 3);
        let interfaces: Vec<Option<&str>> = keyboard.interfaces.iter().map(|i| i.usb_interface.as_deref()).collect();
        assert_eq!(interfaces, vec![Some("0"), Some("1"), Some("1")]);
        assert!(keyboard.hyprland_linked);
        assert_eq!(keyboard.hyprland_names().len(), 3);
        assert!(keyboard.codes().contains(&140) && keyboard.codes().contains(&30));
        assert!(inventory.hyprland_only.is_empty());
    }

    #[test]
    fn two_identical_keyboards_are_told_apart_by_port_but_not_by_hyprland_name() {
        let mut sys = FakeSys::new();
        usb_keyboard(&mut sys, "1-2", "USB Keyboard");
        usb_keyboard(&mut sys, "1-3", "USB Keyboard");
        let names = hypr(&[
            "semico-usb-keyboard",
            "semico-usb-keyboard-1",
            "semico-usb-keyboard-consumer-control",
            "semico-usb-keyboard-consumer-control-1",
            "semico-usb-keyboard-system-control",
            "semico-usb-keyboard-system-control-1",
        ]);
        let inventory = scan(sys.path(), &sys.udev_data(), Some(&names));
        assert_eq!(inventory.keyboards.len(), 2);
        assert_ne!(inventory.keyboards[0].id, inventory.keyboards[1].id);
        for keyboard in &inventory.keyboards {
            assert!(!keyboard.ambiguous, "the port tells them apart");
            assert!(!keyboard.hyprland_linked);
            assert!(keyboard.hyprland_names().is_empty(), "never guess which -1 is which");
            assert_eq!(keyboard.interfaces[0].hyprland_candidates.len(), 2);
        }
    }

    #[test]
    fn hotplug_changes_the_fingerprint_and_keeps_the_identity() {
        let mut sys = FakeSys::new();
        hp_victus(&mut sys);
        let before = scan(sys.path(), &sys.udev_data(), None);
        let events = usb_keyboard(&mut sys, "1-2", "USB Keyboard");
        let plugged = scan(sys.path(), &sys.udev_data(), None);
        assert_eq!(plugged.keyboards.len(), before.keyboards.len() + 1);
        assert_ne!(plugged.fingerprint, before.fingerprint);
        for event in &events {
            sys.remove(event);
        }
        let unplugged = scan(sys.path(), &sys.udev_data(), None);
        assert_eq!(unplugged.fingerprint, before.fingerprint);
        let again = usb_keyboard(&mut sys, "1-2", "USB Keyboard");
        let replugged = scan(sys.path(), &sys.udev_data(), None);
        assert_ne!(again, events, "the kernel hands out new eventN numbers");
        let id = |inventory: &Inventory| inventory.keyboards.iter().find(|k| k.kind == Kind::Usb).map(|k| k.id.clone());
        assert_eq!(id(&replugged), id(&plugged), "same port, same identity");
    }

    #[test]
    fn no_hyprland_still_lists_keyboards() {
        let mut sys = FakeSys::new();
        hp_victus(&mut sys);
        let inventory = scan(sys.path(), &sys.udev_data(), None);
        assert!(!inventory.hyprland_available);
        assert!(inventory.keyboards.iter().all(|k| !k.hyprland_linked));
    }

    #[test]
    fn virtual_and_bluetooth_keyboards() {
        let mut sys = FakeSys::new();
        sys.input(FakeNode {
            path: "virtual/input",
            name: "ydotoold virtual device",
            phys: "",
            id: (0x6, 0x2333, 0x6666),
            ev: "7",
            key: encode(TYPING),
        });
        // The adapter is a USB device; the keyboards must not merge into it.
        sys.file("pci0000:00/0000:00:14.0/usb1/1-4/idVendor", "8087");
        for _ in 0..2 {
            sys.input(FakeNode {
                path: "pci0000:00/0000:00:14.0/usb1/1-4/1-4:1.0/bluetooth/hci0/hci0:256/0005:046D:B342.0006/input",
                name: "Keyboard K380",
                phys: "aa:bb:cc:dd:ee:ff",
                id: (0x5, 0x46d, 0xb342),
                ev: "12001f",
                key: encode(TYPING),
            });
        }
        let inventory = scan(sys.path(), &sys.udev_data(), None);
        let kinds: Vec<Kind> = inventory.keyboards.iter().map(|k| k.kind).collect();
        assert_eq!(kinds, vec![Kind::Bluetooth, Kind::Virtual]);
        let bluetooth = &inventory.keyboards[0];
        assert_eq!(bluetooth.interfaces.len(), 2, "two nodes of one HID device");
        assert!(!bluetooth.id.contains("aa:bb"), "no Bluetooth address in the identity");
        let json = serde_json::to_string(&inventory).unwrap();
        assert!(!json.contains("aa:bb"), "phys of a uhid node is the adapter address: {json}");
    }

    #[test]
    fn two_bluetooth_keyboards_of_one_model_are_ambiguous() {
        let mut sys = FakeSys::new();
        for (connection, hid) in [("hci0:256", "0005:046D:B342.0006"), ("hci0:512", "0005:046D:B342.0007")] {
            sys.input(FakeNode {
                path: &format!("pci0000:00/0000:00:14.0/usb1/1-4/1-4:1.0/bluetooth/hci0/{connection}/{hid}/input"),
                name: "Keyboard K380",
                phys: "aa:bb:cc:dd:ee:ff",
                id: (0x5, 0x46d, 0xb342),
                ev: "12001f",
                key: encode(TYPING),
            });
        }
        let inventory = scan(sys.path(), &sys.udev_data(), None);
        let ids: Vec<&str> = inventory.keyboards.iter().map(|k| k.id.as_str()).collect();
        assert_eq!(ids, vec!["bluetooth:046d:b342#1", "bluetooth:046d:b342#2"]);
        assert!(inventory.keyboards.iter().all(|k| k.ambiguous));
    }
}
