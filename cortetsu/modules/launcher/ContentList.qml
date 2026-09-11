pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import "../CortetsuSurface.qml"
import "../CortetsuText.qml"
import "../CortetsuIcon.qml"
import ".."
import "../../components"
import "../../utils"

Item {
    id: root

    required property var content
    required property var screenState
    required property var panels
    required property real maxHeight
    required property TextField search
    required property int padding
    required property int rounding

    readonly property bool showWallpapers: search.text.startsWith(`${CortetsuConfig.actionPrefix}wallpaper `)
    readonly property bool listLoading: showWallpapers && wallpaperList.status === Loader.Loading
    readonly property var currentList: showWallpapers ? wallpaperList.item : appList.item // Can be either ListView or PathView, so can't type properly
    property string animState: showWallpapers ? "wallpapers" : "apps"

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom

    clip: true
    state: animState

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.implicitWidth: Math.max(760, 760)
                root.implicitHeight: Math.min(root.maxHeight, appList.implicitHeight > 0 ? appList.implicitHeight : empty.implicitHeight)
                appList.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        },
        State {
            name: "wallpapers"

            PropertyChanges {
                root.implicitWidth: Math.max(760 * 1.2, wallpaperList.implicitWidth)
                root.implicitHeight: 300
                wallpaperList.active: true
            }
        }
    ]

    Behavior on animState {
        SequentialAnimation {
            CortetsuAnim {
                target: root
                property: "opacity"
                from: 1
                to: 0
                type: CortetsuAnim.DefaultEffects
            }
            PropertyAction {}
            CortetsuAnim {
                target: root
                property: "opacity"
                from: 0
                to: 1
                type: CortetsuAnim.DefaultEffects
            }
        }
    }

    Loader {
        id: appList

        active: false

        anchors.fill: parent

        sourceComponent: AppList {
            objectName: "launcherAppList"

            search: root.search
            screenState: root.screenState
        }
    }

    Loader {
        id: wallpaperList

        asynchronous: true
        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        sourceComponent: WallpaperList {
            objectName: "launcherWallpaperList"

            search: root.search
            screenState: root.screenState
            panels: root.panels
            content: root.content
        }
    }

    CortetsuStateMessage {
        id: empty

        opacity: !root.listLoading && root.currentList?.count === 0 ? 1 : 0
        scale: root.currentList?.count === 0 ? 1 : 0.5

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: 360
        icon: root.state === "wallpapers" ? "wallpaper_slideshow" : "manage_search"
        title: root.state === "wallpapers" ? qsTr("No wallpapers found") : qsTr("No results")
        detail: root.state === "wallpapers" && CortetsuWallpapers.list.length === 0
            ? qsTr("Try putting some wallpapers in %1").arg(Paths.shortenHome(CortetsuWallpapers.wallsdir))
            : qsTr("Try searching for something else")

        Behavior on opacity {
            CortetsuAnim {
                type: CortetsuAnim.DefaultEffects
            }
        }

        Behavior on scale {
            CortetsuAnim {}
        }
    }

    CortetsuStateMessage {
        id: loading

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: 360
        visible: root.listLoading
        kind: "loading"
        icon: "sync"
        title: qsTr("Loading wallpapers")
        detail: qsTr("Preparing the wallpaper library")
    }

    Behavior on implicitWidth {
        enabled: root.screenState?.launcher ?? false

        CortetsuAnim {}
    }

    Behavior on implicitHeight {
        enabled: root.screenState?.launcher ?? false

        CortetsuAnim {}
    }
}
