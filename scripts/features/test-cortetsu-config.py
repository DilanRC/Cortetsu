from pathlib import Path
import re

repo = Path(__file__).resolve().parents[2]
modules = repo / "cortetsu/modules"
config = (modules / "CortetsuConfig.qml").read_text(encoding="utf-8")
hub = (modules / "BottomHub.qml").read_text(encoding="utf-8")
app_list = (modules / "launcher/AppList.qml").read_text(encoding="utf-8")
content = (modules / "launcher/Content.qml").read_text(encoding="utf-8")
content_list = (modules / "launcher/ContentList.qml").read_text(encoding="utf-8")
wrapper = (modules / "launcher/Wrapper.qml").read_text(encoding="utf-8")
apps_service = (modules / "launcher/services/Apps.qml").read_text(encoding="utf-8")
actions_service = (modules / "launcher/services/Actions.qml").read_text(encoding="utf-8")
schemes_service = (modules / "launcher/services/Schemes.qml").read_text(encoding="utf-8")
variants_service = (modules / "launcher/services/M3Variants.qml").read_text(encoding="utf-8")
manifest = (repo / "cortetsu/contracts/patch-debt.tsv").read_text(encoding="utf-8")
desktop_clock = (modules / "background/DesktopClock.qml").read_text(encoding="utf-8")
spectrum = (repo / "cortetsu/services/CortetsuSpectrum.qml").read_text(encoding="utf-8")
visualiser = (modules / "background/Visualiser.qml").read_text(encoding="utf-8")
wallpaper_service = (modules / "CortetsuWallpapers.qml").read_text(encoding="utf-8")
bar_clock = (modules / "bar/components/Clock.qml").read_text(encoding="utf-8")
status_icons = (modules / "bar/components/StatusIcons.qml").read_text(encoding="utf-8")
vpn_service = (repo / "cortetsu/base/services/VPN.qml").read_text(encoding="utf-8")
battery_monitor = (modules / "BatteryMonitor.qml").read_text(encoding="utf-8")
service_loader = (modules / "ServiceLoader.qml").read_text(encoding="utf-8")
game_mode = (repo / "cortetsu/services/GameMode.qml").read_text(encoding="utf-8")
# Behaviour lives in scripts/features/test-gamemode-runtime.py (nested Hyprland).
assert '"reload"' not in game_mode, "game mode must not reload the whole Hyprland config"
requests = (repo / "cortetsu/services/Requests.qml").read_text(encoding="utf-8")
assert "onExited: code => root.finish(request, code" in requests
assert "onExited: root.finish(request, exitCode" not in requests
weather = (repo / "cortetsu/services/Weather.qml").read_text(encoding="utf-8")
icons = (repo / "cortetsu/utils/Icons.qml").read_text(encoding="utf-8")
sysinfo = (repo / "cortetsu/utils/SysInfo.qml").read_text(encoding="utf-8")
notifs = (repo / "cortetsu/services/Notifs.qml").read_text(encoding="utf-8")
notif_data = (repo / "cortetsu/services/NotifData.qml").read_text(encoding="utf-8")
notification_view = (repo / "cortetsu/modules/notifications/Notification.qml").read_text(encoding="utf-8")
utilities_wrapper = (repo / "cortetsu/modules/utilities/Wrapper.qml").read_text(encoding="utf-8")
colours = (repo / "cortetsu/services/CortetsuColours.qml").read_text(encoding="utf-8")
shell = (repo / "cortetsu/shell.qml").read_text(encoding="utf-8")

assert "pragma Singleton" in config
assert "XDG_CONFIG_HOME" in config and "/cortetsu/preferences.json" in config
for marker in ("favouriteApps", "hiddenApps", "hiddenTrayIcons", "terminalCommand", "audioCommand", "playbackCommand", "explorerCommand", "gpuType", "statusIcons", "quickToggles", "transparencyEnabled", "actionPrefix", "specialPrefix", "actions", "enableDangerousActions", "useFuzzyApps", "useFuzzyWallpapers", "useFuzzyActions", "useFuzzySchemes", "useFuzzyVariants", "smartScheme", "wallpaperDirectory", "wallpaperEnabled", "desktopClockEnabled", "desktopClockPosition", "borderThickness", "useTwelveHourClock", "useFahrenheit", "useFahrenheitPerformance", "weatherLocation", "audioIncrement", "brightnessIncrement", "maxVolume", "visualiserBars", "defaultPlayer", "playerAliases", "toastAudioOutputChanged", "toastAudioInputChanged", "toastNowPlaying", "toastFullscreen", "maxToasts", "toastChargingChanged", "toastCapsLockChanged", "toastNumLockChanged", "toastKbLayoutChanged", "toastKbLimit", "toastVpnChanged", "notificationExpire", "suppressNotificationsInFullscreen", "notificationDefaultExpireTimeout", "notificationFullscreenExpireTimeout", "notificationActionOnClick", "notificationFullscreenMode", "notificationClearThreshold", "notificationExpandThreshold", "notificationGroupPreviewNum", "notificationOpenExpanded", "lockRecolourLogo", "lockHideNotifs", "lockEnableFprint", "lockMaxFprintTries", "lockEnableHowdy", "lockMaxHowdyTries", "lockTriggerHowdyOnWake", "dashboardMediaUpdateInterval", "dashboardResourceUpdateInterval", "nexusWallpapersPerRow", "nexusMaxNetworksShown", "nexusNetworkRescanInterval", "toastDndChanged", "toastGameModeChanged", "vimKeybinds", "workspacesShown", "dashboard", "launcher", "sidebar", "utilities", "bar", "activeIndicator", "activeTrail", "maxWindowIcons", "perMonitorWorkspaces", "scrollActions", "background", "activeWindow", "popouts", "clock", "function load", "function save", "function setFavouriteApps", "function setHiddenApps", "function setHiddenTrayIcons", "function setWorkspacesShown", "function moveStatusIcon", "function removeStatusIcon", "function setStatusIconEnabled", "function insertStatusIcon", "function setQuickToggleEnabled"):
    assert marker in config, marker
assert "entries: bar.entries" in config
assert "CortetsuConfig.bar.workspaces.perMonitorWorkspaces" in hub
assert "bottomHub.statusCluster" in config
assert "bottomHub.segments" in config
assert "function snapshot()" in config
assert "watchChanges: false" in config
assert "patchBottomHubAfterSave" not in config
assert "onSaved:" in config
assert "loaded = false;" in config
snapshot = config.split("function snapshot()", 1)[1].split("function save()", 1)[0]
for retired_bar_preference in (
    "bar.persistent", "scrollActions.workspaces", "scrollActions.brightness",
    "tray.compact", "activeWindow.compact", "clock.showDate",
):
    assert retired_bar_preference not in snapshot, retired_bar_preference
assert "key in bar && typeof data.bar[key] === \"boolean\"" in config
assert 'property bool showDate' not in config and 'property bool persistent' not in config
# The Caelestia migration is finished across the whole tree, not file by file.
all_qml = {path: path.read_text(encoding="utf-8") for path in (repo / "cortetsu").rglob("*.qml")}
for path, text in all_qml.items():
    for legacy in ("import Caelestia", "GlobalConfig", "GlobalCortetsuConfig", "CUtils.", "ServiceRef", "caelestiaLogo"):
        assert legacy not in text, (path, legacy)
consumers = "\n".join(text for path, text in all_qml.items() if path.name != "CortetsuConfig.qml")
for marker in ("CortetsuConfig.dashboard", "CortetsuConfig.launcher", "CortetsuConfig.sidebar", "CortetsuConfig.utilities", "CortetsuConfig.bar", "CortetsuConfig.bar.workspaces", "CortetsuConfig.bar.popouts", "CortetsuConfig.lockEnableFprint", "CortetsuConfig.useFuzzyActions", "CortetsuConfig.useFuzzySchemes"):
    assert marker in consumers, marker
assert "CortetsuConfig.vpn.providers" in vpn_service
# Base code that nothing imported was deleted in phase 3.9; it must not return.
for gone in ("modules/nexus", "modules/dashboard", "modules/sidebar", "modules/windowinfo", "modules/utilities",
             "modules/notifications", "modules/bar/components", "components/filedialog", "components/blobs",
             "components/images", "components/controls", "components/effects"):
    assert not (repo / "cortetsu/base" / gone).exists(), gone
assert not [p for p in (repo / "cortetsu/base/modules/lock").glob("*.qml") if p.name != "Pam.qml"]
assert "noNotifsPic" in (repo / "cortetsu/utils/Paths.qml").read_text(encoding="utf-8")
utils_service = (repo / "cortetsu/utils/CortetsuUtils.qml").read_text(encoding="utf-8")
assert "function clamp" in utils_service and "function deleteFile" in utils_service
assert "caelestia" not in (repo / "cortetsu/base/assets/wrap_term_launch.sh").read_text(encoding="utf-8")
metrics = {
    "Cpu.qml": ("/proc/stat", "property real percentage"),
    "Memory.qml": ("/proc/meminfo", "property real used"),
    "Storage.qml": ('"df", "-kP"', "property list<var> disks"),
    "NetworkUsage.qml": ("/proc/net/dev", "property real downloadSpeed"),
    "Gpu.qml": ("cortetsu-hardware-probe", "property int noneType"),
    "UsageFmt.qml": ("formatKib", "QtObject"),
}
for filename, markers in metrics.items():
    service_text = (repo / "cortetsu/services" / filename).read_text(encoding="utf-8")
    for marker in markers:
        assert marker in service_text, (filename, marker)
# StandardPaths lives in QtCore; without the import QML only fails at run time
# (ReferenceError), as services/Gpu.qml did after 9317563.
for qml in (repo / "cortetsu").rglob("*.qml"):
    qml_text = qml.read_text(encoding="utf-8")
    if "StandardPaths." in qml_text:
        assert re.search(r"^import QtCore\s*$", qml_text, re.M), f"{qml}: StandardPaths without import QtCore"
storage = (repo / "cortetsu/services/Storage.qml").read_text(encoding="utf-8")
assert "match[4].startsWith(\"/\")" in storage
assert "match[5].startsWith(\"/\")" not in storage
session_service = (repo / "cortetsu/services/CortetsuSession.qml").read_text(encoding="utf-8")
assert 'org.freedesktop.login1.Manager' in session_service and 'signal resumed' in session_service
assert "CortetsuSession" in (repo / "cortetsu/base/modules/lock/Pam.qml").read_text(encoding="utf-8")
lyrics_service = (repo / "cortetsu/services/Lyrics.qml").read_text(encoding="utf-8")
for marker in ("parseLrc", "indexForTime", "timeForIndex", "lrclib.net/api/search", "CORTETSU_LYRICS_DIR"):
    assert marker in lyrics_service, marker
assert "GlobalConfig.launcher.favouriteApps" not in hub
assert "GlobalConfig.bar.tray.hiddenIcons" not in hub
assert "GlobalConfig.bar.workspaces.shown" not in hub
assert "import Caelestia" not in desktop_clock
assert "CortetsuRegional.useTwelveHourClock" in desktop_clock
assert "Time.hourStr" in desktop_clock and "Time.format" in desktop_clock
assert "CortetsuConfig.visualiserBars" in spectrum
assert "CortetsuConfig.useFuzzyWallpapers" in wallpaper_service
assert "WallpaperSearch.matches" in wallpaper_service
assert 'command: ["cava"]' in spectrum and '"sh"' not in spectrum
assert 'readonly property bool shouldRun: CortetsuConfig.visualiserEnabled' in spectrum
assert 'running: root.shouldRun' in spectrum
assert 'onRunningChanged: if (!running)' in spectrum
assert "Caelestia" not in spectrum
assert "CortetsuSpectrum.values" in visualiser
assert "VisualiserBars" not in visualiser
assert "Audio.cava" not in visualiser
for legacy in ("Caelestia.Config", "qs.services", "qs.components", "Colours.", "Tokens.", "StyledRect", "StyledText", "MaterialIcon", "GlobalConfig"):
    assert legacy not in bar_clock, legacy
assert "Time.hourStr" in bar_clock and "CortetsuDesign.colorTertiary" in bar_clock
for legacy in ("Caelestia.Config", "qs.services", "qs.components", "Colours.", "Tokens.", "StyledRect", "StyledText", "MaterialIcon", "GlobalConfig"):
    assert legacy not in status_icons, legacy
assert "CortetsuAudio" in status_icons and "CortetsuNetwork" in status_icons and "CortetsuPower" in status_icons
for legacy in ("Caelestia", "GlobalConfig", "Toaster", "SessionManager"):
    assert legacy not in battery_monitor, legacy
assert "CortetsuPower" in battery_monitor
assert "notify-send" in battery_monitor and "CortetsuSession.hibernate()" in battery_monitor
for legacy in ("Caelestia", "GlobalConfig", "GameMode", "Notifs", "Weather", "VPN"):
    assert legacy not in service_loader, legacy
assert "CortetsuAudio" in service_loader and "CortetsuNotifications" in service_loader
for legacy in ("Caelestia", "GlobalConfig", "Toaster", "SessionManager", "Hypr.extras"):
    assert legacy not in game_mode, legacy
assert 'target: "gameMode"' in game_mode
for legacy in ("Caelestia", "GlobalConfig", "Requests.get", "QNetworkAccessManager"):
    assert legacy not in requests, legacy
assert "function get(url, onSuccess, onError, headers = {})" in requests
assert "curl" in requests and "--max-time" in requests and '"20"' in requests
for legacy in ("Caelestia", "GlobalConfig", "CUtils", "Paths.", "Icons.", "qs.utils"):
    assert legacy not in weather, legacy
for marker in ("CortetsuRegional", "Requests.get", "parseForecastResponse", "requestGeneration", "hourlyForecast", "XDG_CACHE_HOME"):
    assert marker in weather, marker
for utility in (icons, sysinfo):
    for legacy in ("Caelestia", "GlobalConfig", "qs.services", "qs.components"):
        assert legacy not in utility, legacy
assert "getAppIcon" in icons and "getBatteryIcon" in icons and "getNotifIcon" in icons
assert "steam_icon_${steamMatch[1]}" in icons and "128x128/apps" in icons
assert "entryIcon.match" in icons and "entryIcon || value" in icons
assert "sanitiseDmi" in sysinfo and "/etc/os-release" in sysinfo
for notification_file in (notifs, notif_data):
    for legacy in ("Caelestia", "GlobalConfig", "qs.services", "qs.components"):
        assert legacy not in notification_file, legacy
assert "NotificationServer" in notifs and "function hasFullscreen" in notifs
assert "function close" in notif_data and "property list<var> actions" in notif_data
for legacy in ("Caelestia", "GlobalConfig", "qs.components", "qs.services"):
    assert legacy not in notification_view, legacy
assert "CortetsuSurface" in notification_view and "modelData.close()" in notification_view
assert "readonly property bool shouldBeActive: false" in utilities_wrapper
assert "modules__utilities__Wrapper.qml.patch" not in utilities_wrapper
assert "readonly property real nonAnimHeight" in utilities_wrapper
vpn = (repo / "cortetsu/base/services/VPN.qml").read_text(encoding="utf-8")
assert "GlobalConfig" not in vpn and "Caelestia" not in vpn
assert "CortetsuConfig.vpn.providers" in vpn and "CortetsuToaster" in vpn
for legacy in ("Caelestia", "GlobalConfig", "qs.services", "qs.components", "Colours.qml"):
    assert legacy not in colours, legacy
assert "Defaults.colorPrimary" in colours and "component CortetsuPalette" in colours
assert 'import "services"' in shell and "import qs.services" not in shell
assert "BottomHub {}" in shell and "settings.watchFiles: false" in shell
assert "import Caelestia" not in visualiser
for marker in ("CortetsuConfig.favouriteApps", "CortetsuConfig.hiddenTrayIcons", "CortetsuConfig.workspacesShown", "CortetsuConfig.setFavouriteApps"):
    assert marker in hub, marker

# The launcher used to finish this migration via four small
# GlobalConfig->CortetsuConfig patches stacked on top of the base launcher
# patches (modules__launcher__CortetsuConfig.qml.patch,
# CortetsuConfigMore, SearchPreferences, RemainingConfig). The launcher is
# now fully first-party under cortetsu/modules/launcher: no GlobalConfig
# anywhere, and those four patch names (plus the four base launcher
# patches they used to sit on top of) are gone for good.
launcher_files = {
    "AppList.qml": app_list,
    "Content.qml": content,
    "ContentList.qml": content_list,
    "Wrapper.qml": wrapper,
    "services/Apps.qml": apps_service,
    "services/Actions.qml": actions_service,
    "services/Schemes.qml": schemes_service,
    "services/M3Variants.qml": variants_service,
}
for name, text in launcher_files.items():
    assert "GlobalConfig" not in text, f"launcher/{name} still references GlobalConfig"

assert "CortetsuConfig.favouriteApps" in app_list
assert "CortetsuConfig.setFavouriteApps" in app_list
assert "CortetsuConfig.actionPrefix" in app_list
assert "CortetsuConfig.terminalCommand" in app_list
assert "CortetsuConfig.hiddenApps" in apps_service
assert "CortetsuConfig.useFuzzyApps" in apps_service
assert "CortetsuConfig.terminalCommand" in apps_service
assert "CortetsuConfig.specialPrefix" in apps_service
assert "CortetsuConfig.actionPrefix" in content
assert "CortetsuConfig.vimKeybinds" in content
assert "CortetsuConfig.actionPrefix" in content_list
assert actions_service.count("CortetsuConfig.actionPrefix") == 2
assert schemes_service.count("CortetsuConfig.actionPrefix") == 1
assert variants_service.count("CortetsuConfig.actionPrefix") == 1
assert "CortetsuConfig.useFuzzyActions" in actions_service
assert "CortetsuConfig.useFuzzySchemes" in schemes_service
assert "CortetsuConfig.useFuzzyApps" in variants_service

gone_patches = (
    "modules__launcher__AppList.qml.patch",
    "modules__launcher__Content.qml.patch",
    "modules__launcher__ContentList.qml.patch",
    "modules__launcher__Wrapper.qml.patch",
    "modules__launcher__services__Apps.qml.patch",
    "modules__launcher__CortetsuConfig.qml.patch",
    "modules__launcher__CortetsuConfigMore.qml.patch",
    "modules__launcher__SearchPreferences.qml.patch",
    "modules__launcher__RemainingConfig.qml.patch",
)
for name in gone_patches:
    assert name not in manifest, f"{name} must not be listed in MANIFEST.tsv anymore"
    assert not (repo / "cortetsu/contracts/patches" / name).exists(), f"{name} must be deleted"

print("PASS: Cortetsu functional preferences use an XDG-owned contract")
