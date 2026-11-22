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
            if (root.rejected)
                cookie.flashRejected();
        }
    }

    readonly property bool wings: width >= 1240
    // Nebula's proportions are drawn for 1080 p and follow the height.
    readonly property real unit: Math.max(0.7, Math.min(1.3, height / 1080))

    // Ambient: nothing typed and nothing wrong for a while. Any key (the
    // buffer changes) or a pointer move brings the scene back at once.
    property bool ambient: false
    property real secondaryOpacity: ambient ? 0.3 : 1
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
        interval: 15000
        running: true
        onTriggered: root.ambient = root.pam.buffer.length === 0 && root.pam.state === 0 && !root.checking
    }
    Connections {
        target: root.pam
        function onBufferChanged(): void { root.wake(); }
        function onStateChanged(): void { root.wake(); }
    }
    HoverHandler { onPointChanged: root.wake() }

    LockSpace {
        anchors.fill: parent
        tone: root.rejected ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
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
        CortetsuIcon {
            text: "person"
            iconSize: CortetsuTypography.iconSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }
        CortetsuText {
            text: root.userLabel
            Layout.maximumWidth: 320
            textSize: CortetsuTypography.bodySmallPx
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        CortetsuText {
            text: qsTr("· sesión bloqueada")
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }
    }

    // --- Centre: the clock disc, the password, the machine ----------------
    LockCookie {
        id: cookie
        objectName: "lockCookie"
        width: Math.round(340 * root.unit)
        height: width
        x: (root.width - width) / 2
        y: root.height * 0.42 - height / 2
        phase: root.markPhase
        rejected: root.rejected
        accepted: root.accepted
    }

    LockMusicCard {
        objectName: "lockMedia"
        visible: root.wings && !!player
        opacity: root.secondaryOpacity
        width: Math.round(300 * root.unit)
        x: cookie.x - width - 48 * root.unit
        y: cookie.y + cookie.height / 2 - height / 2
        onHandBackFocus: root.focusRequested()
    }

    LockMissed {
        objectName: "lockMissed"
        visible: root.wings && !CortetsuConfig.lockHideNotifs && apps.length > 0
        opacity: root.secondaryOpacity
        x: cookie.x + cookie.width + 48 * root.unit
        y: cookie.y + cookie.height / 2 - height / 2
    }

    ColumnLayout {
        id: entry
        x: (root.width - width) / 2
        y: cookie.y + cookie.height + 28 * root.unit
        width: Math.min(root.width - CortetsuDesign.spacingSection * 2, 380)
        spacing: CortetsuDesign.spacingCompact

        Rectangle {
            id: field
            objectName: "lockPasswordField"
            Layout.fillWidth: true
            implicitHeight: 56
            radius: height / 2
            color: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.82)
            border.width: root.rejected ? 2 : root.accepted ? 2 : 1.5
            border.color: root.rejected ? CortetsuDesign.colorVermillion
                : root.accepted ? CortetsuDesign.colorSuccess : Qt.alpha(CortetsuDesign.colorPrimary, 0.8)
            transform: Translate { id: nudge }

            CortetsuIcon {
                id: lockIcon
                anchors.left: parent.left
                anchors.leftMargin: CortetsuDesign.spacingStandard + 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.accepted ? "lock_open" : root.rejected ? "lock_reset" : "lock"
                iconSize: CortetsuTypography.iconMediumPx
                color: root.rejected ? CortetsuDesign.colorVermillion
                    : root.accepted ? CortetsuDesign.colorSuccess : CortetsuDesign.colorOnSurfaceVariant
            }

            CortetsuText {
                anchors.left: lockIcon.right
                anchors.right: capsBadge.visible ? capsBadge.left : parent.right
                anchors.margins: CortetsuDesign.spacingStandard
                anchors.verticalCenter: parent.verticalCenter
                text: root.accepted ? qsTr("Desbloqueando…")
                    : root.checking ? qsTr("Comprobando…")
                    : root.pam.buffer.length ? "• ".repeat(root.pam.buffer.length) : qsTr("Contraseña")
                textSize: CortetsuTypography.bodyLargePx
                color: root.accepted ? CortetsuDesign.colorSuccess
                    : root.pam.buffer.length ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOnSurfaceVariant
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
                visible: root.pam.state === 0
                opacity: root.accepted ? 1 : root.secondaryOpacity
                spacing: CortetsuDesign.spacingCompact
                Rectangle {
                    Layout.preferredWidth: 7
                    Layout.preferredHeight: 7
                    radius: 3.5
                    color: root.checking ? CortetsuDesign.colorWarning : CortetsuDesign.colorSuccess
                }
                CortetsuText {
                    text: root.accepted ? qsTr("Autenticación correcta")
                        : root.checking ? qsTr("PAM comprueba la contraseña") : qsTr("Escribe para desbloquear · Intro confirma")
                    textSize: CortetsuTypography.labelSmallPx
                    font.weight: root.accepted ? Font.DemiBold : Font.Normal
                    color: root.accepted ? CortetsuDesign.colorSuccess : CortetsuDesign.colorOnSurfaceVariant
                }
            }
        }
    }

    LockStatsPanel {
        objectName: "lockStatusBar"
        x: (root.width - width) / 2
        y: Math.min(root.height - height - 28 * root.unit, entry.y + entry.height + 28 * root.unit)
        opacity: root.secondaryOpacity
        batteryLabel: root.batteryLabel + (root.batteryCharging ? qsTr(" · cargando") : "")
        networkLabel: root.networkLabel
        keyboardLabel: root.keyboardLayout + (root.numLock ? qsTr(" · Bloq Num") : "")
    }
}
