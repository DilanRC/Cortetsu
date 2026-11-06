pragma Singleton

import QtQml
import "Navigation.js" as Navigation

// Eight end-4-level destinations composed from Cortetsu's existing sections.
// Each leaf stays owned by its original service; this controller only routes.
QtObject {
    id: root

    property string search: ""
    property string selectedId: "quick"

    readonly property var pageSections: ({
        quick: ["appearance"],
        general: ["audio", "power", "input"],
        bar: ["bottomhub"],
        background: ["wallpaper"],
        interface: ["desktop", "launcher", "notifications"],
        services: ["network", "bluetooth", "automation"],
        advanced: ["display", "shortcuts"],
        about: ["about"]
    })
    readonly property var categories: [
        { id: "quick", group: qsTr("Ajustes"), title: qsTr("Quick Settings"), icon: "instant_mix", keywords: qsTr("rápido tema color scheme wallpaper fondo apariencia"), settings: [qsTr("Ink"), qsTr("Washi"), qsTr("Kurogane"), qsTr("Esquema de color"), qsTr("Esquema según el fondo"), qsTr("Superficies transparentes"), qsTr("Grosor de bordes"), qsTr("Reloj de 12 horas"), qsTr("Temperatura en Fahrenheit"), qsTr("Visualizador de audio")] },
        { id: "general", group: qsTr("Ajustes"), title: qsTr("General"), icon: "browse", keywords: qsTr("general audio volumen batería energía teclado entrada vim"), settings: [qsTr("Volumen máximo"), qsTr("Incremento por paso"), qsTr("Volumen de salida"), qsTr("Dispositivo de salida"), qsTr("Volumen por aplicación"), qsTr("Volumen de entrada"), qsTr("Dispositivo de entrada"), qsTr("Evitar reposo durante el audio"), qsTr("Evitar reposo mientras carga"), qsTr("Bloquear antes de suspender"), qsTr("Distribución activa"), qsTr("Navegación estilo Vim")] },
        { id: "bar", group: qsTr("Ajustes"), title: qsTr("Bar"), icon: "dock_to_bottom", keywords: qsTr("bottom hub barra indicadores bandeja espacios estado rueda estados detalles"), settings: [qsTr("Bottom Hub"), qsTr("Detalle al pulsar un estado"), qsTr("Volumen con la rueda"), qsTr("Segmentos"), qsTr("Aplicaciones"), qsTr("Bandeja del sistema"), qsTr("Indicadores de estado"), qsTr("Espacios de trabajo")] },
        { id: "background", group: qsTr("Ajustes"), title: qsTr("Background"), icon: "texture", keywords: qsTr("fondo wallpaper imagen orbital"), settings: [qsTr("Posición del reloj"), qsTr("Fondo de escritorio"), qsTr("Cambiar fondo"), qsTr("Gestor de fondos"), qsTr("Sincronizar esquema con el fondo")] },
        { id: "interface", group: qsTr("Ajustes"), title: qsTr("Interface"), icon: "bottom_app_bar", keywords: qsTr("interfaz dashboard launcher notificaciones escritorio multimedia clima métricas reloj historial no molestar"), settings: [qsTr("Dashboard"), qsTr("Abrir al acercar el puntero"), qsTr("Multimedia"), qsTr("Clima"), qsTr("Métricas"), qsTr("Reloj del escritorio"), qsTr("Espacios por monitor"), qsTr("Lanzador"), qsTr("Búsqueda aproximada"), qsTr("No molestar"), qsTr("Ocultar en pantalla completa"), qsTr("Avisos visibles por grupo"), qsTr("Avisar del modo de juego"), qsTr("Vaciar historial")] },
        { id: "services", group: qsTr("Ajustes"), title: qsTr("Services"), icon: "settings", keywords: qsTr("servicios wifi red bluetooth automatización coordinador conexiones redes guardadas contraseña perfil ip dns emparejar reglas"), settings: [qsTr("Wi-Fi"), qsTr("Redes cercanas"), qsTr("Redes guardadas"), qsTr("Conexión automática"), qsTr("Copiar contraseña"), qsTr("Perfiles de red"), qsTr("DNS"), qsTr("Bluetooth"), qsTr("Adaptador Bluetooth"), qsTr("Dispositivos"), qsTr("Automatización"), qsTr("Notificaciones automáticas"), qsTr("Modo de juego automático"), qsTr("Energía automática"), qsTr("Reglas de pantalla"), qsTr("Pausar quince minutos"), qsTr("Decisiones recientes")] },
        { id: "advanced", group: qsTr("Ajustes"), title: qsTr("Advanced"), icon: "construction", keywords: qsTr("avanzado pantallas brillo atajos gamma diagnóstico filtro temperatura color vibrance nvidia"), settings: [qsTr("Pantalla"), qsTr("Brillo"), qsTr("Filtro de color"), qsTr("Temperatura de color"), qsTr("Gamma"), qsTr("Vibrance NVIDIA"), qsTr("Gestor de pantallas"), qsTr("Atajos del shell"), qsTr("Editar atajos")] },
        { id: "about", group: qsTr("Ajustes"), title: qsTr("About"), icon: "info", keywords: qsTr("acerca versión revisión generación créditos"), settings: [qsTr("Revisión instalada"), qsTr("Generación"), qsTr("Estado y diagnóstico")] }
    ]
    readonly property var selectedCategory: categories.find(item => item.id === selectedId) ?? null
    readonly property var matchingIds: Navigation.matchingIds(categories, search)

    function pageForSection(sectionId: string): string {
        if (pageSections[sectionId])
            return sectionId;
        for (const page of categories)
            if (pageSections[page.id].includes(sectionId))
                return page.id;
        return "";
    }

    // Kept so existing callers can deep-link to a settings domain while the
    // navigation itself presents the eight pages.
    function select(id: string): void {
        const pageId = pageForSection(id);
        if (categories.some(item => item.id === pageId))
            selectedId = pageId;
    }

    function selectNeighbour(delta: int): void {
        const next = Navigation.neighbour(matchingIds, selectedId, delta);
        if (next)
            selectedId = next;
    }
}
