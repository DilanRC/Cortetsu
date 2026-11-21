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
    // PAM accepted the attempt; the lock is about to be released.
    property bool accepted: false
    // The mark follows the authentication, never the other way round
    // (ADR-008): Ascended while locked, even while typing; Monster after PAM
    // rejects an attempt, until another is allowed; Cosmic once PAM accepts.
    readonly property string markPhase: accepted ? "Cosmic" : rejected ? "Monster" : "Ascended"
    property string userLabel: ""
    property string keyboardLayout: ""
    property bool capsLock: false
    property bool numLock: false
    property string batteryLabel: ""
    property bool batteryCharging: false
    property string networkLabel: ""
    // Pam.PamState: 1 Error, 2 MaxTries, 3 Failed. LockCard is rendered
    // with a plain double as well, so it reads the numbers.
    readonly property bool unavailable: root.pam.state === 1
    readonly property bool lockedOut: root.pam.state === 2
    readonly property bool failed: root.pam.state === 3
    readonly property bool rejected: failed || lockedOut
    readonly property alias passwordField: field

    readonly property bool checking: root.pam.checking ?? false

    signal focusRequested()

    // Each rejected attempt shakes the field twice in 200 ms, without bounce.
    // flashMsg fires per attempt even when the state stays Failed.
    Connections {
        target: root.pam
        function onFlashMsg(): void {
            if (root.rejected && !CortetsuDesign.reducedMotion)
                shake.restart();
        }
    }

    // Wide screens carry what is playing and who wrote on either side of
    // the clock; a narrow one keeps only the centre.
    readonly property bool wings: width >= 1240

    // A halo of the accent behind the mark: the light the scene is lit by.
    CortetsuInkPanel {
        x: center.x + center.width / 2 - width / 2
        y: center.y + mark.y + mark.height / 2 - height / 2
        width: 560
        height: 560
        radius: width / 2
        groundAlpha: 0
        grain: 0
        hairline: false
        marks: false
        wash: root.rejected ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
        washAlpha: CortetsuDesign.materialHeroWashAlpha
        washX: 0.5
        washY: 0.5
    }

    LockMedia {
        objectName: "lockMedia"
        visible: root.wings && !!player
        anchors.right: center.left
        anchors.rightMargin: CortetsuDesign.spacingSection * 1.5
        y: center.y + clock.y + clock.height / 2 - height / 2
        onHandBackFocus: root.focusRequested()
    }

    LockMissed {
        objectName: "lockMissed"
        visible: root.wings && !CortetsuConfig.lockHideNotifs && apps.length > 0
        anchors.left: center.right
        anchors.leftMargin: CortetsuDesign.spacingSection * 1.5
        y: center.y + clock.y + clock.height / 2 - height / 2
    }

    ColumnLayout {
        id: center
        anchors.centerIn: parent
        width: Math.min(parent.width - CortetsuDesign.spacingSection * 2, 480)
        spacing: CortetsuDesign.spacingStandard

        // The mark is the lock's emblem: large, and the one place where
        // the state of the authentication is drawn rather than written.
        CortetsuEvolvingMark {
            id: mark
            objectName: "lockMark"
            phase: root.markPhase
            animated: !CortetsuDesign.reducedMotion
            monochrome: true
            monochromeColor: root.rejected ? CortetsuDesign.colorVermillion : CortetsuDesign.colorWashi
            Layout.preferredWidth: 132
            Layout.preferredHeight: 132
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: CortetsuDesign.spacingCompact
        }

        // The clock is the focal point; the date and the user follow it.
        CortetsuText {
            id: clock
            Layout.alignment: Qt.AlignHCenter
            text: Time.timeStr
            textSize: CortetsuTypography.displayHeroPx * 2
            font.weight: Font.Light
            font.letterSpacing: 2
        }

        CortetsuText {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: CortetsuDesign.spacingSpacious
            text: CortetsuRegional.formatDate(Time.date, "longDay", true)
            textSize: CortetsuTypography.titleSmallPx
            color: CortetsuDesign.colorOnSurface
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
            implicitHeight: 56
            radius: height / 2
            color: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.78)
            border.width: root.rejected ? 2 : 1
            border.color: root.rejected ? CortetsuDesign.colorVermillion : Qt.alpha(CortetsuDesign.colorPrimary, 0.7)
            transform: Translate { id: nudge }

            CortetsuIcon {
                id: lockIcon
                anchors.left: parent.left
                anchors.leftMargin: CortetsuDesign.spacingStandard + 4
                anchors.verticalCenter: parent.verticalCenter
                text: root.rejected ? "lock_reset" : "lock"
                iconSize: CortetsuTypography.iconSmallPx
                color: root.rejected ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
            }

            CortetsuText {
                anchors.left: lockIcon.right
                anchors.right: capsBadge.visible ? capsBadge.left : parent.right
                anchors.margins: CortetsuDesign.spacingStandard
                anchors.verticalCenter: parent.verticalCenter
                text: root.checking ? qsTr("Comprobando…")
                    : root.pam.buffer.length ? "• ".repeat(root.pam.buffer.length) : qsTr("Contraseña")
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
            objectName: "lockMessage"
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: parent.width
            Layout.preferredHeight: implicitHeight
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            opacity: root.pam.state > 0 && !root.checking ? 1 : 0
            // Too many attempts is its own state: it used to be shadowed by
            // the wrong-password text and was never shown.
            text: root.lockedOut
                ? qsTr("Demasiados intentos. Espera antes de volver a probar.")
                : root.failed
                    ? qsTr("Contraseña incorrecta. Inténtalo de nuevo.")
                    : qsTr("La autenticación no está disponible")
            textSize: CortetsuTypography.bodySmallPx
            color: CortetsuDesign.colorVermillion
        }

        // Context, not controls: one quiet bar of glass.
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: CortetsuDesign.spacingCompact
            implicitWidth: status.implicitWidth + CortetsuDesign.spacingSpacious * 2
            implicitHeight: status.implicitHeight + CortetsuDesign.spacingStandard * 2

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.62)
                border.width: 1
                border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.10)
            }

        RowLayout {
            id: status
            anchors.centerIn: parent
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
}
