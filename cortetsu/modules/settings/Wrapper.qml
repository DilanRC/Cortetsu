import QtQuick

Item {
    id: root
    required property var screenState
    required property var screen

    Content {
        anchors.fill: parent
        screenState: root.screenState
        screen: root.screen
        controller: SettingsController
    }
}
