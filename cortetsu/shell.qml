//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QS_DROP_EXPENSIVE_FONTS=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded
//@ pragma DefaultEnv QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import QtQuick
import Quickshell
import "modules"
import "modules/drawers"
import "modules/background"
import "modules/areapicker"
import "modules/lock"
import "modules/pomodoro"
import "services"

ShellRoot {
    id: root
    settings.watchFiles: false
    // Keep the wallpaper lifecycle controller alive with the shell so its
    // monitor-aware IPC contract is available before the first visual open.
    readonly property var wallpaperController: WallpaperController
    // Owns the active scheme and feeds it to the design tokens from startup.
    readonly property var colours: CortetsuColours
    // Owns the Pomodoro daemon and its phase-end toasts from startup.
    readonly property var pomodoro: Pomodoro
    // Restores a saved display colour filter at start.
    readonly property var displayCalibration: DisplayCalibration
    Binding { target: ShellState; property: "shellRoot"; value: root }
    ShellLifecycle {}
    // One coordinator belongs to this shell session. All automation domains
    // remain disabled until the user grants consent in Settings.
    readonly property bool policySessionAvailable: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "").length > 0
        && (Quickshell.env("XDG_RUNTIME_DIR") || "").length > 0
    readonly property var policyBridge: policyBridgeLoader.item
    Loader {
        id: policyBridgeLoader
        active: root.policySessionAvailable
        source: "modules/CortetsuPolicyBridge.qml"
    }
    ServiceLoader {}
    Background {}
    Drawers {}
    BottomHub {}
    AreaPicker {}
    DashboardHost {}
    LauncherHost {}
    SettingsHost {}
    SessionHost { lockController: lock }
    PolkitHost {}
    SecretPromptHost {}
    RetainedSurfacesHost {}
    Lock { id: lock }
    Shortcuts {}
    BatteryMonitor {}
    OverviewController {}
    CalendarController {}
    ClipboardController {}
    HardwareController {}
    KeyboardsController {}
    DisplayController {}
    IdleMonitors { lock: lock }
}
