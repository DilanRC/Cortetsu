pragma ComponentBehavior: Bound

import QtQuick
import "../components"
import "../theme"
import "CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    property bool recordingActive: false
    property bool dndActive: false
    property bool idleInhibited: false

    readonly property bool hasStatus: recordingActive || dndActive || idleInhibited
    // In a lateral Hub the states stack and show their glyph only; the
    // tooltip still names each one.
    property bool vertical: false
    property string tooltipPlacement: "above"
    // The pill opens along the Hub: its length is animated, never its girth.
    property real along: hasStatus ? (vertical ? pill.implicitHeight : pill.implicitWidth) : 0

    signal stopRecordingRequested()
    signal toggleDndRequested()
    signal toggleIdleInhibitorRequested()

    width: vertical ? 44 : along
    height: vertical ? along : 44
    implicitWidth: width
    implicitHeight: height
    visible: hasStatus || along > 0
    opacity: hasStatus ? 1 : 0
    scale: hasStatus ? 1 : 0.97
    transformOrigin: Item.Center
    clip: true

    // design-lint: allow motion-layout-property: the hub row opens the gap with the pill; without it the neighbours jump
    Behavior on along {
        NumberAnimation {
            duration: CortetsuDesign.motionStandardMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }

    CortetsuSurface {
        id: pill

        anchors.centerIn: parent
        implicitWidth: root.vertical ? 36 : statusRow.implicitWidth + CortetsuDesign.spacingStandard * 2
        implicitHeight: root.vertical ? statusRow.implicitHeight + CortetsuDesign.spacingCompact * 2 : 36
        radiusValue: Math.min(width, height) / 2
        baseColor: Qt.lighter(CortetsuDesign.colorTetsu, 1.04)
        outlined: true

        HubFlow {
            id: statusRow

            anchors.centerIn: parent
            vertical: root.vertical
            spacing: root.vertical ? 2 : CortetsuDesign.spacingCompact

            StatusPillItem {
                visible: root.recordingActive
                icon: "fiber_manual_record"
                label: qsTr("REC")
                tooltip: qsTr("Grabación de pantalla activa")
                iconColor: CortetsuDesign.colorVermillion
                textColor: CortetsuDesign.colorVermillion
                pulse: true
                onClicked: root.stopRecordingRequested()
            }

            StatusPillDivider {
                visible: root.recordingActive && (root.dndActive || root.idleInhibited)
            }

            StatusPillItem {
                visible: root.dndActive
                icon: "do_not_disturb_on"
                label: qsTr("DND")
                tooltip: qsTr("No molestar activado")
                iconColor: CortetsuDesign.colorIndigo
                textColor: CortetsuDesign.colorWashi
                onClicked: root.toggleDndRequested()
            }

            StatusPillDivider {
                visible: root.dndActive && root.idleInhibited
            }

            StatusPillItem {
                visible: root.idleInhibited
                icon: "coffee"
                label: qsTr("Activo")
                tooltip: qsTr("Reposo suspendido")
                iconColor: CortetsuDesign.colorWashi
                textColor: CortetsuDesign.colorWashi
                onClicked: root.toggleIdleInhibitorRequested()
            }
        }
    }

    component StatusPillDivider: Rectangle {
        width: root.vertical ? 18 : 1
        height: root.vertical ? 1 : 18
        color: Qt.darker(CortetsuDesign.colorMuted, 1.9)
    }

    component StatusPillItem: Item {
        id: item

        property string icon: ""
        property string label: ""
        property string tooltip: ""
        property color iconColor: CortetsuDesign.colorWashi
        property color textColor: CortetsuDesign.colorWashi
        property bool pulse: false

        signal clicked()

        implicitWidth: root.vertical ? 32 : content.implicitWidth + CortetsuDesign.spacingCompact
        implicitHeight: root.vertical ? 32 : 36
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: item.tooltip

        CortetsuSurface {
            anchors.fill: parent
            radiusValue: height / 2
            baseColor: "transparent"
            hoverColor: Qt.lighter(CortetsuDesign.colorTetsu, 1.18)
            hovered: mouse.containsMouse
            pressed: mouse.pressed
            focused: item.activeFocus
            outlined: false
        }

        Row {
            id: content

            anchors.centerIn: parent
            spacing: CortetsuDesign.spacingUnit

            CortetsuIcon {
                id: iconLabel

                anchors.verticalCenter: parent.verticalCenter
                text: item.icon
                color: item.iconColor
                iconSize: CortetsuTypography.iconSmallPx

                // A recording in progress is the one live state here: the dot
                // breathes in opacity and stays still in size.
                SequentialAnimation on opacity {
                    running: item.pulse && root.recordingActive && !CortetsuDesign.reducedMotion
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) iconLabel.opacity = 1

                    NumberAnimation {
                        to: 0.45
                        duration: CortetsuDesign.motionDeliberateMs * 2
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: 1
                        duration: CortetsuDesign.motionDeliberateMs * 2
                        easing.type: Easing.InOutSine
                    }
                }
            }

            CortetsuText {
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.vertical
                text: item.label
                color: item.textColor
                textSize: CortetsuTypography.labelSmallPx
            }
        }

        CortetsuTooltip {
            target: item
            hovered: mouse.containsMouse
            focused: item.activeFocus
            text: item.tooltip
            placement: root.tooltipPlacement
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: item.forceActiveFocus()
            onClicked: item.clicked()
        }

        Keys.onEnterPressed: item.clicked()
        Keys.onReturnPressed: item.clicked()
        Keys.onSpacePressed: item.clicked()
    }
}
