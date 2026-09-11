pragma Singleton

import QtQml

QtObject {
    id: root

    property string search: ""
    property string selectedId: "appearance"
    readonly property var categories: [
        { id: "appearance", title: qsTr("Appearance"), icon: "palette", detail: qsTr("Scheme, surface and motion") },
        { id: "desktop", title: qsTr("Desktop"), icon: "desktop_windows", detail: qsTr("Gaps and workspace behavior") },
        { id: "bottomhub", title: qsTr("BottomHub"), icon: "dock_to_bottom", detail: qsTr("Cluster and popouts") },
        { id: "launcher", title: qsTr("Launcher"), icon: "search", detail: qsTr("Search and result density") },
        { id: "notifications", title: qsTr("Notifications"), icon: "notifications", detail: qsTr("DND, history and toasts") },
        { id: "network", title: qsTr("Network"), icon: "wifi", detail: qsTr("Connection status") },
        { id: "bluetooth", title: qsTr("Bluetooth"), icon: "bluetooth", detail: qsTr("Devices and adapters") },
        { id: "audio", title: qsTr("Audio"), icon: "volume_up", detail: qsTr("Output and input") },
        { id: "power", title: qsTr("Power"), icon: "bolt", detail: qsTr("Battery and idle") },
        { id: "display", title: qsTr("Display"), icon: "monitor", detail: qsTr("Modes and layout") },
        { id: "input", title: qsTr("Input"), icon: "keyboard", detail: qsTr("Keyboard and gestures") },
        { id: "shortcuts", title: qsTr("Shortcuts"), icon: "keyboard_command_key", detail: qsTr("Current bindings") },
        { id: "wallpaper", title: qsTr("Wallpaper"), icon: "wallpaper", detail: qsTr("Current surface") },
        { id: "about", title: qsTr("About"), icon: "info", detail: qsTr("Cortetsu identity") }
    ]

    readonly property var filteredCategories: categories.filter(item => {
        const needle = root.search.trim().toLowerCase();
        return !needle || `${item.title} ${item.detail}`.toLowerCase().includes(needle);
    })

    function select(id: string): void { selectedId = id; }
}
