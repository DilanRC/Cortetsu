//! Portable visual preferences only; imports cannot replace command preferences.
use crate::common::*;
use serde_json::{Value, json};
use std::{
    fs,
    io::{Read, Write},
    os::unix::fs::OpenOptionsExt,
    path::Path,
};

const KEYS: &[&str] = &[
    "themeId",
    "themePreferences",
    "transparencyEnabled",
    "reducedMotion",
    "smartScheme",
    "themeIntegrations",
    "borderThickness",
];

pub fn run(args: &[String]) -> Result<i32> {
    let [action, filename] = args else {
        return Err("usage: profile export|import /absolute/file.json".into());
    };
    let file = Path::new(filename);
    if !file.is_absolute() || file.is_symlink() {
        return Err("profile path must be absolute and not a symlink".into());
    }
    if action == "export"
        && let Some(parent) = file.parent().and_then(|p| p.canonicalize().ok())
        && parent
            .ancestors()
            .any(|p| p.join("BUILD_ID").is_file() || p.join("MANIFEST.json").is_file())
    {
        return Err("profiles cannot be written inside sealed generations".into());
    }
    let scheme = state().join("scheme.json");
    let preferences = config().join("cortetsu/preferences.json");
    let _guard = lock(&scheme.with_file_name("scheme.lock"), false)?;
    let mut current = json_object(&scheme)?;
    let mut prefs = json_object(&preferences)?;
    let defaults: Value = serde_json::from_str(include_str!(
        "../../platform-rs/templates/preferences-defaults.json"
    ))?;
    match action.as_str() {
        "export" => {
            let theme = current["themeId"].as_str().unwrap_or("ink").to_owned();
            for (key, default) in [
                ("schema", json!(2)),
                ("themeId", json!(theme)),
                ("origin", json!("theme")),
                ("name", json!(theme)),
                ("flavour", json!("default")),
                ("colours", json!({})),
            ] {
                if current.get(key).is_none() {
                    current[key] = default;
                }
            }
            let mut visual = json!({});
            for key in KEYS {
                visual[*key] = prefs.get(*key).unwrap_or(&defaults[*key]).clone();
            }
            let mut integrations = defaults["themeIntegrations"].clone();
            for (key, value) in visual["themeIntegrations"]
                .as_object()
                .into_iter()
                .flatten()
            {
                integrations[key] = value.clone();
            }
            visual["themeIntegrations"] = integrations;
            let payload = json!({"schema":1,"scheme":current,"preferences":visual});
            let mut output = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(file)?;
            output.write_all(&(serde_json::to_string_pretty(&payload)? + "\n").into_bytes())?;
            output.sync_all()?;
            emit(&json!({"committed":true,"path":filename}))?;
        }
        "import" => {
            if !fs::metadata(file)?.is_file() || fs::metadata(file)?.len() > 1024 * 1024 {
                return Err("visual profile exceeds 1 MiB".into());
            }
            let mut bytes = Vec::new();
            fs::File::open(file)?
                .take(1024 * 1024 + 1)
                .read_to_end(&mut bytes)?;
            if bytes.len() > 1024 * 1024 {
                return Err("visual profile exceeds 1 MiB".into());
            }
            let imported: Value = serde_json::from_slice(&bytes)?;
            if imported["schema"] != 1 {
                return Err("unsupported visual profile schema".into());
            }
            let mut next = imported["scheme"].clone();
            validate_saved_theme_scheme(&next)?;
            if !["ink", "washi", "kurogane"].contains(&next["themeId"].as_str().unwrap_or("ink")) {
                return Err("invalid profile theme".into());
            }
            if next.get("themeProfiles").is_some_and(|v| !v.is_object()) {
                return Err("invalid saved theme profiles".into());
            }
            if next["themeProfiles"].as_object().is_some_and(|m| {
                m.keys()
                    .any(|k| !["ink", "washi", "kurogane"].contains(&k.as_str()))
            }) {
                return Err("unknown archived theme".into());
            }
            for profile in next["themeProfiles"]
                .as_object()
                .into_iter()
                .flatten()
                .map(|(_, v)| v)
            {
                validate_saved_theme_scheme(profile)?;
            }
            let effective = crate::theme_sync::effective(&next)?;
            next["effectiveColours"] = effective["colours"].clone();
            next["mode"] = effective["mode"].clone();
            let visual = imported["preferences"]
                .as_object()
                .ok_or("missing visual preferences")?;
            for key in KEYS {
                if let Some(value) = visual.get(*key) {
                    let valid = match *key {
                        "themeId" => {
                            ["ink", "washi", "kurogane"].contains(&value.as_str().unwrap_or(""))
                        }
                        "themePreferences" => valid_preferences(value),
                        "themeIntegrations" => valid_integrations(value),
                        "borderThickness" => value.as_i64().is_some_and(|n| (0..=20).contains(&n)),
                        _ => value.is_boolean(),
                    };
                    if !valid {
                        return Err(format!("invalid visual preference {key}").into());
                    }
                    if *key == "themeIntegrations" {
                        let mut merged = defaults["themeIntegrations"].clone();
                        for current in [prefs.get(*key), Some(value)].into_iter().flatten() {
                            if !valid_integrations(current) {
                                return Err("invalid integration preferences".into());
                            }
                            for (key, value) in current.as_object().ok_or("invalid integrations")? {
                                merged[key] = value.clone();
                            }
                        }
                        prefs[*key] = merged;
                    } else {
                        prefs[*key] = value.clone();
                    }
                }
            }
            // The native scheme commit is the authority after an interrupted import.
            prefs["themeId"] = effective["themeId"].clone();
            let backup = state()
                .join("theme-backups")
                .join(format!("import-{}", (now() * 1000.0) as u64));
            json_save(&backup.join("scheme.json"), &current)?;
            json_save(
                &backup.join("preferences.json"),
                &json_object(&preferences)?,
            )?;
            json_save(&scheme, &next)?;
            if let Err(error) = json_save(&preferences, &prefs) {
                json_save(&scheme, &current)?;
                return Err(error);
            }
            emit(&json!({"committed":true,"preferences":prefs,"backup":backup}))?;
        }
        _ => return Err("unknown profile action".into()),
    }
    Ok(0)
}

pub(crate) fn valid_integrations(value: &Value) -> bool {
    value.as_object().is_some_and(|m| {
        m.iter().all(|(k, v)| {
            ["hyprland", "kitty", "gtk", "qt"].contains(&k.as_str()) && v.is_boolean()
        })
    })
}
fn valid_preferences(value: &Value) -> bool {
    let metadata: Value = serde_json::from_str(include_str!(
        "../../platform-rs/templates/theme-metadata.json"
    ))
    .expect("theme metadata");
    value.as_object().is_some_and(|profiles| {
        profiles.iter().all(|(id, profile)| {
            ["ink", "washi", "kurogane"].contains(&id.as_str())
                && profile.as_object().is_some_and(|p| {
                    p.iter().all(|(key, value)| match key.as_str() {
                        "borderThickness" => value.as_i64().is_some_and(|n| (0..=20).contains(&n)),
                        "transparencyEnabled" | "reducedMotion" | "smartScheme" => {
                            value.is_boolean()
                        }
                        "tokens" => value.as_object().is_some_and(|tokens| {
                            tokens.iter().all(|(token, value)| {
                                let limits = &metadata["TOKEN_LIMITS"][token];
                                if metadata["FONT_TOKENS"]
                                    .as_array()
                                    .is_some_and(|v| v.iter().any(|v| v == token))
                                {
                                    return value.as_str().is_some_and(|s| {
                                        !s.trim().is_empty()
                                            && s.encode_utf16().count() <= 128
                                            && !s.chars().any(char::is_control)
                                    });
                                }
                                value.as_f64().is_some_and(|n| {
                                    limits[0]
                                        .as_f64()
                                        .zip(limits[1].as_f64())
                                        .is_some_and(|(min, max)| n >= min && n <= max)
                                })
                            })
                        }),
                        _ => false,
                    })
                })
        })
    })
}

pub(crate) fn validate_saved_theme_scheme(value: &Value) -> Result<()> {
    let object = value.as_object().ok_or("invalid saved theme scheme")?;
    if !["schema", "origin", "name", "flavour", "variant", "colours"]
        .iter()
        .any(|key| object.contains_key(*key))
    {
        return Err("saved theme scheme has no recognised fields".into());
    }
    for key in ["origin", "name", "flavour", "variant", "mode", "seed"] {
        if value.get(key).is_some_and(|field| !field.is_string()) {
            return Err(format!("invalid saved theme scheme {key}").into());
        }
    }
    if value
        .get("mode")
        .is_some_and(|v| !matches!(v.as_str(), Some("dark" | "light")))
    {
        return Err("invalid saved colour mode".into());
    }
    if value
        .get("origin")
        .is_some_and(|v| !matches!(v.as_str(), Some("manual" | "wallpaper" | "theme")))
    {
        return Err("invalid saved colour origin".into());
    }
    if let Some(seed) = value.get("seed") {
        crate::theme_sync::hex(seed)?;
    }
    if value.get("colours").is_some_and(|field| !field.is_object()) {
        return Err("invalid saved theme scheme colours".into());
    }
    if value["schema"] == 2
        && (!matches!(
            value["origin"].as_str(),
            Some("manual" | "wallpaper" | "theme")
        ) || !value["name"].is_string()
            || !value["flavour"].is_string()
            || !value["colours"].is_object())
    {
        return Err("invalid saved theme scheme metadata".into());
    }
    if value["colours"]
        .as_object()
        .is_some_and(|colours| !colours.is_empty())
    {
        for colour in value["colours"]
            .as_object()
            .ok_or("invalid colours")?
            .values()
        {
            crate::theme_sync::hex(colour)?;
        }
    }
    Ok(())
}
