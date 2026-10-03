pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../modules"
import "../theme"
import "../theme/CortetsuDesignDefaults.js" as Defaults

Singleton {
    id: root
    property bool showPreview: false
    property string scheme: "cortetsu"
    property string flavour: "dark"
    property bool currentLight: false
    property bool previewLight: false
    readonly property bool light: showPreview ? previewLight : currentLight
    readonly property string schemePath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/cortetsu/scheme.json`
    property var currentColours: ({})
    property var previewColours: ({})
    readonly property var activeColours: showPreview && Object.keys(previewColours).length > 0
        ? previewColours
        : currentColours
    readonly property QtObject palette: CortetsuPalette {}
    readonly property QtObject current: palette
    readonly property QtObject preview: palette
    readonly property QtObject tPalette: palette
    readonly property QtObject transparency: QtObject { readonly property bool enabled: CortetsuConfig.transparencyEnabled; readonly property real base: 0.92; readonly property real layers: 0.92 }
    readonly property real wallLuminance: root.luminance(root.schemeColour("surface", Defaults.colorSurface))

    function normaliseHex(value): string {
        const text = String(value ?? "").trim();
        const hex = text.startsWith("#") ? text : `#${text}`;
        return /^#[0-9a-fA-F]{6}$/.test(hex) ? hex : "";
    }

    function schemeColour(name: string, fallback): color {
        const values = activeColours || {};
        return normaliseHex(values[name]) || fallback;
    }

    function luminance(value): real {
        const colour = Qt.color(value);
        return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b;
    }

    // The design tokens follow the same scheme, preview included, so every
    // surface repaints together without reloading the shell.
    Binding {
        target: CortetsuDesign
        property: "scheme"
        value: root.activeColours
    }

    FileView {
        id: schemeFile
        path: root.schemePath
        watchChanges: true
        printErrors: false
        onLoaded: root.load(text(), false)
        // text() is the last loaded content; a change on disk needs a reload,
        // which reports back through onLoaded.
        onFileChanged: reload()
        onLoadFailed: root.currentColours = ({})
    }

    function layer(colour, layerNumber = 0) { return colour; }
    function load(data, isPreview) {
        try {
            const value = JSON.parse(data);
            if (!value || typeof value.colours !== "object" || Array.isArray(value.colours)) {
                if (isPreview)
                    clearPreview();
                else
                    currentColours = ({});
                return;
            }
            if (isPreview) {
                previewColours = value.colours;
                previewLight = value.mode === "light";
                showPreview = true;
            } else {
                currentColours = value.colours;
                scheme = value.name ?? "cortetsu";
                flavour = value.flavour ?? "dark";
                currentLight = value.mode === "light";
            }
        } catch (_) {
            if (isPreview)
                clearPreview();
            else
                currentColours = ({});
        }
    }
    function clearPreview(): void {
        previewColours = ({});
        previewLight = currentLight;
        showPreview = false;
    }
    function setMode(mode) { Quickshell.execDetached(["cortetsu", "scheme", "set", "--mode", mode]); }

    component CortetsuPalette: QtObject {
        readonly property color m3primary_paletteKeyColor: root.schemeColour("primary_paletteKeyColor", Defaults.colorPrimary)
        readonly property color m3secondary_paletteKeyColor: root.schemeColour("secondary_paletteKeyColor", Defaults.colorSecondary)
        readonly property color m3tertiary_paletteKeyColor: root.schemeColour("tertiary_paletteKeyColor", Defaults.colorTertiary)
        readonly property color m3neutral_paletteKeyColor: root.schemeColour("neutral_paletteKeyColor", Defaults.colorSurface)
        readonly property color m3neutral_variant_paletteKeyColor: root.schemeColour("neutral_variant_paletteKeyColor", Defaults.colorOutlineVariant)
        readonly property color m3background: root.schemeColour("background", Defaults.colorSumi)
        readonly property color m3onBackground: root.schemeColour("onBackground", Defaults.colorOnSurface)
        readonly property color m3surface: root.schemeColour("surface", Defaults.colorSurface)
        readonly property color m3surfaceDim: root.schemeColour("surfaceDim", Defaults.colorSumi)
        readonly property color m3surfaceBright: root.schemeColour("surfaceBright", Defaults.colorSurfaceHigh)
        readonly property color m3surfaceContainerLowest: root.schemeColour("surfaceContainerLowest", Defaults.colorSumi)
        readonly property color m3surfaceContainerLow: root.schemeColour("surfaceContainerLow", Defaults.colorSurface)
        readonly property color m3surfaceContainer: root.schemeColour("surfaceContainer", Defaults.colorSurface)
        readonly property color m3surfaceContainerHigh: root.schemeColour("surfaceContainerHigh", Defaults.colorSurfaceHigh)
        readonly property color m3surfaceContainerHighest: root.schemeColour("surfaceContainerHighest", Defaults.colorSurfaceHigh)
        readonly property color m3onSurface: root.schemeColour("onSurface", Defaults.colorOnSurface)
        readonly property color m3surfaceVariant: root.schemeColour("surfaceVariant", Defaults.colorSurfaceHigh)
        readonly property color m3onSurfaceVariant: root.schemeColour("onSurfaceVariant", Defaults.colorOnSurfaceVariant)
        readonly property color m3inverseSurface: root.schemeColour("inverseSurface", Defaults.colorWashi)
        readonly property color m3inverseOnSurface: root.schemeColour("inverseOnSurface", Defaults.colorTetsu)
        readonly property color m3outline: root.schemeColour("outline", Defaults.colorOutline)
        readonly property color m3outlineVariant: root.schemeColour("outlineVariant", Defaults.colorOutlineVariant)
        readonly property color m3shadow: root.schemeColour("shadow", Defaults.colorSumi)
        readonly property color m3scrim: root.schemeColour("scrim", Defaults.colorScrim)
        readonly property color m3surfaceTint: root.schemeColour("surfaceTint", Defaults.colorPrimary)
        readonly property color m3primary: root.schemeColour("primary", Defaults.colorPrimary)
        readonly property color m3onPrimary: root.schemeColour("onPrimary", Defaults.colorOnPrimary)
        readonly property color m3primaryContainer: root.schemeColour("primaryContainer", Defaults.colorPrimaryContainer)
        readonly property color m3onPrimaryContainer: root.schemeColour("onPrimaryContainer", Defaults.colorOnPrimaryContainer)
        readonly property color m3inversePrimary: root.schemeColour("inversePrimary", Defaults.colorIndigo)
        readonly property color m3secondary: root.schemeColour("secondary", Defaults.colorSecondary)
        readonly property color m3onSecondary: root.schemeColour("onSecondary", Defaults.colorOnPrimary)
        readonly property color m3secondaryContainer: root.schemeColour("secondaryContainer", Defaults.colorSecondaryContainer)
        readonly property color m3onSecondaryContainer: root.schemeColour("onSecondaryContainer", Defaults.colorOnSecondaryContainer)
        readonly property color m3tertiary: root.schemeColour("tertiary", Defaults.colorTertiary)
        readonly property color m3onTertiary: root.schemeColour("onTertiary", Defaults.colorWashi)
        readonly property color m3tertiaryContainer: root.schemeColour("tertiaryContainer", Defaults.colorTertiary)
        readonly property color m3onTertiaryContainer: root.schemeColour("onTertiaryContainer", Defaults.colorSumi)
        // Vermillion is a Cortetsu semantic role, not a wallpaper accent.
        readonly property color m3error: Defaults.colorVermillion
        readonly property color m3onError: Defaults.colorWashi
        readonly property color m3errorContainer: Defaults.colorVermillion
        readonly property color m3onErrorContainer: Defaults.colorSumi
        readonly property color m3success: root.schemeColour("success", Defaults.colorSuccess)
        readonly property color m3onSuccess: root.schemeColour("onSuccess", Defaults.colorSumi)
        readonly property color m3successContainer: root.schemeColour("successContainer", Defaults.colorSuccess)
        readonly property color m3onSuccessContainer: root.schemeColour("onSuccessContainer", Defaults.colorWashi)
        readonly property color m3primaryFixed: root.schemeColour("primaryFixed", Defaults.colorPrimaryContainer)
        readonly property color m3primaryFixedDim: root.schemeColour("primaryFixedDim", Defaults.colorPrimary)
        readonly property color m3onPrimaryFixed: root.schemeColour("onPrimaryFixed", Defaults.colorSumi)
        readonly property color m3onPrimaryFixedVariant: root.schemeColour("onPrimaryFixedVariant", Defaults.colorTetsu)
        readonly property color m3secondaryFixed: root.schemeColour("secondaryFixed", Defaults.colorSecondaryContainer)
        readonly property color m3secondaryFixedDim: root.schemeColour("secondaryFixedDim", Defaults.colorSecondary)
        readonly property color m3onSecondaryFixed: root.schemeColour("onSecondaryFixed", Defaults.colorSumi)
        readonly property color m3onSecondaryFixedVariant: root.schemeColour("onSecondaryFixedVariant", Defaults.colorTetsu)
        readonly property color m3tertiaryFixed: root.schemeColour("tertiaryFixed", Defaults.colorTertiary)
        readonly property color m3tertiaryFixedDim: root.schemeColour("tertiaryFixedDim", Defaults.colorTertiary)
        readonly property color m3onTertiaryFixed: root.schemeColour("onTertiaryFixed", Defaults.colorSumi)
        readonly property color m3onTertiaryFixedVariant: root.schemeColour("onTertiaryFixedVariant", Defaults.colorTetsu)
    }
}
