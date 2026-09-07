import QtQuick

Item {
    id: root
    required property var screenState

    Content {
        anchors.fill: parent
        screenState: root.screenState
        controller: SettingsController
    }
}
