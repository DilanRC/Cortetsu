pragma ComponentBehavior: Bound

import QtQuick
import "../components"
import "CortetsuDesign.js" as CortetsuDesign
import "CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    property bool recordingActive: false
    property bool dndActive: false
    property bool idleInhibited: false

    readonly property bool hasStatus: recordingActive || dndActive || idleInhibited

    signal stopRecordingRequested()
    signal toggleDndRequested()
    signal toggleIdleInhibitorRequested()

    width: hasStatus ? pill.implicitWidth : 0
    implicitWidth: width
    implicitHeight: 44
    height: implicitHeight
    visible: hasStatus || width > 0
    opacity: hasStatus ? 1 : 0
    scale: hasStatus ? 1 : 0.97
    transformOrigin: Item.Center
    clip: true

    Behavior on width {
        NumberAnimation {
            duration: CortetsuDesign.motionStandardMs
            easing.type: Easing.OutCubic
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.OutCubic
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.OutCubic
        }
    }

    CortetsuSurface {
        id: pill

        anchors.centerIn: parent
        implicitWidth: statusRow.implicitWidth + CortetsuDesign.spacingStandard * 2
        implicitHeight: 36
        radiusValue: CortetsuDesign.radiusLarge
        baseColor: Qt.lighter(CortetsuDesign.colorTetsu, 1.04)
        outlined: true

        Row {
            id: statusRow

            anchors.centerIn: parent
            spacing: CortetsuDesign.spacingCompact

            StatusPillItem {
                visible: root.recordingActive
                icon: "fiber_manual_record"
                label: qsTr("REC")
                tooltip: qsTr("Screen recording active")
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
                tooltip: qsTr("Do Not Disturb enabled")
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
                label: qsTr("Awake")
                tooltip: qsTr("Idle inhibition active")
                iconColor: CortetsuDesign.colorWashi
                textColor: CortetsuDesign.colorWashi
                onClicked: root.toggleIdleInhibitorRequested()
            }
        }
    }

    component StatusPillDivider: Rectangle {
        width: 1
        height: 18
        anchors.verticalCenter: parent.verticalCenter
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

        implicitWidth: content.implicitWidth + CortetsuDesign.spacingCompact
        implicitHeight: 28
        focus: true
        activeFocusOnTab: true

        CortetsuSurface {
            anchors.fill: parent
            radiusValue: CortetsuDesign.radiusSmall
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
                scale: item.pulse && root.recordingActive ? 1 : 0.9

                SequentialAnimation on scale {
                    running: item.pulse && root.recordingActive
                    loops: Animation.Infinite

                    NumberAnimation {
                        to: 1.08
                        duration: CortetsuDesign.motionDeliberateMs * 2
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: 0.9
                        duration: CortetsuDesign.motionDeliberateMs * 2
                        easing.type: Easing.InOutSine
                    }
                }
            }

            CortetsuText {
                anchors.verticalCenter: parent.verticalCenter
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
