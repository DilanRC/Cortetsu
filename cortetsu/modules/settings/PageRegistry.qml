pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "controls"
import "pages"
import "sections"
import "bluetooth"
import "display"

// What each destination shows. A page is created only while it is open; the
// sections inside it are the same ones whatever page holds them, and each
// reads and writes its own service.
QtObject {
    id: root

    required property var context
    required property var controller

    function component(id: string): Component {
        const table = {
            home: home, about: about,
            display: display, sound: sound, power: power, shortcuts: shortcuts, capture: capture,
            bluetooth: bluetooth, input: input, wifi: wifi,
            themes: themes, colors: colors, background: background, bottomhub: bottomhub, panels: panels,
            launcher: launcher, notifications: notifications, indicators: indicators,
            automation: automation, weather: weather, motion: motion,
            sync: sync, profiles: profiles, diagnostics: diagnostics
        };
        return table[id] ?? (root.controller.categories.some(item => item.id === id) ? landing : null);
    }

    readonly property Component home: Component { HomePage { context: root.context; controller: root.controller } }
    readonly property Component landing: Component { CategoryPage { context: root.context; controller: root.controller } }
    readonly property Component about: Component { AboutPage { context: root.context } }

    readonly property Component display: Component {
        SettingsPage {
            kind: "wide"
            DisplayPage { context: root.context; Layout.fillWidth: true }
        }
    }
    readonly property Component sound: Component {
        SettingsPage {
            AudioSection { context: root.context }
        }
    }
    readonly property Component power: Component {
        SettingsPage {
            PowerSection { context: root.context }
        }
    }
    readonly property Component shortcuts: Component {
        SettingsPage {
            ShortcutsSection { objectName: "shortcutsSection"; context: root.context }
        }
    }
    readonly property Component capture: Component {
        SettingsPage {
            RecorderSection {}
            ScreenshotSection {}
        }
    }
    readonly property Component bluetooth: Component {
        SettingsPage {
            kind: "wide"
            BluetoothPage { context: root.context; Layout.fillWidth: true }
        }
    }
    readonly property Component input: Component {
        SettingsPage {
            InputSection { context: root.context }
        }
    }
    readonly property Component wifi: Component {
        SettingsPage {
            kind: "wide"
            NetworkPage { context: root.context; Layout.fillWidth: true }
        }
    }

    readonly property Component themes: Component {
        SettingsPage {
            kind: "wide"
            ThemeGallery {}
            SettingsColumns {
                ThemeOptionsSection {}
                ThemeGeometrySection { collapsible: true }
                aside: RelatedSection {
                    controller: root.controller
                    pages: ["colors", "background", "sync", "profiles"]
                }
            }
        }
    }
    readonly property Component colors: Component {
        SettingsPage {
            kind: "wide"
            SchemeSection { context: root.context }
        }
    }
    readonly property Component background: Component {
        SettingsPage {
            WallpaperSection { context: root.context }
            VisualiserSection {}
        }
    }
    readonly property Component bottomhub: Component {
        SettingsPage {
            kind: "wide"
            BottomHubSection { context: root.context }
        }
    }
    readonly property Component panels: Component {
        SettingsPage {
            kind: "wide"
            DashboardSection { context: root.context }
        }
    }

    readonly property Component launcher: Component {
        SettingsPage {
            LauncherSection { context: root.context }
        }
    }
    readonly property Component notifications: Component {
        SettingsPage {
            NotificationsSection { context: root.context }
        }
    }
    readonly property Component indicators: Component {
        SettingsPage {
            OsdSection {}
            ClockUnitsSection {}
        }
    }

    readonly property Component automation: Component {
        SettingsPage {
            AutomationSection { context: root.context }
        }
    }
    readonly property Component weather: Component {
        SettingsPage {
            WeatherSection {}
        }
    }
    readonly property Component motion: Component {
        SettingsPage {
            AccessibilitySection { context: root.context }
        }
    }

    readonly property Component sync: Component {
        SettingsPage {
            IntegrationsSection {}
        }
    }
    readonly property Component profiles: Component {
        SettingsPage {
            ThemeProfileSection {}
            ThemeResetSection {}
        }
    }
    readonly property Component diagnostics: Component {
        SettingsPage {
            DiagnosticsSection { context: root.context }
        }
    }
}
