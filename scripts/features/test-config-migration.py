import json
import os
import subprocess
import tempfile
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
script = repo / "tests/reference/python-runtime/core/migrate_config.py"

with tempfile.TemporaryDirectory(prefix="cortetsu-config-test-") as directory:
    home = Path(directory)
    legacy = home / ".config/caelestia/shell.json"
    legacy.parent.mkdir(parents=True)
    legacy.write_text(json.dumps({
        "launcher": {"favouriteApps": ["steam", 7], "hiddenApps": ["qt6ct"], "actions": [{"name": "Open", "command": ["open"]}, 7], "actionPrefix": "/", "specialPrefix": "@", "enableDangerousActions": False, "useFuzzy": {"apps": False, "wallpapers": False}, "vimKeybinds": False},
        "paths": {"wallpaperDir": "~/Wallpapers"},
        "services": {"smartScheme": False, "useTwelveHourClock": True, "useFahrenheit": True, "useFahrenheitPerformance": True, "weatherLocation": "9.9,-84.1", "audioIncrement": 0.05, "brightnessIncrement": 0.2, "maxVolume": 1.5, "visualiserBars": 48, "defaultPlayer": "VLC", "playerAliases": [{"from": "vlc", "to": "VLC"}]},
        "utilities": {"toasts": {"audioOutputChanged": False, "audioInputChanged": False, "nowPlaying": True}, "vpn": {"provider": [{"id": "office", "name": "wireguard", "displayName": "Office", "interface": "wg-office", "connectCmd": ["wg-quick", "up", "wg-office", 9], "disconnectCmd": ["wg-quick", "down", "wg-office"]}], "selectedProvider": "office", "enabled": True}},
        "notifs": {"expire": False, "fullscreen": "off", "defaultExpireTimeout": 7000, "fullscreenExpireTimeout": 3000, "actionOnClick": True},
        "bar": {
            "persistent": True,
            "scrollActions": {"brightness": False, "workspaces": False},
            "tray": {"compact": True, "hiddenIcons": ["nm-applet", None]},
            "activeWindow": {"compact": False},
            "clock": {"showDate": True},
            "workspaces": {"shown": 6},
        },
        "general": {"apps": {"terminal": ["foot", 9]}},
    }), encoding="utf-8")
    legacy_state = home / ".local/state/caelestia"
    (legacy_state / "wallpaper").mkdir(parents=True)
    (legacy_state / "wallpaper/path.txt").write_text("/wallpaper.png\n")
    (legacy_state / "scheme.json").write_text('{"name":"dynamic"}\n')
    (legacy_state / "notifs.json").write_text('[{"summary":"Migrated"}]\n')
    env = {**os.environ, "XDG_CONFIG_HOME": str(home / ".config"), "XDG_DATA_HOME": str(home / ".local/share"), "XDG_STATE_HOME": str(home / ".local/state")}
    subprocess.run(["python3", str(script), "--home", str(home)], env=env, check=True)
    target = home / ".config/cortetsu/preferences.json"
    payload = json.loads(target.read_text())
    assert not any(key.startswith("bar") for key in payload), "retired top-bar preferences must not be migrated"
    assert payload == {"schema": 1, "favouriteApps": ["steam"], "hiddenApps": ["qt6ct"], "hiddenTrayIcons": ["nm-applet"], "terminalCommand": ["foot"], "vpn": {"providers": [{"id": "office", "name": "wireguard", "displayName": "Office", "interface": "wg-office", "connectCmd": ["wg-quick", "up", "wg-office"], "disconnectCmd": ["wg-quick", "down", "wg-office"]}], "selectedProvider": "office", "enabled": True}, "actions": [{"name": "Open", "command": ["open"]}], "actionPrefix": "/", "specialPrefix": "@", "enableDangerousActions": False, "useFuzzyApps": False, "useFuzzyWallpapers": False, "smartScheme": False, "wallpaperDirectory": "~/Wallpapers", "useTwelveHourClock": True, "useFahrenheit": True, "useFahrenheitPerformance": True, "weatherLocation": "9.9,-84.1", "audioIncrement": 0.05, "brightnessIncrement": 0.2, "maxVolume": 1.5, "visualiserBars": 48, "defaultPlayer": "VLC", "playerAliases": [{"from": "vlc", "to": "VLC"}], "toastAudioOutputChanged": False, "toastAudioInputChanged": False, "toastNowPlaying": True, "notificationExpire": False, "suppressNotificationsInFullscreen": True, "notificationDefaultExpireTimeout": 7000, "notificationFullscreenExpireTimeout": 3000, "notificationActionOnClick": True, "toastDndChanged": True, "toastGameModeChanged": True, "vimKeybinds": False, "workspacesShown": 6}
    backups = list((home / ".local/share/cortetsu/migrations").glob("*/preferences/legacy-shell.json"))
    assert len(backups) == 1
    assert (home / ".local/state/cortetsu/wallpaper/path.txt").read_text() == "/wallpaper.png\n"
    assert (home / ".local/state/cortetsu/scheme.json").is_file()
    assert (home / ".local/state/cortetsu/notifs.json").read_text() == '[{"summary":"Migrated"}]\n'
    assert len(list((home / ".local/share/cortetsu/migrations").glob("*/runtime-state/wallpaper/path.txt"))) == 1
    subprocess.run(["python3", str(script), "--home", str(home)], env=env, check=True)
    assert len(list((home / ".local/share/cortetsu/migrations").glob("*/preferences/legacy-shell.json"))) == 1
    assert len(list((home / ".local/share/cortetsu/migrations").glob("*/runtime-state/wallpaper/path.txt"))) == 1
print("PASS: functional preference migration is backed up and idempotent")
