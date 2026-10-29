pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import ".."
import "../../services"
import "../../utils"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// What the lock screen shows. It only reads PAM state: keys, focus and the
// release stay in LockSurface, so this can be rendered without a session lock.
Item {
    id: root

    required property var pam
    property string markPhase: "Human"
    property string userLabel: ""
    property string keyboardLayout: ""
    property bool capsLock: false
    property bool numLock: false
    property string batteryLabel: ""
    property bool batteryCharging: false
    property string networkLabel: ""
    readonly property bool failed: root.pam.state === 2 || root.pam.state === 3
    readonly property alias passwordField: field

    signal focusRequested()

    // Each rejected attempt shakes the field twice in 200 ms, without bounce.
    // flashMsg fires per attempt even when the state stays Failed.
    Connections {
        target: root.pam
        function onFlashMsg(): void {
            if (root.pam.state >= 2)
                shake.restart();
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - CortetsuDesign.spacingSection * 2, 480)
        spacing: CortetsuDesign.spacingStandard

        CortetsuEvolvingMark {
            phase: root.markPhase
            monochrome: true
            monochromeColor: CortetsuDesign.colorWashi
            Layout.preferredWidth: 56
            Layout.preferredHeight: 56
            Layout.alignment: Qt.AlignHCenter
        }

        // The clock is the focal point; the date and the user follow it.
        CortetsuText {
            Layout.alignment: Qt.AlignHCenter
            text: `${Time.hourStr}:${Time.minuteStr}`
            textSize: CortetsuTypography.displayHeroPx * 1.5
            font.weight: Font.DemiBold
        }

        CortetsuText {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: CortetsuDesign.spacingSpacious
            text: CortetsuRegional.formatDate(Time.date, "longDay", true)
            textSize: CortetsuTypography.bodyPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }

        CortetsuText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: parent.width
            text: root.userLabel
            textSize: CortetsuTypography.titleMediumPx
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Rectangle {
            id: field
            objectName: "lockPasswordField"
            Layout.fillWidth: true
            implicitHeight: 52
            radius: CortetsuDesign.radiusMedium
            color: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.92)
            border.width: 1
            border.color: root.failed ? CortetsuDesign.colorVermillion : CortetsuDesign.colorIndicator
            transform: Translate { id: nudge }

            CortetsuText {
                anchors.left: parent.left
                anchors.right: capsBadge.visible ? capsBadge.left : parent.right
                anchors.margins: CortetsuDesign.spacingStandard
                anchors.verticalCenter: parent.verticalCenter
                text: root.pam.buffer.length ? "• ".repeat(root.pam.buffer.length) : qsTr("Contraseña")
                textSize: CortetsuTypography.bodyLargePx
                color: root.pam.buffer.length ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideLeft
            }

            // Caps Lock matters while typing a password, so it sits in the field.
            CortetsuText {
                id: capsBadge
                objectName: "lockCapsLock"
                anchors.right: parent.right
                anchors.rightMargin: CortetsuDesign.spacingStandard
                anchors.verticalCenter: parent.verticalCenter
                visible: root.capsLock
                text: qsTr("Bloq Mayús")
                textSize: CortetsuTypography.labelSmallPx
                font.weight: Font.DemiBold
                color: CortetsuDesign.colorWarning
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.focusRequested()
            }

            SequentialAnimation {
                id: shake
                // design-lint: allow token-literal-duration: four 50 ms legs make the 200 ms budget
                NumberAnimation { target: nudge; property: "x"; to: -8; duration: 50; easing.type: Easing.OutCubic }
                NumberAnimation { target: nudge; property: "x"; to: 8; duration: 50; easing.type: Easing.OutCubic } // design-lint: allow token-literal-duration: part of the 200 ms shake
                NumberAnimation { target: nudge; property: "x"; to: -4; duration: 50; easing.type: Easing.OutCubic } // design-lint: allow token-literal-duration: part of the 200 ms shake
                NumberAnimation { target: nudge; property: "x"; to: 0; duration: 50; easing.type: Easing.OutCubic } // design-lint: allow token-literal-duration: part of the 200 ms shake
            }
        }

        // Says what failed and what to do; empty while nothing went wrong.
        CortetsuText {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: implicitHeight
            opacity: root.pam.state > 0 ? 1 : 0
            text: root.failed
                ? qsTr("Contraseña incorrecta. Inténtalo de nuevo.")
                : root.pam.state === 2
                    ? qsTr("Demasiados intentos. Espera antes de volver a probar.")
                    : qsTr("La autenticación no está disponible")
            textSize: CortetsuTypography.bodySmallPx
            color: CortetsuDesign.colorVermillion
        }

        // Context, not controls: one quiet line.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: parent.width
            spacing: CortetsuDesign.spacingSpacious

            Repeater {
                model: [
                    { icon: CortetsuPower.hasBattery ? Icons.getBatteryIcon(CortetsuPower.value, root.batteryCharging) : "power", text: root.batteryLabel },
                    { icon: CortetsuNetwork.activeEthernet ? "cable" : (CortetsuNetwork.active ? "wifi" : "wifi_off"), text: root.networkLabel },
                    { icon: "keyboard", text: root.keyboardLayout + (root.numLock ? qsTr(" · Bloq Num") : "") }
                ]
                delegate: RowLayout {
                    required property var modelData
                    spacing: CortetsuDesign.spacingCompact
                    CortetsuIcon {
                        text: parent.modelData.icon
                        iconSize: CortetsuTypography.iconSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                    CortetsuText {
                        Layout.maximumWidth: 160
                        text: parent.modelData.text
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
