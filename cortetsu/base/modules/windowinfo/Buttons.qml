pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property var client
    property bool moveToWsExpanded

    anchors.fill: parent
    spacing: CortetsuTokens.spacing.small

    RowLayout {
        Layout.topMargin: CortetsuTokens.padding.large
        Layout.leftMargin: CortetsuTokens.padding.large
        Layout.rightMargin: CortetsuTokens.padding.large

        spacing: CortetsuTokens.spacing.medium

        CortetsuText {
            Layout.fillWidth: true
            text: qsTr("Move to workspace")
            elide: Text.ElideRight
        }

        CortetsuSurface {
            color: CortetsuColours.palette.m3primary
            radius: CortetsuTokens.rounding.medium

            implicitWidth: moveToWsIcon.implicitWidth + CortetsuTokens.padding.small
            implicitHeight: moveToWsIcon.implicitHeight + CortetsuTokens.padding.extraSmall

            CortetsuStateLayer {
                color: CortetsuColours.palette.m3onPrimary
                onClicked: root.moveToWsExpanded = !root.moveToWsExpanded
            }

            CortetsuIcon {
                id: moveToWsIcon

                anchors.centerIn: parent

                animate: true
                text: root.moveToWsExpanded ? "expand_more" : "keyboard_arrow_right"
                color: CortetsuColours.palette.m3onPrimary
                fontStyle: CortetsuTokens.font.icon.large
            }
        }
    }

    GridLayout {
        id: wsGrid

        Layout.fillWidth: true
        Layout.leftMargin: CortetsuTokens.padding.large
        Layout.rightMargin: CortetsuTokens.padding.large
        Layout.bottomMargin: root.moveToWsExpanded ? CortetsuTokens.spacing.medium : 0
        Layout.preferredHeight: root.moveToWsExpanded ? implicitHeight : 0
        opacity: root.moveToWsExpanded ? 1 : 0
        clip: true

        rowSpacing: CortetsuTokens.spacing.small
        columnSpacing: CortetsuTokens.spacing.small
        columns: 5

        Behavior on Layout.bottomMargin {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on Layout.preferredHeight {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Repeater {
            model: 10

            Button {
                required property int index
                readonly property int wsId: Math.floor((Hypr.activeWsId - 1) / 10) * 10 + index + 1
                readonly property bool isCurrent: root.client?.workspace.id === wsId

                onClicked: {
                    Hypr.moveWindow(root.client?.address ?? "", wsId, true);
                }

                color: isCurrent ? CortetsuColours.tPalette.m3surfaceContainerHighest : CortetsuColours.palette.m3tertiaryContainer
                onColor: isCurrent ? CortetsuColours.palette.m3onSurface : CortetsuColours.palette.m3onTertiaryContainer
                text: wsId
                disabled: isCurrent
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: CortetsuTokens.padding.large
        Layout.rightMargin: CortetsuTokens.padding.large
        Layout.bottomMargin: CortetsuTokens.padding.large

        spacing: root.client?.lastIpcObject.floating ? CortetsuTokens.spacing.medium : CortetsuTokens.spacing.small

        Button {
            color: CortetsuColours.palette.m3secondaryContainer
            onColor: CortetsuColours.palette.m3onSecondaryContainer
            text: root.client?.lastIpcObject.floating ? qsTr("Tile") : qsTr("Float")
            onClicked: Hypr.toggleFloat(root.client?.address ?? "")
        }

        Loader {
            asynchronous: true
            active: root.client?.lastIpcObject.floating ?? false
            Layout.fillWidth: active
            Layout.leftMargin: active ? 0 : -parent.spacing
            Layout.rightMargin: active ? 0 : -parent.spacing

            sourceComponent: Button {
                color: CortetsuColours.palette.m3secondaryContainer
                onColor: CortetsuColours.palette.m3onSecondaryContainer
                text: root.client?.lastIpcObject.pinned ? qsTr("Unpin") : qsTr("Pin")
                onClicked: Hypr.togglePin(root.client?.address ?? "")
            }
        }

        Button {
            color: CortetsuColours.palette.m3errorContainer
            onColor: CortetsuColours.palette.m3onErrorContainer
            text: qsTr("Kill")
            onClicked: Hypr.killWindow(root.client?.address ?? "")
        }
    }

    component Button: CortetsuSurface {
        property color onColor: CortetsuColours.palette.m3onSurface
        property alias disabled: stateLayer.disabled
        property alias text: label.text

        signal clicked

        radius: CortetsuTokens.rounding.medium

        Layout.fillWidth: true
        implicitHeight: label.implicitHeight + CortetsuTokens.padding.small

        CortetsuStateLayer {
            id: stateLayer

            color: parent.onColor
            onClicked: parent.clicked()
        }

        CortetsuText {
            id: label

            anchors.centerIn: parent

            animate: true
            color: parent.onColor
            font: CortetsuTokens.font.body.medium
        }
    }
}
