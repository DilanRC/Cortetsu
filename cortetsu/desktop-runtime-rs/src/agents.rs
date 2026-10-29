//! `cortetsu-agents`: the session's NetworkManager secret agent and BlueZ
//! pairing agent, both answered with the shell's dialog.
//!
//! NetworkManager asks it for a Wi-Fi password (a new network, a saved one
//! whose password changed, a hidden network) or a WPA-Enterprise login.
//! BlueZ asks it to confirm a pairing code, to type a PIN or passkey, to show
//! a code to type on a keyboard, and to authorize a service of an untrusted
//! device. Each question becomes one dialog over `shellprompt`.
//!
//! The shell starts this helper and it dies with the shell (parent-death
//! signal), so the agents exist only while a dialog can be shown. A lock
//! keeps one instance per user: a second shell's helper (the nested test
//! harness) waits instead of taking the agents over.
use crate::{
    common::Result,
    shellprompt::{Pending, ask},
};
use serde_json::{Value, json};
use std::{collections::HashMap, env, fs, sync::Arc, time::Duration};
use zbus::{
    blocking::{Connection, connection::Builder, fdo::DBusProxy},
    zvariant::{OwnedObjectPath, OwnedValue, Str},
};

const NM: &str = "org.freedesktop.NetworkManager";
const NM_AGENT_PATH: &str = "/org/freedesktop/NetworkManager/SecretAgent";
const BLUEZ: &str = "org.bluez";
const BT_AGENT_PATH: &str = "/org/cortetsu/BluetoothAgent";
const IDENTIFIER: &str = "org.cortetsu.agents";

type Settings = HashMap<String, HashMap<String, OwnedValue>>;

// NM_SECRET_AGENT_GET_SECRETS_FLAG_* (libnm/nm-secret-agent-old.h).
const ALLOW_INTERACTION: u32 = 0x1;
const REQUEST_NEW: u32 = 0x2;

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.freedesktop.NetworkManager.SecretAgent")]
enum NmError {
    #[zbus(error)]
    ZBus(zbus::Error),
    NoSecrets(String),
    UserCanceled(String),
}

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.bluez.Error")]
enum BtError {
    #[zbus(error)]
    ZBus(zbus::Error),
    Rejected(String),
    Canceled(String),
}

// --- NetworkManager ------------------------------------------------------

fn string(settings: &Settings, section: &str, key: &str) -> Option<String> {
    let value = settings.get(section)?.get(key)?;
    <&str>::try_from(value).ok().map(str::to_owned)
}

fn strings(settings: &Settings, section: &str, key: &str) -> Vec<String> {
    settings
        .get(section)
        .and_then(|s| s.get(key))
        .and_then(|v| v.try_clone().ok())
        .and_then(|v| Vec::<String>::try_from(v).ok())
        .unwrap_or_default()
}

/// The SSID for a Wi-Fi connection, else the connection's name.
fn network_name(settings: &Settings) -> String {
    settings
        .get("802-11-wireless")
        .and_then(|s| s.get("ssid"))
        .and_then(|v| v.try_clone().ok())
        .and_then(|v| Vec::<u8>::try_from(v).ok())
        .map(|ssid| String::from_utf8_lossy(&ssid).trim().to_owned())
        .filter(|ssid| !ssid.is_empty())
        .or_else(|| string(settings, "connection", "id"))
        .unwrap_or_default()
}

/// One NetworkManager question: where the answer goes and what to show.
#[derive(Debug, PartialEq)]
struct SecretAsk {
    setting: String,
    secret: String,
    identity: Option<String>,
    request: Value,
}

/// What to ask for `setting_name`, or None for secrets this agent does not
/// handle (VPN, mobile broadband, PPPoE): NetworkManager then reports
/// NoSecrets and the connection fails as it does without an agent.
// ponytail: Wi-Fi and 802.1X only. VPN secrets need each plugin's
// auth-dialog; add them here if a VPN profile is ever used.
fn secret_ask(settings: &Settings, setting_name: &str, flags: u32) -> Option<SecretAsk> {
    let name = network_name(settings);
    let warning = if flags & REQUEST_NEW != 0 {
        "La contraseña guardada no fue aceptada. Escribe la actual."
    } else {
        ""
    };
    let base = |message: String, description: String| {
        json!({
            "kind": "password",
            "icon": "wifi_password",
            "title": "",
            "message": message,
            "description": description,
            "warning": warning,
            "continueLabel": "Conectar",
        })
    };
    match setting_name {
        "802-11-wireless-security" => {
            let key_mgmt = string(settings, setting_name, "key-mgmt").unwrap_or_default();
            let (secret, mut request) = match key_mgmt.as_str() {
                "wpa-psk" => {
                    let mut r = base(
                        format!("Contraseña de «{name}»"),
                        "La red Wi-Fi necesita una contraseña.".into(),
                    );
                    // NetworkManager rejects a WPA key outside 8–63 characters
                    // (or 64 hex digits).
                    r["minLength"] = 8.into();
                    r["maxLength"] = 64.into();
                    ("psk".to_owned(), r)
                }
                "sae" => (
                    "psk".to_owned(),
                    base(
                        format!("Contraseña de «{name}»"),
                        "La red Wi-Fi necesita una contraseña.".into(),
                    ),
                ),
                "none" | "" => {
                    let index = settings
                        .get(setting_name)
                        .and_then(|s| s.get("wep-tx-keyidx"))
                        .and_then(|v| u32::try_from(v).ok())
                        .filter(|i| *i < 4)
                        .unwrap_or(0);
                    (
                        format!("wep-key{index}"),
                        base(
                            format!("Clave WEP de «{name}»"),
                            "La red usa WEP, un cifrado antiguo e inseguro.".into(),
                        ),
                    )
                }
                _ => return None,
            };
            request["passwordLabel"] = "Contraseña".into();
            Some(SecretAsk {
                setting: setting_name.to_owned(),
                secret,
                identity: None,
                request,
            })
        }
        "802-1x" => {
            let eap = strings(settings, setting_name, "eap");
            if eap.is_empty() {
                return None;
            }
            if eap.iter().all(|m| m == "tls") {
                let mut request = base(
                    format!("Certificado de «{name}»"),
                    "Escribe la contraseña de la clave privada del certificado.".into(),
                );
                request["passwordLabel"] = "Contraseña de la clave privada".into();
                return Some(SecretAsk {
                    setting: setting_name.to_owned(),
                    secret: "private-key-password".into(),
                    identity: None,
                    request,
                });
            }
            let mut request = base(
                format!("Inicio de sesión en «{name}»"),
                "La red usa WPA-Enterprise: escribe tu usuario y tu contraseña.".into(),
            );
            request["identityLabel"] = "Usuario".into();
            request["identity"] = string(settings, setting_name, "identity")
                .unwrap_or_default()
                .into();
            request["passwordLabel"] = "Contraseña".into();
            Some(SecretAsk {
                setting: setting_name.to_owned(),
                secret: "password".into(),
                identity: Some("identity".into()),
                request,
            })
        }
        _ => None,
    }
}

/// The GetSecrets reply for the shell's answer.
fn secrets_of(ask: &SecretAsk, answer: Option<&Value>) -> std::result::Result<Settings, NmError> {
    let canceled = || NmError::UserCanceled("El usuario canceló".into());
    let answer = answer.ok_or_else(canceled)?;
    if answer["reply"].as_str() != Some("yes") {
        return Err(canceled());
    }
    let password = answer["password"].as_str().ok_or_else(canceled)?;
    let mut section = HashMap::from([(
        ask.secret.clone(),
        OwnedValue::from(Str::from(password.to_owned())),
    )]);
    if let Some(key) = &ask.identity {
        let identity = answer["identity"].as_str().unwrap_or_default();
        section.insert(
            key.clone(),
            OwnedValue::from(Str::from(identity.to_owned())),
        );
    }
    Ok(HashMap::from([(ask.setting.clone(), section)]))
}

struct NmAgent {
    pending: Arc<Pending>,
}

#[zbus::interface(name = "org.freedesktop.NetworkManager.SecretAgent")]
impl NmAgent {
    async fn get_secrets(
        &self,
        connection: Settings,
        connection_path: OwnedObjectPath,
        setting_name: String,
        _hints: Vec<String>,
        flags: u32,
    ) -> std::result::Result<Settings, NmError> {
        let no_secrets = || NmError::NoSecrets("Sin secretos".into());
        // Without interaction NetworkManager only wants stored secrets, and
        // this agent stores none: system-owned secrets live in the profile.
        if flags & ALLOW_INTERACTION == 0 {
            return Err(no_secrets());
        }
        let wanted = secret_ask(&connection, &setting_name, flags).ok_or_else(no_secrets)?;
        let key = format!("nm:{}:{setting_name}", connection_path.as_str());
        let pending = self.pending.clone();
        let request = wanted.request.clone();
        let answer = blocking::unblock(move || ask(request, &key, &pending, || false)).await;
        secrets_of(&wanted, answer.as_ref())
    }

    fn cancel_get_secrets(&self, connection_path: OwnedObjectPath, setting_name: String) {
        self.pending
            .cancel(&format!("nm:{}:{setting_name}", connection_path.as_str()));
    }

    // System-owned secrets are saved by NetworkManager in the profile. An
    // agent-owned secret (psk-flags 1) is not kept, so it is asked again.
    fn save_secrets(&self, _connection: Settings, _connection_path: OwnedObjectPath) {}

    fn delete_secrets(&self, _connection: Settings, _connection_path: OwnedObjectPath) {}
}

// --- BlueZ ---------------------------------------------------------------

/// Service names for the UUIDs a headset, speaker, controller or phone asks
/// for (Bluetooth Assigned Numbers, 16-bit service classes).
fn service_name(uuid: &str) -> &'static str {
    let short = uuid
        .strip_prefix("0000")
        .and_then(|rest| rest.get(..4))
        .unwrap_or("")
        .to_ascii_lowercase();
    match short.as_str() {
        "110a" | "110b" | "110d" => "el audio",
        "110c" | "110e" | "110f" => "el control multimedia",
        "1108" | "1112" | "111e" | "111f" => "las llamadas",
        "1124" | "1812" => "la entrada (teclado, ratón o mando)",
        "1115" | "1116" | "1117" => "la red",
        "1105" | "1106" => "la transferencia de archivos",
        "112f" => "la agenda de contactos",
        "1132" | "1133" | "1134" => "los mensajes",
        _ => "un servicio",
    }
}

fn device_property<T>(conn: &Connection, device: &str, name: &str) -> Option<T>
where
    T: TryFrom<OwnedValue>,
    <T as TryFrom<OwnedValue>>::Error: Into<zbus::Error>,
{
    let proxy = zbus::blocking::Proxy::new(conn, BLUEZ, device, "org.bluez.Device1").ok()?;
    proxy.get_property::<T>(name).ok()
}

/// The device's alias, else its address from the object path.
fn device_name(conn: &Connection, device: &str) -> String {
    device_property::<String>(conn, device, "Alias")
        .filter(|alias| !alias.trim().is_empty())
        .unwrap_or_else(|| {
            device
                .rsplit('/')
                .next()
                .unwrap_or(device)
                .trim_start_matches("dev_")
                .replace('_', ":")
        })
}

fn bt_request(kind: &str, message: String, description: &str) -> Value {
    json!({
        "kind": kind,
        "icon": "bluetooth",
        "title": "",
        "message": message,
        "description": description,
        "continueLabel": "Emparejar",
    })
}

fn accepted(answer: Option<&Value>) -> std::result::Result<&Value, BtError> {
    match answer {
        Some(a) if a["reply"].as_str() == Some("yes") => Ok(a),
        Some(_) => Err(BtError::Rejected("El usuario rechazó".into())),
        None => Err(BtError::Canceled("Cancelado".into())),
    }
}

/// A 6-digit passkey from the dialog's text.
fn passkey_of(text: &str) -> Option<u32> {
    let text = text.trim();
    (!text.is_empty() && text.len() <= 6 && text.bytes().all(|b| b.is_ascii_digit()))
        .then(|| text.parse().ok())
        .flatten()
}

struct BtAgent {
    pending: Arc<Pending>,
}

impl BtAgent {
    async fn confirm(
        &self,
        conn: &zbus::Connection,
        device: &OwnedObjectPath,
        build: impl FnOnce(String) -> Value + Send + 'static,
    ) -> Option<Value> {
        let conn = Connection::from(conn.clone());
        let device = device.to_string();
        let pending = self.pending.clone();
        blocking::unblock(move || {
            let request = build(device_name(&conn, &device));
            ask(request, &format!("bt:{device}"), &pending, || false)
        })
        .await
    }

    /// Shows a code to type on the device. BlueZ does not wait for this
    /// method, so the dialog stays up on its own until the device is paired,
    /// BlueZ cancels, or the user cancels (which cancels the pairing).
    fn display(&self, conn: &zbus::Connection, device: &OwnedObjectPath, code: String) {
        let key = format!("bt:display:{}", device.as_str());
        // BlueZ repeats DisplayPasskey as each digit is typed.
        if !self.pending.claim(&key) {
            return;
        }
        let conn = Connection::from(conn.clone());
        let device = device.to_string();
        let pending = self.pending.clone();
        blocking::unblock(move || {
            let name = device_name(&conn, &device);
            let mut request = bt_request(
                "display",
                format!("Escribe este código en «{name}»"),
                "Después pulsa Intro en el dispositivo.",
            );
            request["code"] = code.into();
            let start = std::time::Instant::now();
            let paired = || {
                start.elapsed() > Duration::from_secs(120)
                    || device_property::<bool>(&conn, &device, "Paired").unwrap_or(false)
            };
            let answer = ask(request, &key, &pending, paired);
            if answer.is_some_and(|a| a["reply"].as_str() != Some("yes")) {
                let proxy =
                    zbus::blocking::Proxy::new(&conn, BLUEZ, device.as_str(), "org.bluez.Device1");
                if let Ok(proxy) = proxy {
                    let _ = proxy.call_method("CancelPairing", &());
                }
            }
        })
        .detach();
    }
}

#[zbus::interface(name = "org.bluez.Agent1")]
impl BtAgent {
    fn release(&self) {
        self.pending.cancel("bt:");
    }

    async fn request_pin_code(
        &self,
        #[zbus(connection)] conn: &zbus::Connection,
        device: OwnedObjectPath,
    ) -> std::result::Result<String, BtError> {
        let answer = self
            .confirm(conn, &device, |name| {
                let mut r = bt_request(
                    "password",
                    format!("PIN de «{name}»"),
                    "Escribe el PIN del dispositivo. Muchos usan 0000 o 1234.",
                );
                r["reveal"] = true.into();
                r["maxLength"] = 16.into();
                r["passwordLabel"] = "PIN".into();
                r
            })
            .await;
        let pin = accepted(answer.as_ref())?["password"]
            .as_str()
            .unwrap_or_default()
            .to_owned();
        if pin.is_empty() || pin.len() > 16 {
            return Err(BtError::Rejected("PIN no válido".into()));
        }
        Ok(pin)
    }

    async fn request_passkey(
        &self,
        #[zbus(connection)] conn: &zbus::Connection,
        device: OwnedObjectPath,
    ) -> std::result::Result<u32, BtError> {
        let answer = self
            .confirm(conn, &device, |name| {
                let mut r = bt_request(
                    "password",
                    format!("Clave de «{name}»"),
                    "Escribe la clave de seis cifras que muestra el dispositivo.",
                );
                r["reveal"] = true.into();
                r["digits"] = true.into();
                r["maxLength"] = 6.into();
                r["passwordLabel"] = "Clave".into();
                r
            })
            .await;
        let text = accepted(answer.as_ref())?["password"]
            .as_str()
            .unwrap_or_default();
        passkey_of(text).ok_or_else(|| BtError::Rejected("Clave no válida".into()))
    }

    fn display_pin_code(
        &self,
        #[zbus(connection)] conn: &zbus::Connection,
        device: OwnedObjectPath,
        pincode: String,
    ) {
        self.display(conn, &device, pincode);
    }

    fn display_passkey(
        &self,
        #[zbus(connection)] conn: &zbus::Connection,
        device: OwnedObjectPath,
        passkey: u32,
        _entered: u16,
    ) {
        self.display(conn, &device, format!("{passkey:06}"));
    }

    async fn request_confirmation(
        &self,
        #[zbus(connection)] conn: &zbus::Connection,
        device: OwnedObjectPath,
        passkey: u32,
    ) -> std::result::Result<(), BtError> {
        let answer = self
            .confirm(conn, &device, move |name| {
                let mut r = bt_request(
                    "confirm",
                    format!("¿Emparejar con «{name}»?"),
                    "Comprueba que el dispositivo muestra el mismo código.",
                );
                r["code"] = format!("{passkey:06}").into();
                r
            })
            .await;
        accepted(answer.as_ref()).map(|_| ())
    }

    async fn request_authorization(
        &self,
        #[zbus(connection)] conn: &zbus::Connection,
        device: OwnedObjectPath,
    ) -> std::result::Result<(), BtError> {
        let answer = self
            .confirm(conn, &device, |name| {
                bt_request(
                    "confirm",
                    format!("¿Emparejar con «{name}»?"),
                    "El dispositivo quiere emparejarse sin código.",
                )
            })
            .await;
        accepted(answer.as_ref()).map(|_| ())
    }

    async fn authorize_service(
        &self,
        #[zbus(connection)] conn: &zbus::Connection,
        device: OwnedObjectPath,
        uuid: String,
    ) -> std::result::Result<(), BtError> {
        let service = service_name(&uuid);
        let answer = self
            .confirm(conn, &device, move |name| {
                let mut r = bt_request(
                    "confirm",
                    format!("«{name}» quiere usar {service}"),
                    "El dispositivo está emparejado, pero no es de confianza.",
                );
                r["continueLabel"] = "Permitir".into();
                r["cancelLabel"] = "Rechazar".into();
                r["choiceLabel"] = "Confiar siempre en este dispositivo".into();
                r
            })
            .await;
        let answer = accepted(answer.as_ref())?;
        if answer["choice"].as_bool() == Some(true) {
            let proxy = zbus::Proxy::new(conn, BLUEZ, device.as_str(), "org.bluez.Device1").await?;
            proxy
                .set_property("Trusted", true)
                .await
                .map_err(zbus::Error::from)?;
        }
        Ok(())
    }

    fn cancel(&self) {
        self.pending.cancel("bt:");
    }
}

// --- registration ----------------------------------------------------------

fn register_nm(conn: &Connection) {
    let result = conn.call_method(
        Some(NM),
        "/org/freedesktop/NetworkManager/AgentManager",
        Some("org.freedesktop.NetworkManager.AgentManager"),
        "RegisterWithCapabilities",
        &(IDENTIFIER, 0u32),
    );
    match result {
        Ok(_) => eprintln!("cortetsu-agents: NetworkManager secret agent registered"),
        Err(e) => eprintln!("cortetsu-agents: NetworkManager: {e}"),
    }
}

fn register_bt(conn: &Connection) {
    let path = zbus::zvariant::ObjectPath::from_static_str_unchecked(BT_AGENT_PATH);
    let result = conn
        .call_method(
            Some(BLUEZ),
            "/org/bluez",
            Some("org.bluez.AgentManager1"),
            "RegisterAgent",
            &(&path, "KeyboardDisplay"),
        )
        .and_then(|_| {
            conn.call_method(
                Some(BLUEZ),
                "/org/bluez",
                Some("org.bluez.AgentManager1"),
                "RequestDefaultAgent",
                &(&path,),
            )
        });
    match result {
        Ok(_) => eprintln!("cortetsu-agents: BlueZ agent registered"),
        Err(e) => eprintln!("cortetsu-agents: BlueZ: {e}"),
    }
}

fn lock_path() -> std::path::PathBuf {
    env::var_os("CORTETSU_AGENTS_LOCK")
        .map(Into::into)
        // Not XDG_RUNTIME_DIR: a nested test shell may use its own.
        .unwrap_or_else(|| {
            format!("/run/user/{}/cortetsu-agents.lock", nix::unistd::getuid()).into()
        })
}

pub fn main(_args: &[String]) -> Result<i32> {
    // Die with the shell that started this helper.
    nix::sys::prctl::set_pdeathsig(nix::sys::signal::Signal::SIGTERM)?;
    let lock = fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(lock_path())?;
    fs2::FileExt::lock_exclusive(&lock)?;

    let pending = Arc::new(Pending::default());
    let builder = match env::var("CORTETSU_AGENTS_BUS") {
        Ok(address) => Builder::address(address.as_str())?,
        Err(_) => Builder::system()?,
    };
    let conn = builder
        .method_timeout(Duration::from_secs(30))
        .serve_at(
            NM_AGENT_PATH,
            NmAgent {
                pending: pending.clone(),
            },
        )?
        .serve_at(BT_AGENT_PATH, BtAgent { pending })?
        .build()?;
    register_nm(&conn);
    register_bt(&conn);

    // A restarted NetworkManager or bluetoothd forgets its agents.
    let bus = DBusProxy::new(&conn)?;
    for signal in bus.receive_name_owner_changed()? {
        let Ok(args) = signal.args() else { continue };
        if args.new_owner().is_none() {
            continue;
        }
        match args.name().as_str() {
            NM => register_nm(&conn),
            BLUEZ => register_bt(&conn),
            _ => {}
        }
    }
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use zbus::zvariant::Value as V;

    fn settings(entries: &[(&str, &str, V<'static>)]) -> Settings {
        let mut s = Settings::new();
        for (section, key, value) in entries {
            s.entry((*section).into()).or_default().insert(
                (*key).into(),
                OwnedValue::try_from(value.try_clone().unwrap()).unwrap(),
            );
        }
        s
    }

    fn wifi(key_mgmt: &str) -> Settings {
        settings(&[
            ("connection", "id", V::from("Casa")),
            ("802-11-wireless", "ssid", V::from(b"Casa 5G".to_vec())),
            (
                "802-11-wireless-security",
                "key-mgmt",
                V::from(key_mgmt.to_owned()),
            ),
        ])
    }

    #[test]
    fn asks_psk_for_wpa_with_ssid_and_length() {
        let ask = secret_ask(&wifi("wpa-psk"), "802-11-wireless-security", 1).unwrap();
        assert_eq!(ask.secret, "psk");
        assert_eq!(ask.request["message"], "Contraseña de «Casa 5G»");
        assert_eq!(ask.request["minLength"], 8);
        assert_eq!(ask.request["warning"], "");
        let again = secret_ask(&wifi("sae"), "802-11-wireless-security", 1 | REQUEST_NEW).unwrap();
        assert!(
            again.request["warning"]
                .as_str()
                .unwrap()
                .contains("no fue aceptada")
        );
        assert!(again.request.get("minLength").is_none());
    }

    #[test]
    fn asks_the_wep_key_by_index() {
        let mut s = wifi("none");
        s.get_mut("802-11-wireless-security")
            .unwrap()
            .insert("wep-tx-keyidx".into(), OwnedValue::from(2u32));
        assert_eq!(
            secret_ask(&s, "802-11-wireless-security", 1)
                .unwrap()
                .secret,
            "wep-key2"
        );
    }

    #[test]
    fn enterprise_asks_identity_and_tls_the_key_password() {
        let mut s = wifi("wpa-eap");
        s.insert(
            "802-1x".into(),
            HashMap::from([
                (
                    "eap".into(),
                    OwnedValue::try_from(V::from(vec!["peap".to_owned()])).unwrap(),
                ),
                ("identity".into(), OwnedValue::from(Str::from("ana"))),
            ]),
        );
        let ask = secret_ask(&s, "802-1x", 1).unwrap();
        assert_eq!(ask.request["identity"], "ana");
        assert_eq!(ask.identity.as_deref(), Some("identity"));
        let reply = secrets_of(
            &ask,
            Some(&json!({"reply": "yes", "password": "pw", "identity": "ana.b"})),
        )
        .unwrap();
        let section = &reply["802-1x"];
        assert_eq!(<&str>::try_from(&section["password"]).unwrap(), "pw");
        assert_eq!(<&str>::try_from(&section["identity"]).unwrap(), "ana.b");

        s.get_mut("802-1x").unwrap().insert(
            "eap".into(),
            OwnedValue::try_from(V::from(vec!["tls".to_owned()])).unwrap(),
        );
        let tls = secret_ask(&s, "802-1x", 1).unwrap();
        assert_eq!(tls.secret, "private-key-password");
        assert!(tls.identity.is_none());
    }

    #[test]
    fn leaves_other_secrets_and_owe_alone() {
        assert!(secret_ask(&wifi("owe"), "802-11-wireless-security", 1).is_none());
        assert!(secret_ask(&wifi("wpa-psk"), "vpn", 1).is_none());
        assert!(secret_ask(&wifi("wpa-psk"), "gsm", 1).is_none());
    }

    #[test]
    fn a_cancel_is_user_canceled() {
        let ask = secret_ask(&wifi("wpa-psk"), "802-11-wireless-security", 1).unwrap();
        assert!(matches!(
            secrets_of(&ask, None),
            Err(NmError::UserCanceled(_))
        ));
        assert!(matches!(
            secrets_of(&ask, Some(&json!({"reply": "no"}))),
            Err(NmError::UserCanceled(_))
        ));
        let ok = secrets_of(&ask, Some(&json!({"reply": "yes", "password": "12345678"}))).unwrap();
        assert_eq!(
            <&str>::try_from(&ok["802-11-wireless-security"]["psk"]).unwrap(),
            "12345678"
        );
    }

    #[test]
    fn passkeys_are_six_digits_at_most() {
        assert_eq!(passkey_of("012345"), Some(12345));
        assert_eq!(passkey_of(" 999999 "), Some(999_999));
        assert_eq!(passkey_of("1234567"), None);
        assert_eq!(passkey_of("12a4"), None);
        assert_eq!(passkey_of(""), None);
    }

    #[test]
    fn names_common_services() {
        assert_eq!(
            service_name("0000110b-0000-1000-8000-00805f9b34fb"),
            "el audio"
        );
        assert_eq!(
            service_name("0000111E-0000-1000-8000-00805f9b34fb"),
            "las llamadas"
        );
        assert_eq!(
            service_name("ffffffff-0000-1000-8000-00805f9b34fb"),
            "un servicio"
        );
        assert_eq!(service_name(""), "un servicio");
    }
}
