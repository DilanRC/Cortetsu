//! What the running Hyprland reports: its keyboards and its effective binds.
//!
//! Everything goes through `hyprctl` (`CORTETSU_HYPRCTL` overrides the path
//! for tests). `None` means Hyprland could not be asked, which callers must
//! keep distinct from "asked and found nothing".

use serde::Deserialize;
use std::time::Duration;

#[derive(Debug, Clone, Deserialize, PartialEq, Eq, Default)]
pub struct Keyboard {
    pub name: String,
    #[serde(default)]
    pub layout: String,
    #[serde(default)]
    pub variant: String,
    #[serde(default)]
    pub options: String,
    #[serde(default)]
    pub model: String,
    #[serde(default)]
    pub main: bool,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq, Default)]
pub struct Bind {
    #[serde(default)]
    pub modmask: u32,
    #[serde(default)]
    pub key: String,
    #[serde(default)]
    pub keycode: u32,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub submap: String,
    #[serde(default)]
    pub mouse: bool,
    #[serde(default)]
    pub release: bool,
    #[serde(default)]
    pub dispatcher: String,
    #[serde(default)]
    pub arg: String,
}

pub fn hyprctl() -> String {
    crate::env_or("CORTETSU_HYPRCTL", "hyprctl")
}

pub fn run(args: &[&str], timeout: Duration) -> Option<String> {
    crate::run(&hyprctl(), args, timeout)
}

pub fn keyboards() -> Option<Vec<Keyboard>> {
    #[derive(Deserialize)]
    struct Devices {
        keyboards: Vec<Keyboard>,
    }
    let text = run(&["devices", "-j"], Duration::from_secs(5))?;
    serde_json::from_str::<Devices>(&text).ok().map(|devices| devices.keyboards)
}

pub fn binds() -> Option<Vec<Bind>> {
    let text = run(&["binds", "-j"], Duration::from_secs(5))?;
    serde_json::from_str(&text).ok()
}

/// Hyprland's internal device name: lowercase, spaces and newlines as dashes.
/// A second device with the same name gets `-1`, `-2`… in creation order.
pub fn internal_name(name: &str) -> String {
    name.chars().map(|c| if c == ' ' || c == '\n' { '-' } else { c }).collect::<String>().to_lowercase()
}

/// `name` is `base` or `base-N`.
pub fn is_instance_of(name: &str, base: &str) -> bool {
    name == base
        || name
            .strip_prefix(base)
            .and_then(|rest| rest.strip_prefix('-'))
            .is_some_and(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()))
}

pub const MOD_SHIFT: u32 = 1;
pub const MOD_CTRL: u32 = 4;
pub const MOD_ALT: u32 = 8;
pub const MOD_SUPER: u32 = 64;
pub const MOD_MOD5: u32 = 128;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn internal_names_match_hyprctl_devices() {
        assert_eq!(internal_name("AT Translated Set 2 keyboard"), "at-translated-set-2-keyboard");
        assert_eq!(internal_name("HP WMI hotkeys"), "hp-wmi-hotkeys");
    }

    #[test]
    fn duplicate_names_get_a_numeric_suffix() {
        assert!(is_instance_of("video-bus", "video-bus"));
        assert!(is_instance_of("video-bus-1", "video-bus"));
        assert!(!is_instance_of("video-bus-extra", "video-bus"));
        assert!(!is_instance_of("video-bus-", "video-bus"));
        assert!(!is_instance_of("video", "video-bus"));
    }

    #[test]
    fn parses_the_fields_it_uses_from_real_output() {
        let bind: Bind = serde_json::from_str(
            r#"{"locked":false,"mouse":false,"release":true,"modmask":64,"submap":"","key":"SUPER_L",
                "keycode":0,"description":"cortetsu:kbLauncher","dispatcher":"__lua","arg":"11"}"#,
        )
        .unwrap();
        assert_eq!((bind.modmask, bind.key.as_str(), bind.release), (64, "SUPER_L", true));
    }
}
