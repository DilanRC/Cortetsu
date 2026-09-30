pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.components.controls
import qs.components.effects
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    required property var dialog
    readonly property FileEntry currentItem: view.currentItem as FileEntry

    CortetsuSurface {
        anchors.fill: parent
        color: CortetsuColours.tPalette.m3surfaceContainer

        layer.enabled: true
        layer.effect: Mask {
            maskSource: mask
            maskInverted: true
        }
    }

    Item {
        id: mask

        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            anchors.fill: parent
            anchors.margins: CortetsuTokens.padding.extraSmall
            radius: CortetsuTokens.rounding.medium
        }
    }

    Loader {
        asynchronous: true
        anchors.centerIn: parent

        opacity: view.count === 0 ? 1 : 0
        active: opacity > 0

        sourceComponent: ColumnLayout {
            CortetsuIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "scan_delete"
                color: CortetsuColours.palette.m3outline
                fontStyle: CortetsuTokens.font.icon.builders.extraLarge.scale(2).weight(Font.Medium).build()
            }

            CortetsuText {
                text: qsTr("This folder is empty")
                color: CortetsuColours.palette.m3outline
                font: CortetsuTokens.font.body.builders.large.weight(Font.Medium).build()
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    GridView {
        id: view

        anchors.fill: parent
        anchors.margins: CortetsuTokens.padding.extraSmall + CortetsuTokens.padding.medium

        cellWidth: Sizes.itemWidth + CortetsuTokens.spacing.small
        cellHeight: Sizes.itemWidth + CortetsuTokens.spacing.large + CortetsuTokens.padding.medium * 2 + 1

        clip: true
        focus: true
        currentIndex: -1
        Keys.onEscapePressed: currentIndex = -1

        Keys.onReturnPressed: {
            if (root.dialog.selectionValid)
                root.dialog.accepted((currentItem as FileEntry).modelData.path);
        }
        Keys.onEnterPressed: {
            if (root.dialog.selectionValid)
                root.dialog.accepted((currentItem as FileEntry).modelData.path);
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: view
        }

        model: FileSystemModel {
            path: {
                if (root.dialog.cwd[0] !== "Home")
                    return root.dialog.cwd.join("/");
                if (root.dialog.cwd.length === 1)
                    return Paths.home;

                const base = Paths.userDirectory(root.dialog.cwd[1]);
                const rest = root.dialog.cwd.slice(2).join("/");
                return rest.length > 0 ? `${base}/${rest}` : base;
            }
            onPathChanged: view.currentIndex = -1
        }

        delegate: FileEntry {}

        add: Transition {
            Anim {
                properties: "opacity,scale"
                from: 0
                to: 1
            }
        }

        remove: Transition {
            Anim {
                type: Anim.DefaultEffects
                property: "opacity"
                to: 0
            }
            Anim {
                property: "scale"
                to: 0.5
            }
        }

        displaced: Transition {
            Anim {
                type: Anim.DefaultEffects
                properties: "opacity,scale"
                to: 1
                easing: CortetsuTokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }
    }

    CurrentItem {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: CortetsuTokens.padding.extraSmall

        currentItem: view.currentItem
    }

    component FileEntry: CortetsuSurface {
        id: item

        required property int index
                required property var modelData

        readonly property real nonAnimHeight: icon.implicitHeight + name.anchors.topMargin + name.implicitHeight + CortetsuTokens.padding.medium * 2

        implicitWidth: Sizes.itemWidth
        implicitHeight: nonAnimHeight

        radius: CortetsuTokens.rounding.large
        color: Qt.alpha(CortetsuColours.tPalette.m3surfaceContainerHighest, GridView.isCurrentItem ? CortetsuColours.tPalette.m3surfaceContainerHighest.a : 0)
        z: GridView.isCurrentItem || implicitHeight !== nonAnimHeight ? 1 : 0
        clip: true

        CortetsuStateLayer {
            onClicked: view.currentIndex = item.index
            onDoubleClicked: {
                if (item.modelData.isDir)
                    root.dialog.cwd.push(item.modelData.name);
                else if (root.dialog.selectionValid)
                    root.dialog.accepted(item.modelData.path);
            }
        }

        CachingIconImage {
            id: icon

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: CortetsuTokens.padding.medium

            implicitSize: Sizes.itemWidth - CortetsuTokens.padding.medium * 2

            Component.onCompleted: {
                const file = item.modelData;
                if (file.isImage)
                    source = Qt.resolvedUrl(file.path);
                else if (!file.isDir)
                    source = Quickshell.iconPath(file.mimeType.replace("/", "-"), "application-x-zerosize");
                else if (root.dialog.cwd.length === 1 && ["Desktop", "Documents", "Downloads", "Music", "Pictures", "Public", "Templates", "Videos"].includes(file.name))
                    source = Quickshell.iconPath(`folder-${file.name.toLowerCase()}`);
                else
                    source = Quickshell.iconPath("inode-directory");
            }
        }

        CortetsuText {
            id: name

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: icon.bottom
            anchors.topMargin: CortetsuTokens.spacing.small
            anchors.margins: CortetsuTokens.padding.medium

            horizontalAlignment: Text.AlignHCenter
            elide: item.GridView.isCurrentItem ? Text.ElideNone : Text.ElideRight
            wrapMode: item.GridView.isCurrentItem ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap

            Component.onCompleted: text = item.modelData.name
        }

        Behavior on implicitHeight {
            Anim {}
        }
    }
}
