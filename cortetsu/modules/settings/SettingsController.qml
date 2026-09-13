pragma Singleton

import QtQml

QtObject {
    id: root

    property string search: ""
    property string selectedId: "appearance"
    readonly property var categories: [
        { id: "appearance", title: qsTr("Apariencia"), icon: "palette", detail: qsTr("Esquema, superficie y movimiento") },
        { id: "desktop", title: qsTr("Escritorio"), icon: "desktop_windows", detail: qsTr("Espacios y comportamiento de ventanas") },
        { id: "bottomhub", title: qsTr("BottomHub"), icon: "dock_to_bottom", detail: qsTr("Grupo y ventanas emergentes") },
        { id: "launcher", title: qsTr("Lanzador"), icon: "search", detail: qsTr("Búsqueda y densidad de resultados") },
        { id: "notifications", title: qsTr("Notificaciones"), icon: "notifications", detail: qsTr("No molestar, historial y avisos") },
        { id: "network", title: qsTr("Red"), icon: "wifi", detail: qsTr("Estado de la conexión") },
        { id: "bluetooth", title: qsTr("Bluetooth"), icon: "bluetooth", detail: qsTr("Dispositivos y adaptadores") },
        { id: "audio", title: qsTr("Audio"), icon: "volume_up", detail: qsTr("Salida y entrada") },
        { id: "power", title: qsTr("Energía"), icon: "bolt", detail: qsTr("Batería y reposo") },
        { id: "display", title: qsTr("Pantalla"), icon: "monitor", detail: qsTr("Modos y distribución") },
        { id: "input", title: qsTr("Entrada"), icon: "keyboard", detail: qsTr("Teclado y gestos") },
        { id: "shortcuts", title: qsTr("Atajos"), icon: "keyboard_command_key", detail: qsTr("Asignaciones actuales") },
        { id: "wallpaper", title: qsTr("Fondo de pantalla"), icon: "wallpaper", detail: qsTr("Superficie actual") },
        { id: "about", title: qsTr("Acerca de"), icon: "info", detail: qsTr("Identidad de Cortetsu") }
    ]

    readonly property var filteredCategories: categories.filter(item => {
        const needle = root.search.trim().toLowerCase();
        return !needle || `${item.title} ${item.detail}`.toLowerCase().includes(needle);
    })

    function select(id: string): void { selectedId = id; }
}
