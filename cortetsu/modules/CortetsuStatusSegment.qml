import QtQuick
import "CortetsuDesign.js" as CortetsuDesign
import "CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property string volumeIcon
    required property bool volumeMuted
    required property string networkIcon
    required property bool networkActive
    required property string bluetoothIcon
    required property bool bluetoothActive
    required property string batteryIcon
    required property bool batteryCritical
    required property string batteryTooltip
    required property int notificationCount
    required property bool sidebarActive
    required property bool recordingActive
    required property bool dndActive
    required property bool idleInhibited
    required property date now
    required property bool sessionActive

    signal attachedControlRequested(string mode, real centerX)
    signal detachedControlRequested(string mode)
    signal volumeMuteRequested()
    signal volumeWheel(real delta)
    signal notificationsRequested()
    signal stopRecordingRequested()
    signal toggleDndRequested()
    signal toggleIdleInhibitorRequested()
    signal calendarRequested()
    signal sessionRequested()

    function centerFor(item): real {
        return item.x + item.width / 2;
    }

    implicitWidth: statusRow.implicitWidth + CortetsuDesign.spacingCompact
    implicitHeight: 52
    width: implicitWidth
    height: implicitHeight

    component Hairline: Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: 24
        radius: 1
        color: Qt.alpha(CortetsuDesign.colorMuted, 0.18)
    }

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusLarge
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.72)
        outlineColor: Qt.alpha(CortetsuDesign.colorMuted, 0.2)
        outlined: true
    }

    Row {
        id: statusRow
        anchors.centerIn: parent
        spacing: 2

        HubButton {
            id: volumeButton
            buttonSize: 40
            iconSize: CortetsuTypography.iconMediumPx
            icon: root.volumeIcon
            iconColor: root.volumeMuted
                ? Qt.alpha(CortetsuDesign.colorMuted, 0.68)
                : CortetsuDesign.colorMuted
            tooltip: root.volumeMuted ? qsTr("Unmute") : qsTr("Mute")
            onHoveredChanged: {
                if (hovered)
                    root.attachedControlRequested("audio", root.centerFor(volumeButton));
            }
            onClicked: root.volumeMuteRequested()
            onWheel: delta => root.volumeWheel(delta)
        }

        HubButton {
            id: networkButton
            buttonSize: 40
            iconSize: CortetsuTypography.iconMediumPx
            icon: root.networkIcon
            active: root.networkActive
            tooltip: qsTr("Network")
            onHoveredChanged: {
                if (hovered)
                    root.attachedControlRequested("network", root.centerFor(networkButton));
            }
            onClicked: root.attachedControlRequested("network", root.centerFor(networkButton))
        }

        HubButton {
            id: bluetoothButton
            buttonSize: 40
            iconSize: CortetsuTypography.iconMediumPx
            icon: root.bluetoothIcon
            active: root.bluetoothActive
            tooltip: qsTr("Bluetooth")
            onHoveredChanged: {
                if (hovered)
                    root.attachedControlRequested("bluetooth", root.centerFor(bluetoothButton));
            }
            onClicked: root.attachedControlRequested("bluetooth", root.centerFor(bluetoothButton))
        }

        HubButton {
            id: batteryButton
            buttonSize: 40
            iconSize: CortetsuTypography.iconMediumPx
            icon: root.batteryIcon
            iconColor: root.batteryCritical
                ? CortetsuDesign.colorVermillion
                : CortetsuDesign.colorMuted
            tooltip: root.batteryTooltip
            onHoveredChanged: {
                if (hovered)
                    root.attachedControlRequested("battery", root.centerFor(batteryButton));
            }
            onClicked: root.attachedControlRequested("battery", root.centerFor(batteryButton))
        }

        Hairline {}

        Item {
            implicitWidth: 44
            implicitHeight: 44
            width: implicitWidth
            height: implicitHeight

            HubButton {
                anchors.fill: parent
                buttonSize: 44
                iconSize: CortetsuTypography.iconMediumPx
                icon: "notifications"
                active: root.sidebarActive
                tooltip: qsTr("Notifications")
                onClicked: root.notificationsRequested()
            }

            Rectangle {
                visible: root.notificationCount > 0
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 1
                anchors.rightMargin: 1
                width: 17
                height: 17
                radius: 9
                color: CortetsuDesign.colorIndigo
                border.width: 1
                border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.22)

                CortetsuText {
                    anchors.centerIn: parent
                    text: root.notificationCount > 9 ? qsTr("9+") : root.notificationCount
                    color: CortetsuDesign.colorWashi
                    textSize: CortetsuTypography.labelSmallPx
                }
            }
        }

        StatusPill {
            recordingActive: root.recordingActive
            dndActive: root.dndActive
            idleInhibited: root.idleInhibited
            onStopRecordingRequested: root.stopRecordingRequested()
            onToggleDndRequested: root.toggleDndRequested()
            onToggleIdleInhibitorRequested: root.toggleIdleInhibitorRequested()
        }

        Hairline {}

        Item {
            implicitWidth: 74
            implicitHeight: 44
            width: implicitWidth
            height: implicitHeight
            focus: true
            activeFocusOnTab: true

            CortetsuSurface {
                anchors.fill: parent
                anchors.margins: 2
                radiusValue: CortetsuDesign.radiusSmall
                baseColor: "transparent"
                hoverColor: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.94)
                outlineColor: parent.activeFocus
                    ? Qt.alpha(CortetsuDesign.colorWashi, 0.82)
                    : Qt.alpha(CortetsuDesign.colorMuted, 0.12)
                hovered: clockMouse.containsMouse
                focused: parent.activeFocus
                outlined: false
            }

            Column {
                anchors.centerIn: parent
                spacing: -2

                CortetsuText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(root.now, "HH:mm")
                    color: CortetsuDesign.colorWashi
                    textSize: CortetsuTypography.labelLargePx
                }

                CortetsuText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(root.now, "ddd d")
                    color: CortetsuDesign.colorMuted
                    textSize: CortetsuTypography.labelSmallPx
                }
            }

            MouseArea {
                id: clockMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: parent.forceActiveFocus()
                onClicked: root.calendarRequested()
            }

            Keys.onEnterPressed: root.calendarRequested()
            Keys.onReturnPressed: root.calendarRequested()
            Keys.onSpacePressed: root.calendarRequested()
        }

        HubButton {
            buttonSize: 44
            iconSize: CortetsuTypography.iconMediumPx
            icon: "power_settings_new"
            active: root.sessionActive
            tooltip: qsTr("Session")
            activeColor: Qt.alpha(CortetsuDesign.colorVermillion, 0.74)
            iconColor: active || hovered || activeFocus
                ? CortetsuDesign.colorWashi
                : CortetsuDesign.colorMuted
            onClicked: root.sessionRequested()
        }
    }
}
