pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../theme"
import "../../../theme/ThemeProfiles.js" as Profiles
import "../../../theme/CortetsuDesignDefaults.js" as Defaults

// A small window drawn in one theme's own material, fonts, radii and
// colours, whatever theme is active: a title, a row with a switch, a slider
// and two choices. It is what the theme looks like, not a list of swatches.
Item {
    id: root

    required property string themeId
    readonly property var t: Profiles.tokens(themeId)

    function token(name) {
        return t[name] !== undefined ? t[name] : Defaults[name];
    }

    readonly property color ground: token("colorSumi")
    readonly property color surface: token("colorSurface")
    readonly property color high: token("colorSurfaceHigh")
    readonly property color text: token("colorOnSurface")
    readonly property color muted: token("colorOnSurfaceVariant")
    readonly property color primary: token("colorPrimary")
    readonly property color container: token("colorPrimaryContainer")
    readonly property color outline: token("colorOutlineVariant")
    readonly property int style: token("materialStyle")
    readonly property real radius: token("radiusMedium")

    implicitHeight: 148
    clip: true

    // The desk under the window: the theme's ground lit by its accent.
    Rectangle {
        anchors.fill: parent
        radius: CortetsuDesign.radiusMedium
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.ground }
            GradientStop { position: 1; color: Qt.tint(root.ground, Qt.alpha(root.primary, 0.35)) }
        }
    }

    CortetsuInkPanel {
        id: sheet
        x: 18
        y: 16
        width: parent.width - 36
        height: parent.height - 26
        style: root.style
        radius: root.token("radiusLarge")
        ground: root.surface
        groundAlpha: 1
        wash: root.primary
        washAlpha: root.token("materialWashAlpha")
        grain: root.token("materialGrain")
        edge: root.text
        accent: root.primary
        shadowAlpha: root.token("materialShadowAlpha")
        marks: root.style === 2
    }

    ColumnLayout {
        anchors.fill: sheet
        anchors.margins: 14
        spacing: 8

        Text {
            text: root.token("labelCaps") ? qsTr("AJUSTES") : qsTr("Ajustes")
            color: root.text
            font.family: root.token("fontHeading")
            font.weight: root.token("headingWeight")
            font.pixelSize: root.token("labelCaps") ? 12 : 16
            font.letterSpacing: root.token("labelTracking")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: qsTr("Superficies")
                color: root.text
                font.family: root.token("fontUi")
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Rectangle {
                implicitWidth: 28
                implicitHeight: 15
                radius: root.style === 2 ? 2 : height / 2
                color: root.primary

                Rectangle {
                    x: parent.width - width - 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11
                    height: 11
                    radius: root.style === 2 ? 1 : width / 2
                    color: root.token("colorOnPrimary")
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 4
            radius: height / 2
            color: Qt.alpha(root.outline, 0.7)

            Rectangle {
                width: parent.width * 0.62
                height: parent.height
                radius: parent.radius
                color: root.primary
            }
        }

        RowLayout {
            spacing: 6

            Repeater {
                model: [true, false]

                Rectangle {
                    required property bool modelData
                    implicitWidth: 44
                    implicitHeight: 16
                    radius: root.style === 2 ? 2 : height / 2
                    color: modelData ? root.container : "transparent"
                    border.width: 1
                    border.color: modelData ? "transparent" : Qt.alpha(root.outline, 0.9)
                }
            }
        }
    }
}
