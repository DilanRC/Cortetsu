pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services

ColumnLayout {
    id: root

    function refresh() {
        kb.refresh();
    }

    spacing: CortetsuTokens.spacing.small
    width: CortetsuTokens.sizes.bar.kbLayoutWidth

    Component.onCompleted: kb.start()

    KbLayoutModel {
        id: kb
    }

    CortetsuText {
        Layout.topMargin: CortetsuTokens.padding.medium
        Layout.rightMargin: CortetsuTokens.padding.extraSmall
        text: qsTr("Keyboard Layouts")
        font: CortetsuTokens.font.body.builders.medium.weight(Font.Medium).build()
    }

    ListView {
        id: list

        model: kb.visibleModel

        Layout.fillWidth: true
        Layout.rightMargin: CortetsuTokens.padding.extraSmall
        Layout.topMargin: CortetsuTokens.spacing.small

        clip: true
        interactive: true
        implicitHeight: Math.min(contentHeight, 320)
        visible: kb.visibleModel.count > 0
        spacing: CortetsuTokens.spacing.small

        add: Transition {
            NumberAnimation {
                properties: "opacity"
                from: 0
                to: 1
                duration: CortetsuTokens.anim.durations.small
            }
            NumberAnimation {
                properties: "y"
                duration: CortetsuTokens.anim.durations.normal
                easing.type: Easing.OutCubic
            }
        }
        remove: Transition {
            NumberAnimation {
                properties: "opacity"
                to: 0
                duration: CortetsuTokens.anim.durations.small
            }
        }
        move: Transition {
            NumberAnimation {
                properties: "y"
                duration: CortetsuTokens.anim.durations.normal
                easing.type: Easing.OutCubic
            }
        }
        displaced: Transition {
            NumberAnimation {
                properties: "y"
                duration: CortetsuTokens.anim.durations.normal
                easing.type: Easing.OutCubic
            }
        }

        delegate: Item {
            id: kbDelegate

            required property int layoutIndex
            required property string label
            readonly property bool isDisabled: layoutIndex > 3

            width: list.width
            height: Math.max(36, rowText.implicitHeight + CortetsuTokens.padding.small)
            ToolTip.visible: isDisabled && layer.containsMouse
            ToolTip.text: "XKB limitation: maximum 4 layouts allowed"

            CortetsuStateLayer {
                id: layer

                onClicked: {
                    if (!kbDelegate.isDisabled)
                        kb.switchTo(kbDelegate.layoutIndex);
                }

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: parent.height - 4
                radius: CortetsuTokens.rounding.full
                enabled: !kbDelegate.isDisabled
            }

            CortetsuText {
                id: rowText

                anchors.verticalCenter: layer.verticalCenter
                anchors.left: layer.left
                anchors.right: layer.right
                anchors.leftMargin: CortetsuTokens.padding.extraSmall
                anchors.rightMargin: CortetsuTokens.padding.extraSmall
                text: kbDelegate.label
                elide: Text.ElideRight
                opacity: kbDelegate.isDisabled ? 0.4 : 1.0
            }
        }
    }

    Rectangle {
        visible: kb.activeLabel.length > 0
        Layout.fillWidth: true
        Layout.rightMargin: CortetsuTokens.padding.extraSmall
        Layout.topMargin: CortetsuTokens.spacing.small

        implicitHeight: 1
        color: CortetsuColours.palette.m3onSurfaceVariant
        opacity: 0.35
    }

    RowLayout {
        id: activeRow

        visible: kb.activeLabel.length > 0
        Layout.fillWidth: true
        Layout.rightMargin: CortetsuTokens.padding.extraSmall
        Layout.topMargin: CortetsuTokens.spacing.small
        spacing: CortetsuTokens.spacing.small

        opacity: 1
        scale: 1

        CortetsuIcon {
            text: "keyboard"
            color: CortetsuColours.palette.m3primary
        }

        CortetsuText {
            Layout.fillWidth: true
            text: kb.activeLabel
            elide: Text.ElideRight
            font: CortetsuTokens.font.body.builders.medium.weight(Font.Medium).build()
            color: CortetsuColours.palette.m3primary
        }

        Connections {
            function onActiveLabelChanged() {
                if (!activeRow.visible)
                    return;
                popIn.restart();
            }

            target: kb
        }

        // A layout switch usually comes from the keyboard: the new label
        // fades in briefly and does not move or overshoot.
        NumberAnimation {
            id: popIn

            target: activeRow
            property: "opacity"
            from: 0.4
            to: 1
            duration: CortetsuTokens.anim.durations.small
            easing.type: Easing.OutCubic
        }
    }
}
