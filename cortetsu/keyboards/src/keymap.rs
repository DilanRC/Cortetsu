//! Keysyms for Linux key codes under a device's effective XKB layout.
//!
//! `xkbcli compile-keymap` (libxkbcommon) prints the keymap Hyprland would
//! compile for the same layout, variant, options and model. Its text is parsed
//! for the keycode names and each key's first-group levels. Linux code N is
//! XKB keycode N + 8. Without xkbcli the keys keep their Linux names and no
//! keysym, which the caller reports as lower confidence.

use crate::inventory::Layout;
use std::collections::BTreeMap;
use std::time::Duration;

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Keymap {
    /// Linux code -> keysyms by shift level (level 1 first).
    pub levels: BTreeMap<u16, Vec<String>>,
}

pub fn compile(layout: &Layout) -> Option<Keymap> {
    let mut args = vec!["compile-keymap"];
    for (flag, value) in [
        ("--layout", &layout.layout),
        ("--variant", &layout.variant),
        ("--options", &layout.options),
        ("--model", &layout.model),
    ] {
        if !value.is_empty() {
            args.extend([flag, value.as_str()]);
        }
    }
    let text = crate::run(&crate::env_or("CORTETSU_XKBCLI", "xkbcli"), &args, Duration::from_secs(5))?;
    let keymap = parse(&text);
    (!keymap.levels.is_empty()).then_some(keymap)
}

fn name_between(text: &str) -> Option<&str> {
    let start = text.find('<')? + 1;
    let end = start + text[start..].find('>')?;
    Some(&text[start..end])
}

pub fn parse(text: &str) -> Keymap {
    let mut codes: BTreeMap<String, u32> = BTreeMap::new();
    let mut aliases: Vec<(String, String)> = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("alias ") {
            if let (Some(alias), Some((_, target))) = (name_between(rest), rest.split_once('='))
                && let Some(target) = name_between(target)
            {
                aliases.push((alias.to_owned(), target.to_owned()));
            }
        } else if line.starts_with('<')
            && let (Some(name), Some((_, value))) = (name_between(line), line.split_once('='))
            && let Ok(code) = value.trim().trim_end_matches(';').trim().parse()
        {
            codes.insert(name.to_owned(), code);
        }
    }
    for (alias, target) in aliases {
        if let Some(&code) = codes.get(&target) {
            codes.entry(alias).or_insert(code);
        }
    }

    let mut levels = BTreeMap::new();
    let mut rest = text;
    while let Some(start) = rest.find("key <") {
        let block_start = &rest[start..];
        let Some(end) = block_start.find("};") else { break };
        let block = &block_start[..end];
        rest = &block_start[end + 2..];
        let Some(name) = name_between(block) else { continue };
        let Some(&xkb_code) = codes.get(name) else { continue };
        let Some(linux) = xkb_code.checked_sub(8).and_then(|c| u16::try_from(c).ok()) else { continue };
        // An explicit first group wins over any other bracket in the block.
        let body = ["symbols[1]", "symbols[Group1]"]
            .iter()
            .find_map(|marker| block.find(marker).map(|at| &block[at..]))
            .unwrap_or(block);
        let (Some(open), Some(close)) = (body.find('['), body.find(']')) else { continue };
        let body = if body.starts_with("symbols[") {
            // Skip the index bracket of `symbols[1]= [ … ]`.
            let after = &body[close + 1..];
            match (after.find('['), after.find(']')) {
                (Some(o), Some(c)) if o < c => &after[o + 1..c],
                _ => continue,
            }
        } else if open < close {
            &body[open + 1..close]
        } else {
            continue;
        };
        let syms: Vec<String> = body.split(',').map(|s| s.trim().to_owned()).filter(|s| !s.is_empty()).collect();
        if !syms.is_empty() {
            levels.insert(linux, syms);
        }
    }
    Keymap { levels }
}

#[cfg(test)]
pub const LATAM_EXCERPT: &str = r#"xkb_keymap {
xkb_keycodes "(unnamed)" {
	minimum = 8;
	maximum = 708;
	<ESC>                = 9;
	<AE01>               = 10;
	<AE02>               = 11;
	<AD01>               = 24;
	<AC01>               = 38;
	<AC10>               = 47;
	<LFSH>               = 50;
	<RTRN>               = 36;
	<RALT>               = 108;
	<LWIN>               = 133;
	<I148>               = 148;
	<I157>               = 157;
	<I163>               = 163;
	<FK13>               = 191;
	<FK23>               = 201;
	<I473>               = 473;
	alias <I201>         = <FK23>;
};
xkb_symbols "(unnamed)" {
	key <ESC>                {	[          Escape ] };
	key <AE01>               {	[               1,          exclam,             bar,      exclamdown ] };
	key <AE02>               {	[               2,        quotedbl,              at,       oneeighth ] };
	key <AD01>               {	[               q,               Q,              at,     Greek_OMEGA ] };
	key <AC01>               {	[               a,               A,              ae,              AE ] };
	key <AC10>               {	[          ntilde,          Ntilde,      asciitilde, dead_doubleacute ] };
	key <LFSH>               {	[         Shift_L ] };
	key <RTRN>               {	[          Return ] };
	key <RALT>               {
		type= "ONE_LEVEL",
		symbols[1]= [ ISO_Level3_Shift ]
	};
	key <LWIN>               {	[         Super_L ] };
	key <I148>               {	[  XF86Calculator ] };
	key <I157>               {	[     XF86Launch2 ] };
	key <I163>               {	[        XF86Mail ] };
	key <FK13>               {	[       XF86Tools ] };
	key <FK23>               {
		type= "PC_SHIFT_SUPER_LEVEL2",
		symbols[1]= [             F23,   XF86Assistant ]
	};
	key <I473>               {	[      XF86Fn_Esc ] };
};
};
"#;

#[cfg(test)]
mod tests {
    use super::*;

    impl Keymap {
        fn keysym(&self, code: u16) -> Option<&str> {
            self.levels.get(&code).and_then(|l| l.first()).map(String::as_str)
        }
    }

    #[test]
    fn latam_levels_and_altgr() {
        let keymap = parse(LATAM_EXCERPT);
        assert_eq!(keymap.keysym(2), Some("1"));
        assert_eq!(keymap.levels[&3], vec!["2", "quotedbl", "at", "oneeighth"], "AltGr+2 types @");
        assert_eq!(keymap.keysym(100), Some("ISO_Level3_Shift"), "right Alt is AltGr in latam");
        assert_eq!(keymap.keysym(39), Some("ntilde"));
    }

    #[test]
    fn hardware_keys_map_to_their_keysyms() {
        let keymap = parse(LATAM_EXCERPT);
        assert_eq!(keymap.keysym(140), Some("XF86Calculator"), "KEY_CALC");
        assert_eq!(keymap.keysym(149), Some("XF86Launch2"), "KEY_PROG2 is OMEN");
        assert_eq!(keymap.keysym(183), Some("XF86Tools"), "KEY_F13 is not F13 under evdev rules");
        assert_eq!(keymap.levels[&193], vec!["F23", "XF86Assistant"]);
        assert_eq!(keymap.keysym(465), Some("XF86Fn_Esc"), "codes above 255 resolve too");
    }

    #[test]
    fn real_xkbcli_agrees() {
        let layout = Layout { layout: "latam".into(), ..Default::default() };
        // CI installs xkbcli (libxkbcommon-tools); a missing tool fails here
        // instead of passing silently.
        let keymap = compile(&layout).expect("xkbcli compile-keymap --layout latam");
        assert_eq!(keymap.keysym(140), Some("XF86Calculator"));
        assert_eq!(keymap.keysym(149), Some("XF86Launch2"));
        assert_eq!(keymap.levels[&3][2], "at");
    }
}
