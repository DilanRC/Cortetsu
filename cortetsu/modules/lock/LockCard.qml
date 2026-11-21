pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import ".."
import "../../services"
import "../../utils"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// What the lock screen shows: a whole scene (07-lockscreen, with the
// composition of Nebula's LockScene studied, not copied): the mark over a
// horizon of light, the clock, who is locked, the password capsule, what
// plays on the left, who wrote on the right, and the state of the machine
// in a bar at the foot. After a quiet while the scene goes ambient: the
// secondary parts dim, the clock stays. Keys never wait for that: they go
// to LockSurface, which owns focus, PAM and the release, so this item only
// reads PAM state and can be rendered without a session lock.
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
    // the clock; a narrow one keeps only the centre and the bar.
    readonly property bool wings: width >= 1240
    // The scene is drawn for 1920×1080 and follows the screen's height.
    readonly property real unit: Math.max(0.72, Math.min(1.25, height / 1080))

    // Ambient: nothing typed and nothing wrong for a while. Any key (the
    // buffer changes) or a pointer move brings the scene back at once.
    property bool ambient: false
    property real secondaryOpacity: ambient ? 0.38 : 1
    Behavior on secondaryOpacity {
        enabled: !CortetsuDesign.reducedMotion
        NumberAnimation { duration: CortetsuDesign.motionPanelMs; easing.type: Easing.OutCubic }
    }
    function wake(): void {
        root.ambient = false;
        ambientTimer.restart();
    }
    Timer {
        id: ambientTimer
        interval: 20000
        running: true
        onTriggered: root.ambient = root.pam.buffer.length === 0 && root.pam.state === 0 && !root.checking
    }
    Connections {
        target: root.pam
        function onBufferChanged(): void { root.wake(); }
        function onStateChanged(): void { root.wake(); }
    }
    HoverHandler { onPointChanged: root.wake() }

    // --- Light: a halo behind the mark and a horizon under it ------------
    CortetsuInkPanel {
        x: root.width / 2 - width / 2
        y: center.y + mark.y + mark.height / 2 - height / 2
        width: 640 * root.unit
        height: width
        radius: width / 2
        groundAlpha: 0
        grain: 0
        hairline: false
        marks: false
        wash: root.rejected ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
        washAlpha: CortetsuDesign.materialHeroWashAlpha * 1.4
        washX: 0.5
        washY: 0.5
    }

    // A planet's rim: a very large circle whose top edge passes just under
    // the mark, lit along its edge and fading inwards.
    Item {
        objectName: "lockHorizon"
        anchors.fill: parent
        clip: true
        Rectangle {
            readonly property real diameter: root.width * 2.2
            width: diameter
            height: diameter
            radius: diameter / 2
            x: root.width / 2 - diameter / 2
            y: center.y + mark.y + mark.height * 0.78
            border.width: 2
            border.color: Qt.alpha(root.rejected ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary, 0.55)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(root.rejected ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary, 0.16) }
                GradientStop { position: 0.08; color: Qt.alpha(CortetsuDesign.colorSumi, 0.30) }
                GradientStop { position: 1; color: Qt.alpha(CortetsuDesign.colorSumi, 0.30) }
            }
        }
    }

    // --- Brand, top left --------------------------------------------------
    RowLayout {
        objectName: "lockBrand"
        x: 40 * root.unit
        y: 32 * root.unit
        spacing: CortetsuDesign.spacingStandard
        opacity: root.secondaryOpacity
        CortetsuEvolvingMark {
            phase: "Ascended"
            animated: false
            monochrome: true
            monochromeColor: CortetsuDesign.colorWashi
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
        }
        CortetsuText {
            text: "Cortetsu"
            textSize: CortetsuTypography.titleSmallPx
            font.weight: Font.DemiBold
        }
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 26
            color: Qt.alpha(CortetsuDesign.colorWashi, 0.24)
        }
        CortetsuText {
            text: qsTr("Sesión bloqueada")
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }
    }

    // --- Wings --------------------------------------------------------------
    LockMedia {
        objectName: "lockMedia"
        visible: root.wings && !!player
        opacity: root.secondaryOpacity
        anchors.right: center.left
        anchors.rightMargin: CortetsuDesign.spacingSection * 1.5
        y: center.y + clock.y + clock.height / 2 - height / 2
        onHandBackFocus: root.focusRequested()
    }

    LockMissed {
        objectName: "lockMissed"
        visible: root.wings && !CortetsuConfig.lockHideNotifs && apps.length > 0
        opacity: root.secondaryOpacity
        anchors.left: center.right
        anchors.leftMargin: CortetsuDesign.spacingSection * 1.5
        y: center.y + clock.y + clock.height / 2 - height / 2
    }

    // --- Centre -------------------------------------------------------------
    ColumnLayout {
        id: center
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -40 * root.unit
        width: Math.min(parent.width - CortetsuDesign.spacingSection * 2, 520)
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
            Layout.preferredWidth: 168 * root.unit
            Layout.preferredHeight: 168 * root.unit
            Layout.alignment: Qt.AlignHCenter
        }

        // The clock is the focal point; the date follows it.
        CortetsuText {
            id: clock
            objectName: "lockClock"
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: CortetsuDesign.spacingStandard
            text: Time.timeStr
            textSize: Math.round(CortetsuTypography.displayHeroPx * 2.6 * root.unit)
            font.weight: Font.Light
            font.letterSpacing: 2
        }

        CortetsuText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: -CortetsuDesign.spacingCompact
            Layout.bottomMargin: CortetsuDesign.spacingStandard
            text: CortetsuRegional.formatDate(Time.date, "longDay", true)
            textSize: CortetsuTypography.titleMediumPx
            color: CortetsuDesign.colorOnSurface
        }

        // Who is locked: a capsule with the initial and the session.
        Item {
            objectName: "lockUser"
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: parent.width
            implicitWidth: Math.min(center.width, 340)
            implicitHeight: 64

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.55)
                border.width: 1
                border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.12)
            }
            RowLayout {
                id: userRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 10
                anchors.rightMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                spacing: CortetsuDesign.spacingStandard
                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: width / 2
                    color: CortetsuDesign.colorPrimaryContainer
                    border.width: 1
                    border.color: Qt.alpha(CortetsuDesign.colorPrimary, 0.5)
                    CortetsuText {
                        anchors.centerIn: parent
                        text: root.userLabel.slice(0, 1).toLocaleUpperCase()
                        textSize: CortetsuTypography.titleSmallPx
                        font.weight: Font.DemiBold
                        color: CortetsuDesign.colorOnPrimaryContainer
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 0
                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.userLabel
                        textSize: CortetsuTypography.bodyLargePx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    CortetsuText {
                        Layout.fillWidth: true
                        text: qsTr("Sesión Wayland bloqueada")
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Rectangle {
            id: field
            objectName: "lockPasswordField"
            Layout.fillWidth: true
            Layout.topMargin: CortetsuDesign.spacingCompact
            implicitHeight: 60
            radius: height / 2
            color: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.78)
            border.width: root.rejected ? 2 : 1.5
            border.color: root.rejected ? CortetsuDesign.colorVermillion : Qt.alpha(CortetsuDesign.colorPrimary, 0.8)
            transform: Translate { id: nudge }

            CortetsuIcon {
                id: lockIcon
                anchors.left: parent.left
                anchors.leftMargin: CortetsuDesign.spacingStandard + 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.rejected ? "lock_reset" : "lock"
                iconSize: CortetsuTypography.iconMediumPx
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
                anchors.rightMargin: CortetsuDesign.spacingStandard + 8
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

        // Under the field: what went wrong, or that PAM is ready.
        Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(message.implicitHeight, ready.implicitHeight)

            CortetsuText {
                id: message
                objectName: "lockMessage"
                width: parent.width
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

            RowLayout {
                id: ready
                objectName: "lockReady"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.pam.state === 0 && !root.accepted
                opacity: root.secondaryOpacity
                spacing: CortetsuDesign.spacingCompact
                Rectangle {
                    Layout.preferredWidth: 7
                    Layout.preferredHeight: 7
                    radius: 3.5
                    color: root.checking ? CortetsuDesign.colorWarning : CortetsuDesign.colorSuccess
                }
                CortetsuText {
                    text: root.checking ? qsTr("PAM comprueba la contraseña") : qsTr("Escribe para desbloquear · Intro confirma")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
            }
        }
    }

    // --- The machine, at the foot: battery, network, keyboard -------------
    Item {
        objectName: "lockStatusBar"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 36 * root.unit
        implicitWidth: status.implicitWidth + CortetsuDesign.spacingSpacious * 2
        implicitHeight: 64
        opacity: root.secondaryOpacity

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
            spacing: CortetsuDesign.spacingSection

            Repeater {
                model: [
                    { icon: CortetsuPower.hasBattery ? Icons.getBatteryIcon(CortetsuPower.value, root.batteryCharging) : "power",
                      text: root.batteryLabel, detail: CortetsuPower.hasBattery ? (root.batteryCharging ? qsTr("Cargando") : qsTr("Con batería")) : qsTr("Sin batería") },
                    { icon: CortetsuNetwork.activeEthernet ? "cable" : (CortetsuNetwork.active ? "wifi" : "wifi_off"),
                      text: root.networkLabel, detail: CortetsuNetwork.activeEthernet || CortetsuNetwork.active ? qsTr("Conectada") : qsTr("Desconectada") },
                    { icon: "keyboard", text: root.keyboardLayout, detail: root.numLock ? qsTr("Bloq Num activo") : qsTr("Distribución") }
                ]
                delegate: RowLayout {
                    required property var modelData
                    spacing: CortetsuDesign.spacingStandard
                    CortetsuIcon {
                        text: parent.modelData.icon
                        iconSize: CortetsuTypography.iconMediumPx
                        color: CortetsuDesign.colorOnSurface
                    }
                    ColumnLayout {
                        spacing: 0
                        CortetsuText {
                            Layout.maximumWidth: 200
                            text: parent.parent.modelData.text
                            textSize: CortetsuTypography.bodySmallPx
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        CortetsuText {
                            text: parent.parent.modelData.detail
                            textSize: CortetsuTypography.labelSmallPx
                            color: CortetsuDesign.colorOnSurfaceVariant
                        }
                    }
                }
            }
        }
    }
}
