//! Keyboards present right now, read from sysfs.
//!
//! Every `eventN` node with EV_KEY codes other than mouse/touchpad buttons is
//! an interface. Interfaces are grouped into physical devices by their nearest
//! USB device ancestor (a USB keyboard's "Keyboard", "Consumer Control" and
//! "System Control" nodes are one keyboard), else their HID device, else the
//! node itself. `eventN` is reported for diagnostics only; identities come
//! from the bus, the vendor/product and the port path, which survive reboots.
//! Serial numbers (`uniq`) are never read: the port tells two identical
//! keyboards apart, and the data stays free of identifiers that follow a
//! person between machines.

use crate::bitmap;
use crate::hypr;
use crate::keycodes;
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

pub const BUS_USB: u16 = 0x03;
pub const BUS_BLUETOOTH: u16 = 0x05;
pub const BUS_VIRTUAL: u16 = 0x06;
pub const BUS_I8042: u16 = 0x11;
pub const BUS_I2C: u16 = 0x18;
pub const BUS_HOST: u16 = 0x19;

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
    /// Two connected devices share `model` and nothing tells them apart.
    pub ambiguous: bool,
    /// Every interface has a Hyprland name, so a per-device bind can target it.
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
        if interface.is_none() && dir.join("bInterfaceNumber").is_file() {
            let number = read(&dir.join("bInterfaceNumber"));
            interface =
                Some(number.trim_start_matches('0').to_owned()).map(|n| if n.is_empty() { "0".into() } else { n });
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
        let model = match kind {
            Kind::Usb | Kind::Bluetooth => {
                let bus = if kind == Kind::Usb { "usb" } else { "bluetooth" };
                format!("{bus}:{:04x}:{:04x}", first.vendor, first.product)
            }
            Kind::Virtual => format!("virtual:{}", first.name),
            _ => format!("{:04x}:{:04x}:{:04x}:{}", first.bus, first.vendor, first.product, first.name),
        };
        // USB: the port path. Bluetooth has no port and the address is a
        // serial number in all but name, so it stays at the model.
        let id = match kind {
            Kind::Usb => format!("{model}@{}", relative(group, sys)),
            Kind::Internal | Kind::VendorHotkeys | Kind::SystemButtons | Kind::Other => {
                format!("{model}@{}", if first.phys.is_empty() { relative(group, sys) } else { first.phys.clone() })
            }
            Kind::Bluetooth | Kind::Virtual => model.clone(),
        };
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

    // Same id twice (two Bluetooth keyboards of one model): number them so
    // each row is addressable, and mark both as ambiguous.
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

/// Fill each interface's Hyprland name and layout. A name is assigned only
/// when one physical device owns every node with that base name: Hyprland
/// numbers duplicates in creation order, which sysfs cannot reproduce.
fn link_hyprland(keyboards: &mut [Keyboard], hyprland: Option<&[hypr::Keyboard]>) -> Vec<String> {
    let Some(hyprland) = hyprland else {
        return Vec::new();
    };
    let mut owners: BTreeMap<String, BTreeSet<usize>> = BTreeMap::new();
    let mut count: BTreeMap<String, usize> = BTreeMap::new();
    for (index, keyboard) in keyboards.iter().enumerate() {
        for interface in &keyboard.interfaces {
            let base = hypr::internal_name(&interface.name);
            owners.entry(base.clone()).or_default().insert(index);
            *count.entry(base).or_default() += 1;
        }
    }
    let mut used = BTreeSet::new();
    for keyboard in keyboards.iter_mut() {
        let mut linked = true;
        let mut assigned_in_group: BTreeSet<String> = BTreeSet::new();
        for interface in &mut keyboard.interfaces {
            let base = hypr::internal_name(&interface.name);
            let matches: Vec<&hypr::Keyboard> =
                hyprland.iter().filter(|k| hypr::is_instance_of(&k.name, &base)).collect();
            let single_owner = owners.get(&base).is_some_and(|o| o.len() == 1);
            if single_owner && count[&base] == 1 && matches.len() == 1 {
                interface.hyprland_name = Some(matches[0].name.clone());
            } else if single_owner && matches.len() == count[&base] {
                // One device with several same-named nodes: which is which
                // does not matter for a bind on the device, so give each a
                // distinct name of the set.
                interface.hyprland_name =
                    matches.iter().map(|k| k.name.clone()).find(|name| !assigned_in_group.contains(name));
            } else {
                interface.hyprland_candidates = matches.iter().map(|k| k.name.clone()).collect();
            }
            if let Some(name) = &interface.hyprland_name {
                assigned_in_group.insert(name.clone());
                used.insert(name.clone());
            } else {
                linked = false;
                used.extend(interface.hyprland_candidates.iter().cloned());
            }
            let layout_source = interface
                .hyprland_name
                .as_ref()
                .and_then(|name| hyprland.iter().find(|k| &k.name == name))
                .or_else(|| matches.first().copied());
            interface.layout = layout_source.map(|k| Layout {
                layout: k.layout.clone(),
                variant: k.variant.clone(),
                options: k.options.clone(),
                model: k.model.clone(),
            });
        }
        keyboard.hyprland_linked = linked;
        if !linked && keyboard.interfaces.iter().any(|i| !i.hyprland_candidates.is_empty()) {
            keyboard.ambiguous = true;
        }
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
pub mod fixtures {
    //! Fake sysfs trees. Bitmaps marked "real" were read on the HP Victus
    //! reference laptop on 2026-10-17.
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicUsize, Ordering};

    pub struct FakeSys {
        pub root: PathBuf,
        next_event: usize,
    }

    impl Drop for FakeSys {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.root);
        }
    }

    pub fn encode(codes: &[u16]) -> String {
        let max = codes.iter().copied().max().unwrap_or(0) as usize;
        let mut words = vec![0u64; max / 64 + 1];
        for &code in codes {
            words[code as usize / 64] |= 1 << (code % 64);
        }
        words.iter().rev().map(|w| format!("{w:x}")).collect::<Vec<_>>().join(" ")
    }

    pub struct FakeNode<'a> {
        pub path: &'a str,
        pub name: &'a str,
        pub phys: &'a str,
        pub id: (u16, u16, u16),
        pub ev: &'a str,
        pub key: String,
    }

    impl FakeSys {
        pub fn new() -> Self {
            static COUNTER: AtomicUsize = AtomicUsize::new(0);
            let root = std::env::temp_dir().join(format!(
                "cortetsu-keyboards-sys-{}-{}",
                std::process::id(),
                COUNTER.fetch_add(1, Ordering::SeqCst)
            ));
            let _ = fs::remove_dir_all(&root);
            fs::create_dir_all(root.join("class/input")).unwrap();
            FakeSys { root, next_event: 0 }
        }

        pub fn file(&self, relative: &str, contents: &str) {
            let path = self.root.join("devices").join(relative);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(path, format!("{contents}\n")).unwrap();
        }

        /// An input node at devices/<path>; returns its eventN.
        pub fn input(&mut self, node: FakeNode) -> String {
            let event = format!("event{}", self.next_event);
            self.next_event += 1;
            let dir = format!("{}/{}", node.path, event.replace("event", "input"));
            self.file(&format!("{dir}/name"), node.name);
            self.file(&format!("{dir}/phys"), node.phys);
            self.file(&format!("{dir}/uniq"), "");
            self.file(&format!("{dir}/id/bustype"), &format!("{:04x}", node.id.0));
            self.file(&format!("{dir}/id/vendor"), &format!("{:04x}", node.id.1));
            self.file(&format!("{dir}/id/product"), &format!("{:04x}", node.id.2));
            self.file(&format!("{dir}/capabilities/ev"), node.ev);
            self.file(&format!("{dir}/capabilities/key"), &node.key);
            let event_dir = self.root.join("devices").join(&dir).join(&event);
            fs::create_dir_all(&event_dir).unwrap();
            fs::write(event_dir.join("dev"), format!("13:{}\n", 64 + self.next_event)).unwrap();
            std::os::unix::fs::symlink(&event_dir, self.root.join("class/input").join(&event)).unwrap();
            event
        }

        /// udev's database entry for a node, as /run/udev/data/c13:N.
        pub fn udev(&self, event: &str, lines: &str) {
            let dev = fs::read_to_string(self.root.join("class/input").join(event).join("dev")).unwrap();
            let data = self.udev_data();
            fs::create_dir_all(&data).unwrap();
            fs::write(data.join(format!("c{}", dev.trim())), lines).unwrap();
        }

        pub fn udev_data(&self) -> PathBuf {
            self.root.join("run-udev-data")
        }

        pub fn remove(&self, event: &str) {
            fs::remove_file(self.root.join("class/input").join(event)).unwrap();
        }

        pub fn path(&self) -> &Path {
            &self.root
        }
    }

    pub const AT_KEY: &str =
        "20000 6000000000000020 0 0 10500f02100007 ff803078f900d401 feffffdfffcfffff fffffffffffffffe";
    /// Real udev database lines of the AT keyboard (HP hwdb entries).
    pub const AT_UDEV: &str = "E:KEYBOARD_KEY_81=fn_esc\nE:KEYBOARD_KEY_8b=camera\nE:KEYBOARD_KEY_92=brightnessdown\n\
        E:KEYBOARD_KEY_a1=!calc\nE:KEYBOARD_KEY_d7=wlan\nE:ID_INPUT_KEYBOARD=1\n";
    pub const HP_WMI_KEY: &str = "180000 20000 0 4000000000 0 101000700000000 2302400 0 0";

    /// The reference laptop as read from /sys (real bitmaps).
    pub fn hp_victus(sys: &mut FakeSys) {
        let at = sys.input(FakeNode {
            path: "platform/i8042/serio0/input",
            name: "AT Translated Set 2 keyboard",
            phys: "isa0060/serio0/input0",
            id: (0x11, 0x1, 0x1),
            ev: "120013",
            key: AT_KEY.into(),
        });
        sys.udev(&at, AT_UDEV);
        sys.input(FakeNode {
            path: "virtual/input",
            name: "HP WMI hotkeys",
            phys: "wmi/input0",
            id: (0x19, 0, 0),
            ev: "33",
            key: HP_WMI_KEY.into(),
        });
        sys.input(FakeNode {
            path: "platform/PNP0C0C:00/input",
            name: "Power Button",
            phys: "PNP0C0C/button/input0",
            id: (0x19, 0, 1),
            ev: "3",
            key: "8000 10000000000000 0".into(),
        });
        sys.input(FakeNode {
            path: "platform/AMDI0010:03/i2c-0/i2c-ELAN07FB:00/0018:04F3:321A.0005/input",
            name: "ELAN07FB:00 04F3:321A Touchpad",
            phys: "i2c-ELAN07FB:00",
            id: (0x18, 0x4f3, 0x321a),
            ev: "1b",
            key: "e520 10000 0 0 0 0".into(),
        });
    }

    pub const TYPING: &[u16] = &[1, 2, 3, 14, 15, 16, 17, 28, 29, 30, 42, 56, 57, 59, 87, 88, 97, 100, 103, 125];
    pub const CONSUMER: &[u16] = &[113, 114, 115, 140, 148, 150, 155, 163, 164, 165, 166, 172, 183, 184];
    pub const SYSTEM: &[u16] = &[116, 142, 143];

    /// A full-size USB keyboard with three HID interfaces on one port.
    /// Returns the eventN of each node.
    pub fn usb_keyboard(sys: &mut FakeSys, port: &str, product: &str) -> Vec<String> {
        let usb = format!("pci0000:00/0000:00:14.0/usb1/{port}");
        sys.file(&format!("{usb}/idVendor"), "1a2c");
        sys.file(&format!("{usb}/idProduct"), "2124");
        sys.file(&format!("{usb}/manufacturer"), "SEMICO");
        sys.file(&format!("{usb}/product"), product);
        let mut events = Vec::new();
        for (iface, hid, name, codes) in [
            ("1.0", "0003:1A2C:2124.0001", "SEMICO USB Keyboard", TYPING),
            ("1.1", "0003:1A2C:2124.0002", "SEMICO USB Keyboard Consumer Control", CONSUMER),
            ("1.1", "0003:1A2C:2124.0002", "SEMICO USB Keyboard System Control", SYSTEM),
        ] {
            let interface = format!("{usb}/{port}:{iface}");
            sys.file(&format!("{interface}/bInterfaceNumber"), &format!("0{}", &iface[2..]));
            events.push(sys.input(FakeNode {
                path: &format!("{interface}/{hid}/input"),
                name,
                phys: &format!("usb-0000:00:14.0-{port}/input{}", &iface[2..]),
                id: (0x3, 0x1a2c, 0x2124),
                ev: "120013",
                key: super::fixtures::encode(codes),
            }));
        }
        events
    }
}

#[cfg(test)]
mod tests {
    use super::fixtures::*;
    use super::*;

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
            assert!(keyboard.ambiguous && !keyboard.hyprland_linked);
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
    }
}
