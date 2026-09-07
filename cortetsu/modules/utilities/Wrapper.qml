import QtQuick
import Quickshell
import "../../services"
import qs.modules
import "../CortetsuDesign.js" as CortetsuDesign

Item {
    id: root

    required property var screenState
    required property var popouts
    readonly property PersistentProperties props: PersistentProperties {
        property bool recordingListExpanded: false
        property string recordingConfirmDelete: ""
        property string recordingMode: ""
        reloadableId: "utilities"
    }
    readonly property bool shouldBeActive: screenState.utilities
        && !(screenState.session && CortetsuConfig.notificationExpire === false)
    readonly property real totalPadding: CortetsuDesign.spacingComfortable * 2
    readonly property real nonAnimHeight: ((content.item as Content)?.nonAnimHeight ?? 0) + totalPadding
    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    anchors.bottomMargin: 66 + (-implicitHeight - 5 - 66) * offsetScale
    implicitHeight: content.implicitHeight + totalPadding
    implicitWidth: Math.min(520, parent.width - CortetsuDesign.spacingComfortable)
    opacity: 1 - offsetScale
    scale: 1 - 0.018 * offsetScale
    transformOrigin: Item.Bottom

    Behavior on offsetScale {
        NumberAnimation {
            duration: root.shouldBeActive
                ? CortetsuDesign.motionStandardMs
                : CortetsuDesign.motionFastMs
            easing.type: root.shouldBeActive ? Easing.OutCubic : Easing.InCubic
        }
    }

    Loader {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: CortetsuDesign.spacingComfortable
        asynchronous: true
        active: root.shouldBeActive || root.visible
        sourceComponent: Content {
            implicitWidth: root.implicitWidth - root.totalPadding
            props: root.props
            screenState: root.screenState
            popouts: root.popouts
        }
    }
}
