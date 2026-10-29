//! `cortetsu-agents` end to end on a private bus. Fake NetworkManager and
//! BlueZ managers record the registrations and call the agents the way the
//! daemons do; a fake shell answers each dialog over the helper's socket.
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    fs,
    io::{BufRead, BufReader, Write},
    os::unix::{fs::PermissionsExt, net::UnixStream},
    path::PathBuf,
    process::{Child, Command, Stdio},
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant},
};
use zbus::{
    blocking::{Connection, connection::Builder},
    message::Header,
    zvariant::{ObjectPath, OwnedValue, Str, Value as V},
};

type Settings = HashMap<String, HashMap<String, OwnedValue>>;
const NM_AGENT: &str = "/org/freedesktop/NetworkManager/SecretAgent";
const NM_IFACE: &str = "org.freedesktop.NetworkManager.SecretAgent";
const BT_AGENT: &str = "/org/cortetsu/BluetoothAgent";
const DEVICE: &str = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF";

fn wait_for(what: &str, limit: Duration, mut ready: impl FnMut() -> bool) {
    let start = Instant::now();
    while !ready() {
        assert!(start.elapsed() < limit, "timed out waiting for {what}");
        thread::sleep(Duration::from_millis(20));
    }
}

#[derive(Default)]
struct Calls(Mutex<Vec<String>>);

impl Calls {
    fn push(&self, call: String) {
        self.0.lock().unwrap().push(call);
    }
    fn count(&self, prefix: &str) -> usize {
        self.0
            .lock()
            .unwrap()
            .iter()
            .filter(|c| c.starts_with(prefix))
            .count()
    }
}

struct AgentManager(Arc<Calls>);

#[zbus::interface(name = "org.freedesktop.NetworkManager.AgentManager")]
impl AgentManager {
    fn register_with_capabilities(&self, #[zbus(header)] h: Header<'_>, id: &str, caps: u32) {
        self.0
            .push(format!("nm {id} {caps} {}", h.sender().unwrap()));
    }
}

struct BluezManager(Arc<Calls>);

#[zbus::interface(name = "org.bluez.AgentManager1")]
impl BluezManager {
    fn register_agent(&self, path: ObjectPath<'_>, capability: &str) {
        self.0.push(format!("bt-register {path} {capability}"));
    }
    fn request_default_agent(&self, path: ObjectPath<'_>) {
        self.0.push(format!("bt-default {path}"));
    }
}

struct Device(Arc<Calls>);

#[zbus::interface(name = "org.bluez.Device1")]
impl Device {
    #[zbus(property)]
    fn alias(&self) -> String {
        "Auriculares ZON".into()
    }
    #[zbus(property)]
    fn paired(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn trusted(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn set_trusted(&mut self, value: bool) {
        self.0.push(format!("trusted {value}"));
    }
    fn cancel_pairing(&self) {
        self.0.push("cancel-pairing".into());
    }
}

struct Session {
    dir: tempfile::TempDir,
    address: String,
    children: Vec<Child>,
    calls: Arc<Calls>,
    daemons: Option<Connection>,
}

impl Drop for Session {
    fn drop(&mut self) {
        for child in self.children.iter_mut().rev() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

impl Session {
    fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("run")).unwrap();
        fs::set_permissions(dir.path().join("run"), fs::Permissions::from_mode(0o700)).unwrap();
        let socket = dir.path().join("bus");
        let config = dir.path().join("bus.conf");
        fs::write(
            &config,
            format!(
                r#"<busconfig><type>session</type><listen>unix:path={}</listen>
<auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow receive_sender="*"/><allow own="*"/></policy></busconfig>"#,
                socket.display()
            ),
        )
        .unwrap();
        let bus = Command::new("dbus-daemon")
            .arg(format!("--config-file={}", config.display()))
            .arg("--nofork")
            .stdout(Stdio::null())
            .spawn()
            .unwrap();
        wait_for("the bus", Duration::from_secs(5), || socket.exists());
        let address = format!("unix:path={}", socket.display());
        Self {
            dir,
            address,
            children: vec![bus],
            calls: Arc::default(),
            daemons: None,
        }
    }

    fn path(&self, sub: &str) -> PathBuf {
        self.dir.path().join(sub)
    }

    fn bus(&self) -> Connection {
        Builder::address(self.address.as_str())
            .unwrap()
            .build()
            .unwrap()
    }

    /// Fake NetworkManager and bluetoothd, owning their real names.
    fn daemons(&mut self) {
        let conn = Builder::address(self.address.as_str())
            .unwrap()
            .serve_at(
                "/org/freedesktop/NetworkManager/AgentManager",
                AgentManager(self.calls.clone()),
            )
            .unwrap()
            .serve_at("/org/bluez", BluezManager(self.calls.clone()))
            .unwrap()
            .serve_at(DEVICE, Device(self.calls.clone()))
            .unwrap()
            .name("org.freedesktop.NetworkManager")
            .unwrap()
            .name("org.bluez")
            .unwrap()
            .build()
            .unwrap();
        self.daemons = Some(conn);
    }

    /// The helper with a fake `qs` that records each dialog request. With
    /// `shell` false, `qs` fails as it does with no shell running.
    fn agents(&mut self, shell: bool) {
        let qs = self.path("qs");
        let body = if shell {
            format!(
                "[ \"$6\" = request ] && echo \"$7 $8\" >> {}/requests\nexit 0",
                self.dir.path().display()
            )
        } else {
            "exit 1".into()
        };
        fs::write(&qs, format!("#!/bin/sh\n{body}\n")).unwrap();
        fs::set_permissions(&qs, fs::Permissions::from_mode(0o755)).unwrap();
        let child = Command::new(env!("CARGO_BIN_EXE_cortetsu-desktop-runtime"))
            .arg("cortetsu-agents")
            .env_clear()
            .env("PATH", std::env::var_os("PATH").unwrap())
            .env("CORTETSU_AGENTS_BUS", &self.address)
            .env("CORTETSU_AGENTS_LOCK", self.path("agents.lock"))
            .env("CORTETSU_QS_BIN", &qs)
            .env("CORTETSU_SHELL_PATH", self.dir.path())
            .env("XDG_RUNTIME_DIR", self.path("run"))
            .stdout(Stdio::null())
            .spawn()
            .unwrap();
        self.children.push(child);
        wait_for("both registrations", Duration::from_secs(10), || {
            self.calls.count("nm ") >= 1 && self.calls.count("bt-default") >= 1
        });
    }

    fn agent_name(&self) -> String {
        let calls = self.calls.0.lock().unwrap();
        let line = calls.iter().rev().find(|c| c.starts_with("nm ")).unwrap();
        line.rsplit(' ').next().unwrap().to_owned()
    }

    fn requests(&self) -> Vec<String> {
        fs::read_to_string(self.path("requests"))
            .map(|t| t.lines().map(str::to_owned).collect())
            .unwrap_or_default()
    }
}

/// Plays the shell for dialog `n`: reads its request and, unless `answer` is
/// None, writes `answer` back with the request's token.
fn shell_dialog(session: &Session, n: usize, answer: Option<Value>) -> (Value, UnixStream) {
    wait_for("a dialog", Duration::from_secs(15), || {
        session.requests().len() > n
    });
    let line = session.requests()[n].clone();
    let (socket, token) = line.split_once(' ').unwrap();
    let mode = fs::metadata(socket).unwrap().permissions().mode() & 0o777;
    assert_eq!(mode, 0o600, "socket must be private");
    let mut stream = UnixStream::connect(socket).unwrap();
    let mut reader = BufReader::new(stream.try_clone().unwrap());
    let mut text = String::new();
    reader.read_line(&mut text).unwrap();
    let request: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(request["token"], token);
    if let Some(mut answer) = answer {
        answer["token"] = token.into();
        stream.write_all(format!("{answer}\n").as_bytes()).unwrap();
    }
    (request, stream)
}

fn closed(stream: &mut UnixStream) -> bool {
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    let mut rest = String::new();
    BufReader::new(stream)
        .read_line(&mut rest)
        .is_ok_and(|n| n == 0)
}

fn wifi(key_mgmt: &str) -> Settings {
    let v = |v: V<'static>| OwnedValue::try_from(v).unwrap();
    HashMap::from([
        (
            "connection".into(),
            HashMap::from([("id".into(), v(V::from("Casa")))]),
        ),
        (
            "802-11-wireless".into(),
            HashMap::from([("ssid".into(), v(V::from(b"Casa 5G".to_vec())))]),
        ),
        (
            "802-11-wireless-security".into(),
            HashMap::from([(
                "key-mgmt".into(),
                OwnedValue::from(Str::from(key_mgmt.to_owned())),
            )]),
        ),
    ])
}

fn get_secrets(conn: &Connection, agent: &str, flags: u32) -> zbus::Result<Settings> {
    let path = ObjectPath::try_from("/org/freedesktop/NetworkManager/Settings/7").unwrap();
    conn.call_method(
        Some(agent),
        NM_AGENT,
        Some(NM_IFACE),
        "GetSecrets",
        &(
            wifi("wpa-psk"),
            &path,
            "802-11-wireless-security",
            Vec::<String>::new(),
            flags,
        ),
    )?
    .body()
    .deserialize::<Settings>()
}

fn error_name(result: zbus::Result<impl Sized>) -> String {
    match result {
        Err(zbus::Error::MethodError(name, _, _)) => name.to_string(),
        Err(e) => panic!("unexpected error {e}"),
        Ok(_) => "ok".into(),
    }
}

fn bt_call(
    conn: &Connection,
    agent: &str,
    method: &str,
    body: &(impl serde::Serialize + zbus::zvariant::DynamicType),
) -> zbus::Result<zbus::message::Message> {
    conn.call_method(
        Some(agent),
        BT_AGENT,
        Some("org.bluez.Agent1"),
        method,
        body,
    )
}

#[test]
fn wifi_password_cancel_and_no_interaction() {
    let mut s = Session::new();
    s.daemons();
    s.agents(true);
    assert!(s.calls.count("nm org.cortetsu.agents 0") == 1);
    let agent = s.agent_name();
    let conn = s.bus();

    // A password: the dialog names the network, and the secret comes back.
    let caller = {
        let (conn, agent) = (s.bus(), agent.clone());
        thread::spawn(move || get_secrets(&conn, &agent, 0x1))
    };
    let (request, _stream) = shell_dialog(
        &s,
        0,
        Some(json!({"reply": "yes", "password": "correcta-larga"})),
    );
    assert_eq!(request["kind"], "password");
    assert_eq!(request["message"], "Contraseña de «Casa 5G»");
    assert_eq!(request["minLength"], 8);
    let secrets = caller.join().unwrap().unwrap();
    assert_eq!(
        <&str>::try_from(&secrets["802-11-wireless-security"]["psk"]).unwrap(),
        "correcta-larga"
    );

    // Without ALLOW_INTERACTION there is no dialog.
    assert_eq!(
        error_name(get_secrets(&conn, &agent, 0)),
        "org.freedesktop.NetworkManager.SecretAgent.NoSecrets"
    );
    assert_eq!(s.requests().len(), 1);

    // NetworkManager gives up: CancelGetSecrets closes the open dialog,
    // while GetSecrets is still waiting (so calls run concurrently).
    let caller = {
        let (conn, agent) = (s.bus(), agent.clone());
        thread::spawn(move || get_secrets(&conn, &agent, 0x1 | 0x2))
    };
    let (request, mut stream) = shell_dialog(&s, 1, None);
    assert!(
        request["warning"]
            .as_str()
            .unwrap()
            .contains("no fue aceptada")
    );
    let path = ObjectPath::try_from("/org/freedesktop/NetworkManager/Settings/7").unwrap();
    conn.call_method(
        Some(agent.as_str()),
        NM_AGENT,
        Some(NM_IFACE),
        "CancelGetSecrets",
        &(&path, "802-11-wireless-security"),
    )
    .unwrap();
    assert!(closed(&mut stream), "the dialog must close");
    assert_eq!(
        error_name(caller.join().unwrap()),
        "org.freedesktop.NetworkManager.SecretAgent.UserCanceled"
    );
}

#[test]
fn bluetooth_pairing_dialogs() {
    let mut s = Session::new();
    s.daemons();
    s.agents(true);
    assert_eq!(
        s.calls
            .count(&format!("bt-register {BT_AGENT} KeyboardDisplay")),
        1
    );
    assert_eq!(s.calls.count(&format!("bt-default {BT_AGENT}")), 1);
    let agent = s.agent_name();
    let device = ObjectPath::try_from(DEVICE).unwrap();
    let spawn_call = |method: &'static str, body: (ObjectPath<'static>, u32)| {
        let (conn, agent) = (s.bus(), agent.clone());
        thread::spawn(move || {
            let r = if method == "RequestPasskey" {
                bt_call(&conn, &agent, method, &(&body.0,))
            } else {
                bt_call(&conn, &agent, method, &body)
            };
            r.map(|m| m.body().deserialize::<u32>().unwrap_or(0))
        })
    };

    // Confirm the code on both sides.
    let call = spawn_call("RequestConfirmation", (device.clone(), 12345));
    let (request, _a) = shell_dialog(&s, 0, Some(json!({"reply": "yes"})));
    assert_eq!(request["kind"], "confirm");
    assert_eq!(request["code"], "012345");
    assert_eq!(request["message"], "¿Emparejar con «Auriculares ZON»?");
    assert!(call.join().unwrap().is_ok());

    // Refusing is Rejected.
    let call = spawn_call("RequestConfirmation", (device.clone(), 1));
    let _b = shell_dialog(&s, 1, Some(json!({"reply": "no"})));
    assert_eq!(error_name(call.join().unwrap()), "org.bluez.Error.Rejected");

    // A typed passkey comes back as a number; a bad one is rejected.
    let call = spawn_call("RequestPasskey", (device.clone(), 0));
    let (request, _c) = shell_dialog(&s, 2, Some(json!({"reply": "yes", "password": "004321"})));
    assert_eq!(request["digits"], true);
    assert_eq!(call.join().unwrap().unwrap(), 4321);
    let call = spawn_call("RequestPasskey", (device.clone(), 0));
    let _d = shell_dialog(&s, 3, Some(json!({"reply": "yes", "password": "12x"})));
    assert_eq!(error_name(call.join().unwrap()), "org.bluez.Error.Rejected");

    // BlueZ cancels a pending confirmation: the dialog closes.
    let call = spawn_call("RequestConfirmation", (device.clone(), 7));
    let (_, mut stream) = shell_dialog(&s, 4, None);
    bt_call(&s.bus(), &agent, "Cancel", &()).unwrap();
    assert!(closed(&mut stream));
    assert_eq!(error_name(call.join().unwrap()), "org.bluez.Error.Canceled");

    // A service of an untrusted device, with "always trust".
    let conn = s.bus();
    let call = {
        let (conn, agent) = (s.bus(), agent.clone());
        let device = device.clone();
        thread::spawn(move || {
            bt_call(
                &conn,
                &agent,
                "AuthorizeService",
                &(&device, "0000110b-0000-1000-8000-00805f9b34fb"),
            )
        })
    };
    let (request, _e) = shell_dialog(&s, 5, Some(json!({"reply": "yes", "choice": true})));
    assert_eq!(request["message"], "«Auriculares ZON» quiere usar el audio");
    assert!(call.join().unwrap().is_ok());
    wait_for("Trusted set", Duration::from_secs(5), || {
        s.calls.count("trusted true") == 1
    });

    // A code to type: the method returns at once; repeats do not stack
    // dialogs; cancelling in the shell cancels the pairing.
    bt_call(&conn, &agent, "DisplayPasskey", &(&device, 987654u32, 0u16)).unwrap();
    let (request, mut stream) = shell_dialog(&s, 6, None);
    assert_eq!(request["kind"], "display");
    assert_eq!(request["code"], "987654");
    bt_call(&conn, &agent, "DisplayPasskey", &(&device, 987654u32, 1u16)).unwrap();
    thread::sleep(Duration::from_millis(300));
    assert_eq!(
        s.requests().len(),
        7,
        "a repeat must not open another dialog"
    );
    let token = request["token"].as_str().unwrap();
    stream
        .write_all(format!("{}\n", json!({"token": token, "reply": "no"})).as_bytes())
        .unwrap();
    wait_for("CancelPairing", Duration::from_secs(5), || {
        s.calls.count("cancel-pairing") == 1
    });
}

#[test]
fn no_shell_refuses_and_daemon_restart_reregisters() {
    let mut s = Session::new();
    s.daemons();
    s.agents(false);
    let agent = s.agent_name();
    let conn = s.bus();
    assert_eq!(
        error_name(get_secrets(&conn, &agent, 0x1)),
        "org.freedesktop.NetworkManager.SecretAgent.UserCanceled"
    );
    assert_eq!(
        error_name(bt_call(
            &conn,
            &agent,
            "RequestAuthorization",
            &(ObjectPath::try_from(DEVICE).unwrap(),)
        )),
        "org.bluez.Error.Canceled"
    );

    // NetworkManager and bluetoothd restart: the agents register again.
    s.daemons = None;
    wait_for("names released", Duration::from_secs(5), || {
        conn.call_method(
            Some("org.freedesktop.DBus"),
            "/org/freedesktop/DBus",
            Some("org.freedesktop.DBus"),
            "NameHasOwner",
            &("org.bluez",),
        )
        .is_ok_and(|m| !m.body().deserialize::<bool>().unwrap())
    });
    s.daemons();
    wait_for("re-registration", Duration::from_secs(10), || {
        s.calls.count("nm ") == 2 && s.calls.count("bt-default") == 2
    });
}

#[test]
fn a_second_helper_waits_for_the_first() {
    let mut s = Session::new();
    s.daemons();
    s.agents(true);
    let mut second = Command::new(env!("CARGO_BIN_EXE_cortetsu-desktop-runtime"))
        .arg("cortetsu-agents")
        .env_clear()
        .env("CORTETSU_AGENTS_BUS", &s.address)
        .env("CORTETSU_AGENTS_LOCK", s.path("agents.lock"))
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    thread::sleep(Duration::from_millis(500));
    assert_eq!(s.calls.count("nm "), 1, "the second helper must wait");
    assert!(second.try_wait().unwrap().is_none());
    // The first goes away (its shell exited): the second takes over.
    let mut first = s.children.pop().unwrap();
    first.kill().unwrap();
    first.wait().unwrap();
    wait_for("takeover", Duration::from_secs(10), || {
        s.calls.count("nm ") == 2
    });
    second.kill().unwrap();
    second.wait().unwrap();
}
