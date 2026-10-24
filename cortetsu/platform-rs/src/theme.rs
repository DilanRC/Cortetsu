use crate::util::*;
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
};
fn metadata() -> Value {
    serde_json::from_str(include_str!("../templates/theme-metadata.json")).expect("theme constants")
}
fn wall(data: &Value) -> Result<Value> {
    let mut out = json!({});
    for (name, pair) in metadata()["WALL_UTILITY_REFS"]
        .as_object()
        .ok_or("wall metadata")?
    {
        let section = pair[0].as_str().ok_or("wall section")?;
        let key = pair[1].as_str().ok_or("wall key")?;
        if data["wall_utility"][name] != format!("{section}.{key}")
            || data[section][key].as_i64().unwrap_or(0) <= 0
        {
            return fail(format!("invalid wall_utility.{name}"));
        }
        out[name] = data[section][key].clone();
    }
    Ok(out)
}
fn load(repo: &Path) -> Result<Value> {
    let v = toml_json(&repo.join("dotfiles/home/.config/cortetsu/ui.toml"))?;
    if v["schema"] != 1 {
        return fail("ui.toml schema must be 1");
    }
    let hex = regex::Regex::new(r"^#[0-9A-Fa-f]{6}$")?;
    for name in ["sumi", "tetsu", "washi", "indigo", "vermillion", "muted"] {
        if !v["palette"][name].as_str().is_some_and(|s| hex.is_match(s)) {
            return fail(format!("invalid palette.{name}"));
        }
    }
    for name in [
        "surface_high",
        "primary_container",
        "secondary",
        "secondary_container",
        "outline_variant",
        "scrim",
    ] {
        if !v["palette"]["semantic"][name]
            .as_str()
            .is_some_and(|s| hex.is_match(s))
        {
            return fail(format!("invalid palette.semantic.{name}"));
        }
    }
    for name in ["instant_ms", "fast_ms", "standard_ms", "deliberate_ms"] {
        if v["motion"][name].as_i64().unwrap_or(0) <= 0 {
            return fail(format!("invalid motion.{name}"));
        }
    }
    if v["motion"]["hover_scale"].as_f64().unwrap_or(0.0) <= 1.0 {
        return fail("invalid motion.hover_scale");
    }
    wall(&v)?;
    Ok(v)
}
fn rgb(s: &str) -> Result<[u8; 3]> {
    if s.len() != 7 || !s.starts_with('#') || !s[1..].bytes().all(|b| b.is_ascii_hexdigit()) {
        return fail("invalid colour");
    }
    Ok([
        u8::from_str_radix(&s[1..3], 16)?,
        u8::from_str_radix(&s[3..5], 16)?,
        u8::from_str_radix(&s[5..7], 16)?,
    ])
}
fn mix(a: &str, b: &str, amount: f64) -> Result<String> {
    let a = rgb(a)?;
    let b = rgb(b)?;
    let mut c = [0u8; 3];
    for i in 0..3 {
        c[i] = (f64::from(a[i]) + (f64::from(b[i]) - f64::from(a[i])) * amount)
            .round_ties_even()
            .clamp(0.0, 255.0) as u8;
    }
    Ok(format!("#{:02X}{:02X}{:02X}", c[0], c[1], c[2]))
}
fn derived(v: &Value) -> Result<BTreeMap<String, String>> {
    let p = &v["palette"];
    let mut c = BTreeMap::new();
    for name in ["sumi", "tetsu", "washi", "indigo", "vermillion", "muted"] {
        c.insert(
            name.into(),
            p[name].as_str().ok_or("missing palette")?.to_owned(),
        );
    }
    for (name, a, b, x) in [
        ("surface_alt", "sumi", "tetsu", 0.55),
        ("accent_soft", "vermillion", "washi", 0.24),
        ("link", "indigo", "washi", 0.38),
        ("positive", "indigo", "washi", 0.56),
        ("warning", "vermillion", "washi", 0.48),
        ("bright", "washi", "#FFFFFF", 0.58),
        ("dim", "muted", "sumi", 0.34),
        ("violet", "indigo", "vermillion", 0.46),
    ] {
        let right = if b.starts_with('#') { b } else { &c[b] };
        c.insert(name.into(), mix(&c[a], right, x)?);
    }
    Ok(c)
}
fn template(t: &str, v: &Value) -> Result<String> {
    let re = regex::Regex::new(r"\{\{([^}]+)\}\}")?;
    let mut out = String::new();
    let mut start = 0;
    for cap in re.captures_iter(t) {
        let m = cap.get(0).ok_or("template match")?;
        out += &t[start..m.start()];
        let mut value = v;
        for part in cap[1].split('.') {
            value = &value[part];
        }
        if value.is_null() {
            return fail(format!("missing template value {}", &cap[1]));
        }
        out += &value
            .as_str()
            .map(str::to_owned)
            .unwrap_or_else(|| value.to_string());
        start = m.end();
    }
    out += &t[start..];
    Ok(out)
}
fn outputs(repo: &Path, v: &Value) -> Result<Vec<(PathBuf, String)>> {
    let defaults = template(
        include_str!("../templates/design.js.template"),
        &json!({"p":v["palette"],"s":v["palette"]["semantic"],"shape":v["shape"],"spacing":v["spacing"],"density":v["density"],"motion":v["motion"],"wall_utility":wall(v)?}),
    )?;
    let meta = metadata();
    let mut singleton = include_str!("../templates/design-singleton.template").to_owned();
    singleton.push('\n');
    for line in defaults.lines() {
        if let Some(l) = line.strip_prefix("var ") {
            let (name, value) = l.split_once('=').ok_or("invalid design var")?;
            let name = name.trim();
            let value = value.trim();
            let (ty, expr) = if !name.starts_with("color") {
                ("real", format!("Defaults.{name}"))
            } else if let Some(role) = meta["SCHEME_ROLES"][name].as_str() {
                let read = format!("role(\"{role}\", Defaults.{name})");
                let text_role = meta["READABLE_TEXT_ROLES"]
                    .as_array()
                    .is_some_and(|roles| roles.iter().any(|r| r == name));
                if text_role {
                    ("color", format!("readable({read}, [colorTetsu, colorSurfaceHigh])"))
                } else {
                    ("color", read)
                }
            } else if value.starts_with('"') {
                ("color", format!("Defaults.{name}"))
            } else {
                ("color", value.to_owned())
            };
            singleton += &format!("    readonly property {ty} {name}: {expr}\n");
        }
    }
    singleton += "}\n";
    let c = derived(v)?;
    let mut kitty = Vec::new();
    for t in strings(&meta["kitty_prefix"]) {
        kitty.push(template(&t, &json!({"c":c}))?);
    }
    let mut ansi = vec![
        c["tetsu"].clone(),
        c["vermillion"].clone(),
        c["positive"].clone(),
        c["warning"].clone(),
        c["indigo"].clone(),
        c["violet"].clone(),
        c["link"].clone(),
        c["washi"].clone(),
        c["muted"].clone(),
        c["accent_soft"].clone(),
    ];
    for (a, x) in [
        ("positive", 0.28),
        ("warning", 0.28),
        ("indigo", 0.48),
        ("violet", 0.34),
        ("link", 0.38),
    ] {
        ansi.push(mix(&c[a], &c["washi"], x)?);
    }
    ansi.push(c["bright"].clone());
    for (i, colour) in ansi.iter().enumerate() {
        kitty.push(format!("color{i} {colour}"));
    }
    let mut gtk = vec!["/* Generated by Cortetsu from ui.toml. Do not edit by hand. */".to_owned()];
    for pair in meta["gtk"].as_array().ok_or("gtk mapping")? {
        gtk.push(format!(
            "@define-color {} {};",
            pair[0].as_str().unwrap_or_default(),
            c[pair[1].as_str().unwrap_or_default()]
        ));
    }
    for line in [
        "@define-color primary @accent_color;",
        "@define-color sidebar_bg_color @window_bg_color;",
        "@define-color sidebar_fg_color @window_fg_color;",
        "@define-color sidebar_border_color @card_bg_color;",
        "@define-color sidebar_backdrop_color @window_bg_color;",
    ] {
        gtk.push(line.into());
    }
    let csv = |s: &str| -> Result<String> {
        let c = rgb(s)?;
        Ok(format!("{},{},{}", c[0], c[1], c[2]))
    };
    let mut sections = vec!["[General]\nName=Cortetsu\n".into()];
    for (name, bg, alt) in [
        ("Button", "tetsu", "surface_alt"),
        ("Complementary", "sumi", "surface_alt"),
        ("Header", "tetsu", "sumi"),
        ("Selection", "vermillion", "accent_soft"),
        ("Tooltip", "tetsu", "surface_alt"),
        ("View", "sumi", "tetsu"),
        ("Window", "tetsu", "surface_alt"),
    ] {
        let mut section = format!("[Colors:{name}]\n");
        for (key, col) in [
            ("BackgroundAlternate", alt),
            ("BackgroundNormal", bg),
            ("DecorationFocus", "vermillion"),
            ("DecorationHover", "accent_soft"),
            ("ForegroundActive", "accent_soft"),
            ("ForegroundInactive", "muted"),
            ("ForegroundLink", "link"),
            ("ForegroundNegative", "vermillion"),
            ("ForegroundNeutral", "warning"),
            ("ForegroundNormal", "washi"),
            ("ForegroundPositive", "positive"),
            ("ForegroundVisited", "violet"),
        ] {
            section += &format!("{key}={}\n", csv(&c[col])?);
        }
        sections.push(section);
    }
    let mut wm = "[WM]\n".to_owned();
    for (key, col) in [
        ("activeBackground", "tetsu"),
        ("activeBlend", "vermillion"),
        ("activeForeground", "washi"),
        ("inactiveBackground", "sumi"),
        ("inactiveBlend", "muted"),
        ("inactiveForeground", "muted"),
    ] {
        wm += &format!("{key}={}\n", csv(&c[col])?);
    }
    sections.push(wm);
    let generated = repo.join("dotfiles/generated/theme/home");
    Ok(vec![
        (
            repo.join("cortetsu/theme/CortetsuDesignDefaults.js"),
            defaults,
        ),
        (repo.join("cortetsu/theme/CortetsuDesign.qml"), singleton),
        (
            generated.join(".config/kitty/cortetsu-theme.conf"),
            kitty.join("\n") + "\n",
        ),
        (
            generated.join(".config/gtk-3.0/cortetsu-colors.css"),
            gtk.join("\n") + "\n",
        ),
        (
            generated.join(".config/gtk-4.0/cortetsu-colors.css"),
            gtk.join("\n") + "\n",
        ),
        (
            generated.join(".local/share/color-schemes/Cortetsu.colors"),
            sections.join("\n"),
        ),
    ])
}
fn general_value(text: &str, key: &str, value: &str) -> Result<String> {
    let nl = if text.contains("\r\n") { "\r\n" } else { "\n" };
    let mut lines: Vec<String> = text.split_inclusive('\n').map(str::to_owned).collect();
    let mut start = None;
    let mut end = lines.len();
    let section = regex::Regex::new(r"^\s*\[([^]]+)\]")?;
    for (i, l) in lines.iter().enumerate() {
        if let Some(m) = section.captures(l) {
            if start.is_some() {
                end = i;
                break;
            }
            if m[1].eq_ignore_ascii_case("general") {
                start = Some(i);
            }
        }
    }
    let pat = regex::Regex::new(&format!(
        r"(?i)^(\s*{}\s*=)[^\r\n]*(\r?\n)?$",
        regex::escape(key)
    ))?;
    if let Some(s) = start {
        let mut found = false;
        for l in &mut lines[s + 1..end] {
            if let Some(m) = pat.captures(l) {
                *l = format!("{}{value}{}", &m[1], m.get(2).map_or("", |x| x.as_str()));
                found = true;
            }
        }
        if !found {
            lines.insert(s + 1, format!("{key}={value}{nl}"));
        }
    } else {
        if let Some(l) = lines.last_mut()
            && !l.ends_with(['\n', '\r'])
        {
            *l += nl;
        }
        lines.push(format!("[General]{nl}{key}={value}{nl}"));
    }
    Ok(lines.concat())
}
fn adopt() -> Result<()> {
    crate::install::check_mutation()?;
    let cfg = config_home()?;
    let root = data_root()?;
    let cli = cfg.join("caelestia/cli.json");
    let mut payload = if cli.is_file() {
        let mut v = json(&cli)?;
        if !v.is_object() {
            return fail("CLI config must contain a JSON object");
        }
        if v.get("theme").is_none() {
            v["theme"] = json!({});
        }
        if !v["theme"].is_object() {
            return fail("theme must be a JSON object");
        }
        Some(v)
    } else {
        None
    };
    let kde = cfg.join("kdeglobals");
    let backup = root
        .join("migrations")
        .join(unique())
        .join("theme-ownership");
    let mut resolved = None;
    let mut mode = 0o600;
    let original = if kde.is_symlink() {
        let target = fs::canonicalize(&kde)?;
        if !target.starts_with(fs::canonicalize(root.join("dotfiles/builds"))?) || !target.is_file()
        {
            return fail("refusing to replace external kdeglobals symlink");
        }
        mode = fs::metadata(&target)?.permissions().mode();
        let t = fs::read_to_string(&target)?;
        resolved = Some(target);
        t
    } else if kde.exists() {
        if !kde.is_file() {
            return fail("kdeglobals is not a regular file");
        }
        mode = fs::metadata(&kde)?.permissions().mode();
        fs::read_to_string(&kde)?
    } else {
        "[General]\nColorScheme=Cortetsu\n\n[KDE]\ncontrast=4\n".into()
    };
    let updated = general_value(&original, "ColorScheme", "Cortetsu")?;
    if resolved.is_some() || !kde.exists() || updated != original {
        if kde.exists() {
            copy_path(
                resolved.as_deref().unwrap_or(&kde),
                &backup.join("kdeglobals"),
            )?;
        }
        atomic_write(&kde, updated, mode)?;
        println!(
            "Cortetsu theme ownership: KDE palette is editable at {}",
            kde.display()
        );
    }
    if let Some(v) = payload.as_mut() {
        let keys = ["enableTerm", "enableHypr", "enableGtk", "enableQt"];
        if keys.iter().any(|k| v["theme"][k] != false) {
            copy_path(&cli, &backup.join("cli.json"))?;
            for k in keys {
                v["theme"][k] = json!(false);
            }
            let mut text = serde_json::to_string_pretty(v)?;
            text.push('\n');
            atomic_write(&cli, text, fs::metadata(&cli)?.permissions().mode())?;
            println!(
                "Cortetsu theme ownership: disabled Caelestia mutations for terminal/Hyprland/GTK/Qt"
            );
        } else {
            println!("Cortetsu theme ownership: already native for terminal/Hyprland/GTK/Qt");
        }
    } else {
        println!(
            "Cortetsu theme ownership: no Caelestia CLI config at {}; nothing to disable",
            cli.display()
        );
    }
    if backup.exists() {
        println!("BACKUP theme-ownership={}", backup.display());
    }
    Ok(())
}
pub fn run(a: &Args) -> Result<i32> {
    a.check(&["repo"])?;
    let action = a.action("check");
    if action == "adopt" {
        adopt()?;
        return Ok(0);
    }
    let repo = a.repo()?;
    let output = outputs(&repo, &load(&repo)?)?;
    match action.as_str() {
        "compile" => {
            for (p, t) in output {
                atomic_write(&p, t, 0o644)?;
                println!("GENERATED {}", p.strip_prefix(&repo)?.display());
            }
        }
        "check" => {
            let mut stale = false;
            for (p, t) in output {
                if fs::read_to_string(&p).ok().as_ref() != Some(&t) {
                    eprintln!("STALE {}", p.strip_prefix(&repo)?.display());
                    stale = true;
                }
            }
            if stale {
                return Ok(1);
            }
            println!("PASS: Cortetsu native theme outputs match ui.toml");
        }
        _ => return fail("unknown theme action"),
    };
    Ok(0)
}
