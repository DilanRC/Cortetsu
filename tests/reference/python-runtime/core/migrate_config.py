#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path


def config_home(home: Path) -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")).expanduser()


def data_home(home: Path) -> Path:
    return Path(os.environ.get("XDG_DATA_HOME", home / ".local/share")).expanduser()


def state_home(home: Path) -> Path:
    return Path(os.environ.get("XDG_STATE_HOME", home / ".local/state")).expanduser()


def migrate_runtime_state(home: Path, data_root: Path) -> None:
    legacy_root = state_home(home) / "caelestia"
    target_root = state_home(home) / "cortetsu"
    candidates = (
        (legacy_root / "wallpaper/path.txt", target_root / "wallpaper/path.txt"),
        (legacy_root / "scheme.json", target_root / "scheme.json"),
        (legacy_root / "notifs.json", target_root / "notifs.json"),
    )
    pending = [(source, target) for source, target in candidates if source.is_file() and not target.exists()]
    if not pending:
        return
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup_root = data_root / "migrations" / stamp / "runtime-state"
    for source, target in pending:
        relative = source.relative_to(legacy_root)
        backup = backup_root / relative
        backup.parent.mkdir(parents=True, exist_ok=True)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, backup)
        shutil.copy2(source, target)
        print(f"MIGRATED state={target}")
    print(f"BACKUP state={backup_root}")


def payload_from_legacy(path: Path) -> dict[str, object]:
    data = json.loads(path.read_text(encoding="utf-8"))
    launcher = data.get("launcher", {})
    bar = data.get("bar", {})
    workspaces = bar.get("workspaces", {})
    tray = bar.get("tray", {})
    apps = data.get("general", {}).get("apps", {})
    services = data.get("services", {})
    toasts = data.get("utilities", {}).get("toasts", {})
    vpn = data.get("utilities", {}).get("vpn", {})
    notifs = data.get("notifs", {})
    shown = workspaces.get("shown", 5)
    try:
        shown = max(1, min(20, int(shown)))
    except (TypeError, ValueError):
        shown = 5
    providers = []
    for value in vpn.get("provider", []) if isinstance(vpn, dict) else []:
        if isinstance(value, str):
            providers.append(value)
            continue
        if not isinstance(value, dict) or not isinstance(value.get("name"), str):
            continue
        provider = {key: value[key] for key in ("id", "name", "displayName", "interface") if isinstance(value.get(key), str)}
        for key in ("connectCmd", "disconnectCmd"):
            if isinstance(value.get(key), list):
                provider[key] = [item for item in value[key] if isinstance(item, str)]
        providers.append(provider)
    return {
        "schema": 1,
        "favouriteApps": [x for x in launcher.get("favouriteApps", []) if isinstance(x, str)],
        "hiddenApps": [x for x in launcher.get("hiddenApps", []) if isinstance(x, str)],
        "hiddenTrayIcons": [x for x in tray.get("hiddenIcons", []) if isinstance(x, str)],
        "terminalCommand": [x for x in apps.get("terminal", ["kitty"]) if isinstance(x, str)],
        "vpn": {
            "providers": providers,
            "selectedProvider": vpn.get("selectedProvider", "") if isinstance(vpn, dict) and isinstance(vpn.get("selectedProvider", ""), str) else "",
            "enabled": vpn.get("enabled", False) is True if isinstance(vpn, dict) else False,
        },
        "actions": [x for x in launcher.get("actions", []) if isinstance(x, dict)],
        "actionPrefix": launcher.get("actionPrefix", ">") if isinstance(launcher.get("actionPrefix", ">"), str) else ">",
        "specialPrefix": launcher.get("specialPrefix", "@") if isinstance(launcher.get("specialPrefix", "@"), str) else "@",
        "enableDangerousActions": launcher.get("enableDangerousActions", True) is True,
        "useFuzzyApps": launcher.get("useFuzzy", {}).get("apps", True) is True,
        "useFuzzyWallpapers": launcher.get("useFuzzy", {}).get("wallpapers", True) is True,
        "smartScheme": data.get("services", {}).get("smartScheme", True) is True,
        "wallpaperDirectory": data.get("paths", {}).get("wallpaperDir", "~/Imágenes/Wallpapers") if isinstance(data.get("paths", {}).get("wallpaperDir", "~/Imágenes/Wallpapers"), str) else "~/Imágenes/Wallpapers",
        "useTwelveHourClock": services.get("useTwelveHourClock", False) is True,
        "useFahrenheit": services.get("useFahrenheit", False) is True,
        "useFahrenheitPerformance": services.get("useFahrenheitPerformance", False) is True,
        "weatherLocation": services.get("weatherLocation", "") if isinstance(services.get("weatherLocation", ""), str) else "",
        "audioIncrement": services.get("audioIncrement", 0.1) if isinstance(services.get("audioIncrement", 0.1), (int, float)) else 0.1,
        "brightnessIncrement": services.get("brightnessIncrement", 0.1) if isinstance(services.get("brightnessIncrement", 0.1), (int, float)) else 0.1,
        "maxVolume": services.get("maxVolume", 1.0) if isinstance(services.get("maxVolume", 1.0), (int, float)) else 1.0,
        "visualiserBars": services.get("visualiserBars", 60) if isinstance(services.get("visualiserBars", 60), int) else 60,
        "defaultPlayer": services.get("defaultPlayer", "Spotify") if isinstance(services.get("defaultPlayer", "Spotify"), str) else "Spotify",
        "playerAliases": [x for x in services.get("playerAliases", [{"from": "com.github.th_ch.youtube_music", "to": "YT Music"}]) if isinstance(x, dict)],
        "toastAudioOutputChanged": toasts.get("audioOutputChanged", True) is True,
        "toastAudioInputChanged": toasts.get("audioInputChanged", True) is True,
        "toastNowPlaying": toasts.get("nowPlaying", False) is True,
        "notificationExpire": notifs.get("expire", True) is True,
        "suppressNotificationsInFullscreen": notifs.get("fullscreen", "on") in (0, "off", "Off"),
        "notificationDefaultExpireTimeout": notifs.get("defaultExpireTimeout", 5000) if isinstance(notifs.get("defaultExpireTimeout", 5000), int) else 5000,
        "notificationFullscreenExpireTimeout": notifs.get("fullscreenExpireTimeout", 2000) if isinstance(notifs.get("fullscreenExpireTimeout", 2000), int) else 2000,
        "notificationActionOnClick": notifs.get("actionOnClick", False) is True,
        "toastDndChanged": toasts.get("dndChanged", True) is True,
        "toastGameModeChanged": toasts.get("gameModeChanged", True) is True,
        "vimKeybinds": launcher.get("vimKeybinds", True) is True,
        "workspacesShown": shown,
    }


def atomic_write(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        temporary = Path(handle.name)
        json.dump(payload, handle, indent=2)
        handle.write("\n")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def migrate(home: Path, target: Path | None = None, data_root: Path | None = None) -> int:
    home = home.expanduser().resolve()
    target = target or config_home(home) / "cortetsu/preferences.json"
    data_root = data_root or data_home(home) / "cortetsu"
    legacy = config_home(home) / "caelestia/shell.json"
    migrate_runtime_state(home, data_root)

    if target.exists():
        current = json.loads(target.read_text(encoding="utf-8"))
        if not isinstance(current, dict):
            raise ValueError(f"preferences must be an object: {target}")
        if not legacy.is_file():
            print(f"PASS: Cortetsu preferences already exist: {target}")
            return 0
        legacy_payload = payload_from_legacy(legacy)
        merged = dict(current)
        changed = False
        for key, value in legacy_payload.items():
            if key not in merged:
                merged[key] = value
                changed = True
        if changed:
            stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
            backup = data_root / "migrations" / stamp / "preferences" / "legacy-shell.json"
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(legacy, backup)
            atomic_write(target, merged)
            print(f"UPDATED preferences={target}")
            print(f"BACKUP preferences={backup}")
        else:
            print(f"PASS: Cortetsu preferences already exist: {target}")
        return 0
    if not legacy.is_file():
        print("PASS: no legacy shell preferences to migrate")
        return 0

    payload = payload_from_legacy(legacy)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup = data_root / "migrations" / stamp / "preferences" / "legacy-shell.json"
    backup.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(legacy, backup)
    atomic_write(target, payload)
    print(f"MIGRATED preferences={target}")
    print(f"BACKUP preferences={backup}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Migrate functional preferences to Cortetsu XDG config")
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--target", type=Path)
    parser.add_argument("--data-root", type=Path)
    args = parser.parse_args()
    return migrate(args.home, args.target, args.data_root)


if __name__ == "__main__":
    raise SystemExit(main())
