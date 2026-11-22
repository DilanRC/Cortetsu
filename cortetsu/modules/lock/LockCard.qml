pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import ".."
import "../../services"
import "../../utils"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "../desktop" as Desktop

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

    LockSky {
        anchors.fill: parent
        centerY: center.y + 110 * root.unit
    }

    // --- Brand and user, top left ---------------------------------------------
    RowLayout {
        objectName: "lockBrand"
        x: 40 * root.unit
        y: 32 * root.unit
        spacing: CortetsuDesign.spacingStandard
        opacity: root.secondaryOpacity
        CortetsuText {
            text: "Cortetsu"
            textSize: CortetsuTypography.titleSmallPx
            font.weight: Font.DemiBold
        }
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 26
            color: Qt.alpha(CortetsuDesign.colorWashi, 0.3)
        }
        CortetsuIcon {
            text: "person"
            iconSize: CortetsuTypography.iconSmallPx
            color: CortetsuDesign.colorWashi
        }
        CortetsuText {
            text: root.userLabel
            Layout.maximumWidth: 320
            textSize: CortetsuTypography.bodySmallPx
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }

    // --- Above the clock: sky, moon, battery (Nebula's bubbles) -------------
    // The moon's age from a known new moon (2000-01-06 18:14 UTC); a real
    // computation, not a picture.
    readonly property real moonAge: {
        void Time.date;
        const days = (Date.now() - Date.UTC(2000, 0, 6, 18, 14)) / 86400000;
        return ((days % 29.530588853) + 29.530588853) % 29.530588853;
    }
    readonly property string moonGlyph: ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"][Math.round(moonAge / 29.530588853 * 8) % 8]

    Row {
        objectName: "lockBubbles"
        x: (root.width - width) / 2
        y: center.y - height - 24 * root.unit
        spacing: 22 * root.unit
        opacity: root.secondaryOpacity
        LockBubble {
            visible: !!Weather.cc
            glyph: Weather.icon
            text: Weather.temp
        }
        LockBubble {
            glyph: root.moonGlyph
            text: qsTr("Luna")
        }
        LockBubble {
            visible: CortetsuPower.hasBattery
            ring: CortetsuPower.value
        }
    }

    // --- Centre: the mark, large, and the time ----------------------------
    ColumnLayout {
        id: center
        objectName: "lockCenter"
        x: (root.width - width) / 2
        y: root.height * 0.40 - height / 2
        spacing: 0

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 220 * root.unit
            Layout.preferredHeight: 220 * root.unit

            LockBlackHole {
                anchors.centerIn: parent
                width: parent.width * 0.7
                height: width
                playing: !!Players.active?.isPlaying
                tone: root.accepted ? CortetsuDesign.colorSuccess : root.rejected ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
            }

            // Acceptance lights a halo around the mark before the release.
            Rectangle {
                objectName: "lockAcceptedHalo"
                anchors.centerIn: parent
                width: parent.width * (root.accepted ? 1.5 : 1.1)
                height: width
                radius: width / 2
                color: Qt.alpha(root.accepted ? CortetsuDesign.colorSuccess : root.rejected ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary,
                    root.accepted ? 0.22 : root.rejected ? 0.2 : 0.10)
                border.width: root.accepted ? 3 : 0
                border.color: Qt.alpha(CortetsuDesign.colorSuccess, 0.6)
                Behavior on width { enabled: !CortetsuDesign.reducedMotion; NumberAnimation { duration: 700; easing.type: Easing.OutCubic } } // design-lint: allow token-literal-duration: fits the 900 ms hold
                Behavior on color { ColorAnimation { duration: 200 } } // design-lint: allow token-literal-duration: a state flash
            }
            CortetsuEvolvingMark {
                id: mark
                objectName: "lockMark"
                anchors.fill: parent
                phase: root.markPhase
                animated: !CortetsuDesign.reducedMotion
                monochrome: true
                monochromeColor: root.rejected ? CortetsuDesign.colorVermillion
                    : root.accepted ? CortetsuDesign.colorSuccess : CortetsuDesign.colorWashi
            }
        }
        CortetsuText {
            objectName: "lockClock"
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8 * root.unit
            text: Time.timeStr
            textSize: Math.round(84 * root.unit)
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
            style: Text.Raised
            styleColor: Qt.alpha(CortetsuDesign.colorSumi, 0.4)
        }
        CortetsuText {
            Layout.alignment: Qt.AlignHCenter
            text: CortetsuRegional.formatDate(Time.date, "longDay", true)
            textSize: CortetsuTypography.titleSmallPx
            color: Qt.alpha(CortetsuDesign.colorWashi, 0.85)
        }
    }

    LockMusicCard {
        objectName: "lockMedia"
        visible: root.wings && !!player
        opacity: root.secondaryOpacity
        width: Math.round(300 * root.unit)
        x: center.x - width - 70 * root.unit
        y: center.y + center.height / 2 - height / 2
        onHandBackFocus: root.focusRequested()
    }

    LockMissed {
        objectName: "lockMissed"
        visible: root.wings && !CortetsuConfig.lockHideNotifs && apps.length > 0
        opacity: root.secondaryOpacity
        width: Math.round(320 * root.unit)
        x: center.x + center.width + 70 * root.unit
        y: center.y + center.height / 2 - height / 2
    }

    ColumnLayout {
        id: entry
        x: (root.width - width) / 2
        y: center.y + center.height + 24 * root.unit
        width: Math.min(root.width - CortetsuDesign.spacingSection * 2, 340)
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
                // Typed characters show as coloured dots (below); the text
                // stays for screen readers and the tests.
                opacity: root.pam.buffer.length && !root.checking && !root.accepted ? 0 : 1
                textSize: CortetsuTypography.bodyLargePx
                color: root.accepted ? CortetsuDesign.colorSuccess
                    : root.pam.buffer.length ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideLeft
            }

            // One dot per character, in the scheme's colours, popping in
            // (Nebula's input), at most twelve.
            Row {
                objectName: "lockTypedDots"
                anchors.left: lockIcon.right
                anchors.leftMargin: CortetsuDesign.spacingStandard
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                visible: root.pam.buffer.length > 0 && !root.checking && !root.accepted
                Repeater {
                    model: Math.min(root.pam.buffer.length, 12)
                    delegate: Rectangle {
                        required property int index
                        width: 14
                        height: 14
                        radius: [7, 4, 7][index % 3]
                        rotation: index % 3 === 1 ? 45 : 0
                        color: [CortetsuDesign.colorPrimary, CortetsuDesign.colorIndicator, CortetsuDesign.colorSecondary][index % 3]
                        scale: 0
                        Component.onCompleted: scale = 1
                        Behavior on scale { enabled: !CortetsuDesign.reducedMotion; NumberAnimation { duration: 260; easing.type: Easing.OutBack } } // design-lint: allow token-literal-duration: a dot popping in
                    }
                }
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

    // The machine under the password (Nebula's usage cards): two rows of
    // three real readings with a minute of history; probes run only while
    // the lock is on screen.
    Desktop.ServiceUse { target: Cpu; active: root.visible }
    Desktop.ServiceUse { target: Gpu; active: root.visible }
    Desktop.ServiceUse { target: Memory; active: root.visible }
    Desktop.ServiceUse { target: Storage; active: root.visible }
    Desktop.ServiceUse { target: NetworkUsage; active: root.visible }

    Grid {
        objectName: "lockStatusBar"
        columns: 3
        spacing: 14 * root.unit
        x: (root.width - width) / 2
        y: Math.min(root.height - height - 24 * root.unit, entry.y + entry.height + 26 * root.unit)
        opacity: root.secondaryOpacity

        LockUsageCard { label: qsTr("CPU"); icon: "memory"; fraction: Cpu.percentage; text: `${Math.round(Cpu.percentage * 100)} %`
            subText: Cpu.temperature > 0 ? qsTr("%1 °C").arg(Math.round(Cpu.temperature)) : "" }
        LockUsageCard {
            label: qsTr("GPU"); icon: "developer_board"
            fraction: Gpu.type !== Gpu.noneType ? Gpu.percentage : -1
            text: Gpu.type !== Gpu.noneType ? `${Math.round(Gpu.percentage * 100)} %` : qsTr("En reposo")
        }
        LockUsageCard { label: qsTr("Memoria"); icon: "memory_alt"; fill: CortetsuDesign.colorIndicator
            fraction: Memory.total > 0 ? Memory.percentage : -1; text: Memory.total > 0 ? `${Math.round(Memory.percentage * 100)} %` : "—"
            subText: Memory.total > 0 ? qsTr("%1 GB en uso").arg((Memory.used / 1048576).toFixed(1)) : "" }
        LockUsageCard {
            label: CortetsuPower.hasBattery ? qsTr("Batería") : qsTr("Energía"); icon: CortetsuPower.hasBattery ? Icons.getBatteryIcon(CortetsuPower.value, root.batteryCharging) : "power"
            fraction: CortetsuPower.hasBattery ? CortetsuPower.value : -1
            text: CortetsuPower.hasBattery ? root.batteryLabel.replace(qsTr("Batería "), "") : qsTr("Enchufado")
            subText: CortetsuPower.hasBattery && root.batteryCharging ? qsTr("Cargando") : ""
        }
        LockUsageCard {
            label: qsTr("Disco"); icon: "hard_drive"; fill: CortetsuDesign.colorSecondary
            fraction: Storage.primaryDisk ? Storage.percentage : -1
            text: Storage.primaryDisk ? `${Math.round(Storage.percentage * 100)} %` : "—"
            subText: Storage.primaryDisk ? (Storage.primaryDisk.mount ?? "") : ""
        }
        LockUsageCard {
            visible: false
            label: qsTr("Temperatura"); icon: "thermostat"
            fraction: Cpu.temperature > 0 ? Math.min(1, Cpu.temperature / 100) : -1
            text: Cpu.temperature > 0 ? qsTr("%1 °C").arg(Math.round(Cpu.temperature)) : "—"
        }
        LockUsageCard {
            id: netCard
            function speed(bytes: real): string {
                return bytes >= 1048576 ? qsTr("%1 MB/s").arg((bytes / 1048576).toFixed(1)) : qsTr("%1 KB/s").arg(Math.round(bytes / 1024));
            }
            label: root.networkLabel; icon: CortetsuNetwork.activeEthernet ? "cable" : (CortetsuNetwork.active ? "wifi" : "wifi_off")
            fill: CortetsuDesign.colorIndicator
            fraction: -1
            text: ""
            // Nebula's speed pills: down and up, each with its arrow.
            Column {
                x: 12
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                spacing: 6
                Repeater {
                    model: [["arrow_downward", NetworkUsage.downloadSpeed], ["arrow_upward", NetworkUsage.uploadSpeed]]
                    delegate: Rectangle {
                        required property var modelData
                        width: 150
                        height: 26
                        radius: 13
                        color: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.7)
                        Rectangle {
                            x: 3; anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20; radius: 10
                            color: Qt.alpha(CortetsuDesign.colorIndicator, 0.22)
                            CortetsuIcon { anchors.centerIn: parent; text: parent.parent.modelData[0]; iconSize: 13; color: CortetsuDesign.colorIndicator }
                        }
                        CortetsuText {
                            x: 30; anchors.verticalCenter: parent.verticalCenter
                            text: netCard.speed(parent.modelData[1])
                            textSize: CortetsuTypography.labelSmallPx
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }
        }
    }

    // Power and the greeter, at the bottom left (Nebula keeps them there).
    LockSessionControls {
        objectName: "lockSessionControls"
        x: 40 * root.unit
        y: root.height - height - 32 * root.unit
        opacity: root.secondaryOpacity
        onHandBackFocus: root.focusRequested()
    }
}
