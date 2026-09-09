pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io

// Functional preferences owned by Cortetsu. Design tokens remain separate.
QtObject {
    id: root

    readonly property string path: `${Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`}/cortetsu/preferences.json`
    property list<string> favouriteApps: []
    property list<string> hiddenApps: []
    property list<string> hiddenTrayIcons: []
    property list<string> terminalCommand: ["kitty"]
    onTerminalCommandChanged: if (loaded) save()
    property list<string> audioCommand: ["pwvucontrol"]
    onAudioCommandChanged: if (loaded) save()
    property list<string> playbackCommand: ["mpv"]
    onPlaybackCommandChanged: if (loaded) save()
    property list<string> explorerCommand: ["dolphin"]
    onExplorerCommandChanged: if (loaded) save()
    property int gpuType: 0
    onGpuTypeChanged: if (loaded) save()
    property int lyricsBackend: 0
    onLyricsBackendChanged: if (loaded) save()
    property list<var> statusIcons: [
        { id: "lockStatus", enabled: true },
        { id: "audio", enabled: false },
        { id: "microphone", enabled: false },
        { id: "kbLayout", enabled: false },
        { id: "network", enabled: true },
        { id: "bluetooth", enabled: true },
        { id: "battery", enabled: true }
    ]
    onStatusIconsChanged: if (loaded) save()
    property list<var> quickToggles: [
        { id: "wifi", enabled: true },
        { id: "bluetooth", enabled: true },
        { id: "mic", enabled: true },
        { id: "settings", enabled: true },
        { id: "gameMode", enabled: true },
        { id: "dnd", enabled: true },
        { id: "vpn", enabled: true }
    ]
    onQuickTogglesChanged: if (loaded) save()
    readonly property QtObject vpn: QtObject {
        property list<var> providers: []
        onProvidersChanged: if (root.loaded) root.save()
        property string selectedProvider: ""
        onSelectedProviderChanged: if (root.loaded) root.save()
        property bool enabled: false
        onEnabledChanged: if (root.loaded) root.save()
    }
    property string actionPrefix: ">"
    property string specialPrefix: "@"
    property var actions: []
    property bool enableDangerousActions: true
    property bool useFuzzyApps: true
    property bool useFuzzyWallpapers: true
    property bool useFuzzyActions: true
    onUseFuzzyActionsChanged: if (loaded) save()
    property bool useFuzzySchemes: true
    onUseFuzzySchemesChanged: if (loaded) save()
    property bool useFuzzyVariants: true
    onUseFuzzyVariantsChanged: if (loaded) save()
    property bool smartScheme: true
    property string wallpaperDirectory: "~/Pictures/Wallpapers"
    property bool wallpaperEnabled: true
    property bool transparencyEnabled: false
    onTransparencyEnabledChanged: if (loaded) save()
    property bool desktopClockEnabled: false
    property string desktopClockPosition: "topLeft"
    property int borderThickness: 1
    property bool borderSmoothing: true
    property bool useTwelveHourClock: false
    property bool useFahrenheit: false
    property bool useFahrenheitPerformance: false
    property string weatherLocation: ""
    property real audioIncrement: 0.1
    property real brightnessIncrement: 0.1
    property real maxVolume: 1.0
    property int visualiserBars: 60
    property bool visualiserEnabled: false
    property bool visualiserAutoHide: true
    property bool visualiserBlur: false
    property real visualiserSpacing: 1
    property real visualiserRounding: 1
    property string defaultPlayer: "Spotify"
    property var playerAliases: [{ from: "com.github.th_ch.youtube_music", to: "YT Music" }]
    property bool toastAudioOutputChanged: true
    property bool toastAudioInputChanged: true
    property bool toastNowPlaying: false
    property string toastFullscreen: "off"
    onToastFullscreenChanged: if (loaded) save()
    property int maxToasts: 4
    onMaxToastsChanged: if (loaded) save()
    property bool toastChargingChanged: true
    onToastChargingChanged: if (loaded) save()
    property bool toastCapsLockChanged: true
    onToastCapsLockChanged: if (loaded) save()
    property bool toastNumLockChanged: true
    onToastNumLockChanged: if (loaded) save()
    property bool toastKbLayoutChanged: true
    onToastKbLayoutChanged: if (loaded) save()
    property bool toastKbLimit: true
    onToastKbLimitChanged: if (loaded) save()
    property bool toastVpnChanged: true
    onToastVpnChanged: if (loaded) save()
    property bool notificationExpire: true
    onNotificationExpireChanged: if (loaded) save()
    property bool suppressNotificationsInFullscreen: false
    property int notificationDefaultExpireTimeout: 5000
    onNotificationDefaultExpireTimeoutChanged: if (loaded) save()
    property int notificationFullscreenExpireTimeout: 2000
    property bool notificationActionOnClick: false
    property int notificationFullscreenMode: 0
    onNotificationFullscreenModeChanged: if (loaded) save()
    property real notificationClearThreshold: 0.3
    onNotificationClearThresholdChanged: if (loaded) save()
    property int notificationExpandThreshold: 20
    onNotificationExpandThresholdChanged: if (loaded) save()
    property int notificationGroupPreviewNum: 3
    onNotificationGroupPreviewNumChanged: if (loaded) save()
    property bool notificationOpenExpanded: false
    onNotificationOpenExpandedChanged: if (loaded) save()
    property bool toastDndChanged: true
    property bool toastGameModeChanged: true
    property bool lockRecolourLogo: true
    onLockRecolourLogoChanged: if (loaded) save()
    property bool lockHideNotifs: false
    onLockHideNotifsChanged: if (loaded) save()
    property bool lockEnableFprint: true
    onLockEnableFprintChanged: if (loaded) save()
    property int lockMaxFprintTries: 3
    onLockMaxFprintTriesChanged: if (loaded) save()
    property bool lockEnableHowdy: true
    onLockEnableHowdyChanged: if (loaded) save()
    property int lockMaxHowdyTries: 3
    onLockMaxHowdyTriesChanged: if (loaded) save()
    property bool lockTriggerHowdyOnWake: true
    onLockTriggerHowdyOnWakeChanged: if (loaded) save()
    property bool vimKeybinds: true
    property int workspacesShown: 5
    property int dashboardMediaUpdateInterval: 500
    onDashboardMediaUpdateIntervalChanged: if (loaded) save()
    property int dashboardResourceUpdateInterval: 1000
    onDashboardResourceUpdateIntervalChanged: if (loaded) save()
    property int nexusWallpapersPerRow: 4
    onNexusWallpapersPerRowChanged: if (loaded) save()
    property int nexusMaxNetworksShown: 5
    onNexusMaxNetworksShownChanged: if (loaded) save()
    property int nexusNetworkRescanInterval: 15000
    onNexusNetworkRescanIntervalChanged: if (loaded) save()
    property bool idleInhibitWhenAudio: true
    property bool idleInhibitWhenCharging: false
    property bool idleLockBeforeSleep: true
    property list<var> idleTimeouts: [{ enabled: true, timeout: 900000, respectInhibitors: true, idleAction: "lock", returnAction: "unlock" }]
    property bool loaded: false

    readonly property QtObject dashboard: QtObject {
        property bool enabled: true
        onEnabledChanged: if (root.loaded) root.save()
        property bool showOnHover: true
        onShowOnHoverChanged: if (root.loaded) root.save()
        property bool showDashboard: true
        onShowDashboardChanged: if (root.loaded) root.save()
        property bool showMedia: true
        onShowMediaChanged: if (root.loaded) root.save()
        property bool showPerformance: true
        onShowPerformanceChanged: if (root.loaded) root.save()
        property bool showWeather: true
        onShowWeatherChanged: if (root.loaded) root.save()
        property int dragThreshold: 24
        onDragThresholdChanged: if (root.loaded) root.save()
        readonly property QtObject performance: QtObject {
            property bool showCpu: true
            onShowCpuChanged: if (root.loaded) root.save()
            property bool showGpu: true
            onShowGpuChanged: if (root.loaded) root.save()
            property bool showMemory: true
            onShowMemoryChanged: if (root.loaded) root.save()
            property bool showStorage: true
            onShowStorageChanged: if (root.loaded) root.save()
            property bool showNetwork: true
            onShowNetworkChanged: if (root.loaded) root.save()
            property bool showBattery: true
            onShowBatteryChanged: if (root.loaded) root.save()
        }
    }

    readonly property QtObject launcher: QtObject {
        property bool enabled: true
        onEnabledChanged: if (root.loaded) root.save()
        property bool showOnHover: false
        onShowOnHoverChanged: if (root.loaded) root.save()
        property int maxShown: 8
        onMaxShownChanged: if (root.loaded) root.save()
        property int maxWallpapers: 8
        onMaxWallpapersChanged: if (root.loaded) root.save()
        property int dragThreshold: 24
        onDragThresholdChanged: if (root.loaded) root.save()
    }

    readonly property QtObject sidebar: QtObject {
        property bool enabled: true
        onEnabledChanged: if (root.loaded) root.save()
        property bool showOnHover: true
        onShowOnHoverChanged: if (root.loaded) root.save()
        property int dragThreshold: 24
        onDragThresholdChanged: if (root.loaded) root.save()
        property int minHoverThreshold: 24
        onMinHoverThresholdChanged: if (root.loaded) root.save()
    }

    readonly property QtObject utilities: QtObject {
        property bool enabled: true
        onEnabledChanged: if (root.loaded) root.save()
        readonly property QtObject cards: QtObject {
            property bool keepAwake: true
            onKeepAwakeChanged: if (root.loaded) root.save()
            property bool recorder: true
            onRecorderChanged: if (root.loaded) root.save()
            property bool quickToggles: true
            onQuickTogglesChanged: if (root.loaded) root.save()
        }
    }

    readonly property QtObject bar: QtObject {
        property bool persistent: false
        onPersistentChanged: if (root.loaded) root.save()
        property bool showOnHover: false
        onShowOnHoverChanged: if (root.loaded) root.save()
        property int dragThreshold: 24
        onDragThresholdChanged: if (root.loaded) root.save()
        readonly property QtObject scrollActions: QtObject {
            property bool workspaces: true
            onWorkspacesChanged: if (root.loaded) root.save()
            property bool volume: true
            onVolumeChanged: if (root.loaded) root.save()
            property bool brightness: true
            onBrightnessChanged: if (root.loaded) root.save()
        }
        readonly property QtObject tray: QtObject {
            property bool background: true
            onBackgroundChanged: if (root.loaded) root.save()
            property bool compact: false
            onCompactChanged: if (root.loaded) root.save()
            property bool recolour: false
            onRecolourChanged: if (root.loaded) root.save()
        }
        readonly property QtObject activeWindow: QtObject {
            property bool compact: true
            onCompactChanged: if (root.loaded) root.save()
            property bool inverted: false
            onInvertedChanged: if (root.loaded) root.save()
            property bool showOnHover: false
            onShowOnHoverChanged: if (root.loaded) root.save()
        }
        readonly property QtObject popouts: QtObject {
            property bool activeWindow: true
            onActiveWindowChanged: if (root.loaded) root.save()
            property bool statusIcons: true
            onStatusIconsChanged: if (root.loaded) root.save()
            property bool tray: true
            onTrayChanged: if (root.loaded) root.save()
        }
        readonly property QtObject clock: QtObject {
            property bool background: true
            onBackgroundChanged: if (root.loaded) root.save()
            property bool showDate: false
            onShowDateChanged: if (root.loaded) root.save()
            property bool showIcon: false
            onShowIconChanged: if (root.loaded) root.save()
        }
        readonly property QtObject workspaces: QtObject {
            property bool activeIndicator: true
            onActiveIndicatorChanged: if (root.loaded) root.save()
            property bool activeTrail: false
            onActiveTrailChanged: if (root.loaded) root.save()
            property bool occupiedBg: false
            onOccupiedBgChanged: if (root.loaded) root.save()
            property bool showWindows: false
            onShowWindowsChanged: if (root.loaded) root.save()
            property bool showWindowsOnSpecialWorkspaces: true
            onShowWindowsOnSpecialWorkspacesChanged: if (root.loaded) root.save()
            property int maxWindowIcons: 5
            onMaxWindowIconsChanged: if (root.loaded) root.save()
            property bool perMonitorWorkspaces: true
            onPerMonitorWorkspacesChanged: if (root.loaded) root.save()
            property int displayType: 0 // 0 = shapes, 1 = text
            property string label: "  "
            property string occupiedLabel: "󰮯"
            property string activeLabel: "󰮯"
            property int capitalisation: 0 // 0 = preserve, 1 = upper, 2 = lower
        }
        property list<var> entries: [
            { id: "logo", enabled: true },
            { id: "workspaces", enabled: true },
            { id: "spacer", enabled: true },
            { id: "activeWindow", enabled: true },
            { id: "spacer", enabled: true },
            { id: "tray", enabled: true },
            { id: "clock", enabled: true },
            { id: "statusIcons", enabled: true },
            { id: "power", enabled: true }
        ]
    }

    function load(raw: string): void {
        try {
            const data = JSON.parse(raw);
            if (Array.isArray(data.favouriteApps))
                favouriteApps = data.favouriteApps.filter(value => typeof value === "string");
            if (Array.isArray(data.hiddenApps))
                hiddenApps = data.hiddenApps.filter(value => typeof value === "string");
            if (Array.isArray(data.hiddenTrayIcons))
                hiddenTrayIcons = data.hiddenTrayIcons.filter(value => typeof value === "string");
            if (Array.isArray(data.terminalCommand))
                terminalCommand = data.terminalCommand.filter(value => typeof value === "string");
            for (const key of ["audioCommand", "playbackCommand", "explorerCommand"])
                if (Array.isArray(data[key])) root[key] = data[key].filter(value => typeof value === "string");
            if (Number.isInteger(data.gpuType))
                gpuType = Math.max(0, Math.min(4, data.gpuType));
            if (Number.isInteger(data.lyricsBackend))
                lyricsBackend = Math.max(0, Math.min(3, data.lyricsBackend));
            if (Array.isArray(data.statusIcons))
                statusIcons = data.statusIcons.filter(value => value && typeof value === "object" && typeof value.id === "string").map(value => ({ id: value.id, enabled: value.enabled !== false }));
            if (Array.isArray(data.quickToggles))
                quickToggles = data.quickToggles.filter(value => value && typeof value === "object" && typeof value.id === "string").map(value => ({ id: value.id, enabled: value.enabled !== false }));
            if (data.vpn && typeof data.vpn === "object") {
                if (Array.isArray(data.vpn.providers))
                    vpn.providers = data.vpn.providers.filter(value => typeof value === "string" || (value && typeof value === "object" && typeof value.name === "string"));
                if (typeof data.vpn.selectedProvider === "string")
                    vpn.selectedProvider = data.vpn.selectedProvider;
                if (typeof data.vpn.enabled === "boolean")
                    vpn.enabled = data.vpn.enabled;
            }
            if (Array.isArray(data.actions))
                actions = data.actions.filter(value => value && typeof value === "object");
            if (typeof data.actionPrefix === "string" && data.actionPrefix.length > 0)
                actionPrefix = data.actionPrefix;
            if (typeof data.specialPrefix === "string" && data.specialPrefix.length > 0)
                specialPrefix = data.specialPrefix;
            if (typeof data.enableDangerousActions === "boolean")
                enableDangerousActions = data.enableDangerousActions;
            if (typeof data.useFuzzyApps === "boolean")
                useFuzzyApps = data.useFuzzyApps;
            if (typeof data.useFuzzyWallpapers === "boolean")
                useFuzzyWallpapers = data.useFuzzyWallpapers;
            if (typeof data.useFuzzyActions === "boolean")
                useFuzzyActions = data.useFuzzyActions;
            if (typeof data.useFuzzySchemes === "boolean")
                useFuzzySchemes = data.useFuzzySchemes;
            if (typeof data.useFuzzyVariants === "boolean")
                useFuzzyVariants = data.useFuzzyVariants;
            for (const key of ["lockRecolourLogo", "lockHideNotifs", "lockEnableFprint", "lockEnableHowdy", "lockTriggerHowdyOnWake"])
                if (typeof data[key] === "boolean") root[key] = data[key];
            for (const key of ["lockMaxFprintTries", "lockMaxHowdyTries"])
                if (Number.isInteger(data[key])) root[key] = Math.max(1, Math.min(20, data[key]));
            if (typeof data.toastFullscreen === "string" && ["off", "important", "all"].includes(data.toastFullscreen))
                toastFullscreen = data.toastFullscreen;
            if (Number.isInteger(data.maxToasts))
                maxToasts = Math.max(1, Math.min(20, data.maxToasts));
            for (const key of ["toastChargingChanged", "toastCapsLockChanged", "toastNumLockChanged", "toastKbLayoutChanged", "toastKbLimit", "toastVpnChanged"])
                if (typeof data[key] === "boolean") root[key] = data[key];
            if (typeof data.notificationExpire === "boolean")
                notificationExpire = data.notificationExpire;
            if (Number.isInteger(data.notificationDefaultExpireTimeout))
                notificationDefaultExpireTimeout = Math.max(0, data.notificationDefaultExpireTimeout);
            if (Number.isInteger(data.notificationFullscreenMode))
                notificationFullscreenMode = Math.max(0, Math.min(1, data.notificationFullscreenMode));
            if (typeof data.notificationClearThreshold === "number")
                notificationClearThreshold = Math.max(0, Math.min(1, data.notificationClearThreshold));
            if (Number.isInteger(data.notificationExpandThreshold))
                notificationExpandThreshold = Math.max(0, data.notificationExpandThreshold);
            if (Number.isInteger(data.notificationGroupPreviewNum))
                notificationGroupPreviewNum = Math.max(1, Math.min(20, data.notificationGroupPreviewNum));
            if (typeof data.notificationOpenExpanded === "boolean")
                notificationOpenExpanded = data.notificationOpenExpanded;
            if (Number.isInteger(data.dashboardMediaUpdateInterval))
                dashboardMediaUpdateInterval = Math.max(50, data.dashboardMediaUpdateInterval);
            if (Number.isInteger(data.dashboardResourceUpdateInterval))
                dashboardResourceUpdateInterval = Math.max(50, data.dashboardResourceUpdateInterval);
            if (Number.isInteger(data.nexusWallpapersPerRow))
                nexusWallpapersPerRow = Math.max(1, Math.min(12, data.nexusWallpapersPerRow));
            if (Number.isInteger(data.nexusMaxNetworksShown))
                nexusMaxNetworksShown = Math.max(1, Math.min(50, data.nexusMaxNetworksShown));
            if (Number.isInteger(data.nexusNetworkRescanInterval))
                nexusNetworkRescanInterval = Math.max(1000, data.nexusNetworkRescanInterval);
            if (data.dashboard && typeof data.dashboard === "object") {
                for (const key of ["enabled", "showOnHover", "showDashboard", "showMedia", "showPerformance", "showWeather"])
                    if (typeof data.dashboard[key] === "boolean") dashboard[key] = data.dashboard[key];
                if (Number.isFinite(data.dashboard.dragThreshold)) dashboard.dragThreshold = Math.max(0, data.dashboard.dragThreshold);
                if (data.dashboard.performance && typeof data.dashboard.performance === "object") {
                    for (const key of ["showCpu", "showGpu", "showMemory", "showStorage", "showNetwork", "showBattery"])
                        if (typeof data.dashboard.performance[key] === "boolean") dashboard.performance[key] = data.dashboard.performance[key];
                }
            }
            for (const group of ["launcher", "sidebar"])
                if (data[group] && typeof data[group] === "object") {
                    for (const key of ["enabled", "showOnHover"])
                        if (typeof data[group][key] === "boolean") root[group][key] = data[group][key];
                    for (const key of ["maxShown", "maxWallpapers", "dragThreshold", "minHoverThreshold"])
                        if (Number.isFinite(data[group][key]) && key in root[group]) root[group][key] = Math.max(0, data[group][key]);
                }
            if (data.utilities && typeof data.utilities === "object") {
                if (typeof data.utilities.enabled === "boolean") utilities.enabled = data.utilities.enabled;
                if (data.utilities.cards && typeof data.utilities.cards === "object")
                    for (const key of ["keepAwake", "recorder", "quickToggles"])
                        if (typeof data.utilities.cards[key] === "boolean") utilities.cards[key] = data.utilities.cards[key];
            }
            if (data.bar && data.bar.workspaces && typeof data.bar.workspaces === "object") {
                for (const key of ["activeIndicator", "activeTrail", "occupiedBg", "showWindows", "showWindowsOnSpecialWorkspaces", "perMonitorWorkspaces"])
                    if (typeof data.bar.workspaces[key] === "boolean") bar.workspaces[key] = data.bar.workspaces[key];
                if (Number.isInteger(data.bar.workspaces.maxWindowIcons))
                    bar.workspaces.maxWindowIcons = Math.max(0, Math.min(20, data.bar.workspaces.maxWindowIcons));
                if (Number.isInteger(data.bar.workspaces.displayType))
                    bar.workspaces.displayType = Math.max(0, Math.min(1, data.bar.workspaces.displayType));
                for (const key of ["label", "occupiedLabel", "activeLabel"])
                    if (typeof data.bar.workspaces[key] === "string") bar.workspaces[key] = data.bar.workspaces[key];
                if (Number.isInteger(data.bar.workspaces.capitalisation))
                    bar.workspaces.capitalisation = Math.max(0, Math.min(2, data.bar.workspaces.capitalisation));
            }
            if (data.bar && typeof data.bar === "object") {
                for (const key of ["persistent", "showOnHover"])
                    if (typeof data.bar[key] === "boolean") bar[key] = data.bar[key];
                if (Number.isInteger(data.bar.dragThreshold))
                    bar.dragThreshold = Math.max(0, data.bar.dragThreshold);
                for (const group of ["scrollActions", "tray", "activeWindow", "popouts", "clock"])
                    if (data.bar[group] && typeof data.bar[group] === "object")
                        for (const key of Object.keys(data.bar[group]))
                            if (key in bar[group] && typeof data.bar[group][key] === "boolean") bar[group][key] = data.bar[group][key];
                if (Array.isArray(data.bar.entries))
                    bar.entries = data.bar.entries.filter(value => value && typeof value.id === "string").map(value => ({ id: value.id, enabled: value.enabled !== false }));
            }
            if (typeof data.smartScheme === "boolean")
                smartScheme = data.smartScheme;
            if (typeof data.wallpaperDirectory === "string" && data.wallpaperDirectory.length > 0)
                wallpaperDirectory = data.wallpaperDirectory;
            if (typeof data.wallpaperEnabled === "boolean")
                wallpaperEnabled = data.wallpaperEnabled;
            if (typeof data.transparencyEnabled === "boolean")
                transparencyEnabled = data.transparencyEnabled;
            if (typeof data.borderSmoothing === "boolean")
                borderSmoothing = data.borderSmoothing;
            if (typeof data.desktopClockEnabled === "boolean")
                desktopClockEnabled = data.desktopClockEnabled;
            if (typeof data.desktopClockPosition === "string" && data.desktopClockPosition.length > 0)
                desktopClockPosition = data.desktopClockPosition;
            if (Number.isInteger(data.borderThickness))
                borderThickness = Math.max(0, Math.min(20, data.borderThickness));
            if (typeof data.useTwelveHourClock === "boolean")
                useTwelveHourClock = data.useTwelveHourClock;
            if (typeof data.useFahrenheit === "boolean")
                useFahrenheit = data.useFahrenheit;
            if (typeof data.useFahrenheitPerformance === "boolean")
                useFahrenheitPerformance = data.useFahrenheitPerformance;
            if (typeof data.weatherLocation === "string")
                weatherLocation = data.weatherLocation;
            if (typeof data.audioIncrement === "number")
                audioIncrement = Math.max(0.01, Math.min(1, data.audioIncrement));
            if (typeof data.brightnessIncrement === "number")
                brightnessIncrement = Math.max(0.01, Math.min(1, data.brightnessIncrement));
            if (typeof data.maxVolume === "number")
                maxVolume = Math.max(0, Math.min(2, data.maxVolume));
            if (Number.isInteger(data.visualiserBars))
                visualiserBars = Math.max(1, Math.min(256, data.visualiserBars));
            if (typeof data.visualiserEnabled === "boolean")
                visualiserEnabled = data.visualiserEnabled;
            if (typeof data.visualiserAutoHide === "boolean")
                visualiserAutoHide = data.visualiserAutoHide;
            if (typeof data.visualiserBlur === "boolean")
                visualiserBlur = data.visualiserBlur;
            if (typeof data.visualiserSpacing === "number")
                visualiserSpacing = Math.max(0, Math.min(10, data.visualiserSpacing));
            if (typeof data.visualiserRounding === "number")
                visualiserRounding = Math.max(0, Math.min(10, data.visualiserRounding));
            if (typeof data.defaultPlayer === "string")
                defaultPlayer = data.defaultPlayer;
            if (Array.isArray(data.playerAliases))
                playerAliases = data.playerAliases.filter(value => value && typeof value === "object");
            if (typeof data.toastAudioOutputChanged === "boolean")
                toastAudioOutputChanged = data.toastAudioOutputChanged;
            if (typeof data.toastAudioInputChanged === "boolean")
                toastAudioInputChanged = data.toastAudioInputChanged;
            if (typeof data.toastNowPlaying === "boolean")
                toastNowPlaying = data.toastNowPlaying;
            if (typeof data.notificationExpire === "boolean")
                notificationExpire = data.notificationExpire;
            if (typeof data.suppressNotificationsInFullscreen === "boolean")
                suppressNotificationsInFullscreen = data.suppressNotificationsInFullscreen;
            if (Number.isInteger(data.notificationDefaultExpireTimeout))
                notificationDefaultExpireTimeout = Math.max(0, data.notificationDefaultExpireTimeout);
            if (Number.isInteger(data.notificationFullscreenExpireTimeout))
                notificationFullscreenExpireTimeout = Math.max(0, data.notificationFullscreenExpireTimeout);
            if (typeof data.notificationActionOnClick === "boolean")
                notificationActionOnClick = data.notificationActionOnClick;
            if (typeof data.toastDndChanged === "boolean")
                toastDndChanged = data.toastDndChanged;
            if (typeof data.toastGameModeChanged === "boolean")
                toastGameModeChanged = data.toastGameModeChanged;
            if (typeof data.vimKeybinds === "boolean")
                vimKeybinds = data.vimKeybinds;
            if (Number.isInteger(data.workspacesShown))
                workspacesShown = Math.max(1, Math.min(20, data.workspacesShown));
            if (typeof data.idleInhibitWhenAudio === "boolean")
                idleInhibitWhenAudio = data.idleInhibitWhenAudio;
            if (typeof data.idleInhibitWhenCharging === "boolean")
                idleInhibitWhenCharging = data.idleInhibitWhenCharging;
            if (typeof data.idleLockBeforeSleep === "boolean")
                idleLockBeforeSleep = data.idleLockBeforeSleep;
            if (Array.isArray(data.idleTimeouts))
                idleTimeouts = data.idleTimeouts.filter(value => value && typeof value === "object");
        } catch (_) {}
        loaded = true;
    }

    function save(): void {
        if (!loaded)
            return;
        storage.setText(JSON.stringify({ schema: 1, favouriteApps, hiddenApps, hiddenTrayIcons, terminalCommand, audioCommand, playbackCommand, explorerCommand, gpuType, lyricsBackend, statusIcons, quickToggles, vpn: { providers: vpn.providers, selectedProvider: vpn.selectedProvider, enabled: vpn.enabled }, actions, actionPrefix, specialPrefix, enableDangerousActions, useFuzzyApps, useFuzzyWallpapers, useFuzzyActions, useFuzzySchemes, useFuzzyVariants, smartScheme, wallpaperDirectory, wallpaperEnabled, transparencyEnabled, desktopClockEnabled, desktopClockPosition, borderThickness, borderSmoothing, useTwelveHourClock, useFahrenheit, useFahrenheitPerformance, weatherLocation, audioIncrement, brightnessIncrement, maxVolume, visualiserBars, visualiserEnabled, visualiserAutoHide, visualiserBlur, visualiserSpacing, visualiserRounding, defaultPlayer, playerAliases, toastAudioOutputChanged, toastAudioInputChanged, toastNowPlaying, toastFullscreen, maxToasts, toastChargingChanged, toastCapsLockChanged, toastNumLockChanged, toastKbLayoutChanged, toastKbLimit, toastVpnChanged, notificationExpire, suppressNotificationsInFullscreen, notificationDefaultExpireTimeout, notificationFullscreenExpireTimeout, notificationActionOnClick, notificationFullscreenMode, notificationClearThreshold, notificationExpandThreshold, notificationGroupPreviewNum, notificationOpenExpanded, toastDndChanged, toastGameModeChanged, lockRecolourLogo, lockHideNotifs, lockEnableFprint, lockMaxFprintTries, lockEnableHowdy, lockMaxHowdyTries, lockTriggerHowdyOnWake, vimKeybinds, workspacesShown, dashboardMediaUpdateInterval, dashboardResourceUpdateInterval, nexusWallpapersPerRow, nexusMaxNetworksShown, nexusNetworkRescanInterval, dashboard: { enabled: dashboard.enabled, showOnHover: dashboard.showOnHover, showDashboard: dashboard.showDashboard, showMedia: dashboard.showMedia, showPerformance: dashboard.showPerformance, showWeather: dashboard.showWeather, dragThreshold: dashboard.dragThreshold, performance: { showCpu: dashboard.performance.showCpu, showGpu: dashboard.performance.showGpu, showMemory: dashboard.performance.showMemory, showStorage: dashboard.performance.showStorage, showNetwork: dashboard.performance.showNetwork, showBattery: dashboard.performance.showBattery } }, launcher: { enabled: launcher.enabled, showOnHover: launcher.showOnHover, maxShown: launcher.maxShown, maxWallpapers: launcher.maxWallpapers, dragThreshold: launcher.dragThreshold }, sidebar: { enabled: sidebar.enabled, showOnHover: sidebar.showOnHover, dragThreshold: sidebar.dragThreshold, minHoverThreshold: sidebar.minHoverThreshold }, utilities: { enabled: utilities.enabled, cards: { keepAwake: utilities.cards.keepAwake, recorder: utilities.cards.recorder, quickToggles: utilities.cards.quickToggles } }, bar: { persistent: bar.persistent, showOnHover: bar.showOnHover, dragThreshold: bar.dragThreshold, entries: bar.entries, scrollActions: { workspaces: bar.scrollActions.workspaces, volume: bar.scrollActions.volume, brightness: bar.scrollActions.brightness }, tray: { background: bar.tray.background, compact: bar.tray.compact, recolour: bar.tray.recolour }, activeWindow: { compact: bar.activeWindow.compact, inverted: bar.activeWindow.inverted, showOnHover: bar.activeWindow.showOnHover }, popouts: { activeWindow: bar.popouts.activeWindow, statusIcons: bar.popouts.statusIcons, tray: bar.popouts.tray }, clock: { background: bar.clock.background, showDate: bar.clock.showDate, showIcon: bar.clock.showIcon }, workspaces: { activeIndicator: bar.workspaces.activeIndicator, activeTrail: bar.workspaces.activeTrail, occupiedBg: bar.workspaces.occupiedBg, showWindows: bar.workspaces.showWindows, maxWindowIcons: bar.workspaces.maxWindowIcons, showWindowsOnSpecialWorkspaces: bar.workspaces.showWindowsOnSpecialWorkspaces, perMonitorWorkspaces: bar.workspaces.perMonitorWorkspaces, displayType: bar.workspaces.displayType, label: bar.workspaces.label, occupiedLabel: bar.workspaces.occupiedLabel, activeLabel: bar.workspaces.activeLabel, capitalisation: bar.workspaces.capitalisation } }, idleInhibitWhenAudio, idleInhibitWhenCharging, idleLockBeforeSleep, idleTimeouts }, null, 2) + "\n");
    }

    function setFavouriteApps(values: list<string>): void {
        favouriteApps = values.filter(value => typeof value === "string");
        save();
    }

    function moveStatusIcon(from: int, to: int): void {
        const values = statusIcons.slice();
        if (from < 0 || from >= values.length || to < 0 || to >= values.length)
            return;
        values.splice(to, 0, values.splice(from, 1)[0]);
        statusIcons = values;
        save();
    }

    function removeStatusIcon(index: int): void {
        const values = statusIcons.slice();
        if (index < 0 || index >= values.length)
            return;
        values.splice(index, 1);
        statusIcons = values;
        save();
    }

    function setStatusIconEnabled(index: int, enabled: bool): void {
        const values = statusIcons.slice();
        if (index < 0 || index >= values.length)
            return;
        values[index] = { id: values[index].id, enabled };
        statusIcons = values;
        save();
    }

    function insertStatusIcon(id: string): void {
        if (!id || statusIcons.some(item => item.id === id))
            return;
        statusIcons = statusIcons.concat([{ id, enabled: true }]);
        save();
    }

    function setQuickToggleEnabled(id: string, enabled: bool): void {
        const values = quickToggles.slice();
        const index = values.findIndex(item => item.id === id);
        if (index < 0) {
            values.push({ id, enabled });
        } else {
            values[index] = { id, enabled };
        }
        quickToggles = values;
        save();
    }

    function setHiddenTrayIcons(values: list<string>): void {
        hiddenTrayIcons = values.filter(value => typeof value === "string");
        save();
    }

    function setHiddenApps(values: list<string>): void {
        hiddenApps = values.filter(value => typeof value === "string");
        save();
    }

    function setWorkspacesShown(value: int): void {
        workspacesShown = Math.max(1, Math.min(20, value));
        save();
    }

    property var storage: FileView {
        path: root.path
        watchChanges: true
        printErrors: false
        onLoaded: root.load(text())
        onFileChanged: root.load(text())
    }
}
