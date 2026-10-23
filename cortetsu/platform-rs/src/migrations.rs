use crate::util::*;
use serde_json::{Value, json};
use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
};
const REPLACEMENTS: [(&str, &str); 5] = [
    (
        "qs -c caelestia kill; sleep .1; caelestia shell -d",
        "systemctl --user restart cortetsu-shell.service",
    ),
    (
        "qs -c caelestia kill",
        "systemctl --user stop cortetsu-shell.service",
    ),
    (
        "caelestia shell -d",
        "systemctl --user start cortetsu-shell.service",
    ),
    ("caelestia screenshot", "cortetsu screenshot"),
    ("caelestia emoji", "cortetsu emoji"),
];
pub fn lifecycle_scan(h: &Path) -> Vec<Value> {
    let mut out = Vec::new();
    for rel in [
        ".config/hypr/hyprland/execs.lua",
        ".config/hypr/hyprland/keybinds.lua",
    ] {
        let path = h.join(rel);
        if let Ok(t) = fs::read_to_string(&path) {
            let matches: Vec<_> = REPLACEMENTS
                .iter()
                .filter(|(old, _)| t.contains(old))
                .map(|(old, _)| *old)
                .collect();
            if !matches.is_empty() {
                out.push(json!({"path":path,"matches":matches}));
            }
        }
    }
    out
}
pub fn lifecycle(a: &Args) -> Result<i32> {
    a.check(&["home", "json"])?;
    let h = a.home()?;
    let matches = lifecycle_scan(&h);
    match a.action("scan").as_str() {
        "scan" | "verify" => {
            if a.has("json") {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&json!({"schema":1,"legacyLifecycle":matches}))?
                );
            } else if matches.is_empty() {
                println!("PASS: Hyprland shell lifecycle is systemd-owned");
            } else {
                println!("Legacy shell lifecycle references:");
                for m in &matches {
                    println!("  {}", m["path"].as_str().unwrap_or_default());
                    for t in strings(&m["matches"]) {
                        println!("    - {t}");
                    }
                }
            }
            Ok(if matches.is_empty() { 0 } else { 1 })
        }
        "migrate" => {
            crate::install::check_mutation()?;
            if matches.is_empty() {
                println!("Cortetsu shell lifecycle: already reconciled");
                return Ok(0);
            }
            let backup = data_root()?
                .join("migrations")
                .join(unique())
                .join("hypr-shell-lifecycle");
            for m in matches {
                let path = PathBuf::from(m["path"].as_str().ok_or("missing path")?);
                let t = fs::read_to_string(&path)?;
                let mut updated = t.clone();
                for (old, new) in REPLACEMENTS {
                    updated = updated.replace(old, new);
                }
                if t != updated {
                    copy_path(&path, &backup.join(path.strip_prefix(&h)?))?;
                    atomic_write(&path, updated, fs::metadata(&path)?.permissions().mode())?;
                    println!("MIGRATED lifecycle={}", path.display());
                }
            }
            if !lifecycle_scan(&h).is_empty() {
                return fail("quedaron referencias legacy de lifecycle");
            }
            println!(
                "BACKUP lifecycle={}\nCortetsu shell lifecycle: systemd --user is the only process owner",
                backup.display()
            );
            Ok(0)
        }
        _ => fail("unknown lifecycle action"),
    }
}
fn get<'a>(v: &'a Value, path: &str) -> &'a Value {
    let mut value = v;
    for p in path.split('.') {
        value = &value[p];
    }
    value
}
pub fn preference_payload(legacy: &Value) -> Result<Value> {
    let mut out: Value =
        serde_json::from_str(include_str!("../templates/preferences-defaults.json"))?;
    // Only preferences with a live Cortetsu owner are copied; retired bar
    // fields remain readable in the source file but are intentionally dropped.
    let mapping = [
        ("favouriteApps", "launcher.favouriteApps"),
        ("hiddenApps", "launcher.hiddenApps"),
        ("hiddenTrayIcons", "bar.tray.hiddenIcons"),
        ("terminalCommand", "general.apps.terminal"),
        ("actions", "launcher.actions"),
        ("actionPrefix", "launcher.actionPrefix"),
        ("specialPrefix", "launcher.specialPrefix"),
        ("enableDangerousActions", "launcher.enableDangerousActions"),
        ("useFuzzyApps", "launcher.useFuzzy.apps"),
        ("useFuzzyWallpapers", "launcher.useFuzzy.wallpapers"),
        ("smartScheme", "services.smartScheme"),
        ("wallpaperDirectory", "paths.wallpaperDir"),
        ("useTwelveHourClock", "services.useTwelveHourClock"),
        ("useFahrenheit", "services.useFahrenheit"),
        (
            "useFahrenheitPerformance",
            "services.useFahrenheitPerformance",
        ),
        ("weatherLocation", "services.weatherLocation"),
        ("audioIncrement", "services.audioIncrement"),
        ("brightnessIncrement", "services.brightnessIncrement"),
        ("maxVolume", "services.maxVolume"),
        ("visualiserBars", "services.visualiserBars"),
        ("defaultPlayer", "services.defaultPlayer"),
        ("playerAliases", "services.playerAliases"),
        (
            "toastAudioOutputChanged",
            "utilities.toasts.audioOutputChanged",
        ),
        (
            "toastAudioInputChanged",
            "utilities.toasts.audioInputChanged",
        ),
        ("toastNowPlaying", "utilities.toasts.nowPlaying"),
        ("notificationExpire", "notifs.expire"),
        (
            "notificationDefaultExpireTimeout",
            "notifs.defaultExpireTimeout",
        ),
        (
            "notificationFullscreenExpireTimeout",
            "notifs.fullscreenExpireTimeout",
        ),
        ("notificationActionOnClick", "notifs.actionOnClick"),
        ("toastDndChanged", "utilities.toasts.dndChanged"),
        ("toastGameModeChanged", "utilities.toasts.gameModeChanged"),
        ("vimKeybinds", "launcher.vimKeybinds"),
    ];
    for (key, path) in mapping {
        let source = get(legacy, path);
        let mut cursor = Some(legacy);
        for part in path.split('.') {
            cursor = cursor.and_then(|v| v.get(part));
        }
        if cursor.is_none() {
            continue;
        }
        let default = &out[key];
        let value = if default.is_boolean() {
            Some(json!(source == true))
        } else if default.is_string() {
            source.as_str().map(|v| json!(v))
        } else if default.is_number() {
            if source.is_boolean() {
                Some(source.clone())
            } else if default.is_i64() || default.is_u64() {
                source.as_i64().map(|v| json!(v))
            } else {
                source.as_f64().map(|v| json!(v))
            }
        } else if default.is_array() {
            source.as_array().map(|v| {
                json!(
                    v.iter()
                        .filter(|x| if ["actions", "playerAliases"].contains(&key) {
                            x.is_object()
                        } else {
                            x.is_string()
                        })
                        .cloned()
                        .collect::<Vec<_>>()
                )
            })
        } else {
            None
        };
        if let Some(v) = value {
            out[key] = v;
        }
    }
    let shown = get(legacy, "bar.workspaces.shown");
    out["workspacesShown"] = json!(
        shown
            .as_i64()
            .or_else(|| shown.as_bool().map(i64::from))
            .or_else(|| shown.as_str().and_then(|s| s.parse().ok()))
            .or_else(|| shown.as_f64().map(|v| v as i64))
            .unwrap_or(5)
            .clamp(1, 20)
    );
    let fs = get(legacy, "notifs.fullscreen");
    out["suppressNotificationsInFullscreen"] =
        json!(fs == 0 || fs == false || fs == "off" || fs == "Off");
    let vpn = get(legacy, "utilities.vpn");
    let mut providers = Vec::new();
    if let Some(a) = vpn["provider"].as_array() {
        for p in a {
            if p.is_string() {
                providers.push(p.clone());
            } else if p["name"].is_string() {
                let mut obj = json!({});
                for key in ["id", "name", "displayName", "interface"] {
                    if p[key].is_string() {
                        obj[key] = p[key].clone();
                    }
                }
                for key in ["connectCmd", "disconnectCmd"] {
                    if p[key].is_array() {
                        obj[key] = json!(strings(&p[key]));
                    }
                }
                providers.push(obj);
            }
        }
    }
    out["vpn"] = json!({"providers":providers,"selectedProvider":vpn["selectedProvider"].as_str().unwrap_or(""),"enabled":vpn["enabled"]==true});
    Ok(out)
}
pub fn config(a: &Args) -> Result<i32> {
    a.check(&["home", "target", "data-root"])?;
    let h = a.home()?;
    let cfg = env_path("XDG_CONFIG_HOME", h.join(".config"))?;
    let state = env_path("XDG_STATE_HOME", h.join(".local/state"))?;
    let root = a
        .get("data-root")
        .map(expand)
        .transpose()?
        .unwrap_or(env_path("XDG_DATA_HOME", h.join(".local/share"))?.join("cortetsu"));
    let target = a
        .get("target")
        .map(expand)
        .transpose()?
        .unwrap_or(cfg.join("cortetsu/preferences.json"));
    let legacy = cfg.join("caelestia/shell.json");
    let backup = root.join("migrations").join(unique());
    let mut copied = false;
    for name in ["wallpaper/path.txt", "scheme.json", "notifs.json"] {
        let src = state.join("caelestia").join(name);
        let dst = state.join("cortetsu").join(name);
        if src.is_file() && !dst.exists() {
            copy_path(&src, &backup.join("runtime-state").join(name))?;
            copy_path(&src, &dst)?;
            copied = true;
            println!("MIGRATED state={}", dst.display());
        }
    }
    if copied {
        println!("BACKUP state={}", backup.join("runtime-state").display());
    }
    let existed = target.exists();
    let mut current = if existed { json(&target)? } else { json!({}) };
    if !current.is_object() {
        return fail("preferences must be an object");
    }
    if !legacy.is_file() {
        println!(
            "PASS: {}",
            if existed {
                format!("Cortetsu preferences already exist: {}", target.display())
            } else {
                "no legacy shell preferences to migrate".into()
            }
        );
        return Ok(0);
    }
    let fresh = preference_payload(&json(&legacy)?)?;
    let mut changed = false;
    for (k, v) in fresh.as_object().ok_or("invalid preferences")? {
        if current.get(k).is_none() {
            current[k] = v.clone();
            changed = true;
        }
    }
    if changed {
        let b = backup.join("preferences/legacy-shell.json");
        copy_path(&legacy, &b)?;
        write_json(&target, &current)?;
        println!(
            "{} preferences={}\nBACKUP preferences={}",
            if existed { "UPDATED" } else { "MIGRATED" },
            target.display(),
            b.display()
        );
    } else {
        println!(
            "PASS: Cortetsu preferences already exist: {}",
            target.display()
        );
    }
    Ok(0)
}
fn legacy_files(h: &Path) -> Result<Vec<PathBuf>> {
    let cfg = env_path("XDG_CONFIG_HOME", h.join(".config"))?;
    let mut paths = Vec::new();
    for r in ["hypr", "quickshell", "systemd/user"] {
        let root = cfg.join(r);
        if !root.is_dir() {
            continue;
        }
        for entry in walkdir::WalkDir::new(root).follow_links(false).into_iter() {
            let e = entry?;
            if e.path().is_file()
                && e.path()
                    .extension()
                    .and_then(|s| s.to_str())
                    .is_some_and(|ext| {
                        ["lua", "fish", "service", "desktop", "conf", "sh", "toml"].contains(&ext)
                    })
            {
                paths.push(e.path().to_path_buf());
            }
        }
    }
    paths.sort();
    paths.dedup();
    Ok(paths)
}
pub fn legacy(a: &Args) -> Result<i32> {
    a.check(&["home", "data-root"])?;
    let h = a.home()?;
    let files = legacy_files(&h)?;
    match a.action("scan").as_str() {
        "scan" => {
            println!("Legacy process audit\n====================");
            for (kind, name) in [
                ("pomodoro", "caerice-pomodoro"),
                ("wallpaper-color", "caelestia-wallpaper-color-daemon"),
            ] {
                let found: Vec<_> = files
                    .iter()
                    .filter(|p| fs::read_to_string(p).is_ok_and(|t| t.contains(name)))
                    .collect();
                println!(
                    "{kind}: {}",
                    if found.is_empty() { "ABSENT" } else { "FOUND" }
                );
                for f in found {
                    println!("  {}", f.display());
                }
            }
            let mut live = false;
            for e in fs::read_dir("/proc")?.filter_map(std::result::Result::ok) {
                if e.file_name()
                    .to_string_lossy()
                    .bytes()
                    .all(|b| b.is_ascii_digit())
                    && let Ok(b) = fs::read(e.path().join("cmdline"))
                {
                    let text = String::from_utf8_lossy(&b).replace('\0', " ");
                    for (kind, name) in [
                        ("pomodoro", "caerice-pomodoro"),
                        ("wallpaper-color", "caelestia-wallpaper-color-daemon"),
                    ] {
                        if text.contains(name) {
                            live = true;
                            println!(
                                "  {kind}: pid={} cmd={}",
                                e.file_name().to_string_lossy(),
                                text.trim()
                            );
                        }
                    }
                }
            }
            println!(
                "live processes: {}",
                if live {
                    "FOUND\n  action: audit-only; ownership must be resolved before any stop"
                } else {
                    "none"
                }
            );
        }
        "migrate" => {
            crate::install::check_mutation()?;
            let root = a
                .get("data-root")
                .map(expand)
                .transpose()?
                .unwrap_or(data_root()?);
            let _lock = lock(&root.join("legacy-processes.lock"), false)?;
            let backup = root
                .join("migrations")
                .join(unique())
                .join("legacy-processes");
            let config = env_path("XDG_CONFIG_HOME", h.join(".config"))?;
            let mut count = 0;
            let mut deferred = 0;
            for path in files {
                let original = fs::read_to_string(&path)?;
                let mut updated = original.clone();
                for (legacy, native) in [
                    ("caerice-pomodoro", "cortetsu-pomodoro"),
                    (
                        "caelestia-wallpaper-color-daemon",
                        "cortetsu-wallpaper-color-daemon",
                    ),
                ] {
                    if original.contains(legacy) {
                        if h.join(".local/bin").join(native).is_file() {
                            updated = updated.replace(legacy, native);
                        } else {
                            deferred += 1;
                            println!("DEFERRED {legacy}: Cortetsu helper is not installed");
                        }
                    }
                }
                if updated == original {
                    continue;
                }
                if path.is_symlink() {
                    println!(
                        "DEFERRED managed symlink: update its Cortetsu source instead: {}",
                        path.display()
                    );
                    continue;
                }
                copy_path(
                    &path,
                    &backup.join("config").join(path.strip_prefix(&config)?),
                )?;
                atomic_write(&path, updated, fs::metadata(&path)?.permissions().mode())?;
                count += 1;
            }
            atomic_write(
                &root.join("legacy-processes.last"),
                format!(
                    "changed={count}\ndeferred={deferred}\nbackup={}\n",
                    backup.display()
                ),
                0o600,
            )?;
            println!(
                "MIGRATED pomodoro_files={count} deferred_wallpaper_files={deferred}\nBACKUP legacy-processes={}\nNO_PROCESS_SIGNALING",
                backup.display()
            );
        }
        _ => return fail("unknown legacy processes action"),
    };
    Ok(0)
}
