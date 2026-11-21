pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io
import "ThemePreferences.js" as ThemePreferences
import "HubAnchor.js" as HubAnchor
import "desktop/DesktopLayout.js" as DesktopLayout

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
    readonly property QtObject bottomHub: QtObject {
        // Where the Hub sits (HubAnchor.js): the anchor for every monitor and
        // the monitors that have their own, by output name.
        property string anchor: HubAnchor.fallback
        onAnchorChanged: if (root.loaded) root.save()
        property var anchors: ({})
        onAnchorsChanged: if (root.loaded) root.save()
        function anchorFor(monitorName: string): string {
            return HubAnchor.forMonitor(anchor, anchors, monitorName);
        }
        // "" as the monitor sets the anchor of every monitor without its own.
        function setAnchor(monitorName: string, id: string): void {
            if (!HubAnchor.valid(id))
                return;
            if (monitorName.length === 0) {
                anchor = id;
                return;
            }
            const next = Object.assign({}, anchors);
            next[monitorName] = id;
            anchors = next;
        }
        function clearAnchor(monitorName: string): void {
            if (anchors[monitorName] === undefined)
                return;
            const next = Object.assign({}, anchors);
            delete next[monitorName];
            anchors = next;
        }
        // The App Rail's window preview: whether resting the pointer on a
        // running app opens it (the Menu key always does), and whether its
        // cards take a frame of each window or show the app's icon.
        property bool windowPreviews: true
        onWindowPreviewsChanged: if (root.loaded) root.save()
        property bool windowThumbnails: true
        onWindowThumbnailsChanged: if (root.loaded) root.save()
        // Space between the islands: "compact" | "standard" | "airy".
        property string spacing: "standard"
        onSpacingChanged: if (root.loaded) root.save()
        // The three groups from the start of the edge: a permutation of
        // "core", "apps" and "system". `mirrored` is kept for older
        // versions and derived from it.
        property list<string> order: ["core", "apps", "system"]
        onOrderChanged: if (root.loaded) root.save()
        readonly property bool mirrored: order[0] === "system" && order[2] === "core"
        function setOrder(next: var): void {
            if (Array.isArray(next) && next.length === 3 && ["core", "apps", "system"].every(group => next.includes(group)))
                order = next;
        }
        readonly property QtObject segments: QtObject {
            property bool mode: true
            onModeChanged: if (root.loaded) root.save()
            property bool apps: true
            onAppsChanged: if (root.loaded) root.save()
            property bool tray: true
            onTrayChanged: if (root.loaded) root.save()
            property bool status: true
            onStatusChanged: if (root.loaded) root.save()
        }
        readonly property QtObject statusCluster: QtObject {
            property bool audio: true
            onAudioChanged: if (root.loaded) root.save()
            property bool network: true
            onNetworkChanged: if (root.loaded) root.save()
            property bool bluetooth: true
            onBluetoothChanged: if (root.loaded) root.save()
            property bool battery: true
            onBatteryChanged: if (root.loaded) root.save()
            property bool showNotificationCount: true
            onShowNotificationCountChanged: if (root.loaded) root.save()
            // The reading beside the network and battery glyphs (signal and
            // charge, in percent) on a horizontal Hub.
            property bool showValues: true
            onShowValuesChanged: if (root.loaded) root.save()
        }
    }
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
    property var themeIntegrations: ({hyprland: true, kitty: true, gtk: true, qt: true})
    onThemeIntegrationsChanged: if (loaded) save()
    property string wallpaperDirectory: "~/Imágenes/Wallpapers"
    property bool wallpaperEnabled: true
    property bool transparencyEnabled: false
    onTransparencyEnabledChanged: if (loaded) save()
    property var themePreferences: ({})
    readonly property var activeThemeOverrides: ThemePreferences.sanitise(themePreferences[themeId]?.tokens)
    function setThemeToken(name: string, value: var): void {
        const preferences = Object.assign({}, themePreferences);
        const profile = Object.assign({}, preferences[themeId] || {});
        profile.tokens = ThemePreferences.sanitise(Object.assign({}, profile.tokens || {}, {[name]: value}));
        preferences[themeId] = profile;
        themePreferences = preferences;
        save();
    }
    function resetThemeTokens(): void {
        const preferences = Object.assign({}, themePreferences);
        preferences[themeId] = Object.assign({}, preferences[themeId] || {}, {tokens: {}});
        themePreferences = preferences;
        save();
    }
    function selectTheme(id: string): void {
        if (!["ink", "washi", "kurogane"].includes(id) || id === themeId)
            return;
        const saved = Object.assign({}, themePreferences);
        saved[themeId] = Object.assign({}, saved[themeId] || {}, { transparencyEnabled, reducedMotion, smartScheme, borderThickness });
        themePreferences = saved;
        const next = Object.assign({transparencyEnabled: false, reducedMotion: false, smartScheme: true, borderThickness: 1}, saved[id] || {});
        if (next) {
            if (typeof next.transparencyEnabled === "boolean") transparencyEnabled = next.transparencyEnabled;
            if (typeof next.reducedMotion === "boolean") reducedMotion = next.reducedMotion;
            if (typeof next.smartScheme === "boolean") smartScheme = next.smartScheme;
            if (Number.isInteger(next.borderThickness)) borderThickness = Math.max(0, Math.min(20, next.borderThickness));
        }
        themeId = id;
    }
    property string themeId: "ink"
    onThemeIdChanged: if (loaded) save()
    property bool reducedMotion: false
    onReducedMotionChanged: if (loaded) save()
    property bool desktopClockEnabled: false
    function normaliseClockPosition(value: string): string {
        const position = value.replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase();
        return /^(top|middle|bottom)-(left|center|right)$/.test(position) ? position : "top-left";
    }
    property string desktopClockPosition: "top-left"
    property bool desktopClockShowDate: true
    // Desktop widgets (services/DesktopWidgets.qml owns the edits). Each
    // entry: id, type, screen, cx/cy (centre as a fraction of the monitor),
    // size s|m|l, and showDate (clock) or text (note).
    property var desktopWidgets: []
    onDesktopWidgetsChanged: if (loaded) save()
    property int borderThickness: 1
    property bool borderSmoothing: true
    property bool useTwelveHourClock: false
    property bool useSecondPrecision: false
    property bool useFahrenheit: false
    property bool useFahrenheitPerformance: false
    property int batteryLowWarningPercent: 10
    property string weatherLocation: ""
    property string screenRecordSavePath: ""
    onScreenRecordSavePathChanged: if (loaded) save()
    property string screenSnipSavePath: ""
    onScreenSnipSavePathChanged: if (loaded) save()
    property int weatherRefreshInterval: 3600000
    property real audioIncrement: 0.1
    property real brightnessIncrement: 0.1
    property int osdTimeoutMs: 1500
    onOsdTimeoutMsChanged: if (loaded) save()
    property real maxVolume: 1.0
    property bool audioProtectionEnabled: false
    onAudioProtectionEnabledChanged: if (loaded) save()
    property real audioMaxIncrease: 0.15
    // Opt-in equalizer (services/CortetsuEqualizer.qml): ten gains in dB,
    // -12..12, and the switch. Without the filter-chain node they are kept
    // and nothing is applied.
    property bool eqEnabled: false
    property var eqGains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    onAudioMaxIncreaseChanged: if (loaded) save()
    property bool colorCalibrationEnabled: false
    property int colorTemperature: 6000
    property int colorGamma: 100
    // Night light: the colour filter above, switched on and off by the
    // clock. "HH:mm"; a range that crosses midnight is allowed.
    property bool nightLightSchedule: false
    property string nightLightFrom: "20:00"
    property string nightLightTo: "07:00"
    function validClock(value: var): bool {
        return typeof value === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
    }
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
    // Apps whose notifications go to the history without a popup (a
    // critical one still pops up). Matched by the app name they send.
    property list<string> mutedNotificationApps: []
    onMutedNotificationAppsChanged: if (loaded) save()
    function setNotificationAppMuted(app: string, muted: bool): void {
        const name = String(app ?? "").trim();
        if (!name)
            return;
        const others = mutedNotificationApps.filter(value => value !== name);
        mutedNotificationApps = muted ? others.concat([name]) : others;
    }
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
    property int dashboardResourceUpdateInterval: 1500
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
    // Idle actions with timeouts in milliseconds: "lock", "dpms" (screen off)
    // and "suspend", plus any Hyprland dispatch or command. Screen off and
    // suspend are absent by default: neither runs until chosen in Settings.
    property list<var> idleTimeouts: [{ enabled: true, timeout: 900000, respectInhibitors: true, idleAction: "lock" }]
    property bool idleSuspendOnBatteryOnly: true
    // A focused fullscreen window (a game on a controller, a video) is
    // activity the compositor cannot see.
    property bool idleInhibitWhenFullscreen: true
    property bool loaded: false
    property bool writing: false
    property bool saveQueued: false
    // idle | pending | saving | saved | failed. A surface that edits
    // preferences shows this instead of assuming every write lands.
    property string saveState: "idle"
    property string saveError: ""
    // Set when preferences.json could not be parsed at start-up.
    property string loadError: ""

    readonly property QtObject dashboard: QtObject {
        property bool enabled: true
        onEnabledChanged: if (root.loaded) root.save()
        property bool showOnHover: false
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
        property bool showOnHover: false
        onShowOnHoverChanged: if (root.loaded) root.save()
        property int dragThreshold: 24
        onDragThresholdChanged: if (root.loaded) root.save()
        readonly property QtObject scrollActions: QtObject {
            property bool volume: true
            onVolumeChanged: if (root.loaded) root.save()
        }
        readonly property QtObject tray: QtObject {
            property bool background: true
            onBackgroundChanged: if (root.loaded) root.save()
            property bool recolour: false
            onRecolourChanged: if (root.loaded) root.save()
        }
        readonly property QtObject activeWindow: QtObject {
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
            property bool showAppIcons: false
            onShowWindowsChanged: if (root.loaded) root.save()
            onShowAppIconsChanged: if (root.loaded) root.save()
            property bool monochromeIcons: false
            onMonochromeIconsChanged: if (root.loaded) root.save()
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
        loaded = false;
        let data;
        try {
            data = JSON.parse(raw);
            if (!data || typeof data !== "object" || Array.isArray(data))
                throw new Error("not an object");
        } catch (parseError) {
            // A damaged file is copied aside before anything can overwrite
            // it: the defaults stand and the next change writes a fresh
            // file, but what the user had is kept to recover by hand.
            recovery.setText(raw);
            loadError = qsTranslate("CortetsuConfig", "preferences.json estaba dañado; se guardó una copia en %1").arg(recovery.path);
            Quickshell.execDetached(["notify-send", "--app-name=Cortetsu", qsTranslate("CortetsuConfig", "Preferencias dañadas"), loadError]);
            loaded = true;
            return;
        }
        try {
            if (data.themeIntegrations && typeof data.themeIntegrations === "object") {
                const integrations = Object.assign({}, themeIntegrations);
                for (const key of ["hyprland", "kitty", "gtk", "qt"])
                    if (typeof data.themeIntegrations[key] === "boolean") integrations[key] = data.themeIntegrations[key];
                themeIntegrations = integrations;
            }
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
            if (data.bottomHub && typeof data.bottomHub === "object") {
                // An unknown anchor reads as the bottom, never as nowhere.
                bottomHub.anchor = HubAnchor.normalize(data.bottomHub.anchor);
                bottomHub.anchors = HubAnchor.sanitizeMap(data.bottomHub.anchors);
                if (typeof data.bottomHub.windowPreviews === "boolean")
                    bottomHub.windowPreviews = data.bottomHub.windowPreviews;
                if (typeof data.bottomHub.windowThumbnails === "boolean")
                    bottomHub.windowThumbnails = data.bottomHub.windowThumbnails;
                if (["compact", "standard", "airy"].includes(data.bottomHub.spacing))
                    bottomHub.spacing = data.bottomHub.spacing;
                if (Array.isArray(data.bottomHub.order))
                    bottomHub.setOrder(data.bottomHub.order);
                else if (data.bottomHub.mirrored === true)
                    bottomHub.setOrder(["system", "apps", "core"]);
                if (data.bottomHub.segments && typeof data.bottomHub.segments === "object")
                    for (const key of ["mode", "apps", "tray", "status"])
                        if (typeof data.bottomHub.segments[key] === "boolean")
                            bottomHub.segments[key] = data.bottomHub.segments[key];
                if (data.bottomHub.statusCluster && typeof data.bottomHub.statusCluster === "object")
                    for (const key of ["audio", "network", "bluetooth", "battery"])
                        if (typeof data.bottomHub.statusCluster[key] === "boolean")
                            bottomHub.statusCluster[key] = data.bottomHub.statusCluster[key];
                if (typeof data.bottomHub.statusCluster?.showNotificationCount === "boolean")
                    bottomHub.statusCluster.showNotificationCount = data.bottomHub.statusCluster.showNotificationCount;
                if (typeof data.bottomHub.statusCluster?.showValues === "boolean")
                    bottomHub.statusCluster.showValues = data.bottomHub.statusCluster.showValues;
            }
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
                dashboardResourceUpdateInterval = Math.max(1000, Math.min(5000,
                    Math.round(data.dashboardResourceUpdateInterval / 250) * 250));
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
                        if (Number.isFinite(data[group][key]) && key in root[group])
                            root[group][key] = ["maxShown", "maxWallpapers"].includes(key)
                                ? Math.max(1, Math.min(50, data[group][key]))
                                : Math.max(0, data[group][key]);
                }
            if (data.utilities && typeof data.utilities === "object") {
                if (typeof data.utilities.enabled === "boolean") utilities.enabled = data.utilities.enabled;
                if (data.utilities.cards && typeof data.utilities.cards === "object")
                    for (const key of ["keepAwake", "recorder", "quickToggles"])
                        if (typeof data.utilities.cards[key] === "boolean") utilities.cards[key] = data.utilities.cards[key];
            }
            if (data.bar && data.bar.workspaces && typeof data.bar.workspaces === "object") {
                for (const key of ["activeIndicator", "activeTrail", "occupiedBg", "showWindows", "showAppIcons", "monochromeIcons", "showWindowsOnSpecialWorkspaces", "perMonitorWorkspaces"])
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
                // Old preferences may still contain removed top-bar keys.
                for (const key of ["showOnHover"])
                    if (key in bar && typeof data.bar[key] === "boolean") bar[key] = data.bar[key];
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
            if (data.themePreferences && typeof data.themePreferences === "object" && !Array.isArray(data.themePreferences))
                themePreferences = data.themePreferences;
            if (["ink", "washi", "kurogane"].includes(data.themeId))
                themeId = data.themeId;
            if (typeof data.reducedMotion === "boolean")
                reducedMotion = data.reducedMotion;
            if (typeof data.borderSmoothing === "boolean")
                borderSmoothing = data.borderSmoothing;
            if (typeof data.desktopClockEnabled === "boolean")
                desktopClockEnabled = data.desktopClockEnabled;
            if (typeof data.desktopClockPosition === "string" && data.desktopClockPosition.length > 0)
                desktopClockPosition = normaliseClockPosition(data.desktopClockPosition);
            if (typeof data.desktopClockShowDate === "boolean")
                desktopClockShowDate = data.desktopClockShowDate;
            // The widget list replaces the single clock of 2.x: without a
            // list yet, an enabled clock becomes the first widget.
            if (Array.isArray(data.desktopWidgets))
                desktopWidgets = DesktopLayout.sanitiseList(data.desktopWidgets);
            else if (data.desktopClockEnabled === true)
                desktopWidgets = [DesktopLayout.legacyClock(desktopClockPosition, desktopClockShowDate)];
            if (Number.isInteger(data.borderThickness))
                borderThickness = Math.max(0, Math.min(20, data.borderThickness));
            if (typeof data.useTwelveHourClock === "boolean")
                useTwelveHourClock = data.useTwelveHourClock;
            if (typeof data.useSecondPrecision === "boolean")
                useSecondPrecision = data.useSecondPrecision;
            if (typeof data.useFahrenheit === "boolean")
                useFahrenheit = data.useFahrenheit;
            if (typeof data.useFahrenheitPerformance === "boolean")
                useFahrenheitPerformance = data.useFahrenheitPerformance;
            if (Number.isInteger(data.batteryLowWarningPercent))
                batteryLowWarningPercent = Math.max(0, Math.min(100, Math.round(data.batteryLowWarningPercent / 5) * 5));
            if (typeof data.weatherLocation === "string")
                weatherLocation = data.weatherLocation;
            if (typeof data.screenRecordSavePath === "string")
                screenRecordSavePath = data.screenRecordSavePath;
            if (typeof data.screenSnipSavePath === "string")
                screenSnipSavePath = data.screenSnipSavePath;
            if (Number.isInteger(data.weatherRefreshInterval))
                weatherRefreshInterval = Math.max(300000, Math.min(14400000, data.weatherRefreshInterval));
            if (typeof data.audioIncrement === "number")
                audioIncrement = Math.max(0.01, Math.min(1, data.audioIncrement));
            if (typeof data.brightnessIncrement === "number")
                brightnessIncrement = Math.max(0.01, Math.min(1, data.brightnessIncrement));
            if (typeof data.maxVolume === "number")
                maxVolume = Math.max(0, Math.min(2, data.maxVolume));
            if (Number.isInteger(data.osdTimeoutMs)) osdTimeoutMs = Math.max(500, Math.min(5000, data.osdTimeoutMs));
            if (typeof data.audioProtectionEnabled === "boolean") audioProtectionEnabled = data.audioProtectionEnabled;
            if (Number.isFinite(data.audioMaxIncrease)) audioMaxIncrease = Math.max(0.01, Math.min(1, data.audioMaxIncrease));
            if (typeof data.eqEnabled === "boolean") eqEnabled = data.eqEnabled;
            if (Array.isArray(data.eqGains) && data.eqGains.length === 10 && data.eqGains.every(Number.isFinite))
                eqGains = data.eqGains.map(value => Math.round(Math.max(-12, Math.min(12, value))));
            if (data.displayCalibration && typeof data.displayCalibration === "object") {
                if (typeof data.displayCalibration.enabled === "boolean")
                    colorCalibrationEnabled = data.displayCalibration.enabled;
                if (Number.isInteger(data.displayCalibration.temperature))
                    colorTemperature = Math.max(2500, Math.min(6500, data.displayCalibration.temperature));
                if (Number.isInteger(data.displayCalibration.gamma))
                    colorGamma = Math.max(50, Math.min(150, data.displayCalibration.gamma));
                const schedule = data.displayCalibration.schedule;
                if (schedule && typeof schedule === "object") {
                    if (typeof schedule.enabled === "boolean") nightLightSchedule = schedule.enabled;
                    if (validClock(schedule.from)) nightLightFrom = schedule.from;
                    if (validClock(schedule.to)) nightLightTo = schedule.to;
                }
            }
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
            if (Array.isArray(data.mutedNotificationApps))
                mutedNotificationApps = data.mutedNotificationApps.filter(value => typeof value === "string" && value.trim().length > 0).slice(0, 64);
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
            if (typeof data.idleSuspendOnBatteryOnly === "boolean")
                idleSuspendOnBatteryOnly = data.idleSuspendOnBatteryOnly;
            if (typeof data.idleInhibitWhenFullscreen === "boolean")
                idleInhibitWhenFullscreen = data.idleInhibitWhenFullscreen;
            if (Array.isArray(data.idleTimeouts))
                idleTimeouts = data.idleTimeouts.filter(value => value && typeof value === "object").map(value => {
                    // Saved preferences may still carry the removed "unlock" return action.
                    if (value.returnAction !== "unlock")
                        return value;
                    const migrated = Object.assign({}, value);
                    delete migrated.returnAction;
                    return migrated;
                });
        } catch (_) {}
        loaded = true;
    }


    // An idle action's timeout in whole minutes, 0 when it is absent or off.
    // A timeout under a minute still reads as 1 so an active lock never
    // shows as "never".
    function idleMinutes(action: string): int {
        const entry = idleTimeouts.find(value => value.idleAction === action);
        return entry && (entry.enabled ?? true) ? Math.max(1, Math.round((entry.timeout ?? 0) / 60000)) : 0;
    }
    function setIdleMinutes(action: string, minutes: int): void {
        const entry = idleTimeouts.find(value => value.idleAction === action)
            ?? { respectInhibitors: true, idleAction: action };
        const others = idleTimeouts.filter(value => value.idleAction !== action);
        if (minutes <= 0 && action !== "lock") {
            idleTimeouts = others;
            return;
        }
        const updated = Object.assign({}, entry, minutes > 0 ? { enabled: true, timeout: minutes * 60000 } : { enabled: false });
        idleTimeouts = [...others, updated];
    }

    // Changes are written once they settle: dragging a slider or flipping
    // several switches in a row costs one write, not one per step.
    function save(): void {
        if (!loaded)
            return;
        saveState = "pending";
        saveDelay.restart();
    }
    function reloadPreferences(): void {
        if (!writing && !saveDelay.running)
            storage.reload();
    }

    function flush(): void {
        if (!saveDelay.running)
            return;
        saveDelay.stop();
        writeState();
    }

    function writeState(): void {
        if (!loaded)
            return;
        if (writing) {
            saveQueued = true;
            return;
        }
        saveQueued = false;
        writing = true;
        saveState = "saving";
        saveError = "";
        storage.setText(JSON.stringify(snapshot(), null, 2) + "\n");
    }

    function snapshot(): var {
        return ({ schema: 1, favouriteApps, hiddenApps, hiddenTrayIcons, terminalCommand, audioCommand, playbackCommand, explorerCommand, gpuType, lyricsBackend, statusIcons, quickToggles, vpn: { providers: vpn.providers, selectedProvider: vpn.selectedProvider, enabled: vpn.enabled }, actions, actionPrefix, specialPrefix, enableDangerousActions, useFuzzyApps, useFuzzyWallpapers, useFuzzyActions, useFuzzySchemes, useFuzzyVariants, smartScheme, wallpaperDirectory, wallpaperEnabled, transparencyEnabled, themeId, themePreferences, reducedMotion, desktopClockEnabled, desktopClockPosition, desktopClockShowDate, desktopWidgets, borderThickness, borderSmoothing, useTwelveHourClock, useSecondPrecision, useFahrenheit, useFahrenheitPerformance, batteryLowWarningPercent, weatherLocation, screenRecordSavePath, screenSnipSavePath, weatherRefreshInterval, audioIncrement, brightnessIncrement, maxVolume, visualiserBars, visualiserEnabled, visualiserAutoHide, visualiserBlur, visualiserSpacing, visualiserRounding, defaultPlayer, playerAliases, toastAudioOutputChanged, toastAudioInputChanged, toastNowPlaying, toastFullscreen, maxToasts, toastChargingChanged, toastCapsLockChanged, toastNumLockChanged, toastKbLayoutChanged, toastKbLimit, toastVpnChanged, notificationExpire, suppressNotificationsInFullscreen, notificationDefaultExpireTimeout, notificationFullscreenExpireTimeout, notificationActionOnClick, notificationFullscreenMode, notificationClearThreshold, notificationExpandThreshold, notificationGroupPreviewNum, notificationOpenExpanded, mutedNotificationApps, toastDndChanged, toastGameModeChanged, lockRecolourLogo, lockHideNotifs, lockEnableFprint, lockMaxFprintTries, lockEnableHowdy, lockMaxHowdyTries, lockTriggerHowdyOnWake, vimKeybinds, workspacesShown, dashboardMediaUpdateInterval, dashboardResourceUpdateInterval, nexusWallpapersPerRow, nexusMaxNetworksShown, nexusNetworkRescanInterval, dashboard: { enabled: dashboard.enabled, showOnHover: dashboard.showOnHover, showDashboard: dashboard.showDashboard, showMedia: dashboard.showMedia, showPerformance: dashboard.showPerformance, showWeather: dashboard.showWeather, dragThreshold: dashboard.dragThreshold, performance: { showCpu: dashboard.performance.showCpu, showGpu: dashboard.performance.showGpu, showMemory: dashboard.performance.showMemory, showStorage: dashboard.performance.showStorage, showNetwork: dashboard.performance.showNetwork, showBattery: dashboard.performance.showBattery } }, launcher: { enabled: launcher.enabled, showOnHover: launcher.showOnHover, maxShown: launcher.maxShown, maxWallpapers: launcher.maxWallpapers, dragThreshold: launcher.dragThreshold }, sidebar: { enabled: sidebar.enabled, showOnHover: sidebar.showOnHover, dragThreshold: sidebar.dragThreshold, minHoverThreshold: sidebar.minHoverThreshold }, utilities: { enabled: utilities.enabled, cards: { keepAwake: utilities.cards.keepAwake, recorder: utilities.cards.recorder, quickToggles: utilities.cards.quickToggles } }, bar: { showOnHover: bar.showOnHover, dragThreshold: bar.dragThreshold, entries: bar.entries, scrollActions: { volume: bar.scrollActions.volume }, tray: { background: bar.tray.background, recolour: bar.tray.recolour }, activeWindow: { inverted: bar.activeWindow.inverted, showOnHover: bar.activeWindow.showOnHover }, popouts: { activeWindow: bar.popouts.activeWindow, statusIcons: bar.popouts.statusIcons, tray: bar.popouts.tray }, clock: { background: bar.clock.background, showIcon: bar.clock.showIcon }, workspaces: { activeIndicator: bar.workspaces.activeIndicator, activeTrail: bar.workspaces.activeTrail, occupiedBg: bar.workspaces.occupiedBg, showWindows: bar.workspaces.showWindows, showAppIcons: bar.workspaces.showAppIcons, monochromeIcons: bar.workspaces.monochromeIcons, maxWindowIcons: bar.workspaces.maxWindowIcons, showWindowsOnSpecialWorkspaces: bar.workspaces.showWindowsOnSpecialWorkspaces, perMonitorWorkspaces: bar.workspaces.perMonitorWorkspaces, displayType: bar.workspaces.displayType, label: bar.workspaces.label, occupiedLabel: bar.workspaces.occupiedLabel, activeLabel: bar.workspaces.activeLabel, capitalisation: bar.workspaces.capitalisation } }, idleInhibitWhenAudio, idleInhibitWhenCharging, idleLockBeforeSleep, idleTimeouts, idleSuspendOnBatteryOnly, idleInhibitWhenFullscreen,
            themeIntegrations,
            audioProtectionEnabled, audioMaxIncrease, eqEnabled, eqGains,
            osdTimeoutMs,
            bottomHub: {
                anchor: bottomHub.anchor,
                anchors: bottomHub.anchors,
                windowPreviews: bottomHub.windowPreviews,
                windowThumbnails: bottomHub.windowThumbnails,
                spacing: bottomHub.spacing,
                order: bottomHub.order,
                mirrored: bottomHub.mirrored,
                segments: { mode: bottomHub.segments.mode, apps: bottomHub.segments.apps, tray: bottomHub.segments.tray, status: bottomHub.segments.status },
                statusCluster: { audio: bottomHub.statusCluster.audio, network: bottomHub.statusCluster.network, bluetooth: bottomHub.statusCluster.bluetooth, battery: bottomHub.statusCluster.battery, showNotificationCount: bottomHub.statusCluster.showNotificationCount, showValues: bottomHub.statusCluster.showValues }
            },
            displayCalibration: { enabled: colorCalibrationEnabled, temperature: colorTemperature, gamma: colorGamma,
                schedule: { enabled: nightLightSchedule, from: nightLightFrom, to: nightLightTo } } });
    }

    property Timer saveDelay: Timer {
        interval: 300
        onTriggered: root.writeState()
    }

    // A change still waiting when the shell goes away is written at once.
    Component.onDestruction: {
        storage.blockWrites = true;
        flush();
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

    property var recovery: FileView {
        path: root.path + ".damaged"
        watchChanges: false
        printErrors: false
        blockLoading: false
        onSaveFailed: error => root.loadError += " (" + FileViewError.toString(error) + ")"
    }

    property var storage: FileView {
        path: root.path
        // The shell owns this file. Watching our own atomic writes caused the
        // initial snapshot to race with the new favourite-app list.
        watchChanges: false
        printErrors: false
        onLoaded: root.load(text())
        // No file yet (a first run): the defaults stand and the first change
        // creates it. Without this nothing would ever be saved.
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                root.loaded = true;
        }
        onSaved: {
            root.writing = false;
            if (root.saveQueued) {
                root.writeState();
                return;
            }
            // A change that arrived while this write was in flight is still
            // waiting on its own delay.
            if (!root.saveDelay.running)
                root.saveState = "saved";
        }
        onSaveFailed: error => {
            root.writing = false;
            root.saveQueued = false;
            root.saveState = "failed";
            root.saveError = FileViewError.toString(error);
        }
    }
}
