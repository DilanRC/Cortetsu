//! A real private bus checks the serialized NetworkManager contract without a
//! NetworkManager daemon, privilege changes, credentials, or network activity.
use std::{
    collections::HashMap,
    io::{BufRead, BufReader, Write},
    process::{Command, Stdio},
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};
use zbus::{
    blocking::connection::Builder,
    zvariant::{OwnedObjectPath, OwnedValue, Str},
};

type Settings = HashMap<String, HashMap<String, OwnedValue>>;
const UUID: &str = "12345678-abcd-1234-abcd-123456789012";
const PATH: &str = "/org/freedesktop/NetworkManager/Settings/1";
struct BusProcess(std::process::Child);
impl Drop for BusProcess {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}
fn clone_settings(s: &Settings) -> Settings {
    s.iter()
        .map(|(k, v)| {
            (
                k.clone(),
                v.iter()
                    .map(|(k, v)| (k.clone(), v.try_clone().unwrap()))
                    .collect(),
            )
        })
        .collect()
}
struct Manager;
#[zbus::interface(name = "org.freedesktop.NetworkManager.Settings")]
impl Manager {
    fn get_connection_by_uuid(&self, uuid: &str) -> zbus::fdo::Result<OwnedObjectPath> {
        if uuid != UUID {
            return Err(zbus::fdo::Error::InvalidArgs("unknown UUID".into()));
        }
        Ok(OwnedObjectPath::try_from(PATH).unwrap())
    }
}
struct Profile {
    settings: Arc<Mutex<Settings>>,
    updates: Arc<AtomicUsize>,
    bad_readback: bool,
}
#[zbus::interface(name = "org.freedesktop.NetworkManager.Settings.Connection")]
impl Profile {
    fn get_settings(&self) -> Settings {
        let mut s = clone_settings(&self.settings.lock().unwrap());
        s.get_mut("802-11-wireless-security").unwrap().remove("psk");
        s
    }
    fn get_secrets(&self, _setting: &str) -> Settings {
        let s = self.settings.lock().unwrap();
        let mut security = HashMap::new();
        if self.bad_readback {
            security.insert("psk".into(), OwnedValue::from(Str::from("wrong-readback")));
        } else if let Some(psk) = s["802-11-wireless-security"].get("psk") {
            security.insert("psk".into(), psk.try_clone().unwrap());
        }
        HashMap::from([("802-11-wireless-security".into(), security)])
    }
    fn update2(
        &self,
        settings: Settings,
        flags: u32,
        _args: HashMap<String, OwnedValue>,
    ) -> zbus::fdo::Result<HashMap<String, OwnedValue>> {
        if flags != 1 {
            return Err(zbus::fdo::Error::InvalidArgs("must persist to disk".into()));
        }
        self.updates.fetch_add(1, Ordering::SeqCst);
        *self.settings.lock().unwrap() = settings;
        Ok(HashMap::new())
    }
}
fn fixture(enterprise: bool) -> Settings {
    HashMap::from([
        (
            "connection".into(),
            HashMap::from([
                ("uuid".into(), OwnedValue::from(Str::from(UUID))),
                (
                    "interface-name".into(),
                    OwnedValue::from(Str::from("wlan2")),
                ),
            ]),
        ),
        ("802-11-wireless".into(), HashMap::new()),
        (
            "802-11-wireless-security".into(),
            HashMap::from([
                (
                    "key-mgmt".into(),
                    OwnedValue::from(Str::from(if enterprise { "wpa-eap" } else { "wpa-psk" })),
                ),
                ("psk-flags".into(), OwnedValue::from(3u32)),
            ]),
        ),
        (
            "ipv4".into(),
            HashMap::from([("method".into(), OwnedValue::from(Str::from("manual")))]),
        ),
    ])
}
fn exercise(bad_readback: bool, enterprise: bool) -> (std::process::Output, Settings, usize) {
    let mut bus = BusProcess(
        Command::new("dbus-daemon")
            .args(["--session", "--nofork", "--nopidfile", "--print-address=1"])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("dbus-daemon is required for protocol tests"),
    );
    let mut address = String::new();
    BufReader::new(bus.0.stdout.take().unwrap())
        .read_line(&mut address)
        .unwrap();
    let settings = Arc::new(Mutex::new(fixture(enterprise)));
    let updates = Arc::new(AtomicUsize::new(0));
    let _server = Builder::address(address.trim())
        .unwrap()
        .method_timeout(Duration::from_secs(2))
        .name("org.freedesktop.NetworkManager")
        .unwrap()
        .serve_at("/org/freedesktop/NetworkManager/Settings", Manager)
        .unwrap()
        .serve_at(
            PATH,
            Profile {
                settings: settings.clone(),
                updates: updates.clone(),
                bad_readback,
            },
        )
        .unwrap()
        .build()
        .unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_cortetsu-desktop-runtime"))
        .args(["cortetsu-connectivity-secret", UUID])
        .env("DBUS_SYSTEM_BUS_ADDRESS", address.trim())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(b"fixture-only-password")
        .unwrap();
    let output = child.wait_with_output().unwrap();
    assert!(!String::from_utf8_lossy(&output.stdout).contains("fixture-only-password"));
    assert!(!String::from_utf8_lossy(&output.stderr).contains("fixture-only-password"));
    let result = clone_settings(&settings.lock().unwrap());
    (output, result, updates.load(Ordering::SeqCst))
}
#[test]
fn update2_preserves_profile_and_confirms_persistent_secret() {
    let (o, s, updates) = exercise(false, false);
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    assert_eq!(o.stdout, b"CREDENTIAL_SAVED\n");
    assert_eq!(updates, 1);
    assert_eq!(<&str>::try_from(&s["ipv4"]["method"]).unwrap(), "manual");
    assert_eq!(
        <&str>::try_from(&s["connection"]["interface-name"]).unwrap(),
        "wlan2"
    );
    assert_eq!(
        u32::try_from(&s["802-11-wireless-security"]["psk-flags"]).unwrap(),
        0
    );
}
#[test]
fn mismatching_readback_fails_closed() {
    let (o, _, updates) = exercise(true, false);
    assert_eq!(o.status.code(), Some(4));
    assert_eq!(o.stderr, b"credential-save-failed\n");
    assert_eq!(updates, 1);
}
#[test]
fn enterprise_profile_never_calls_update() {
    let (o, _, updates) = exercise(false, true);
    assert_eq!(o.status.code(), Some(2));
    assert_eq!(o.stderr, b"profile-invalid\n");
    assert_eq!(updates, 0);
}
