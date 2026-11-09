pragma Singleton

import QtQml
import "Navigation.js" as Navigation

// Where Settings is and how it got there. Categories hold subpages, as in
// Windows 11: Personalización › Temas. Every control stays owned by its
// service; this object only routes, remembers the way back and searches.
QtObject {
    id: root

    property string search: ""
    // The category open in the sidebar and, inside it, the subpage. An empty
    // subpage shows the category's own page: its list of subpages.
    property string selectedId: "home"
    property string subpageId: ""
    // Earlier places, most recent last, for the back button.
    property var history: []
    // A setting that a search result asked to show once its page is open.
    property string reveal: ""

    readonly property var categories: [
        { id: "home", title: qsTr("Inicio"), icon: "home", pages: [], keywords: qsTr("inicio resumen estado accesos rápidos frecuentes") },
        { id: "system", title: qsTr("Sistema"), icon: "computer", keywords: qsTr("sistema"), pages: [
            { id: "display", title: qsTr("Pantalla"), icon: "monitor", summary: "display", detail: qsTr("Brillo, filtro de color y monitores"),
              keywords: qsTr("pantallas brillo gamma filtro temperatura color vibrance nvidia monitor resolución escala"),
              settings: [qsTr("Brillo de esta pantalla"), qsTr("Filtro de color"), qsTr("Temperatura de color"), qsTr("Gamma"), qsTr("Vibrance NVIDIA"), qsTr("Resolución, posición y escala")] },
            { id: "sound", title: qsTr("Sonido"), icon: "volume_up", summary: "audio", detail: qsTr("Salida, entrada, volumen por aplicación y protección"),
              keywords: qsTr("audio volumen altavoz micrófono pipewire salida entrada"),
              settings: [qsTr("Volumen de salida"), qsTr("Silenciar la salida"), qsTr("Volumen de entrada"), qsTr("Silenciar el micrófono"), qsTr("Limitar aumentos bruscos"), qsTr("Aumento máximo por ajuste"), qsTr("Límite al ajustar el volumen"), qsTr("Incremento por paso")] },
            { id: "power", title: qsTr("Energía y batería"), icon: "battery_horiz_075", summary: "power", detail: qsTr("Batería, reposo y perfiles de energía"),
              keywords: qsTr("energía batería reposo suspender inactividad bloquear carga"),
              settings: [qsTr("Nivel de aviso"), qsTr("Mantener despierto"), qsTr("Bloquear tras inactividad"), qsTr("Apagar la pantalla tras inactividad"), qsTr("Suspender tras inactividad"), qsTr("Suspender por inactividad solo con batería"), qsTr("Evitar reposo en pantalla completa"), qsTr("Evitar reposo durante el audio"), qsTr("Evitar reposo mientras carga"), qsTr("Bloquear antes de suspender"), qsTr("Perfil, límites y automatización")] },
            { id: "shortcuts", title: qsTr("Atajos de teclado"), icon: "keyboard_command_key", summary: "shortcuts", detail: qsTr("Atajos del shell y su edición"),
              keywords: qsTr("atajos teclas combinaciones keybinds"), settings: [qsTr("Cambiar o añadir atajos")] },
            { id: "capture", title: qsTr("Capturas y grabación"), icon: "screenshot_monitor", summary: "", detail: qsTr("Dónde se guardan capturas y vídeos"),
              keywords: qsTr("grabador pantalla grabaciones capturas destino carpeta"), settings: [qsTr("Carpeta de destino")] }
        ] },
        { id: "devices", title: qsTr("Bluetooth y dispositivos"), icon: "devices", keywords: qsTr("dispositivos"), pages: [
            { id: "bluetooth", title: qsTr("Bluetooth"), icon: "bluetooth", summary: "bluetooth", detail: qsTr("Adaptador y dispositivos emparejados"),
              keywords: qsTr("bluetooth emparejar auriculares adaptador"), settings: [qsTr("Bluetooth"), qsTr("Dispositivos")] },
            { id: "input", title: qsTr("Teclado y entrada"), icon: "keyboard", summary: "input", detail: qsTr("Distribución y navegación por teclado"),
              keywords: qsTr("teclado entrada distribución vim"), settings: [qsTr("Distribución activa"), qsTr("Navegación estilo Vim")] }
        ] },
        { id: "network", title: qsTr("Red e Internet"), icon: "wifi", keywords: qsTr("red internet"), pages: [
            { id: "wifi", title: qsTr("Wi-Fi"), icon: "wifi", summary: "network", detail: qsTr("Redes, perfiles y diagnóstico"),
              keywords: qsTr("wifi red conexiones redes guardadas contraseña perfil ip dns"),
              settings: [qsTr("Wi-Fi"), qsTr("Redes cercanas"), qsTr("Redes guardadas"), qsTr("Conexión automática"), qsTr("Copiar contraseña"), qsTr("Perfiles de red"), qsTr("DNS")] }
        ] },
        { id: "personalization", title: qsTr("Personalización"), icon: "palette", keywords: qsTr("personalizar apariencia"), pages: [
            { id: "themes", title: qsTr("Temas"), icon: "style", summary: "theme", detail: qsTr("Ink, Washi y Kurogane; modo y materiales"),
              keywords: qsTr("tema ink washi kurogane material tipografía fuente radio geometría transparencia claro oscuro"),
              settings: [qsTr("Ink"), qsTr("Washi"), qsTr("Kurogane"), qsTr("Modo"), qsTr("Superficies transparentes"), qsTr("Fuente de interfaz"), qsTr("Fuente de títulos"), qsTr("Radio de paneles"), qsTr("Altura de filas"), qsTr("Opacidad del material")] },
            { id: "colors", title: qsTr("Colores"), icon: "format_paint", summary: "appearance", detail: qsTr("Esquema de color y variante de paleta"),
              keywords: qsTr("color esquema scheme paleta variante material"),
              settings: [qsTr("Esquema activo"), qsTr("Esquema según el fondo"), qsTr("Variante de paleta"), qsTr("Previsualizar esquemas antes de aplicar")] },
            { id: "background", title: qsTr("Fondo"), icon: "wallpaper", summary: "wallpaper", detail: qsTr("Fondo de escritorio, reloj y visualizador"),
              keywords: qsTr("fondo wallpaper imagen orbital reloj escritorio visualizador barras"),
              settings: [qsTr("Fondo actual"), qsTr("Elegir otro fondo"), qsTr("Posición del reloj"), qsTr("Reloj del escritorio"), qsTr("Mostrar fecha"), qsTr("Espacios por monitor"), qsTr("Visualizador de audio"), qsTr("Número de barras")] },
            { id: "bottomhub", title: qsTr("Bottom Hub"), icon: "dock_to_bottom", summary: "", detail: qsTr("Segmentos, estados, espacios e interacción"),
              keywords: qsTr("bottom hub barra ocultar automáticamente bandeja iconos monocromos espacios estado rueda"),
              settings: [qsTr("Ocultar automáticamente"), qsTr("Detalle al pulsar un estado"), qsTr("Volumen con la rueda"), qsTr("Modo y espacios"), qsTr("Aplicaciones"), qsTr("Bandeja"), qsTr("Iconos monocromos de la bandeja"), qsTr("Mostrar cantidad de notificaciones"), qsTr("Espacios visibles"), qsTr("Mostrar números"), qsTr("Icono de la aplicación")] },
            { id: "panels", title: qsTr("Paneles laterales"), icon: "side_navigation", summary: "desktop", detail: qsTr("Dashboard, panel de avisos y utilidades"),
              keywords: qsTr("dashboard panel lateral sidebar utilidades multimedia clima métricas cpu gpu memoria"),
              settings: [qsTr("Dashboard"), qsTr("Abrir al acercar el puntero"), qsTr("Multimedia"), qsTr("Clima"), qsTr("Métricas"), qsTr("Panel de avisos"), qsTr("Panel de utilidades")] }
        ] },
        { id: "interface", title: qsTr("Interfaz"), icon: "dashboard_customize", keywords: qsTr("interfaz"), pages: [
            { id: "launcher", title: qsTr("Lanzador"), icon: "apps", summary: "launcher", detail: qsTr("Búsqueda, acciones y apertura"),
              keywords: qsTr("launcher lanzador búsqueda aproximada prefijo acciones"),
              settings: [qsTr("Lanzador"), qsTr("Prefijo de acciones"), qsTr("Búsqueda aproximada"), qsTr("Probar el lanzador")] },
            { id: "notifications", title: qsTr("Notificaciones"), icon: "notifications", summary: "notifications", detail: qsTr("No molestar, duración, avisos e historial"),
              keywords: qsTr("notificaciones avisos no molestar historial pantalla completa"),
              settings: [qsTr("No molestar"), qsTr("Ocultar en pantalla completa"), qsTr("Cerrar después de"), qsTr("Avisar del modo de juego"), qsTr("Avisar de Bloq Mayús"), qsTr("Abrir avisos expandidos"), qsTr("Vaciar historial")] },
            { id: "indicators", title: qsTr("Indicadores y formatos"), icon: "schedule", summary: "", detail: qsTr("OSD, reloj y unidades"),
              keywords: qsTr("osd indicadores reloj hora segundos 12 horas fahrenheit unidades"),
              settings: [qsTr("Duración del OSD"), qsTr("Reloj de 12 horas"), qsTr("Mostrar segundos"), qsTr("Temperatura en Fahrenheit")] }
        ] },
        { id: "apps", title: qsTr("Aplicaciones y servicios"), icon: "widgets", keywords: qsTr("servicios aplicaciones"), pages: [
            { id: "automation", title: qsTr("Automatización"), icon: "smart_toy", summary: "automation", detail: qsTr("Coordinador, reglas y muestreo de hardware"),
              keywords: qsTr("automatización coordinador reglas modo de juego energía automática muestreo hardware"),
              settings: [qsTr("Intervalo de actualización"), qsTr("Notificaciones automáticas"), qsTr("Modo de juego automático"), qsTr("Energía automática"), qsTr("Reglas de pantalla"), qsTr("Decisiones recientes")] },
            { id: "weather", title: qsTr("Clima"), icon: "partly_cloudy_day", summary: "", detail: qsTr("Ubicación y frecuencia del pronóstico"),
              keywords: qsTr("clima pronóstico ciudad ubicación"), settings: [qsTr("Ciudad o coordenadas"), qsTr("Actualizar cada")] }
        ] },
        { id: "accessibility", title: qsTr("Accesibilidad"), icon: "accessibility_new", keywords: qsTr("accesibilidad"), pages: [
            { id: "motion", title: qsTr("Movimiento y contraste"), icon: "animation", summary: "", detail: qsTr("Animaciones y bordes"),
              keywords: qsTr("movimiento reducido animación contraste bordes"), settings: [qsTr("Reducir movimiento"), qsTr("Grosor de bordes")] }
        ] },
        { id: "advanced", title: qsTr("Avanzado"), icon: "construction", keywords: qsTr("avanzado"), pages: [
            { id: "sync", title: qsTr("Sincronización de aplicaciones"), icon: "sync", summary: "", detail: qsTr("Hyprland, Kitty, GTK y Qt"),
              keywords: qsTr("sincronización integraciones kitty gtk qt kde hyprland compositor"),
              settings: [qsTr("Compositor"), qsTr("Terminal Kitty"), qsTr("GTK"), qsTr("Qt / KDE"), qsTr("Volver a sincronizar")] },
            { id: "profiles", title: qsTr("Perfiles y recuperación"), icon: "settings_backup_restore", summary: "", detail: qsTr("Exportar, importar y restaurar el tema"),
              keywords: qsTr("perfil exportar importar restaurar respaldo"),
              settings: [qsTr("Exportar perfil actual"), qsTr("Importar perfil visual"), qsTr("Restaurar colores, material y geometría del tema")] },
            { id: "diagnostics", title: qsTr("Diagnóstico"), icon: "monitor_heart", summary: "", detail: qsTr("Estado de Cortetsu y su generación"),
              keywords: qsTr("diagnóstico estado salud generación"), settings: [qsTr("Estado y diagnóstico")] }
        ] },
        { id: "about", title: qsTr("Acerca de Cortetsu"), icon: "info", pages: [], keywords: qsTr("acerca versión revisión generación créditos documentación licencia") }
    ]

    // Every subpage by id, with the category it belongs to.
    readonly property var pages: {
        const out = ({});
        for (const category of categories)
            for (const page of category.pages)
                out[page.id] = Object.assign({ category: category.id }, page);
        return out;
    }
    // Old destinations keep working: the eight pages and the sections of
    // earlier versions, used by shortcuts, IPC and other surfaces.
    readonly property var legacy: ({
        quick: "themes", general: "sound", bar: "bottomhub", services: "wifi", interface: "launcher",
        appearance: "colors", audio: "sound", wallpaper: "background", desktop: "panels",
        network: "wifi", automation: "automation", recorder: "capture", screenshot: "capture"
    })

    readonly property var selectedCategory: categories.find(item => item.id === selectedId) ?? null
    // A category with one subpage opens straight on it.
    readonly property string pageId: subpageId.length > 0
        ? subpageId
        : selectedCategory && selectedCategory.pages.length === 1 ? selectedCategory.pages[0].id : selectedId
    readonly property var selectedPage: pages[pageId] ?? null
    readonly property var matchingIds: Navigation.matchingIds(categories, search)
    readonly property var results: Navigation.results(categories, search)
    readonly property bool canGoBack: history.length > 0

    // Category, subpage or an old destination, to the page that holds it.
    function resolve(id: string): var {
        if (categories.some(item => item.id === id))
            return { category: id, page: "" };
        const pageId = pages[id] ? id : legacy[id] ?? "";
        return pages[pageId] ? { category: pages[pageId].category, page: pageId } : null;
    }

    function pageForSection(id: string): string {
        const place = resolve(id);
        return place ? (place.page || place.category) : "";
    }

    function go(category: string, page: string, remember: bool): void {
        if (category === selectedId && page === subpageId)
            return;
        if (remember)
            history = history.concat([{ category: selectedId, page: subpageId }]).slice(-32);
        selectedId = category;
        subpageId = page;
    }

    // Opens a destination and keeps the way back.
    function select(id: string): void {
        const place = resolve(id);
        if (place)
            go(place.category, place.page, true);
    }

    // A search result: its page, then the setting itself.
    function openResult(pageId: string, setting: string): void {
        select(pageId);
        reveal = setting;
    }

    function back(): void {
        if (!history.length)
            return;
        const last = history[history.length - 1];
        history = history.slice(0, -1);
        go(last.category, last.page, false);
    }

    // The sidebar moves between categories; the arrows never wrap.
    function selectNeighbour(delta: int): void {
        const next = Navigation.neighbour(matchingIds, selectedId, delta);
        if (next)
            go(next, "", true);
    }
}
