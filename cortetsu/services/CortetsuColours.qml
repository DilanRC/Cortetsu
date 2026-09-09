pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../modules"
import "../modules/CortetsuDesign.js" as CortetsuDesign

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
    readonly property real wallLuminance: root.luminance(root.schemeColour("surface", CortetsuDesign.colorSurface))

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

    FileView {
        id: schemeFile
        path: root.schemePath
        watchChanges: true
        printErrors: false
        onLoaded: root.load(text(), false)
        onFileChanged: root.load(text(), false)
        onLoadFailed: root.currentColours = ({})
    }

    function layer(colour, layerNumber = 0) { return colour; }
    function on(colour) {
        return colour.hslLightness < 0.5
            ? CortetsuDesign.colorWashi
            : CortetsuDesign.colorTetsu;
    }
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
        readonly property color m3primary_paletteKeyColor: root.schemeColour("primary_paletteKeyColor", CortetsuDesign.colorPrimary)
        readonly property color m3secondary_paletteKeyColor: root.schemeColour("secondary_paletteKeyColor", CortetsuDesign.colorSecondary)
        readonly property color m3tertiary_paletteKeyColor: root.schemeColour("tertiary_paletteKeyColor", CortetsuDesign.colorTertiary)
        readonly property color m3neutral_paletteKeyColor: root.schemeColour("neutral_paletteKeyColor", CortetsuDesign.colorSurface)
        readonly property color m3neutral_variant_paletteKeyColor: root.schemeColour("neutral_variant_paletteKeyColor", CortetsuDesign.colorOutlineVariant)
        readonly property color m3background: root.schemeColour("background", CortetsuDesign.colorSumi)
        readonly property color m3onBackground: root.schemeColour("onBackground", CortetsuDesign.colorOnSurface)
        readonly property color m3surface: root.schemeColour("surface", CortetsuDesign.colorSurface)
        readonly property color m3surfaceDim: root.schemeColour("surfaceDim", CortetsuDesign.colorSumi)
        readonly property color m3surfaceBright: root.schemeColour("surfaceBright", CortetsuDesign.colorSurfaceHigh)
        readonly property color m3surfaceContainerLowest: root.schemeColour("surfaceContainerLowest", CortetsuDesign.colorSumi)
        readonly property color m3surfaceContainerLow: root.schemeColour("surfaceContainerLow", CortetsuDesign.colorSurface)
        readonly property color m3surfaceContainer: root.schemeColour("surfaceContainer", CortetsuDesign.colorSurface)
        readonly property color m3surfaceContainerHigh: root.schemeColour("surfaceContainerHigh", CortetsuDesign.colorSurfaceHigh)
        readonly property color m3surfaceContainerHighest: root.schemeColour("surfaceContainerHighest", CortetsuDesign.colorSurfaceHigh)
        readonly property color m3onSurface: root.schemeColour("onSurface", CortetsuDesign.colorOnSurface)
        readonly property color m3surfaceVariant: root.schemeColour("surfaceVariant", CortetsuDesign.colorSurfaceHigh)
        readonly property color m3onSurfaceVariant: root.schemeColour("onSurfaceVariant", CortetsuDesign.colorOnSurfaceVariant)
        readonly property color m3inverseSurface: root.schemeColour("inverseSurface", CortetsuDesign.colorWashi)
        readonly property color m3inverseOnSurface: root.schemeColour("inverseOnSurface", CortetsuDesign.colorTetsu)
        readonly property color m3outline: root.schemeColour("outline", CortetsuDesign.colorOutline)
        readonly property color m3outlineVariant: root.schemeColour("outlineVariant", CortetsuDesign.colorOutlineVariant)
        readonly property color m3shadow: root.schemeColour("shadow", CortetsuDesign.colorSumi)
        readonly property color m3scrim: root.schemeColour("scrim", CortetsuDesign.colorScrim)
        readonly property color m3surfaceTint: root.schemeColour("surfaceTint", CortetsuDesign.colorPrimary)
        readonly property color m3primary: root.schemeColour("primary", CortetsuDesign.colorPrimary)
        readonly property color m3onPrimary: root.schemeColour("onPrimary", CortetsuDesign.colorOnPrimary)
        readonly property color m3primaryContainer: root.schemeColour("primaryContainer", CortetsuDesign.colorPrimaryContainer)
        readonly property color m3onPrimaryContainer: root.schemeColour("onPrimaryContainer", CortetsuDesign.colorOnPrimaryContainer)
        readonly property color m3inversePrimary: root.schemeColour("inversePrimary", CortetsuDesign.colorIndigo)
        readonly property color m3secondary: root.schemeColour("secondary", CortetsuDesign.colorSecondary)
        readonly property color m3onSecondary: root.schemeColour("onSecondary", CortetsuDesign.colorOnPrimary)
        readonly property color m3secondaryContainer: root.schemeColour("secondaryContainer", CortetsuDesign.colorSecondaryContainer)
        readonly property color m3onSecondaryContainer: root.schemeColour("onSecondaryContainer", CortetsuDesign.colorOnSecondaryContainer)
        readonly property color m3tertiary: root.schemeColour("tertiary", CortetsuDesign.colorTertiary)
        readonly property color m3onTertiary: root.schemeColour("onTertiary", CortetsuDesign.colorWashi)
        readonly property color m3tertiaryContainer: root.schemeColour("tertiaryContainer", CortetsuDesign.colorTertiary)
        readonly property color m3onTertiaryContainer: root.schemeColour("onTertiaryContainer", CortetsuDesign.colorSumi)
        // Vermillion is a Cortetsu semantic role, not a wallpaper accent.
        readonly property color m3error: CortetsuDesign.colorVermillion
        readonly property color m3onError: CortetsuDesign.colorWashi
        readonly property color m3errorContainer: CortetsuDesign.colorVermillion
        readonly property color m3onErrorContainer: CortetsuDesign.colorSumi
        readonly property color m3success: root.schemeColour("success", CortetsuDesign.colorSuccess)
        readonly property color m3onSuccess: root.schemeColour("onSuccess", CortetsuDesign.colorSumi)
        readonly property color m3successContainer: root.schemeColour("successContainer", CortetsuDesign.colorSuccess)
        readonly property color m3onSuccessContainer: root.schemeColour("onSuccessContainer", CortetsuDesign.colorWashi)
        readonly property color m3primaryFixed: root.schemeColour("primaryFixed", CortetsuDesign.colorPrimaryContainer)
        readonly property color m3primaryFixedDim: root.schemeColour("primaryFixedDim", CortetsuDesign.colorPrimary)
        readonly property color m3onPrimaryFixed: root.schemeColour("onPrimaryFixed", CortetsuDesign.colorSumi)
        readonly property color m3onPrimaryFixedVariant: root.schemeColour("onPrimaryFixedVariant", CortetsuDesign.colorTetsu)
        readonly property color m3secondaryFixed: root.schemeColour("secondaryFixed", CortetsuDesign.colorSecondaryContainer)
        readonly property color m3secondaryFixedDim: root.schemeColour("secondaryFixedDim", CortetsuDesign.colorSecondary)
        readonly property color m3onSecondaryFixed: root.schemeColour("onSecondaryFixed", CortetsuDesign.colorSumi)
        readonly property color m3onSecondaryFixedVariant: root.schemeColour("onSecondaryFixedVariant", CortetsuDesign.colorTetsu)
        readonly property color m3tertiaryFixed: root.schemeColour("tertiaryFixed", CortetsuDesign.colorTertiary)
        readonly property color m3tertiaryFixedDim: root.schemeColour("tertiaryFixedDim", CortetsuDesign.colorTertiary)
        readonly property color m3onTertiaryFixed: root.schemeColour("onTertiaryFixed", CortetsuDesign.colorSumi)
        readonly property color m3onTertiaryFixedVariant: root.schemeColour("onTertiaryFixedVariant", CortetsuDesign.colorTetsu)
    }
}
