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
import "services"

ShellRoot {
    id: root
    settings.watchFiles: false
    Binding { target: ShellState; property: "shellRoot"; value: root }
    ServiceLoader {}
    Background {}
    Drawers {}
    BottomHub {}
    AreaPicker {}
    QsdHost {}
    DashboardHost {}
    LauncherHost {}
    SettingsHost {}
    RetainedSurfacesHost {}
    Lock { id: lock }
    Shortcuts {}
    BatteryMonitor {}
    OverviewController {}
    CalendarController {}
    ClipboardController {}
    HardwareController {}
    DisplayController {}
    WallpaperController {}
    IdleMonitors { lock: lock }
}
