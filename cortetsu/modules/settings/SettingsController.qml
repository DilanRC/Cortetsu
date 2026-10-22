pragma Singleton

import QtQml
import "Navigation.js" as Navigation

// What Settings can show and which page is open. The list never changes at
// run time, so the Nexus keeps its rows and a search only hides some.
QtObject {
    id: root

    property string search: ""
    property string selectedId: "appearance"

    // `settings` names the controls of each page, so a search for a control
    // finds the page that holds it.
    readonly property var categories: [
        { id: "network", group: qsTr("Conexiones"), title: qsTr("Red"), icon: "wifi", keywords: qsTr("wifi ethernet internet contraseña perfil ip dns"),
          settings: [qsTr("Wi-Fi"), qsTr("Redes cercanas"), qsTr("Redes guardadas"), qsTr("Conexión automática"), qsTr("Copiar contraseña")] },
        { id: "bluetooth", group: qsTr("Conexiones"), title: qsTr("Bluetooth"), icon: "bluetooth", keywords: qsTr("inalámbrico emparejar auriculares"),
          settings: [qsTr("Adaptador Bluetooth"), qsTr("Dispositivos")] },
        { id: "audio", group: qsTr("Sistema"), title: qsTr("Audio"), icon: "volume_up", keywords: qsTr("sonido altavoces micrófono silenciar"),
          settings: [qsTr("Volumen de salida"), qsTr("Dispositivo de salida"), qsTr("Volumen de entrada"), qsTr("Dispositivo de entrada"), qsTr("Volumen por aplicación")] },
        { id: "display", group: qsTr("Sistema"), title: qsTr("Pantalla"), icon: "monitor", keywords: qsTr("monitor resolución escala luz nocturna"),
          settings: [qsTr("Brillo"), qsTr("Filtro de color"), qsTr("Temperatura de color"), qsTr("Gamma"), qsTr("Vibrance NVIDIA"), qsTr("Gestor de pantallas")] },
        { id: "power", group: qsTr("Sistema"), title: qsTr("Energía"), icon: "bolt", keywords: qsTr("batería carga suspensión reposo bloqueo"),
          settings: [qsTr("Evitar reposo durante el audio"), qsTr("Evitar reposo mientras carga"), qsTr("Bloquear antes de suspender")] },
        { id: "notifications", group: qsTr("Sistema"), title: qsTr("Notificaciones"), icon: "notifications", keywords: qsTr("dnd avisos historial silencio"),
          settings: [qsTr("No molestar"), qsTr("Ocultar en pantalla completa"), qsTr("Avisos visibles por grupo"), qsTr("Avisar del modo de juego"), qsTr("Vaciar historial")] },
        { id: "input", group: qsTr("Sistema"), title: qsTr("Entrada"), icon: "keyboard", keywords: qsTr("teclado vim distribución idioma"),
          settings: [qsTr("Distribución activa"), qsTr("Navegación estilo Vim")] },
        { id: "appearance", group: qsTr("Personalización"), title: qsTr("Apariencia"), icon: "palette", keywords: qsTr("tema color paleta"),
          settings: [qsTr("Esquema de color"), qsTr("Esquema según el fondo"), qsTr("Superficies transparentes"), qsTr("Grosor de bordes"), qsTr("Reloj de 12 horas"), qsTr("Temperatura en Fahrenheit"), qsTr("Visualizador de audio")] },
        { id: "wallpaper", group: qsTr("Personalización"), title: qsTr("Fondo"), icon: "wallpaper", keywords: qsTr("wallpaper imagen orbital"),
          settings: [qsTr("Cortetsu pone el fondo"), qsTr("Gestor de fondos")] },
        { id: "desktop", group: qsTr("Escritorio"), title: qsTr("Escritorio"), icon: "desktop_windows", keywords: qsTr("dashboard panel clima métricas espacios"),
          settings: [qsTr("Dashboard"), qsTr("Abrir al acercar el puntero"), qsTr("Multimedia"), qsTr("Clima"), qsTr("Métricas"), qsTr("Reloj del escritorio"), qsTr("Espacios por monitor")] },
        { id: "bottomhub", group: qsTr("Escritorio"), title: qsTr("BottomHub"), icon: "dock_to_bottom", keywords: qsTr("barra dock bandeja estado"),
          settings: [qsTr("Detalle al pulsar un estado"), qsTr("Volumen con la rueda"), qsTr("Segmentos"), qsTr("Indicadores de estado")] },
        { id: "launcher", group: qsTr("Escritorio"), title: qsTr("Lanzador"), icon: "search", keywords: qsTr("apps acciones buscador"),
          settings: [qsTr("Lanzador"), qsTr("Abrir al acercar el puntero"), qsTr("Búsqueda aproximada")] },
        { id: "shortcuts", group: qsTr("Escritorio"), title: qsTr("Atajos"), icon: "keyboard_command_key", keywords: qsTr("teclas super combinaciones"),
          settings: [qsTr("Atajos del shell"), qsTr("Editar atajos")] },
        { id: "automation", group: qsTr("Cortetsu"), title: qsTr("Automatización"), icon: "auto_awesome", keywords: qsTr("reglas políticas sesión automático pausa consentimiento"),
          settings: [qsTr("Coordinador"), qsTr("Notificaciones automáticas"), qsTr("Modo de juego automático"), qsTr("Energía automática"), qsTr("Reglas de pantalla"), qsTr("Pausar quince minutos"), qsTr("Decisiones recientes")] },
        { id: "about", group: qsTr("Cortetsu"), title: qsTr("Acerca de"), icon: "info", keywords: qsTr("versión revisión generación"),
          settings: [qsTr("Revisión instalada"), qsTr("Generación")] }
    ]

    readonly property var selectedCategory: categories.find(item => item.id === selectedId) ?? null
    readonly property var matchingIds: Navigation.matchingIds(categories, search)

    function select(id: string): void {
        if (categories.some(item => item.id === id))
            selectedId = id;
    }

    function selectNeighbour(delta: int): void {
        const next = Navigation.neighbour(matchingIds, selectedId, delta);
        if (next)
            selectedId = next;
    }
}
