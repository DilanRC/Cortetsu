pragma Singleton

import QtQml

QtObject {
    id: root

    property string search: ""
    property string selectedId: "appearance"
    readonly property var categories: [
        { id: "appearance", group: qsTr("Personalización"), title: qsTr("Apariencia"), icon: "palette", detail: qsTr("Esquema, superficie y movimiento"), keywords: qsTr("tema color transparencia reloj visualizador") },
        { id: "wallpaper", group: qsTr("Personalización"), title: qsTr("Fondo de pantalla"), icon: "wallpaper", detail: qsTr("Superficie actual"), keywords: qsTr("fondo wallpaper imagen gestor") },
        { id: "desktop", group: qsTr("Escritorio"), title: qsTr("Escritorio"), icon: "desktop_windows", detail: qsTr("Espacios y comportamiento de ventanas"), keywords: qsTr("dashboard clima multimedia métricas reloj") },
        { id: "bottomhub", group: qsTr("Escritorio"), title: qsTr("BottomHub"), icon: "dock_to_bottom", detail: qsTr("Grupo y ventanas emergentes"), keywords: qsTr("barra dock bandeja estado popout volumen") },
        { id: "launcher", group: qsTr("Escritorio"), title: qsTr("Lanzador"), icon: "search", detail: qsTr("Búsqueda y densidad de resultados"), keywords: qsTr("apps acciones fondos esquemas fuzzy hover") },
        { id: "notifications", group: qsTr("Sistema"), title: qsTr("Notificaciones"), icon: "notifications", detail: qsTr("No molestar, historial y avisos"), keywords: qsTr("dnd alertas avisos historial pantalla completa") },
        { id: "network", group: qsTr("Sistema"), title: qsTr("Red"), icon: "wifi", detail: qsTr("Estado de la conexión"), keywords: qsTr("wifi ethernet conexión señal internet") },
        { id: "bluetooth", group: qsTr("Sistema"), title: qsTr("Bluetooth"), icon: "bluetooth", detail: qsTr("Dispositivos y adaptadores"), keywords: qsTr("inalámbrico dispositivos emparejar") },
        { id: "audio", group: qsTr("Sistema"), title: qsTr("Audio"), icon: "volume_up", detail: qsTr("Salida y entrada"), keywords: qsTr("sonido volumen micrófono salida entrada") },
        { id: "power", group: qsTr("Sistema"), title: qsTr("Energía"), icon: "bolt", detail: qsTr("Batería y reposo"), keywords: qsTr("batería suspensión carga bloqueo reposo") },
        { id: "display", group: qsTr("Hardware"), title: qsTr("Pantalla"), icon: "monitor", detail: qsTr("Modos y distribución"), keywords: qsTr("monitor brillo resolución pantalla") },
        { id: "input", group: qsTr("Hardware"), title: qsTr("Entrada"), icon: "keyboard", detail: qsTr("Teclado y gestos"), keywords: qsTr("teclado vim caps lock num lock idioma") },
        { id: "shortcuts", group: qsTr("Hardware"), title: qsTr("Atajos"), icon: "keyboard_command_key", detail: qsTr("Asignaciones actuales"), keywords: qsTr("teclas super shortcut accesos") },
        { id: "about", group: qsTr("Sistema"), title: qsTr("Acerca de"), icon: "info", detail: qsTr("Identidad de Cortetsu"), keywords: qsTr("versión diagnóstico identidad") }
    ]

    readonly property var filteredCategories: categories.filter(item => {
        const needle = root.search.trim().toLowerCase();
        return !needle || `${item.group} ${item.title} ${item.detail} ${item.keywords}`.toLowerCase().includes(needle);
    })

    function select(id: string): void { selectedId = id; }
}
