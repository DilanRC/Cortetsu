pragma Singleton

import QtQuick
import "../theme"
import "../modules/CortetsuTokens.js" as CortetsuTokens
import "../modules/CortetsuTypography.js" as CortetsuTypography

QtObject {
    id: root

    property var screen

    readonly property QtObject padding: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 24
        readonly property int extraLargeIncreased: 28
        readonly property int extraExtraLarge: 40
    }

    readonly property QtObject spacing: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 24
        readonly property int extraLargeIncreased: 28
        readonly property int extraExtraLarge: 40
    }

    readonly property QtObject rounding: QtObject {
        readonly property real scale: 1
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 24
        readonly property int extraLargeIncreased: 28
        readonly property int extraExtraLarge: 40
        readonly property int full: 9999
    }

    readonly property QtObject font: QtObject {
        readonly property QtObject body: QtObject {
            readonly property font small: Qt.font({ family: CortetsuTypography.uiFamily, pixelSize: CortetsuTypography.bodySmallPx })
            readonly property font medium: Qt.font({ family: CortetsuTypography.uiFamily, pixelSize: CortetsuTypography.bodyPx })
            readonly property font large: Qt.font({ family: CortetsuTypography.uiFamily, pixelSize: CortetsuTypography.bodyLargePx })
            readonly property var builders: CortetsuTokens.builders(CortetsuTypography.uiFamily, CortetsuTypography.bodySmallPx, CortetsuTypography.bodyPx, CortetsuTypography.bodyLargePx)
        }
        readonly property QtObject label: QtObject {
            readonly property font small: Qt.font({ family: CortetsuTypography.uiFamily, pixelSize: CortetsuTypography.labelSmallPx })
            readonly property font medium: Qt.font({ family: CortetsuTypography.uiFamily, pixelSize: CortetsuTypography.labelMediumPx })
            readonly property font large: Qt.font({ family: CortetsuTypography.uiFamily, pixelSize: CortetsuTypography.labelLargePx })
            readonly property var builders: CortetsuTokens.builders(CortetsuTypography.uiFamily, CortetsuTypography.labelSmallPx, CortetsuTypography.labelMediumPx, CortetsuTypography.labelLargePx)
        }
        readonly property QtObject title: QtObject {
            readonly property font small: Qt.font({ family: CortetsuTypography.uiFamily, pixelSize: CortetsuTypography.titleSmallPx })
            readonly property font medium: Qt.font({ family: CortetsuTypography.uiFamily, pixelSize: CortetsuTypography.titleMediumPx })
            readonly property font large: Qt.font({ family: CortetsuTypography.uiFamily, pixelSize: CortetsuTypography.titleLargePx })
            readonly property var builders: CortetsuTokens.builders(CortetsuTypography.uiFamily, CortetsuTypography.titleSmallPx, CortetsuTypography.titleMediumPx, CortetsuTypography.titleLargePx)
        }
        readonly property QtObject headline: QtObject {
            readonly property font medium: Qt.font({ family: CortetsuTypography.uiFamily, pixelSize: 24 })
            readonly property var builders: CortetsuTokens.builders(CortetsuTypography.uiFamily, 20, 24, 32)
        }
        readonly property QtObject mono: QtObject {
            readonly property font small: Qt.font({ family: "monospace", pixelSize: CortetsuTypography.bodySmallPx })
            readonly property font medium: Qt.font({ family: "monospace", pixelSize: CortetsuTypography.bodyPx })
            readonly property font large: Qt.font({ family: "monospace", pixelSize: CortetsuTypography.bodyLargePx })
            readonly property var builders: CortetsuTokens.builders("monospace", CortetsuTypography.bodySmallPx, CortetsuTypography.bodyPx, CortetsuTypography.bodyLargePx)
        }
        readonly property QtObject icon: QtObject {
            readonly property font small: Qt.font({ family: CortetsuTypography.iconFamily, pixelSize: CortetsuTypography.iconSmallPx })
            readonly property font medium: Qt.font({ family: CortetsuTypography.iconFamily, pixelSize: CortetsuTypography.iconMediumPx })
            readonly property font large: Qt.font({ family: CortetsuTypography.iconFamily, pixelSize: CortetsuTypography.iconLargePx })
            readonly property font extraLarge: Qt.font({ family: CortetsuTypography.iconFamily, pixelSize: CortetsuTypography.iconExtraLargePx })
            readonly property var builders: CortetsuTokens.builders(CortetsuTypography.iconFamily, CortetsuTypography.iconSmallPx, CortetsuTypography.iconMediumPx, CortetsuTypography.iconLargePx)
            readonly property var size: function(value) { return CortetsuTokens.iconSize(CortetsuTypography.iconFamily, value); }
        }
        readonly property font workspaces: Qt.font({ family: CortetsuTypography.uiFamily, pixelSize: CortetsuTypography.labelSmallPx })
    }

    readonly property QtObject sizes: QtObject {
        readonly property QtObject bar: QtObject {
            readonly property int batteryWidth: 90
            readonly property int innerWidth: 180
            readonly property int kbLayoutWidth: 120
            readonly property int networkWidth: 240
            readonly property int trayMenuWidth: 320
            readonly property int windowPreviewSize: 240
        }
        readonly property QtObject dashboard: QtObject {
            readonly property int logoSize: 72
            readonly property int mediaCoverArtSize: 180
            readonly property int mediaSectionWidth: 420
            readonly property int mediaTabHeight: 44
            readonly property int mediaTabWidth: 120
            readonly property int perfBattHeight: 160
            readonly property int perfBattWidth: 180
            readonly property int perfBattWidthSingle: 360
            readonly property int perfHeroCardWidth: 360
            readonly property int perfNetworkCardHeight: 180
            readonly property int perfNetworkCardWidth: 280
            readonly property int perfPlaceholderWidth: 280
            readonly property int perfStorageTextWidth: 100
            readonly property int perfUsageShapeSize: 140
            readonly property int resourceProgressThickness: 8
            readonly property int tabIndicatorSpacing: 8
            readonly property int uptimeSize: 120
            readonly property int userWidth: 300
        }
        readonly property QtObject launcher: QtObject { readonly property int itemHeight: 56 }
        readonly property QtObject lock: QtObject {
            readonly property int centerWidth: 560
            readonly property int fetch3LinesHeight: 100
            readonly property int fetch4LinesHeight: 124
            readonly property real heightMult: 0.78
            readonly property int largeFontWidth: 460
            readonly property int largeLogoWidth: 240
            readonly property int ratio: 1
            readonly property int showColourBoxRowHeight: 48
            readonly property int showForecastHeight: 180
            readonly property int showWeatherDetailsHeight: 220
        }
        readonly property QtObject nexus: QtObject {
            readonly property real heightMult: 0.78
            readonly property int maxContentWidth: 820
            readonly property int maxDialogHeight: 720
            readonly property int maxDialogWidth: 720
            readonly property int maxNavWidth: 300
            readonly property int maxPopupHeight: 720
            readonly property int minHeight: 620
            readonly property int minPopupHeight: 420
            readonly property int minWidth: 960
            readonly property int networkShowEthDetailWidth: 700
            readonly property int networkShowVpnDetailWidth: 700
            readonly property int popupWidth: 480
            readonly property int smallTextFieldWidth: 180
            readonly property int textFieldWidth: 320
            readonly property real ratio: 1.55
        }
        readonly property QtObject notifs: QtObject { readonly property int badge: 24; readonly property int width: 420 }
        readonly property QtObject winfo: QtObject { readonly property int detailsWidth: 360; readonly property real heightMult: 0.6 }
    }

    readonly property QtObject anim: QtObject {
        // Decorative infinite loops stop while Reduced motion is on.
        readonly property bool reduced: CortetsuDesign.reducedMotion
        readonly property QtObject durations: QtObject {
            // Legacy names read the CortetsuDesign motion tokens, so Reduced
            // motion and the token budget reach base/ too.
            readonly property int small: CortetsuDesign.motionFastMs
            readonly property int normal: CortetsuDesign.motionStandardMs
            readonly property int large: CortetsuDesign.motionPopoverMs
            readonly property int extraLarge: CortetsuDesign.motionPanelMs
            // Stays 1: it scales the infinite spinner loops, and a zero-length
            // infinite animation would spin the render loop.
            readonly property real scale: 1
            readonly property int expressiveDefaultEffects: CortetsuDesign.motionStandardMs
            readonly property int expressiveDefaultSpatial: CortetsuDesign.motionPopoverMs
            readonly property int expressiveFastEffects: CortetsuDesign.motionInstantMs
            readonly property int expressiveFastSpatial: CortetsuDesign.motionFastMs
            readonly property int expressiveSlowSpatial: CortetsuDesign.motionPanelMs
        }
        readonly property var standard: Easing.OutCubic
        readonly property var standardAccel: Easing.InCubic
        readonly property var standardDecel: Easing.OutCubic
        readonly property var emphasized: Easing.InOutCubic
        readonly property var emphasizedAccel: Easing.InCubic
        readonly property var emphasizedDecel: Easing.OutCubic
        readonly property var expressiveDefaultEffects: Easing.OutCubic
        readonly property var expressiveDefaultSpatial: Easing.OutCubic
        readonly property var expressiveFastSpatial: Easing.OutCubic
        readonly property var expressiveSlowSpatial: Easing.OutCubic
    }
}
