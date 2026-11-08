use serde_json::{Value, json};
use std::{fs, os::unix::fs::PermissionsExt, process::Command};
use tempfile::TempDir;

fn command(home: &TempDir, helper: &str, args: &[&str]) -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_cortetsu-desktop-runtime"));
    c.arg(helper)
        .args(args)
        .env("HOME", home.path())
        .env("XDG_STATE_HOME", home.path().join("state"))
        .env("XDG_CONFIG_HOME", home.path().join("config"))
        .env("XDG_CACHE_HOME", home.path().join("cache"))
        .env("XDG_DATA_HOME", home.path().join("data"))
        .env("GSETTINGS_BACKEND", "keyfile")
        .env("XDG_CONFIG_DIRS", home.path().join("system-config"))
        .env(
            "CORTETSU_REPO_ROOT",
            concat!(env!("CARGO_MANIFEST_DIR"), "/../.."),
        );
    c
}
fn payload(mut c: Command) -> Value {
    let o = c.output().unwrap();
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    serde_json::from_slice(&o.stdout).unwrap()
}

#[test]
fn effective_theme_palette_and_projection_failures_are_independent() {
    let home = TempDir::new().unwrap();
    let initial = payload(command(&home, "cortetsu-scheme", &["effective"]));
    assert_eq!(initial["themeId"], "ink");
    assert!(initial["colours"]["surface"].is_string());
    for theme in ["washi", "kurogane", "ink"] {
        payload(command(&home, "cortetsu-scheme", &["theme", theme]));
        let palette = payload(command(&home, "cortetsu-scheme", &["effective"]));
        assert_eq!(palette["themeId"], theme);
        if theme == "washi" {
            assert_eq!(palette["colours"]["surface"], "#F5EFE4");
        }
        if theme == "kurogane" {
            assert_eq!(palette["colours"]["surface"], "#172029");
        }
    }
    let result = payload(command(&home, "cortetsu-scheme", &["sync-projections"]));
    assert_eq!(result["targets"]["kitty"]["status"], "reopen");
    assert_eq!(result["targets"]["gtk"]["status"], "unavailable");
    let kitty = home.path().join("state/cortetsu/kitty-colors.conf");
    let modified = fs::metadata(&kitty).unwrap().modified().unwrap();
    payload(command(&home, "cortetsu-scheme", &["sync-projections"]));
    assert_eq!(fs::metadata(&kitty).unwrap().modified().unwrap(), modified);
    fs::remove_file(&kitty).unwrap();
    fs::create_dir(&kitty).unwrap();
    let result = payload(command(&home, "cortetsu-scheme", &["sync-projections"]));
    assert_eq!(result["targets"]["kitty"]["status"], "error");
    assert_eq!(
        payload(command(&home, "cortetsu-scheme", &["effective"]))["themeId"],
        "ink"
    );
}

#[test]
fn toolkit_projections_preserve_kde_keys_and_restore_on_disable() {
    let home = TempDir::new().unwrap();
    let cfg = home.path().join("config");
    let state = home.path().join("state/cortetsu");
    fs::create_dir_all(cfg.join("gtk-3.0")).unwrap();
    fs::create_dir_all(cfg.join("cortetsu")).unwrap();
    fs::write(
        cfg.join("gtk-3.0/cortetsu-colors.css"),
        format!(
            "@import url(\"file://{}/gtk-colors.css\");",
            state.display()
        ),
    )
    .unwrap();
    fs::write(
        cfg.join("kdeglobals"),
        "[General]\nColorScheme=Cortetsu\nfont=My Font\n[Other]\nKeep=yes\n",
    )
    .unwrap();
    let result = payload(command(&home, "cortetsu-scheme", &["sync-projections"]));
    assert_eq!(result["targets"]["gtk"]["status"], "reopen");
    assert_eq!(result["targets"]["qt"]["status"], "reopen");
    let globals = fs::read_to_string(cfg.join("kdeglobals")).unwrap();
    assert!(globals.contains("ColorScheme=CortetsuLive"));
    assert!(globals.contains("font=My Font\n[Other]\nKeep=yes"));
    assert!(
        fs::read_to_string(state.join("gtk-colors.css"))
            .unwrap()
            .contains("@define-color")
    );
    fs::write(
        cfg.join("cortetsu/preferences.json"),
        r#"{"themeIntegrations":{"gtk":false,"qt":false}}"#,
    )
    .unwrap();
    payload(command(&home, "cortetsu-scheme", &["sync-projections"]));
    assert!(
        fs::read_to_string(cfg.join("kdeglobals"))
            .unwrap()
            .contains("ColorScheme=Cortetsu\n")
    );
    assert!(
        !fs::read_to_string(state.join("gtk-colors.css"))
            .unwrap()
            .contains("@define-color")
    );
}

#[test]
fn light_mode_is_persistent_and_keeps_theme_and_variant() {
    let home = TempDir::new().unwrap();
    payload(command(&home, "cortetsu-scheme", &["theme", "kurogane"]));
    let result = payload(command(
        &home,
        "cortetsu-scheme",
        &["set", "--mode", "light"],
    ));
    assert_eq!(result["committed"], true);
    let palette = payload(command(&home, "cortetsu-scheme", &["effective"]));
    assert_eq!(palette["themeId"], "kurogane");
    assert_eq!(palette["mode"], "light");
    assert_ne!(palette["colours"]["surface"], "#172029");
    let bad = command(&home, "cortetsu-scheme", &["set", "--mode", "garbage"])
        .output()
        .unwrap();
    assert!(!bad.status.success());
    assert_eq!(
        payload(command(&home, "cortetsu-scheme", &["effective"])),
        palette
    );
}

#[test]
fn theme_preview_does_not_commit_and_source_is_explicit() {
    let home = TempDir::new().unwrap();
    let preview = payload(command(
        &home,
        "cortetsu-scheme",
        &["preview-theme", "washi"],
    ));
    assert_eq!(preview["colours"]["surface"], "#F5EFE4");
    assert!(!home.path().join("state/cortetsu/scheme.json").exists());
    payload(command(&home, "cortetsu-scheme", &["source", "manual"]));
    let path = home.path().join("state/cortetsu/scheme.json");
    assert_eq!(
        serde_json::from_slice::<Value>(&fs::read(&path).unwrap()).unwrap()["origin"],
        "manual"
    );
    payload(command(&home, "cortetsu-scheme", &["source", "auto"]));
    let preferences: Value = serde_json::from_slice(
        &fs::read(home.path().join("config/cortetsu/preferences.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(preferences["smartScheme"], true);
    assert_eq!(
        serde_json::from_slice::<Value>(&fs::read(&path).unwrap()).unwrap()["origin"],
        "wallpaper"
    );
}

#[test]
fn visual_profile_export_import_preserves_unrelated_preferences() {
    let home = TempDir::new().unwrap();
    payload(command(&home, "cortetsu-scheme", &["theme", "washi"]));
    let config = home.path().join("config/cortetsu/preferences.json");
    fs::create_dir_all(config.parent().unwrap()).unwrap();
    fs::write(
        &config,
        r#"{"themeId":"washi","transparencyEnabled":true,"borderThickness":3,"terminalCommand":["kitty"]}"#,
    )
    .unwrap();
    let profile = home.path().join("visual.json");
    payload(command(
        &home,
        "cortetsu-scheme",
        &["profile", "export", profile.to_str().unwrap()],
    ));
    payload(command(&home, "cortetsu-scheme", &["theme", "kurogane"]));
    fs::write(
        &config,
        r#"{"themeId":"kurogane","transparencyEnabled":false,"terminalCommand":["custom"]}"#,
    )
    .unwrap();
    payload(command(
        &home,
        "cortetsu-scheme",
        &["profile", "import", profile.to_str().unwrap()],
    ));
    let prefs: Value = serde_json::from_slice(&fs::read(&config).unwrap()).unwrap();
    assert_eq!(prefs["transparencyEnabled"], true);
    assert_eq!(prefs["borderThickness"], 3);
    assert_eq!(prefs["terminalCommand"], json!(["custom"]));
    assert_eq!(
        payload(command(&home, "cortetsu-scheme", &["effective"]))["themeId"],
        "washi"
    );
    let mut partial: Value = serde_json::from_slice(&fs::read(&profile).unwrap()).unwrap();
    partial["preferences"]["themeIntegrations"] = json!({"kitty":false});
    let mut existing = prefs.clone();
    existing["themeIntegrations"] = json!({"gtk":false,"kitty":true});
    fs::write(&config, serde_json::to_vec(&existing).unwrap()).unwrap();
    fs::write(&profile, serde_json::to_vec(&partial).unwrap()).unwrap();
    payload(command(
        &home,
        "cortetsu-scheme",
        &["profile", "import", profile.to_str().unwrap()],
    ));
    let prefs: Value = serde_json::from_slice(&fs::read(&config).unwrap()).unwrap();
    assert_eq!(
        prefs["themeIntegrations"],
        json!({"gtk":false,"kitty":false,"qt":true,"hyprland":true})
    );
    fs::write(&profile, "invalid").unwrap();
    assert!(
        !command(
            &home,
            "cortetsu-scheme",
            &["profile", "import", profile.to_str().unwrap()]
        )
        .output()
        .unwrap()
        .status
        .success()
    );
    assert_eq!(
        prefs,
        serde_json::from_slice::<Value>(&fs::read(&config).unwrap()).unwrap()
    );
}

#[test]
fn invalid_visual_profiles_and_preferences_fail_closed() {
    let home = TempDir::new().unwrap();
    let profile = home.path().join("profile.json");
    payload(command(
        &home,
        "cortetsu-scheme",
        &["profile", "export", profile.to_str().unwrap()],
    ));
    payload(command(
        &home,
        "cortetsu-scheme",
        &["profile", "import", profile.to_str().unwrap()],
    ));
    let valid: Value = serde_json::from_slice(&fs::read(&profile).unwrap()).unwrap();
    let state = home.path().join("state/cortetsu/scheme.json");
    let before = fs::read(&state).unwrap();
    for (field, value) in [
        ("archive", json!("invalid")),
        ("integrations", json!({"gtk":"disabled"})),
        ("tokens", json!({"ink":{"tokens":{"radiusSurface":"wide"}}})),
    ] {
        let mut invalid = valid.clone();
        match field {
            "archive" => invalid["scheme"]["themeProfiles"] = value,
            "integrations" => invalid["preferences"]["themeIntegrations"] = value,
            _ => invalid["preferences"]["themePreferences"] = value,
        }
        fs::write(&profile, serde_json::to_vec(&invalid).unwrap()).unwrap();
        assert!(
            !command(
                &home,
                "cortetsu-scheme",
                &["profile", "import", profile.to_str().unwrap()]
            )
            .output()
            .unwrap()
            .status
            .success()
        );
        assert_eq!(fs::read(&state).unwrap(), before);
    }
    assert!(
        !command(
            &home,
            "cortetsu-scheme",
            &["profile", "import", "/dev/zero"]
        )
        .output()
        .unwrap()
        .status
        .success()
    );
    let preferences = home.path().join("config/cortetsu/preferences.json");
    fs::write(&preferences, "{broken").unwrap();
    let result = payload(command(&home, "cortetsu-scheme", &["sync-projections"]));
    assert_eq!(result["targets"]["state"]["status"], "error");
    assert!(
        !home
            .path()
            .join("state/cortetsu/kitty-colors.conf")
            .exists()
    );
}

#[test]
fn hyprland_reload_retries_and_restoration_reloads() {
    let home = TempDir::new().unwrap();
    let cfg = home.path().join("config/hypr/scheme");
    fs::create_dir_all(&cfg).unwrap();
    fs::write(cfg.join("current.lua"), "return {}\n").unwrap();
    let bin = home.path().join("bin");
    fs::create_dir(&bin).unwrap();
    let calls = home.path().join("reloads");
    let success = home.path().join("success");
    fs::write(
        bin.join("hyprctl"),
        format!(
            "#!/bin/sh\necho reload >> '{}'\n[ -f '{}' ]\n",
            calls.display(),
            success.display()
        ),
    )
    .unwrap();
    fs::set_permissions(bin.join("hyprctl"), fs::Permissions::from_mode(0o755)).unwrap();
    let path = std::env::join_paths(std::iter::once(bin).chain(std::env::split_paths(
        &std::env::var_os("PATH").unwrap_or_default(),
    )))
    .unwrap();
    let sync = || {
        let mut c = command(&home, "cortetsu-scheme", &["sync-projections"]);
        c.env("PATH", &path).env_remove("CORTETSU_SKIP_RELOAD");
        payload(c)
    };
    assert_eq!(sync()["targets"]["hyprland"]["status"], "error");
    assert_eq!(sync()["targets"]["hyprland"]["status"], "error");
    fs::write(&success, "").unwrap();
    assert_eq!(sync()["targets"]["hyprland"]["status"], "applied");
    fs::create_dir_all(home.path().join("config/cortetsu")).unwrap();
    fs::write(
        home.path().join("config/cortetsu/preferences.json"),
        r#"{"themeIntegrations":{"hyprland":false}}"#,
    )
    .unwrap();
    assert_eq!(sync()["targets"]["hyprland"]["status"], "disabled");
    assert_eq!(
        fs::read_to_string(cfg.join("current.lua")).unwrap(),
        "return {}\n"
    );
    assert_eq!(fs::read_to_string(calls).unwrap().lines().count(), 4);
}

#[test]
fn qtengine_updates_only_its_palette_and_restores_it() {
    let home = TempDir::new().unwrap();
    let path = home.path().join("config/qtengine/config.json");
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    let original = json!({"theme":{"colorScheme":"~/old.colors","style":"Fusion","font":{"family":"Test"}},"misc":{"menusHaveIcons":true}});
    fs::write(&path, serde_json::to_vec(&original).unwrap()).unwrap();
    let sync = || {
        let mut c = command(&home, "cortetsu-scheme", &["sync-projections"]);
        c.env("QT_QPA_PLATFORMTHEME", "qtengine");
        payload(c)
    };
    assert_eq!(sync()["targets"]["qt"]["status"], "reopen");
    let changed: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    assert_eq!(changed["misc"], original["misc"]);
    assert_eq!(changed["theme"]["font"], original["theme"]["font"]);
    assert_eq!(changed["theme"]["style"], "Fusion");
    fs::create_dir_all(home.path().join("config/cortetsu")).unwrap();
    fs::write(
        home.path().join("config/cortetsu/preferences.json"),
        r#"{"themeIntegrations":{"qt":false}}"#,
    )
    .unwrap();
    sync();
    assert_eq!(
        serde_json::from_slice::<Value>(&fs::read(&path).unwrap()).unwrap(),
        original
    );
}
