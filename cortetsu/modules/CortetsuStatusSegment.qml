import QtQuick
import "../components"
import "CortetsuDesign.js" as CortetsuDesign
import "CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property string volumeIcon
    required property bool volumeMuted
    required property string networkIcon
    required property string networkTooltip
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
    signal attachedControlEntered(string mode, real centerX)
    signal attachedControlExited()
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
        return statusRow.x + systemControls.x + item.x + item.width / 2;
    }

    implicitWidth: statusRow.implicitWidth + CortetsuDesign.spacingUnit
    implicitHeight: 50
    width: implicitWidth
    height: implicitHeight

    component Hairline: Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: 22
        radius: 1
        color: Qt.alpha(CortetsuDesign.colorMuted, 0.14)
    }

    CortetsuSurface {
        anchors.fill: parent
        anchors.margins: 1
        z: -1
        radiusValue: CortetsuDesign.radiusLarge
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.38)
        outlined: true
    }

    Row {
        id: statusRow
        anchors.centerIn: parent
        spacing: 1

        // The four attached system controls form one hover island. Closing on
        // each individual button exit caused an enter/exit race while moving
        // between adjacent icons and while crossing into the popup window.
        Row {
            id: systemControls
            spacing: 1

            HoverHandler {
                id: systemControlsHover
                onHoveredChanged: {
                    if (!hovered)
                        root.attachedControlExited();
                }
            }

            HubButton {
                id: volumeButton
                buttonSize: 40
                iconSize: CortetsuTypography.iconMediumPx
                icon: root.volumeIcon
                iconColor: root.volumeMuted
                    ? Qt.alpha(CortetsuDesign.colorMuted, 0.68)
                    : CortetsuDesign.colorMuted
                tooltip: root.volumeMuted ? qsTr("Unmute") : qsTr("Mute")
                tooltipOnHover: false
                onHoveredChanged: {
                    if (hovered)
                        root.attachedControlEntered("audio", root.centerFor(volumeButton));
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
                tooltip: root.networkTooltip
                tooltipOnHover: false
                onHoveredChanged: {
                    if (hovered)
                        root.attachedControlEntered("network", root.centerFor(networkButton));
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
                tooltipOnHover: false
                onHoveredChanged: {
                    if (hovered)
                        root.attachedControlEntered("bluetooth", root.centerFor(bluetoothButton));
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
                tooltipOnHover: false
                onHoveredChanged: {
                    if (hovered)
                        root.attachedControlEntered("battery", root.centerFor(batteryButton));
                }
                onClicked: root.attachedControlRequested("battery", root.centerFor(batteryButton))
            }
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
                border.width: 0

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
            implicitWidth: 72
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
                hoverColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.72)
                outlineColor: parent.activeFocus
                    ? Qt.alpha(CortetsuDesign.colorWashi, 0.72)
                    : "transparent"
                hovered: clockMouse.containsMouse
                focused: parent.activeFocus
                outlined: parent.activeFocus
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
