//! Mutable projections of the same resolved roles consumed by the shell.
use crate::common::*;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{fs, os::unix::fs::PermissionsExt, path::Path};

pub fn effective(saved: &Value) -> Result<Value> {
    let id = saved["themeId"].as_str().unwrap_or("ink");
    if !["ink", "washi", "kurogane"].contains(&id) {
        return Err("invalid saved theme identity".into());
    }
    let palettes: Value = serde_json::from_str(include_str!("../../theme/ThemePalettes.json"))?;
    let mut colours = palettes.get(id).unwrap_or(&palettes["ink"]).clone();
    // Explicit selections override theme defaults. Invalid colours never reach a file.
    for (role, value) in saved["colours"].as_object().into_iter().flatten() {
        hex(value)?;
        colours[role] = value.clone();
    }
    for value in colours.as_object().ok_or("invalid palette")?.values() {
        hex(value)?;
    }
    // Resolve text contrast once so native consumers and QML receive the same
    // adjusted roles. The small margin prevents rounding across QML's 4.5 gate.
    let surfaces = [
        rgb(&colours["surface"])?,
        rgb(&colours["surfaceContainerHigh"])?,
    ];
    for role in ["onSurface", "onSurfaceVariant"] {
        let from = rgb(&colours[role])?;
        let target = if surfaces.iter().all(|c| luminance(*c) < 0.18) {
            1.0
        } else {
            0.0
        };
        for step in 0..=20 {
            let t = step as f64 / 20.0;
            let mixed = from.map(|c| ((c + (target - c) * t) * 255.0).round() / 255.0);
            if surfaces.iter().all(|s| contrast(mixed, *s) >= 4.55) || step == 20 {
                colours[role] = json!(format!(
                    "#{:02X}{:02X}{:02X}",
                    (mixed[0] * 255.0) as u8,
                    (mixed[1] * 255.0) as u8,
                    (mixed[2] * 255.0) as u8
                ));
                break;
            }
        }
    }
    let fallback_mode = if light_palette(&colours)? {
        "light"
    } else {
        "dark"
    };
    Ok(
        json!({"themeId":id,"colours":colours,"mode":saved["mode"].as_str().unwrap_or(fallback_mode),"version":1}),
    )
}
fn rgb(colour: &Value) -> Result<[f64; 3]> {
    let hex = hex(colour)?;
    let channel = |i| u8::from_str_radix(&hex[i..i + 2], 16).map(|c| c as f64 / 255.0);
    Ok([channel(1)?, channel(3)?, channel(5)?])
}
fn luminance(c: [f64; 3]) -> f64 {
    let linear = c.map(|v| {
        if v <= 0.03928 {
            v / 12.92
        } else {
            ((v + 0.055) / 1.055).powf(2.4)
        }
    });
    linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
}
fn contrast(a: [f64; 3], b: [f64; 3]) -> f64 {
    let (a, b) = (luminance(a), luminance(b));
    (a.max(b) + 0.05) / (a.min(b) + 0.05)
}

pub fn hex(value: &Value) -> Result<String> {
    let value = value.as_str().ok_or("missing colour")?;
    let value = value.strip_prefix('#').unwrap_or(value);
    if value.len() != 6 || !value.bytes().all(|c| c.is_ascii_hexdigit()) {
        return Err("invalid colour".into());
    }
    Ok(format!("#{}", value.to_uppercase()))
}

fn write_changed(path: &Path, text: &str) -> Result<()> {
    if path.is_symlink() {
        return Err(format!("refusing projection symlink: {}", path.display()).into());
    }
    if fs::read_to_string(path).ok().as_deref() == Some(text) {
        return Ok(());
    }
    let mode = fs::metadata(path)
        .map(|m| m.permissions().mode() & 0o777)
        .unwrap_or(0o644);
    atomic(path, text.as_bytes(), mode)?;
    Ok(())
}

pub(crate) fn project_file(name: &str, path: &Path, text: &str) -> Result<()> {
    // The legacy Kitty overlay explicitly replaces stale generation symlinks.
    // Never read or write through one, including when saving the baseline.
    if name == "kitty" && path.is_symlink() {
        let backup = state().join("theme-backups").join(name);
        if !backup.exists() {
            atomic(&backup, b"", 0o600)?;
        }
        atomic(path, text.as_bytes(), 0o644)?;
        return write_changed(&backup.with_extension("last"), text);
    }
    if path.is_symlink() {
        return Err(format!("refusing projection symlink: {}", path.display()).into());
    }
    let backup = state().join("theme-backups").join(name);
    if !backup.exists() {
        let previous = match fs::read(path) {
            Ok(v) => v,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Vec::new(),
            Err(e) => return Err(e.into()),
        };
        atomic(&backup, &previous, 0o600)?;
    }
    write_changed(path, text)?;
    write_changed(&backup.with_extension("last"), text)
}

fn restore_file(name: &str, path: &Path) -> Result<()> {
    let backup = state().join("theme-backups").join(name);
    if !backup.exists() {
        return Ok(());
    }
    let previous = fs::read_to_string(&backup)?;
    let current = fs::read(path)?;
    if current == previous.as_bytes() {
        return Ok(());
    }
    let last = fs::read(backup.with_extension("last"))?;
    if current != last {
        return Err(format!(
            "{} changed outside Cortetsu; restoration refused",
            path.display()
        )
        .into());
    }
    write_changed(path, &previous)
}

fn restore(target: &str) -> Result<()> {
    match target {
        "kitty" => restore_file("kitty", &state().join("kitty-colors.conf")),
        "gtk" => {
            restore_file("gtk", &state().join("gtk-colors.css"))?;
            crate::toolkit_settings::restore()
        }
        "hyprland" => {
            let path = config().join("hypr/scheme/current.lua");
            let before = fs::read(&path).ok();
            restore_file("hyprland", &path)?;
            let prior = json_load(&state().join("theme-sync.json"), json!({}));
            if (before != fs::read(&path).ok() || prior["targets"]["hyprland"]["status"] == "error")
                && std::env::var_os("CORTETSU_SKIP_RELOAD").is_none()
                && which("hyprctl").is_some()
            {
                reload_hyprland()?;
            }
            Ok(())
        }
        "qt" => {
            let qt_config = config().join("qtengine/config.json");
            let qt_backup = state().join("theme-backups/qtengine.json");
            if qt_backup.is_file() && qt_config.is_file() {
                let previous: Value = serde_json::from_slice(&fs::read(qt_backup)?)?;
                let mut current: Value = serde_json::from_slice(&fs::read(&qt_config)?)?;
                if current["theme"]["colorScheme"]
                    .as_str()
                    .is_some_and(|p| p.ends_with("/color-schemes/CortetsuLive.colors"))
                {
                    current["theme"]["colorScheme"] = previous["theme"]["colorScheme"].clone();
                    write_changed(
                        &qt_config,
                        &(serde_json::to_string_pretty(&current)? + "\n"),
                    )?;
                }
            }
            let path = config().join("kdeglobals");
            let backup = state().join("theme-backups/kdeglobals");
            if !backup.exists() {
                return Ok(());
            }
            let current = fs::read_to_string(&path)?;
            if ini_value(&current, "General", "ColorScheme").as_deref() == Some("CortetsuLive") {
                let previous = fs::read_to_string(backup)?;
                let scheme = ini_value(&previous, "General", "ColorScheme")
                    .ok_or("backup has no KDE palette")?;
                write_changed(&path, &ini_set(&current, "General", "ColorScheme", &scheme))?;
            }
            Ok(())
        }
        _ => Err("unknown theme integration".into()),
    }
}

fn gtk(colours: &Value, mode: &str) -> Result<Value> {
    let roles = [
        ("accent_color", "primary"),
        ("accent_bg_color", "primary"),
        ("accent_fg_color", "onPrimary"),
        ("window_bg_color", "background"),
        ("window_fg_color", "onSurface"),
        ("headerbar_bg_color", "surfaceContainerHigh"),
        ("headerbar_fg_color", "onSurface"),
        ("popover_bg_color", "surfaceContainer"),
        ("popover_fg_color", "onSurface"),
        ("view_bg_color", "surface"),
        ("view_fg_color", "onSurface"),
        ("card_bg_color", "surfaceContainer"),
        ("card_fg_color", "onSurface"),
        ("theme_bg_color", "background"),
        ("theme_fg_color", "onSurface"),
        ("theme_base_color", "surface"),
        ("theme_text_color", "onSurface"),
        ("theme_selected_bg_color", "primary"),
        ("theme_selected_fg_color", "onPrimary"),
        ("insensitive_fg_color", "onSurfaceVariant"),
    ];
    let mut text = "/* Cortetsu live palette. */\n".to_owned();
    for (name, role) in roles {
        text += &format!("@define-color {name} {};\n", hex(&colours[role])?);
    }
    let path = state().join("gtk-colors.css");
    let marker = path
        .to_string_lossy()
        .bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b"/-._~".contains(&b) {
                (b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect::<String>();
    let supported = ["gtk-3.0", "gtk-4.0"].iter().any(|version| {
        fs::read_to_string(config().join(version).join("cortetsu-colors.css"))
            .is_ok_and(|s| s.contains(&marker))
    });
    if !supported {
        return Ok(
            json!({"status":"unavailable","detail":"Install a generation with the mutable GTK palette import"}),
        );
    }
    project_file("gtk", &path, &text)?;
    let desktop = crate::toolkit_settings::apply(mode, &colours["primary"])?;
    Ok(
        json!({"status":"reopen","detail":"GTK symbolic colours; libadwaita follows supported desktop mode and nearest named accent","desktop":desktop}),
    )
}

fn kde(colours: &Value) -> Result<Value> {
    let globals = config().join("kdeglobals");
    if globals.is_symlink() {
        return Err("kdeglobals must be an editable regular file; run theme adopt".into());
    }
    let original = fs::read_to_string(&globals).unwrap_or_default();
    let current = ini_value(&original, "General", "ColorScheme");
    let mut palette = "[General]\nName=CortetsuLive\n".to_owned();
    for section in [
        "Window",
        "View",
        "Button",
        "Selection",
        "Tooltip",
        "Complementary",
        "Header",
    ] {
        let (bg, fg) = if section == "Selection" {
            ("primary", "onPrimary")
        } else {
            ("surface", "onSurface")
        };
        palette += &format!("\n[Colors:{section}]\n");
        for (key, role) in [
            ("BackgroundNormal", bg),
            ("BackgroundAlternate", "surfaceContainer"),
            ("ForegroundNormal", fg),
            ("ForegroundInactive", "onSurfaceVariant"),
            ("DecorationFocus", "primary"),
            ("DecorationHover", "primary"),
            ("ForegroundLink", "primary"),
            ("ForegroundVisited", "secondary"),
        ] {
            let h = hex(&colours[role])?;
            let rgb = (0..3)
                .map(|i| u8::from_str_radix(&h[1 + i * 2..3 + i * 2], 16).map(|n| n.to_string()))
                .collect::<std::result::Result<Vec<_>, _>>()?;
            palette += &format!("{key}={}\n", rgb.join(","));
        }
    }
    let data = std::env::var_os("XDG_DATA_HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| home().join(".local/share"));
    write_changed(&data.join("color-schemes/CortetsuLive.colors"), &palette)?;
    if !matches!(current.as_deref(), Some("Cortetsu" | "CortetsuLive")) {
        return Ok(
            json!({"status":"unavailable","detail":"KDE palette selection is not owned by Cortetsu"}),
        );
    }
    let backup = state().join("theme-backups/kdeglobals");
    if !backup.exists() {
        atomic(&backup, original.as_bytes(), 0o600)?;
    }
    write_changed(
        &globals,
        &ini_set(&original, "General", "ColorScheme", "CortetsuLive"),
    )?;
    Ok(
        json!({"status":"reopen","detail":"KDE colour scheme; qt6ct custom_palette=false does not consume it"}),
    )
}

fn qt(colours: &Value) -> Result<Value> {
    let kde = kde(colours)?;
    let path = config().join("qtengine/config.json");
    if std::env::var("QT_QPA_PLATFORMTHEME").unwrap_or_default() != "qtengine" || !path.is_file() {
        return Ok(kde);
    }
    if path.is_symlink() {
        return Err("qtengine config is not an editable regular file".into());
    }
    let original = fs::read(&path)?;
    let mut settings: Value = serde_json::from_slice(&original)?;
    if !settings["theme"].is_object() {
        return Err("qtengine has no theme object".into());
    }
    let backup = state().join("theme-backups/qtengine.json");
    let previous = if backup.is_file() {
        Some(json_object(&backup)?)
    } else {
        None
    };
    if !backup.exists() {
        atomic(&backup, &original, 0o600)?;
    }
    let data = std::env::var_os("XDG_DATA_HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| home().join(".local/share"));
    let target = json!(data.join("color-schemes/CortetsuLive.colors"));
    if let Some(previous) = previous
        && settings["theme"]["colorScheme"] != target
        && settings["theme"]["colorScheme"] != previous["theme"]["colorScheme"]
    {
        return Ok(
            json!({"status":"unavailable","detail":"qtengine palette changed outside Cortetsu; preserved","kde":kde}),
        );
    }
    settings["theme"]["colorScheme"] = target;
    write_changed(&path, &(serde_json::to_string_pretty(&settings)? + "\n"))?;
    Ok(
        json!({"status":"reopen","detail":"qtengine and compatible KDE applications; reopen to confirm","kde":kde}),
    )
}

fn ini_value(text: &str, section: &str, key: &str) -> Option<String> {
    let mut active = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            active = line == format!("[{section}]");
        } else if active
            && let Some((k, v)) = line.split_once('=')
            && k.trim() == key
        {
            return Some(v.trim().to_owned());
        }
    }
    None
}

fn ini_set(text: &str, section: &str, key: &str, value: &str) -> String {
    let mut out = String::new();
    let mut active = false;
    let mut found = false;
    let mut entered = false;
    for line in text.lines() {
        if line.trim().starts_with('[') {
            if active && !found {
                out += &format!("{key}={value}\n");
                found = true;
            }
            active = line.trim() == format!("[{section}]");
            entered |= active;
        }
        if active && line.split_once('=').is_some_and(|(k, _)| k.trim() == key) {
            if !found {
                out += &format!("{key}={value}\n");
                found = true;
            }
        } else {
            out += line;
            out.push('\n');
        }
    }
    if !entered {
        out += &format!("[{section}]\n");
    }
    if !found {
        out += &format!("{key}={value}\n");
    }
    out
}

pub fn sync(saved: &Value) -> Result<Value> {
    let palette = effective(saved)?;
    let colours = &palette["colours"];
    let preferences = json_object(&config().join("cortetsu/preferences.json"))?;
    if preferences
        .get("themeIntegrations")
        .is_some_and(|v| !crate::theme_profile::valid_integrations(v))
    {
        return Err("invalid theme integration preferences; projections kept unchanged".into());
    }
    let mut targets = json!({});
    for target in ["hyprland", "kitty", "gtk", "qt"] {
        if preferences["themeIntegrations"][target] == false {
            targets[target] = restore(target)
                .map(|()| json!({"status":"disabled"}))
                .unwrap_or_else(|e| json!({"status":"error","detail":e.to_string()}));
            continue;
        }
        let result=match target {
            "hyprland" if !config().join("hypr/scheme/current.lua").is_file()=>Ok(json!({"status":"unavailable","detail":"No mutable Hyprland scheme installed"})),
            "hyprland"=>crate::palette::hypr_scheme(colours).map(|()|json!({"status":"applied"})),
            "kitty"=>crate::palette::sync_kitty(colours).map(|()|json!({"status":"reopen","detail":"New windows or Kitty reload (Ctrl+Shift+F5)"})),
            "gtk"=>gtk(colours,palette["mode"].as_str().unwrap_or("dark")),
            _=>qt(colours),
        };
        targets[target] =
            result.unwrap_or_else(|e| json!({"status":"error","detail":e.to_string()}));
    }
    let digest = format!("{:x}", Sha256::digest(serde_json::to_vec(&palette)?));
    for target in targets
        .as_object_mut()
        .ok_or("invalid projection status")?
        .values_mut()
    {
        target["version"] = json!(1);
        if matches!(target["status"].as_str(), Some("applied" | "reopen")) {
            target["paletteHash"] = json!(digest);
        }
    }
    let result =
        json!({"version":1,"themeId":palette["themeId"],"paletteHash":digest,"targets":targets});
    let encoded = serde_json::to_string_pretty(&result)? + "\n";
    write_changed(&state().join("theme-sync.json"), &encoded)?;
    Ok(result)
}

pub(crate) fn save_scheme(path: &Path, value: &mut Value) -> Result<()> {
    let effective = effective(value)?;
    value["themeId"] = effective["themeId"].clone();
    if value.get("name").is_none() {
        value["name"] = json!("dynamic");
    }
    if value.get("flavour").is_none() {
        value["flavour"] = json!("default");
    }
    if value.get("colours").is_none() {
        value["colours"] = json!({});
    }
    value["schema"] = json!(2);
    if value.get("origin").is_none() {
        value["origin"] = json!(if value["name"] == "dynamic" {
            "wallpaper"
        } else {
            "manual"
        });
    }
    value["effectiveColours"] = effective["colours"].clone();
    value["mode"] = effective["mode"].clone();
    json_save(path, value)
}
pub(crate) fn sync_projections(path: &Path) -> Result<Value> {
    let _projection_guard = lock(&path.with_file_name("theme-projections.lock"), false)?;
    let guard = lock(&path.with_file_name("scheme.lock"), false)?;
    let current = json_object(path)?;
    drop(guard);
    match sync(&current) {
        Ok(result) => Ok(result),
        Err(error) => {
            let mut targets = json!({});
            for target in ["state", "hyprland", "kitty", "gtk", "qt"] {
                targets[target] = json!({"status":"error","detail":error.to_string()});
            }
            let result = json!({"version":1,"targets":targets});
            let _ = write_changed(
                &state().join("theme-sync.json"),
                &(serde_json::to_string_pretty(&result)? + "\n"),
            );
            Ok(result)
        }
    }
}
pub(crate) fn reload_hyprland() -> Result<()> {
    let result = call("hyprctl", &["reload", "config-only"], 15)?;
    if !result.status.success() {
        return Err("Hyprland rejected config-only reload".into());
    }
    Ok(())
}
pub(crate) fn light_palette(colours: &Value) -> Result<bool> {
    let value = hex(&colours["surface"])?;
    let channel = |i| u8::from_str_radix(&value[i..i + 2], 16).map(|v| v as f64 / 255.0);
    Ok(0.2126 * channel(1)? + 0.7152 * channel(3)? + 0.0722 * channel(5)? > 0.5)
}
pub(crate) fn projection_error(projections: &Value) -> Option<String> {
    let errors = projections["targets"]
        .as_object()?
        .iter()
        .filter(|(_, v)| v["status"] == "error")
        .map(|(name, v)| format!("{name}: {}", text(&v["detail"])))
        .collect::<Vec<_>>();
    (!errors.is_empty()).then(|| errors.join("; "))
}

pub fn command(args: &[String]) -> Option<Result<i32>> {
    let a = args.iter().map(String::as_str).collect::<Vec<_>>();
    if !matches!(
        a.first(),
        Some(&"effective" | &"preview-theme" | &"preview-scheme" | &"source" | &"reset-theme")
    ) {
        return None;
    }
    Some((|| {
        let path = state().join("scheme.json");
        let s = json_object(&path)?;
        match a.as_slice() {
            ["preview-scheme", name, flavour] => {
                let catalogue = crate::palette::catalog()?;
                let colours = &catalogue[*name][*flavour];
                if !colours.is_object() {
                    return Err("scheme not found".into());
                }
                let mut preview = s.clone();
                preview["colours"] = colours.clone();
                preview["mode"] = json!(if light_palette(colours)? {
                    "light"
                } else {
                    "dark"
                });
                emit(&effective(&preview)?)?;
            }
            ["reset-theme"] => {
                let guard = lock(&path.with_file_name("scheme.lock"), false)?;
                let previous = json_object(&path)?;
                let id = previous["themeId"].as_str().unwrap_or("ink");
                if previous
                    .get("themeProfiles")
                    .is_some_and(|v| !v.is_object())
                {
                    return Err("invalid saved theme profiles".into());
                }
                let mut next = json!({"schema":2,"themeId":id,"origin":"theme","name":id,"flavour":"default","variant":"tonal-spot","colours":{}});
                if let Some(archive) = previous.get("themeProfiles") {
                    next["themeProfiles"] = archive.clone();
                }
                let backup = state()
                    .join("theme-backups")
                    .join(format!("reset-{}.json", (now() * 1000.0) as u64));
                json_save(&backup, &previous)?;
                save_scheme(&path, &mut next)?;
                drop(guard);
                let result = sync_projections(&path)?;
                emit(
                    &json!({"committed":true,"reset":true,"backup":backup,"projectionError":projection_error(&result)}),
                )?;
            }
            ["effective"] => {
                emit(&effective(&s)?)?;
            }
            ["preview-theme", id] if ["ink", "washi", "kurogane"].contains(id) => {
                let mut preview = s["themeProfiles"][*id]
                    .as_object()
                    .map(|v| Value::Object(v.clone()))
                    .unwrap_or_else(|| json!({}));
                if s["themeId"] == *id {
                    preview = s.clone();
                }
                preview["themeId"] = json!(id);
                emit(&effective(&preview)?)?;
            }
            ["source", source] if ["auto", "manual"].contains(source) => {
                let _guard = lock(&path.with_file_name("scheme.lock"), false)?;
                let prefs_path = config().join("cortetsu/preferences.json");
                let _prefs_guard = lock(&prefs_path.with_extension("lock"), false)?;
                let previous_prefs = json_object(&prefs_path)?;
                let mut prefs = previous_prefs.clone();
                prefs["smartScheme"] = json!(*source == "auto");
                let mut current = json_object(&path)?;
                current["origin"] = json!(if *source == "auto" {
                    "wallpaper"
                } else {
                    "manual"
                });
                json_save(&prefs_path, &prefs)?;
                if let Err(error) = save_scheme(&path, &mut current) {
                    json_save(&prefs_path, &previous_prefs)?;
                    return Err(error);
                }
                emit(&json!({"committed":true,"smartScheme":*source=="auto","preferences":prefs}))?;
            }
            _ => return Err("invalid theme command".into()),
        }
        Ok(0)
    })())
}
