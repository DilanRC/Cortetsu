//! What each declared key is, and whether it can take a new action.
//!
//! A key's states are not exclusive: OMEN can be VERIFIED, ASSIGNED and a
//! vendor key at once. The rules are deliberately conservative:
//! - DECLARED comes from the driver's bitmap, which lists every code the
//!   driver *could* send. An AT keyboard declares KEY_MAIL whether or not the
//!   laptop has that key, so a declared key is never presented as present.
//! - RESERVED protects typing, navigation, modifiers, F1–F12 (applications
//!   use them), system keys the firmware or logind handle, and Fn-layer codes.
//! - CANDIDATE is a dedicated key (media, launch, programmable, F13–F24,
//!   vendor) with a keysym and no global action. No bind in Hyprland does not
//!   prove the key is unused elsewhere, so the UI keeps the evidence visible.
//! - UNKNOWN is anything this table does not classify, or without a keysym.

use crate::hypr;
use crate::inventory::{Keyboard, Kind};
use crate::keycodes;
use crate::keymap::Keymap;
use serde::Serialize;
use std::collections::BTreeSet;

pub const KEY_SYSRQ: u16 = 99;
pub const KEY_POWER: u16 = 116;
pub const KEY_PROG2: u16 = 149;
pub const KEY_SLEEP: u16 = 142;
pub const KEY_WAKEUP: u16 = 143;
pub const KEY_SUSPEND: u16 = 205;
pub const KEY_F23: u16 = 193;
pub const KEY_FN_ESC: u16 = 0x1d1;

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum State {
    Declared,
    Verified,
    Assigned,
    Candidate,
    Reserved,
    Unknown,
}

/// How sure we are that the key physically exists.
#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "lowercase")]
pub enum Confidence {
    /// Pressed during an explicit test.
    Verified,
    /// udev's hardware database maps it for this model.
    Model,
    /// Only the driver's bitmap lists it.
    Declared,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "kebab-case")]
pub enum Category {
    Typing,
    Modifier,
    Navigation,
    Function,
    ExtraFunction,
    Media,
    Launch,
    Programmable,
    System,
    Firmware,
    Other,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Assignment {
    pub chord: String,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Key {
    pub code: u16,
    pub name: String,
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub keysym: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub levels: Vec<String>,
    pub category: Category,
    pub states: Vec<State>,
    pub confidence: Confidence,
    /// What the key is on this device, or why it is RESERVED or UNKNOWN.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    /// Effective binds on this key: alone, or as the key of a combination.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub assignments: Vec<Assignment>,
    /// Interface names that declare it (a USB keyboard's consumer interface).
    pub declared_by: Vec<String>,
}

impl Key {
    pub fn has(&self, state: State) -> bool {
        self.states.contains(&state)
    }
}

pub fn category(code: u16) -> Category {
    use Category::*;
    // Arms are tried in order: modifiers, F1–F12 and Print sit inside the
    // typing range and must win over it.
    match code {
        29 | 42 | 54 | 56 | 58 | 69 | 70 | 97 | 100 | 125 | 126 => Modifier,
        59..=68 | 87 | 88 => Function,
        183..=194 => ExtraFunction,
        102..=111 | 119 => Navigation,
        // Print; calc, file, www, screenlock, mail, bookmarks, computer,
        // back, forward; config, homepage, refresh; all apps, print, camera;
        // email…shop; send…documents; info, favorites, keyboard, text,
        // calendar; office apps; notification centre; task manager…assistant;
        // emoji, dictate; selection actions; selective screenshot.
        KEY_SYSRQ
        | 140
        | 144
        | 150
        | 152
        | 155..=159
        | 171..=173
        | 204
        | 210
        | 212
        | 215..=221
        | 231..=235
        | 358
        | 364
        | 374
        | 388
        | 397
        | 421..=430
        | 444
        | 577
        | 579..=581
        | 583
        | 585
        | 586
        | 596..=598
        | 634 => Launch,
        1..=83 | 85 | 86 | 89..=96 | 98 | 101 | 117 | 118 | 121..=124 | 127 => Typing,
        // Volume; eject…rewind; CD play/pause; play, fast forward, bass
        // boost; media; CD, radio, tuner, player, DVD, MP3, audio, video;
        // next, slow, shuffle, previous; frame back/forward, repeat.
        113..=115
        | 160..=168
        | 200
        | 201
        | 207..=209
        | 226
        | 383
        | 385..=387
        | 389
        | 391..=393
        | 407
        | 409
        | 410
        | 412
        | 436
        | 437
        | 439 => Media,
        112 | 148 | KEY_PROG2 | 202 | 203 | 656..=695 => Programmable,
        // Power, sleep, wake, rotate, suspend, brightness, video mode, keyboard
        // light, battery, radios, display switches, mic mute, touchpad,
        // sensors and toggles, lights, accessibility, privacy screen.
        KEY_POWER
        | KEY_SLEEP
        | KEY_WAKEUP
        | 153
        | KEY_SUSPEND
        | 224
        | 225
        | 227..=230
        | 236..=239
        | 241..=248
        | 530..=532
        | 560..=575
        | 542
        | 590
        | 633
        | 649 => System,
        0x1d0..=0x1e4 => Firmware,
        _ => Other,
    }
}

fn label(code: u16, name: &str) -> String {
    let fixed = match code {
        113 => "Silenciar",
        114 => "Bajar volumen",
        115 => "Subir volumen",
        140 => "Calculadora",
        148 => "Programable 1",
        KEY_PROG2 => "Programable 2",
        150 => "Navegador",
        155 => "Correo",
        156 => "Marcadores",
        157 => "Equipo",
        163 => "Pista siguiente",
        164 => "Reproducir/pausar",
        165 => "Pista anterior",
        166 => "Detener",
        172 => "Inicio web",
        202 => "Programable 3",
        203 => "Programable 4",
        212 => "Cámara",
        217 => "Buscar",
        224 => "Bajar brillo",
        225 => "Subir brillo",
        248 => "Silenciar micrófono",
        KEY_FN_ESC => "Fn + Esc",
        _ => "",
    };
    if !fixed.is_empty() {
        return fixed.into();
    }
    match code {
        183..=194 => format!("F{}", code - 170),
        _ => {
            let bare = name.trim_start_matches("KEY_").replace('_', " ").to_lowercase();
            let mut chars = bare.chars();
            chars.next().map(|c| c.to_uppercase().collect::<String>() + chars.as_str()).unwrap_or_default()
        }
    }
}

/// What a code is on this particular device: (label, note, reserved).
fn on_device(keyboard: &Keyboard, code: u16) -> Option<(&'static str, &'static str, bool)> {
    match code {
        KEY_PROG2 if keyboard.is_hp_wmi() => {
            Some(("OMEN", "Tecla OMEN del HP Victus (KEY_PROG2 en «HP WMI hotkeys»)", false))
        }
        // Copilot keys send Super+Shift+F23; F23 alone stays for applications.
        KEY_F23 if keyboard.kind == Kind::Internal => {
            Some(("Copilot", "La tecla Copilot envía Super + Shift + F23; F23 sola queda para las aplicaciones", true))
        }
        _ => None,
    }
}

fn reserved_reason(category: Category, code: u16) -> Option<&'static str> {
    Some(match category {
        Category::Typing => "Escribe texto: no se reasigna como tecla independiente",
        Category::Modifier => "Modificador: se combina con otras teclas",
        Category::Navigation => "Navegación de las aplicaciones",
        Category::Function => "F1–F12 pertenecen a las aplicaciones",
        Category::System if matches!(code, KEY_POWER | KEY_SLEEP | KEY_WAKEUP | KEY_SUSPEND) => {
            "La gestiona el sistema (logind o el firmware)"
        }
        Category::System => "Función del equipo: brillo, radio, pantalla o batería",
        Category::Firmware if code == KEY_FN_ESC => {
            "Capa Fn del firmware: queda sin asignar hasta confirmar qué envía en cada arranque"
        }
        Category::Firmware => "Capa Fn del firmware",
        _ => return None,
    })
}

/// Keysyms of functions the laptop or the session already owns, whatever
/// code produces them.
fn system_keysym(sym: &str) -> bool {
    [
        "XF86Touchpad",
        "XF86MonBrightness",
        "XF86KbdBrightness",
        "XF86KbdLight",
        "XF86PowerOff",
        "XF86PowerDown",
        "XF86Sleep",
        "XF86Suspend",
        "XF86Hibernate",
        "XF86WakeUp",
        "XF86WLAN",
        "XF86RFKill",
        "XF86Bluetooth",
        "XF86Display",
        "XF86Battery",
        "XF86AudioMicMute",
        "XF86RotateWindows",
        "XF86Fn",
    ]
    .iter()
    .any(|prefix| sym.starts_with(prefix))
}

/// The chord Hyprland would show for a bind, for display only.
pub fn chord_of(bind: &hypr::Bind) -> String {
    let mut parts: Vec<String> = [
        (hypr::MOD_SUPER, "SUPER"),
        (hypr::MOD_CTRL, "CTRL"),
        (hypr::MOD_ALT, "ALT"),
        (hypr::MOD_SHIFT, "SHIFT"),
        (hypr::MOD_MOD5, "MOD5"),
    ]
    .iter()
    .filter(|(bit, _)| bind.modmask & bit != 0)
    .map(|(_, name)| (*name).to_owned())
    .collect();
    parts.push(if bind.key.is_empty() && bind.keycode > 0 {
        format!("code:{}", bind.keycode)
    } else {
        bind.key.clone()
    });
    parts.join(" + ")
}

/// A bind on this key: by keysym (Hyprland compares names case-insensitively)
/// or by `code:N`, where N is the XKB keycode, Linux code + 8.
fn bind_hits(bind: &hypr::Bind, code: u16, keysym: Option<&str>) -> bool {
    if !bind.submap.is_empty() || bind.mouse {
        return false;
    }
    (bind.keycode > 0 && bind.keycode == u32::from(code) + 8)
        || keysym.is_some_and(|sym| bind.key.eq_ignore_ascii_case(sym))
}

pub fn classify(
    keyboard: &Keyboard,
    keymap: Option<&Keymap>,
    binds: Option<&[hypr::Bind]>,
    verified: &BTreeSet<u16>,
) -> Vec<Key> {
    let mut keys = Vec::new();
    for code in keyboard.codes() {
        let Some(name) = keycodes::name(code) else { continue };
        if name.starts_with("BTN_") {
            continue;
        }
        let category = category(code);
        let levels = keymap.and_then(|k| k.levels.get(&code)).cloned().unwrap_or_default();
        let keysym = levels.first().filter(|s| *s != "NoSymbol" && *s != "VoidSymbol").cloned();
        let device = on_device(keyboard, code);
        let hits: Vec<&hypr::Bind> =
            binds.unwrap_or_default().iter().filter(|bind| bind_hits(bind, code, keysym.as_deref())).collect();

        let reserved: Option<String> = if keysym.as_deref() == Some("ISO_Level3_Shift") {
            Some("AltGr escribe caracteres en esta distribución".into())
        } else if let Some(reason) = reserved_reason(category, code) {
            Some(reason.into())
        } else if let Some(sym) = keysym.as_deref().filter(|sym| system_keysym(sym)) {
            // Under evdev rules F20 produces XF86AudioMicMute: binding it
            // would also catch the microphone key.
            Some(format!("En esta distribución produce {sym}, una función del equipo"))
        } else if let Some((_, note, true)) = device {
            Some(note.into())
        } else {
            None
        };
        let unknown: Option<&str> = match (keysym.is_some(), keymap.is_some()) {
            (false, false) => Some("No se pudo leer la distribución del teclado"),
            (false, true) => Some("La distribución no le asigna ningún keysym"),
            _ => None,
        };
        let dedicated =
            matches!(category, Category::ExtraFunction | Category::Media | Category::Launch | Category::Programmable)
                || (keyboard.kind == Kind::VendorHotkeys && category == Category::Other);
        let typing_like =
            matches!(category, Category::Typing | Category::Modifier | Category::Navigation | Category::Function);
        // A typing key used inside SUPER + Q is not "a key with an action".
        let assigned = hits.iter().any(|bind| bind.modmask == 0) || (!typing_like && !hits.is_empty());

        let mut states = vec![State::Declared];
        if verified.contains(&code) {
            states.push(State::Verified);
        }
        if assigned {
            states.push(State::Assigned);
        }
        if reserved.is_some() {
            states.push(State::Reserved);
        }
        if dedicated && keysym.is_some() && !assigned && reserved.is_none() {
            states.push(State::Candidate);
        }
        if (reserved.is_none() && !dedicated) || unknown.is_some() || code == KEY_FN_ESC {
            states.push(State::Unknown);
        }
        let confidence = if verified.contains(&code) {
            Confidence::Verified
        } else if keyboard.interfaces.iter().any(|i| i.model_codes.contains(&code)) {
            Confidence::Model
        } else {
            Confidence::Declared
        };
        keys.push(Key {
            code,
            name: name.to_owned(),
            label: device.map(|(label, _, _)| label.to_owned()).unwrap_or_else(|| label(code, name)),
            keysym,
            levels,
            category,
            states,
            confidence,
            note: device.map(|(_, note, _)| note.to_owned()).or(reserved).or(unknown.map(str::to_owned)),
            assignments: hits
                .iter()
                .map(|bind| Assignment { chord: chord_of(bind), description: bind.description.clone() })
                .collect(),
            declared_by: keyboard
                .interfaces
                .iter()
                .filter(|i| i.codes.binary_search(&code).is_ok())
                .map(|i| i.name.clone())
                .collect(),
        });
    }
    keys
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::inventory::scan;
    use crate::keymap::{LATAM_EXCERPT, parse};
    use crate::testing::*;

    fn bind(modmask: u32, key: &str, description: &str) -> hypr::Bind {
        hypr::Bind { modmask, key: key.into(), description: description.into(), ..Default::default() }
    }

    fn victus() -> (FakeSys, Vec<Keyboard>) {
        let mut sys = FakeSys::new();
        hp_victus(&mut sys);
        let keyboards = scan(sys.path(), &sys.udev_data(), None).keyboards;
        (sys, keyboards)
    }

    fn key(keys: &[Key], code: u16) -> &Key {
        keys.iter().find(|k| k.code == code).unwrap_or_else(|| panic!("code {code} missing"))
    }

    #[test]
    fn typing_keys_are_reserved_never_candidates() {
        let (_sys, keyboards) = victus();
        let keymap = parse(LATAM_EXCERPT);
        let keys =
            classify(&keyboards[0], Some(&keymap), Some(&[bind(64, "Q", "cortetsu:kbCloseWindow")]), &BTreeSet::new());
        for code in [1, 2, 16, 28, 30, 39, 42, 125, 59] {
            let k = key(&keys, code);
            assert!(k.has(State::Reserved) && !k.has(State::Candidate), "{} must be reserved", k.name);
        }
        let q = key(&keys, 16);
        assert!(!q.has(State::Assigned), "SUPER + Q does not make Q a key with an action");
        assert_eq!(q.assignments[0].chord, "SUPER + Q");
    }

    #[test]
    fn altgr_is_reserved_under_latam() {
        let (_sys, keyboards) = victus();
        let keymap = parse(LATAM_EXCERPT);
        let keys = classify(&keyboards[0], Some(&keymap), Some(&[]), &BTreeSet::new());
        let altgr = key(&keys, 100);
        assert!(altgr.has(State::Reserved));
        assert_eq!(altgr.keysym.as_deref(), Some("ISO_Level3_Shift"));
    }

    #[test]
    fn declared_keys_without_a_bind_are_candidates_with_their_evidence() {
        let (_sys, keyboards) = victus();
        let keymap = parse(LATAM_EXCERPT);
        let keys = classify(&keyboards[0], Some(&keymap), Some(&[]), &BTreeSet::new());
        let calc = key(&keys, 140);
        assert!(calc.has(State::Candidate) && !calc.has(State::Verified));
        assert_eq!(
            (calc.confidence, calc.keysym.as_deref()),
            (Confidence::Model, Some("XF86Calculator")),
            "HP hwdb maps a1=calc"
        );
        let mail = key(&keys, 155);
        assert!(mail.has(State::Candidate));
        assert_eq!(mail.confidence, Confidence::Declared, "atkbd declares KEY_MAIL on every laptop");
    }

    #[test]
    fn verification_is_recorded_alongside_other_states() {
        let (_sys, keyboards) = victus();
        let keymap = parse(LATAM_EXCERPT);
        let binds = [bind(0, "XF86Launch2", "")];
        let verified = BTreeSet::from([149]);
        let keys = classify(&keyboards[1], Some(&keymap), Some(&binds), &verified);
        let omen = key(&keys, 149);
        assert_eq!(omen.label, "OMEN");
        assert_eq!(omen.states, vec![State::Declared, State::Verified, State::Assigned]);
        assert_eq!(omen.confidence, Confidence::Verified);
    }

    #[test]
    fn fn_esc_is_never_offered() {
        let (_sys, keyboards) = victus();
        let keymap = parse(LATAM_EXCERPT);
        let keys = classify(&keyboards[1], Some(&keymap), Some(&[]), &BTreeSet::new());
        let fn_esc = key(&keys, 0x1d1);
        assert!(fn_esc.has(State::Reserved) && fn_esc.has(State::Unknown) && !fn_esc.has(State::Candidate));
        assert_eq!(fn_esc.keysym.as_deref(), Some("XF86Fn_Esc"));
    }

    #[test]
    fn copilot_and_f13_under_latam() {
        let (_sys, keyboards) = victus();
        let keymap = parse(LATAM_EXCERPT);
        let binds = [bind(65, "F23", "")];
        let keys = classify(&keyboards[0], Some(&keymap), Some(&binds), &BTreeSet::new());
        let copilot = key(&keys, 193);
        assert_eq!(copilot.label, "Copilot");
        assert!(copilot.has(State::Assigned) && copilot.has(State::Reserved) && !copilot.has(State::Candidate));
        assert_eq!(copilot.assignments[0].chord, "SUPER + SHIFT + F23");
    }

    #[test]
    fn a_bound_media_key_is_assigned_not_free() {
        let mut sys = FakeSys::new();
        usb_keyboard(&mut sys, "1-2", "USB Keyboard");
        let keyboards = scan(sys.path(), &sys.udev_data(), None).keyboards;
        let mut keymap = parse(LATAM_EXCERPT);
        keymap.levels.insert(164, vec!["XF86AudioPlay".into()]);
        keymap.levels.insert(163, vec!["XF86AudioNext".into()]);
        let binds = [bind(0, "XF86AudioPlay", "")];
        let keys = classify(&keyboards[0], Some(&keymap), Some(&binds), &BTreeSet::new());
        assert!(key(&keys, 164).has(State::Assigned) && !key(&keys, 164).has(State::Candidate));
        assert!(key(&keys, 163).has(State::Candidate));
        assert_eq!(key(&keys, 164).declared_by, vec!["SEMICO USB Keyboard Consumer Control"]);
    }

    #[test]
    fn f20_producing_the_mic_mute_keysym_is_reserved() {
        let (_sys, keyboards) = victus();
        let mut keymap = parse(LATAM_EXCERPT);
        keymap.levels.insert(190, vec!["XF86AudioMicMute".into()]);
        let keys = classify(&keyboards[0], Some(&keymap), Some(&[]), &BTreeSet::new());
        let f20 = key(&keys, 190);
        assert!(f20.has(State::Reserved) && !f20.has(State::Candidate), "{:?}", f20.states);
    }

    #[test]
    fn unbound_copilot_f23_is_still_not_offered() {
        let (_sys, keyboards) = victus();
        let keys = classify(&keyboards[0], Some(&parse(LATAM_EXCERPT)), Some(&[]), &BTreeSet::new());
        let copilot = key(&keys, KEY_F23);
        assert!(copilot.has(State::Reserved) && !copilot.has(State::Candidate), "{:?}", copilot.states);
    }

    #[test]
    fn without_a_keymap_nothing_is_a_candidate() {
        let (_sys, keyboards) = victus();
        let keys = classify(&keyboards[0], None, None, &BTreeSet::new());
        assert!(keys.iter().all(|k| !k.has(State::Candidate)));
        assert!(key(&keys, 140).has(State::Unknown));
    }

    #[test]
    fn keycode_binds_count_as_assignments() {
        let (_sys, keyboards) = victus();
        let keymap = parse(LATAM_EXCERPT);
        // XKB keycode 148 is Linux KEY_CALC (140) + 8.
        let binds = [hypr::Bind { keycode: 148, ..Default::default() }];
        let keys = classify(&keyboards[0], Some(&keymap), Some(&binds), &BTreeSet::new());
        assert!(key(&keys, 140).has(State::Assigned), "code:148 is KEY_CALC");
    }
}
