from pathlib import Path

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
for marker in ("favouriteApps", "hiddenApps", "hiddenTrayIcons", "terminalCommand", "audioCommand", "playbackCommand", "explorerCommand", "gpuType", "statusIcons", "quickToggles", "transparencyEnabled", "actionPrefix", "specialPrefix", "actions", "enableDangerousActions", "useFuzzyApps", "useFuzzyWallpapers", "useFuzzyActions", "useFuzzySchemes", "useFuzzyVariants", "smartScheme", "wallpaperDirectory", "wallpaperEnabled", "desktopClockEnabled", "desktopClockPosition", "borderThickness", "useTwelveHourClock", "useFahrenheit", "useFahrenheitPerformance", "weatherLocation", "audioIncrement", "brightnessIncrement", "maxVolume", "visualiserBars", "defaultPlayer", "playerAliases", "toastAudioOutputChanged", "toastAudioInputChanged", "toastNowPlaying", "toastFullscreen", "maxToasts", "toastChargingChanged", "toastCapsLockChanged", "toastNumLockChanged", "toastKbLayoutChanged", "toastKbLimit", "toastVpnChanged", "notificationExpire", "suppressNotificationsInFullscreen", "notificationDefaultExpireTimeout", "notificationFullscreenExpireTimeout", "notificationActionOnClick", "notificationFullscreenMode", "notificationClearThreshold", "notificationExpandThreshold", "notificationGroupPreviewNum", "notificationOpenExpanded", "lockRecolourLogo", "lockHideNotifs", "lockEnableFprint", "lockMaxFprintTries", "lockEnableHowdy", "lockMaxHowdyTries", "lockTriggerHowdyOnWake", "dashboardMediaUpdateInterval", "dashboardResourceUpdateInterval", "nexusWallpapersPerRow", "nexusMaxNetworksShown", "nexusNetworkRescanInterval", "toastDndChanged", "toastGameModeChanged", "vimKeybinds", "workspacesShown", "dashboard", "launcher", "sidebar", "utilities", "bar", "activeIndicator", "activeTrail", "maxWindowIcons", "perMonitorWorkspaces", "persistent", "scrollActions", "background", "activeWindow", "popouts", "clock", "function load", "function save", "function setFavouriteApps", "function setHiddenApps", "function setHiddenTrayIcons", "function setWorkspacesShown", "function moveStatusIcon", "function removeStatusIcon", "function setStatusIconEnabled", "function insertStatusIcon", "function setQuickToggleEnabled"):
    assert marker in config, marker
assert "entries: bar.entries" in config
assert "CortetsuConfig.bar.workspaces.perMonitorWorkspaces" in hub
assert "bottomHub.statusCluster" in config
assert "bottomHub.segments" in config
assert "saveLegacy();" in config
assert "payload.bottomHub" in config
assert "loaded = false;" in config
assert "bar: { persistent: bar.persistent" in config
panel_sources = "\n".join(path.read_text(encoding="utf-8") for path in (repo / "cortetsu/base/modules/nexus/pages/panels").glob("*.qml"))
workspace_sources = "\n".join(path.read_text(encoding="utf-8") for path in (repo / "cortetsu/base/modules/bar/components/workspaces").glob("*.qml"))
bar_sources = "\n".join(path.read_text(encoding="utf-8") for path in (repo / "cortetsu/base/modules/bar").rglob("*.qml"))
nexus_sources = "\n".join(path.read_text(encoding="utf-8") for path in (repo / "cortetsu/base/modules/nexus/pages").rglob("*.qml"))
lock_sources = "\n".join(path.read_text(encoding="utf-8") for path in (repo / "cortetsu/base/modules/lock").rglob("*.qml"))
for marker in ("CortetsuConfig.dashboard", "CortetsuConfig.launcher", "CortetsuConfig.sidebar", "CortetsuConfig.utilities", "CortetsuConfig.bar", "CortetsuConfig.bar.workspaces", "CortetsuConfig.bar.tray", "CortetsuConfig.bar.activeWindow", "CortetsuConfig.bar.popouts", "CortetsuConfig.bar.clock", "CortetsuConfig.toastFullscreen", "CortetsuConfig.maxToasts", "CortetsuConfig.lockRecolourLogo", "CortetsuConfig.lockEnableFprint", "CortetsuConfig.notificationGroupPreviewNum", "CortetsuConfig.dashboardMediaUpdateInterval", "CortetsuConfig.nexusNetworkRescanInterval", "CortetsuConfig.useFuzzyActions", "CortetsuConfig.useFuzzySchemes", "CortetsuConfig.useFuzzyVariants", "CortetsuConfig.audioCommand", "CortetsuConfig.playbackCommand", "CortetsuConfig.explorerCommand", "CortetsuConfig.gpuType", "CortetsuConfig.statusIcons", "CortetsuConfig.quickToggles"):
    assert marker in (panel_sources + workspace_sources + bar_sources + nexus_sources + lock_sources), marker
assert "CortetsuConfig.vpn.providers" in vpn_service
toggles = (repo / "cortetsu/base/modules/utilities/cards/Toggles.qml").read_text(encoding="utf-8")
assert "Caelestia" not in toggles and "GlobalConfig" not in toggles
wallpaper_style = (repo / "cortetsu/base/modules/nexus/pages/WallpaperAndStyle.qml").read_text(encoding="utf-8")
assert "GlobalConfig" not in wallpaper_style and "GlobalCortetsuConfig" not in wallpaper_style
assert "CortetsuConfig.transparencyEnabled" in wallpaper_style
notifications_page = (repo / "cortetsu/base/modules/nexus/pages/services/NotificationsPage.qml").read_text(encoding="utf-8")
assert "GlobalCortetsuConfig" not in notifications_page
assert "CortetsuConfig.notificationGroupPreviewNum" in notifications_page
fetch = (repo / "cortetsu/base/modules/lock/Fetch.qml").read_text(encoding="utf-8")
assert "import Caelestia" not in fetch and "CUtils.clamp" not in fetch
assert "function clamp(value: real, low: real, high: real)" in fetch
cached_image = (repo / "cortetsu/base/components/images/CachingImage.qml").read_text(encoding="utf-8")
coloured_icon = (repo / "cortetsu/base/components/effects/ColouredIcon.qml").read_text(encoding="utf-8")
assert "import Caelestia.Images" not in cached_image and "IUtils." not in cached_image
assert "Paths.absolutePath(path)" in cached_image
assert "import Caelestia.Images" not in coloured_icon and "ImageAnalyser" not in coloured_icon
assert 'sourceColor: "black"' in coloured_icon and "Colouriser" in coloured_icon
cover_visualiser = (repo / "cortetsu/base/modules/dashboard/media/CoverVisualiser.qml").read_text(encoding="utf-8")
assert "import Caelestia.Services" not in cover_visualiser and "ServiceRef" not in cover_visualiser
assert "Audio.cava" in cover_visualiser
for wallpaper_page in (
    repo / "cortetsu/base/modules/nexus/pages/wallandstyle/WallpaperCategory.qml",
    repo / "cortetsu/base/modules/nexus/pages/wallandstyle/WallpaperSelect.qml",
):
    wallpaper_text = wallpaper_page.read_text(encoding="utf-8")
    assert "import Caelestia.Models" not in wallpaper_text
    assert "FileSystemEntry" not in wallpaper_text
file_model = (repo / "cortetsu/base/components/filedialog/FileSystemModel.qml").read_text(encoding="utf-8")
assert "ListModel" in file_model and "find --" in file_model
assert "nameFilters" in file_model and "sortReverse" in file_model
for blob_name in ("BlobGroup.qml", "BlobRect.qml", "BlobInvertedRect.qml"):
    blob = repo / "cortetsu/base/components/blobs" / blob_name
    assert blob.is_file()
    blob_text = blob.read_text(encoding="utf-8")
    assert "property var group" in blob_text or blob_name == "BlobGroup.qml"
for blob_consumer in (
    repo / "cortetsu/base/modules/nexus/Nexus.qml",
    repo / "cortetsu/base/modules/nexus/common/BlobPopup.qml",
    repo / "cortetsu/base/modules/nexus/common/DialogRowButton.qml",
    repo / "cortetsu/base/modules/dashboard/media/LyricsInfo.qml",
):
    assert "import Caelestia.Blobs" not in blob_consumer.read_text(encoding="utf-8")
for model_consumer in (
    repo / "cortetsu/base/components/filedialog/FolderContents.qml",
    repo / "cortetsu/base/modules/utilities/cards/RecordingList.qml",
):
    model_text = model_consumer.read_text(encoding="utf-8")
    assert "import Caelestia.Models" not in model_text
    assert "FileSystemEntry" not in model_text
assert "import qs.components.filedialog" in (repo / "cortetsu/base/modules/utilities/cards/RecordingList.qml").read_text(encoding="utf-8")
bar_source = (repo / "cortetsu/base/modules/bar/Bar.qml").read_text(encoding="utf-8")
workspace_source = (repo / "cortetsu/base/modules/bar/components/workspaces/Workspace.qml").read_text(encoding="utf-8")
assert "import Caelestia.Config" not in bar_source and "CortetsuConfig.bar.entries" in bar_source
assert "import Caelestia.Config" not in workspace_source and "CortetsuConfig.bar.workspaces" in workspace_source
for notif_dock in (
    repo / "cortetsu/base/modules/lock/NotifDock.qml",
    repo / "cortetsu/base/modules/sidebar/NotifDock.qml",
):
    dock_text = notif_dock.read_text(encoding="utf-8")
    assert "import Caelestia.Config" not in dock_text
assert "noNotifsPic" in (repo / "cortetsu/utils/Paths.qml").read_text(encoding="utf-8")
utils_service = (repo / "cortetsu/utils/CortetsuUtils.qml").read_text(encoding="utf-8")
assert "function clamp" in utils_service and "function deleteFile" in utils_service
assert "Caelestia" not in "\n".join(
    (repo / path).read_text(encoding="utf-8")
    for path in (
        "cortetsu/base/modules/utilities/RecordingDeleteModal.qml",
        "cortetsu/base/modules/notifications/Content.qml",
        "cortetsu/base/modules/dashboard/Content.qml",
        "cortetsu/base/modules/nexus/pages/AboutPage.qml",
    )
)
assert "caelestia" not in (repo / "cortetsu/base/assets/wrap_term_launch.sh").read_text(encoding="utf-8")
for logo_consumer in (
    repo / "cortetsu/base/modules/lock/Fetch.qml",
    repo / "cortetsu/base/modules/dashboard/dash/User.qml",
    repo / "cortetsu/base/modules/bar/components/OsIcon.qml",
):
    logo_text = logo_consumer.read_text(encoding="utf-8")
    assert "caelestiaLogo" not in logo_text and "caelestiafetch" not in logo_text, logo_consumer
metrics = {
    "Cpu.qml": ("/proc/stat", "property real percentage"),
    "Memory.qml": ("/proc/meminfo", "property real used"),
    "Storage.qml": ("df -kP", "property list<var> disks"),
    "NetworkUsage.qml": ("/proc/net/dev", "property real downloadSpeed"),
    "Gpu.qml": ("nvidia-smi", "property int noneType"),
    "UsageFmt.qml": ("formatKib", "QtObject"),
}
for filename, markers in metrics.items():
    service_text = (repo / "cortetsu/services" / filename).read_text(encoding="utf-8")
    for marker in markers:
        assert marker in service_text, (filename, marker)
for metric_consumer in (
    repo / "cortetsu/base/modules/dashboard/Performance.qml",
    repo / "cortetsu/base/modules/dashboard/dash/Resources.qml",
    repo / "cortetsu/base/modules/dashboard/performance/BatteryTank.qml",
    repo / "cortetsu/base/modules/dashboard/performance/MemoryCard.qml",
    repo / "cortetsu/base/modules/dashboard/performance/NetworkCard.qml",
    repo / "cortetsu/base/modules/dashboard/performance/StorageCard.qml",
    repo / "cortetsu/base/modules/lock/Resources.qml",
):
    metric_text = metric_consumer.read_text(encoding="utf-8")
    assert "import Caelestia.Services" not in metric_text, metric_consumer
    assert "ServiceRef" not in metric_text, metric_consumer
assert "SparklineItem" not in (repo / "cortetsu/base/modules/dashboard/performance/NetworkCard.qml").read_text(encoding="utf-8")
session_service = (repo / "cortetsu/services/CortetsuSession.qml").read_text(encoding="utf-8")
assert 'org.freedesktop.login1.Manager' in session_service and 'signal resumed' in session_service
assert "import Caelestia.Services" not in (repo / "cortetsu/base/modules/lock/Pam.qml").read_text(encoding="utf-8")
assert "CortetsuSession" in (repo / "cortetsu/base/modules/lock/Pam.qml").read_text(encoding="utf-8")
lyrics_service = (repo / "cortetsu/services/Lyrics.qml").read_text(encoding="utf-8")
for marker in ("parseLrc", "indexForTime", "timeForIndex", "lrclib.net/api/search", "CORTETSU_LYRICS_DIR"):
    assert marker in lyrics_service, marker
for lyrics_consumer in (
    repo / "cortetsu/base/modules/dashboard/media/LyricList.qml",
    repo / "cortetsu/base/modules/dashboard/media/LyricsInfo.qml",
):
    assert "import Caelestia" not in lyrics_consumer.read_text(encoding="utf-8"), lyrics_consumer
apps_page = (repo / "cortetsu/base/modules/nexus/pages/AppsPage.qml").read_text(encoding="utf-8")
assert "import Caelestia\n" not in apps_page and "CUtils.clamp" not in apps_page
for path in (
    repo / "cortetsu/base/modules/utilities/cards/RecordingList.qml",
    repo / "cortetsu/base/modules/sidebar/NotifDock.qml",
    repo / "cortetsu/base/modules/nexus/pages/AppsPage.qml",
    repo / "cortetsu/base/modules/lock/Pam.qml",
    repo / "cortetsu/base/modules/nexus/pages/ServicesPage.qml",
    repo / "cortetsu/base/modules/lock/center/PasswordInput.qml",
    repo / "cortetsu/base/modules/nexus/pages/WallpaperAndStyle.qml",
    repo / "cortetsu/base/modules/lock/center/StateMessage.qml",
    repo / "cortetsu/base/modules/launcher/items/CalcItem.qml",
    repo / "cortetsu/base/modules/nexus/pages/panels/UtilitiesPanel.qml",
    repo / "cortetsu/base/modules/nexus/pages/panels/taskbar/BarStatusIcons.qml",
    repo / "cortetsu/base/modules/bar/popouts/kblayout/KbLayoutModel.qml",
):
    assert "import Caelestia.Config" not in path.read_text(encoding="utf-8"), path
assert "import Caelestia" not in (repo / "cortetsu/base/modules/launcher/items/CalcItem.qml").read_text(encoding="utf-8")
assert "import Caelestia" not in (repo / "cortetsu/base/modules/bar/popouts/kblayout/KbLayoutModel.qml").read_text(encoding="utf-8")
button_row = (repo / "cortetsu/base/components/controls/ButtonRow.qml").read_text(encoding="utf-8")
assert "RowLayout" in button_row and "property real spacing" in button_row
for primitive in ("CircularIndicatorManager.qml", "LinearIndicatorManager.qml"):
    assert (repo / "cortetsu/base/components/controls" / primitive).is_file()
assert (repo / "cortetsu/base/components/controls/WavyLine.qml").is_file()
assert (repo / "cortetsu/base/components/controls/LinearIndicatorSegment.qml").is_file()
for primitive in ("CircularIndicator.qml", "CircularProgress.qml", "StyledProgressBar.qml", "StyledSlider.qml"):
    primitive_text = (repo / "cortetsu/base/components/controls" / primitive).read_text(encoding="utf-8")
    assert "Caelestia.Components" not in primitive_text and "CUtils.clamp" not in primitive_text
assert "GlobalConfig.launcher.favouriteApps" not in hub
assert "GlobalConfig.bar.tray.hiddenIcons" not in hub
assert "GlobalConfig.bar.workspaces.shown" not in hub
assert "import Caelestia" not in desktop_clock
assert "CortetsuRegional.useTwelveHourClock" in desktop_clock
assert "Time.hourStr" in desktop_clock and "Time.format" in desktop_clock
assert "CortetsuConfig.visualiserBars" in spectrum
assert "CortetsuConfig.useFuzzyWallpapers" in wallpaper_service
assert "WallpaperSearch.matches" in wallpaper_service
assert "command -v cava" in spectrum
assert "Caelestia" not in spectrum
assert "CortetsuSpectrum.values" in visualiser
assert "VisualiserBars" not in visualiser
assert "Audio.cava" not in visualiser
for legacy in ("Caelestia.Config", "qs.services", "qs.components", "Colours.", "Tokens.", "StyledRect", "StyledText", "MaterialIcon", "GlobalConfig"):
    assert legacy not in bar_clock, legacy
assert "Time.hourStr" in bar_clock and "CortetsuDesign.colorTertiary" in bar_clock
for legacy in ("Caelestia.Config", "qs.services", "qs.components", "Colours.", "Tokens.", "StyledRect", "StyledText", "MaterialIcon", "GlobalConfig"):
    assert legacy not in status_icons, legacy
assert "CortetsuAudio" in status_icons and "CortetsuNetwork" in status_icons and "UPower" in status_icons
for legacy in ("Caelestia", "GlobalConfig", "Toaster", "SessionManager"):
    assert legacy not in battery_monitor, legacy
assert "Quickshell.Services.UPower" in battery_monitor
assert "notify-send" in battery_monitor and '"systemctl", "hibernate"' in battery_monitor
for legacy in ("Caelestia", "GlobalConfig", "GameMode", "Notifs", "Weather", "VPN"):
    assert legacy not in service_loader, legacy
assert "CortetsuAudio" in service_loader and "CortetsuNotifications" in service_loader
for legacy in ("Caelestia", "GlobalConfig", "Toaster", "SessionManager", "Hypr.extras"):
    assert legacy not in game_mode, legacy
assert "CortetsuHypr.dispatch" in game_mode and "target: \"gameMode\"" in game_mode
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
assert "sanitiseDmi" in sysinfo and "/etc/os-release" in sysinfo
for notification_file in (notifs, notif_data):
    for legacy in ("Caelestia", "GlobalConfig", "qs.services", "qs.components"):
        assert legacy not in notification_file, legacy
assert "NotificationServer" in notifs and "function hasFullscreen" in notifs
assert "function close" in notif_data and "property list<var> actions" in notif_data
for legacy in ("Caelestia", "GlobalConfig", "qs.components", "qs.services"):
    assert legacy not in notification_view, legacy
assert "CortetsuSurface" in notification_view and "modelData.close()" in notification_view
assert "CortetsuConfig" in utilities_wrapper and "modules__utilities__Wrapper.qml.patch" not in utilities_wrapper
assert "readonly property real nonAnimHeight" in utilities_wrapper
vpn = (repo / "cortetsu/base/services/VPN.qml").read_text(encoding="utf-8")
assert "GlobalConfig" not in vpn and "Caelestia" not in vpn
assert "CortetsuConfig.vpn.providers" in vpn and "CortetsuToaster" in vpn
for legacy in ("Caelestia", "GlobalConfig", "qs.services", "qs.components", "Colours.qml"):
    assert legacy not in colours, legacy
assert "CortetsuDesign.colorPrimary" in colours and "component CortetsuPalette" in colours
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
for svc in (actions_service, schemes_service, variants_service):
    assert "CortetsuConfig.useFuzzyApps" in svc, "search services must share the unified useFuzzyApps flag"

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
