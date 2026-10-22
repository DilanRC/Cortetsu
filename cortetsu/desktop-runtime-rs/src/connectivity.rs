//! Secrets enter over stdin and stay in memory and authenticated D-Bus messages.
use crate::common::*;
use std::{collections::HashMap, io::Read, time::Duration};
use zbus::{
    blocking::{Proxy, connection::Builder},
    zvariant::{OwnedObjectPath, OwnedValue, Str},
};
type Settings = HashMap<String, HashMap<String, OwnedValue>>;
#[derive(Clone, Copy, Debug)]
struct CredentialError(&'static str, i32);
fn validate(uuid: &str, password: &str) -> std::result::Result<(), CredentialError> {
    let valid = uuid.len() == 36
        && uuid.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_hexdigit()
            }
        });
    if !valid {
        return Err(CredentialError("profile-invalid", 2));
    }
    if password.is_empty()
        || password.len() > 256
        || password.bytes().any(|b| matches!(b, 0 | b'\r' | b'\n'))
    {
        return Err(CredentialError("password-invalid", 2));
    }
    Ok(())
}
fn string<'a>(settings: &'a Settings, section: &str, key: &str) -> Option<&'a str> {
    settings
        .get(section)?
        .get(key)
        .and_then(|v| <&str>::try_from(v).ok())
}
fn update_password(
    settings: &mut Settings,
    uuid: &str,
    password: &str,
) -> std::result::Result<(), CredentialError> {
    if !settings.contains_key("802-11-wireless")
        || string(settings, "connection", "uuid") != Some(uuid)
    {
        return Err(CredentialError("profile-invalid", 2));
    }
    let key = string(settings, "802-11-wireless-security", "key-mgmt")
        .ok_or(CredentialError("profile-invalid", 2))?;
    if !matches!(key, "wpa-psk" | "sae") {
        return Err(CredentialError("profile-invalid", 2));
    }
    if key == "wpa-psk"
        && !((8..=63).contains(&password.len())
            || (password.len() == 64 && password.bytes().all(|b| b.is_ascii_hexdigit())))
    {
        return Err(CredentialError("profile-invalid", 2));
    }
    let security = settings
        .get_mut("802-11-wireless-security")
        .ok_or(CredentialError("profile-invalid", 2))?;
    security.insert(
        "psk".into(),
        OwnedValue::from(Str::from(password.to_owned())),
    );
    security.insert("psk-flags".into(), OwnedValue::from(0u32));
    Ok(())
}
fn verify(
    settings: &Settings,
    secrets: &Settings,
    password: &str,
) -> std::result::Result<(), CredentialError> {
    let flags = settings
        .get("802-11-wireless-security")
        .and_then(|s| s.get("psk-flags"))
        .map(u32::try_from)
        .transpose()
        .map_err(|_| CredentialError("credential-save-failed", 4))?
        .unwrap_or(0);
    if flags != 0 || string(secrets, "802-11-wireless-security", "psk") != Some(password) {
        return Err(CredentialError("credential-save-failed", 4));
    }
    Ok(())
}
fn dbus_error(e: zbus::Error) -> CredentialError {
    if matches!(e,zbus::Error::InputOutput(ref io) if io.kind()==std::io::ErrorKind::TimedOut) {
        CredentialError("timeout", 3)
    } else {
        CredentialError("credential-save-failed", 4)
    }
}
fn save(uuid: &str, password: &str) -> std::result::Result<(), CredentialError> {
    let bus = Builder::system()
        .and_then(|b| b.method_timeout(Duration::from_secs(10)).build())
        .map_err(|_| CredentialError("service-unavailable", 3))?;
    let manager = Proxy::new(
        &bus,
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager/Settings",
        "org.freedesktop.NetworkManager.Settings",
    )
    .map_err(dbus_error)?;
    let path: OwnedObjectPath = manager
        .call("GetConnectionByUuid", &(uuid,))
        .map_err(|_| CredentialError("profile-invalid", 2))?;
    let connection = Proxy::new(
        &bus,
        "org.freedesktop.NetworkManager",
        path,
        "org.freedesktop.NetworkManager.Settings.Connection",
    )
    .map_err(dbus_error)?;
    let mut settings: Settings = connection.call("GetSettings", &()).map_err(dbus_error)?;
    update_password(&mut settings, uuid, password)?;
    let _: HashMap<String, OwnedValue> = connection
        .call(
            "Update2",
            &(settings, 1u32, HashMap::<String, OwnedValue>::new()),
        )
        .map_err(dbus_error)?;
    let readback: Settings = connection.call("GetSettings", &()).map_err(dbus_error)?;
    let secrets: Settings = connection
        .call("GetSecrets", &("802-11-wireless-security",))
        .map_err(dbus_error)?;
    verify(&readback, &secrets, password)
}
pub fn main(args: &[String]) -> Result<i32> {
    let result = (|| -> std::result::Result<(), CredentialError> {
        if args.len() != 1 {
            return Err(CredentialError("profile-invalid", 2));
        }
        let mut bytes = Vec::new();
        std::io::stdin()
            .take(257)
            .read_to_end(&mut bytes)
            .map_err(|_| CredentialError("password-invalid", 2))?;
        let password =
            String::from_utf8(bytes).map_err(|_| CredentialError("password-invalid", 2))?;
        validate(&args[0], &password)?;
        save(&args[0], &password)
    })();
    match result {
        Ok(()) => {
            println!("CREDENTIAL_SAVED");
            Ok(0)
        }
        Err(CredentialError(code, status)) => {
            eprintln!("{code}");
            Ok(status)
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    const UUID: &str = "12345678-abcd-1234-abcd-123456789012";
    fn profile() -> Settings {
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
                    ("key-mgmt".into(), OwnedValue::from(Str::from("wpa-psk"))),
                    ("psk-flags".into(), OwnedValue::from(3u32)),
                ]),
            ),
            (
                "ipv4".into(),
                HashMap::from([("method".into(), OwnedValue::from(Str::from("manual")))]),
            ),
        ])
    }
    #[test]
    fn preserve_profile_readback_and_enterprise_rejection() {
        let mut p = profile();
        update_password(&mut p, UUID, "fixture-password").unwrap();
        assert_eq!(string(&p, "ipv4", "method"), Some("manual"));
        assert_eq!(string(&p, "connection", "interface-name"), Some("wlan2"));
        assert!(verify(&p, &p, "fixture-password").is_ok());
        assert!(verify(&p, &p, "wrong").is_err());
        p.get_mut("802-11-wireless-security")
            .unwrap()
            .insert("key-mgmt".into(), OwnedValue::from(Str::from("wpa-eap")));
        assert!(update_password(&mut p, UUID, "fixture-password").is_err());
    }
    #[test]
    fn invalid_secret_never_mutates() {
        assert!(validate(UUID, "secret\nline").is_err());
        let mut p = profile();
        assert!(update_password(&mut p, UUID, "short").is_err());
        assert!(string(&p, "802-11-wireless-security", "psk").is_none());
    }
}
