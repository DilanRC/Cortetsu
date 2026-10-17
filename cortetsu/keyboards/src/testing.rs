//! Fake sysfs trees for tests. Bitmaps and udev lines marked "real" were
//! read on the HP Victus reference laptop on 2026-10-17.
#![doc(hidden)]

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

impl Default for FakeSys {
    fn default() -> Self {
        Self::new()
    }
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

pub const AT_KEY: &str = "20000 6000000000000020 0 0 10500f02100007 ff803078f900d401 feffffdfffcfffff fffffffffffffffe";
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
            key: encode(codes),
        }));
    }
    events
}
