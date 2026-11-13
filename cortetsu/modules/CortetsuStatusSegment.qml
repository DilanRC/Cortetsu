import QtQuick
import "../components"
import "../services"
import "../theme"
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
    required property bool audioVisible
    required property bool networkVisible
    required property bool bluetoothVisible
    required property bool batteryVisible
    required property bool statusPopoutsEnabled
    required property int notificationCount
    required property bool sidebarActive
    required property bool recordingActive
    required property bool dndActive
    required property bool idleInhibited
    required property date now
    required property bool sessionActive

    signal attachedControlRequested(string mode, real centerX)
    signal attachedControlEntered(string mode, real centerX)
    signal systemControlsEntered()
    signal systemControlsExited()
    signal detachedControlRequested(string mode)
    signal volumeMuteRequested()
    signal volumeWheel(real delta)
    signal notificationsRequested()
    signal stopRecordingRequested()
    signal toggleDndRequested()
    signal toggleIdleInhibitorRequested()
    signal calendarRequested()
    signal sessionRequested()

    // Read by Bottom Hub to locate the bell for the retained-surfaces scrim.
    readonly property Item notificationsButton: bellButton
    property alias notificationCountBadge: countBadge

    property bool vertical: false
    property string tooltipPlacement: "above"
    readonly property real thickness: Math.max(46, CortetsuDesign.rowHeight - 2)

    // The centre of a system control along the Hub, in segment coordinates.
    function centerFor(item): real {
        return root.vertical
            ? statusRow.y + systemControls.y + item.y + item.height / 2
            : statusRow.x + systemControls.x + item.x + item.width / 2;
    }

    implicitWidth: vertical ? thickness : statusRow.implicitWidth + 20
    implicitHeight: vertical ? statusRow.implicitHeight + 20 : thickness
    width: implicitWidth
    height: implicitHeight

    component Hairline: Rectangle {
        width: root.vertical ? 22 : 1
        height: root.vertical ? 1 : 22
        color: Qt.alpha(CortetsuDesign.colorMuted, 0.14)
    }

    CortetsuIsland {}

    HubFlow {
        id: statusRow
        vertical: root.vertical
        anchors.centerIn: parent
        // Positioners expose implicit size, but their runtime bounds must be
        // explicit for hover ownership and popup anchor calculations.
        width: implicitWidth
        height: implicitHeight
        spacing: 1

        // The four attached system controls form one hover island. Closing on
        // each individual button exit caused an enter/exit race while moving
        // between adjacent icons and while crossing into the popup window.
        HubFlow {
            id: systemControls
            vertical: root.vertical
            width: implicitWidth
            height: implicitHeight
            spacing: 1

            // The four icons are one pointer island. Individual MouseArea exit
            // events can arrive before the next icon enter event, so closing
            // from a child would race while moving across the cluster.
            HoverHandler {
                id: systemControlsHover
                enabled: root.statusPopoutsEnabled
                onHoveredChanged: {
                    if (hovered)
                        root.systemControlsEntered();
                    else
                        root.systemControlsExited();
                }
            }

            HubButton {
                id: volumeButton
                visible: root.audioVisible
                buttonSize: 40
                iconSize: CortetsuTypography.iconMediumPx
                icon: root.volumeIcon
                iconColor: root.volumeMuted
                    ? Qt.alpha(CortetsuDesign.colorMuted, 0.68)
                    : CortetsuDesign.colorMuted
                tooltip: root.volumeMuted ? qsTr("Activar sonido") : qsTr("Silenciar")
                tooltipOnHover: false
                tooltipPlacement: root.tooltipPlacement
                onHoveredChanged: {
                    if (hovered && root.statusPopoutsEnabled)
                        root.attachedControlEntered("audio", root.centerFor(volumeButton));
                }
                onClicked: root.volumeMuteRequested()
                onWheel: delta => root.volumeWheel(delta)
            }

            HubButton {
                id: networkButton
                visible: root.networkVisible
                buttonSize: 40
                iconSize: CortetsuTypography.iconMediumPx
                icon: root.networkIcon
                active: root.networkActive
                tooltip: root.networkTooltip
                tooltipOnHover: false
                tooltipPlacement: root.tooltipPlacement
                onHoveredChanged: {
                    if (hovered && root.statusPopoutsEnabled)
                        root.attachedControlEntered("network", root.centerFor(networkButton));
                }
                onClicked: if (root.statusPopoutsEnabled)
                    root.attachedControlRequested("network", root.centerFor(networkButton))
            }

            HubButton {
                id: bluetoothButton
                visible: root.bluetoothVisible
                buttonSize: 40
                iconSize: CortetsuTypography.iconMediumPx
                icon: root.bluetoothIcon
                active: root.bluetoothActive
                tooltip: qsTr("Bluetooth")
                tooltipOnHover: false
                tooltipPlacement: root.tooltipPlacement
                onHoveredChanged: {
                    if (hovered && root.statusPopoutsEnabled)
                        root.attachedControlEntered("bluetooth", root.centerFor(bluetoothButton));
                }
                onClicked: if (root.statusPopoutsEnabled)
                    root.attachedControlRequested("bluetooth", root.centerFor(bluetoothButton))
            }

            HubButton {
                id: batteryButton
                visible: root.batteryVisible
                buttonSize: 40
                iconSize: CortetsuTypography.iconMediumPx
                icon: root.batteryIcon
                iconColor: root.batteryCritical
                    ? CortetsuDesign.colorVermillion
                    : CortetsuDesign.colorMuted
                tooltip: root.batteryTooltip
                tooltipOnHover: false
                tooltipPlacement: root.tooltipPlacement
                onHoveredChanged: {
                    if (hovered && root.statusPopoutsEnabled)
                        root.attachedControlEntered("battery", root.centerFor(batteryButton));
                }
                onClicked: if (root.statusPopoutsEnabled)
                    root.attachedControlRequested("battery", root.centerFor(batteryButton))
            }
        }

        Hairline {}

        Item {
            id: bellButton
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
                tooltip: qsTr("Notificaciones")
                tooltipPlacement: root.tooltipPlacement
                onClicked: root.notificationsRequested()
            }

            Rectangle {
                id: countBadge
                objectName: "notificationCountBadge"
                visible: CortetsuConfig.bottomHub.statusCluster.showNotificationCount && root.notificationCount > 0
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 1
                anchors.rightMargin: 1
                width: Math.max(height, badgeText.implicitWidth + CortetsuDesign.spacingUnit * 2)
                height: 18
                radius: height / 2
                color: CortetsuDesign.colorIndigo
                border.width: 0

                CortetsuText {
                    id: badgeText
                    anchors.centerIn: parent
                    text: root.notificationCount > 9 ? qsTr("9+") : root.notificationCount
                    // On the primary fill; colorWashi is only light in Ink.
                    color: CortetsuDesign.colorOnPrimary
                    textSize: CortetsuTypography.labelSmallPx
                }
            }
        }

        StatusPill {
            vertical: root.vertical
            tooltipPlacement: root.tooltipPlacement
            recordingActive: root.recordingActive
            dndActive: root.dndActive
            idleInhibited: root.idleInhibited
            onStopRecordingRequested: root.stopRecordingRequested()
            onToggleDndRequested: root.toggleDndRequested()
            onToggleIdleInhibitorRequested: root.toggleIdleInhibitorRequested()
        }

        Hairline {}

        Item {
            objectName: "hubClock"
            implicitWidth: root.vertical ? 44 : 72
            implicitHeight: 44
            width: implicitWidth
            height: implicitHeight
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Calendario, %1").arg(Time.timeStr)

            CortetsuSurface {
                anchors.fill: parent
                anchors.margins: 2
                radiusValue: Math.min(width, height) / 2
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
                    // A lateral Hub is narrower than "12:34 p. m.": the
                    // meridiem drops to a second line there.
                    text: root.vertical ? Time.timeStr.replace(" ", "\n") : Time.timeStr
                    horizontalAlignment: Text.AlignHCenter
                    color: CortetsuDesign.colorWashi
                    textSize: root.vertical ? CortetsuTypography.labelMediumPx : CortetsuTypography.labelLargePx
                }

                CortetsuText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !root.vertical
                    text: CortetsuRegional.formatDate(root.now, "weekdayDay", false)
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
            tooltip: qsTr("Sesión")
            tooltipPlacement: root.tooltipPlacement
            activeColor: Qt.alpha(CortetsuDesign.colorVermillion, 0.74)
            iconColor: active || hovered || activeFocus
                ? CortetsuDesign.colorWashi
                : CortetsuDesign.colorMuted
            onClicked: root.sessionRequested()
        }
    }
}
