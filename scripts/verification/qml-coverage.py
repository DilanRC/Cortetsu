#!/usr/bin/env python3
"""Cortetsu 3.0 coverage matrix: every active QML/JS file of the shell, its
family, what each construction wave did to it and its final state.

The file list and the per-wave changes come from the tree and from Git; the
judgement for each family (references read, deficiencies, why an untouched
file is kept) is the data in FAMILIES below, written by the person who
reviewed it. Regenerate after touching a surface:

    python3 scripts/verification/qml-coverage.py > docs/roadmap/cortetsu-3.0/COBERTURA_FINAL_QML_3_0.md

States: IMPLEMENTADO_SIN_VERIFICAR, CONSERVADO_JUSTIFICADO,
BLOQUEADO_DOCUMENTADO, PENDIENTE. A file in no family is PENDIENTE, so a new
file cannot slip through unreviewed.
"""

import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
WAVE1 = ("6299f21f", "3b4e7c2f")
WAVE2_BASE = "3b4e7c2f"

E4 = "end-4"
CA = "Caelestia"
NE = "Nebula"

# prefix -> family. The longest matching prefix wins.
FAMILIES = {
    "modules/desktop/": dict(
        surface="Widgets de escritorio", refs=[E4, CA, NE],
        deficiency="Solo existía un reloj fijo en nueve posiciones, sin edición, sin datos del equipo y en inglés (Time.format)",
        keep="", deps="Cpu, Memory, Gpu, Storage, NetworkUsage, Weather, CortetsuPower, Players, Time, CortetsuRegional, HubAnchor",
        risks="Rendimiento con muchos widgets a la vista; arrastre en la capa Overlay; foco del campo de nota",
        qa="Añadir/mover/redimensionar/quitar con ratón y teclado; deshacer; monitor ausente; escala 1.25; muestreo detenido con ventanas encima"),
    "modules/DesktopWidgetsController.qml": dict(
        surface="Widgets de escritorio", refs=[NE], deficiency="No había superficie de edición", keep="",
        deps="RetainedSurfaceController", risks="Atajo global sin tecla asignada (se abre desde Ajustes y el lanzador)",
        qa="IPC desktopWidgets open/close/toggle"),
    "modules/cheatsheet/": dict(
        surface="Hoja de atajos", refs=[E4],
        deficiency="Los atajos solo se veían en Ajustes → Atajos", keep="",
        deps="cortetsu-keybinds list, KeyCap", risks="Columnas con 119 atajos a 1080p; Escape con búsqueda",
        qa="SUPER+F1 tras hyprctl reload; filtrar; Escape doble; RePág/AvPág; Editar abre Atajos y teclados"),
    "modules/CheatsheetController.qml": dict(
        surface="Hoja de atajos", refs=[E4], deficiency="—", keep="", deps="RetainedSurfaceController",
        risks="Necesita hyprctl reload para SUPER+F1", qa="IPC cheatsheet"),
    "modules/background/": dict(
        surface="Fondo", refs=[CA, NE],
        deficiency="Visualizador recreaba las barras por muestra; reloj de escritorio duplicado por los widgets", keep="Wallpaper.qml: solo pinta la imagen",
        deps="CortetsuSpectrum, DesktopWidgetLayer", risks="cava ausente en el equipo", qa="Visualizador con cava instalado; widgets por monitor"),
    "modules/settings/": dict(
        surface="Ajustes", refs=[E4, CA, NE],
        deficiency="Faltaban widgets, luz nocturna programada, grabaciones recientes, apps silenciadas y la galería de la biblioteca",
        keep="Página o control ya conforme a ADR-008 (fases 1-2 y ola 1): una hoja, filas abiertas, divisor por token, estados de guardado y error",
        deps="SettingsController, PageRegistry, servicios de cada página", risks="Pruebas de cadenas sobre textos movidos",
        qa="Búsqueda de cada fila nueva; teclado; tres temas; ventana estrecha"),
    "modules/settings/network/": dict(
        surface="Ajustes → Wi-Fi", refs=[CA], deficiency="—",
        keep="Rediseñado y probado en la fase 1 (piloto de Premium sobria)", deps="ConnectivityWifi", risks="—", qa="Regresión de fase 1"),
    "modules/settings/bluetooth/": dict(
        surface="Ajustes → Bluetooth", refs=[CA], deficiency="Dos divisores escritos a mano",
        keep="Rediseñado en la fase 2", deps="ConnectivityBluetooth", risks="—", qa="Detalle de dispositivo emparejado y bloqueado"),
    "modules/settings/pages/": dict(
        surface="Ajustes → Inicio y Acerca de", refs=[E4, CA], deficiency="—",
        keep="Inicio rediseñado en la fase 2 (grupo Estado); Acerca de y la página de categoría ya listan su contenido real",
        deps="SettingsContext", risks="—", qa="Regresión de Ajustes"),
    "modules/osd/": dict(
        surface="OSD y centro de control", refs=[E4, CA, NE],
        deficiency="Centro de control sin reproductor, sin mezclador, sin luz nocturna ni captura", keep="Rediseñado en la ola 1",
        deps="CortetsuAudio, Players, DisplayCalibration, AreaPicker, SettingsController", risks="follow_mouse con el teclado; alto con el pliegue abierto",
        qa="Pliegue de audio con apps; lo que suena; mosaicos nuevos; Hub lateral"),
    "modules/sidebar/": dict(
        surface="Centro de notificaciones", refs=[E4, CA], deficiency="Sin control por aplicación",
        keep="Wrapper: solo aloja el contenido", deps="Notifs, CortetsuConfig", risks="Nombre de app vacío o variable", qa="Silenciar y reactivar; crítica de app silenciada"),
    "modules/notifications/": dict(
        surface="Tarjeta de notificación", refs=[E4, CA], deficiency="—",
        keep="Ya opaca, con acciones reales y estados urgentes (ola 1)", deps="Notifs", risks="—", qa="Regresión"),
    "modules/utilities/": dict(
        surface="Utilidades y toasts", refs=[CA], deficiency="—",
        keep="Toasts corregidos en la ola 1; el panel de utilidades conserva sus tarjetas y no tiene host visual propio",
        deps="CortetsuToaster", risks="—", qa="Regresión de toasts"),
    "modules/launcher/": dict(
        surface="Lanzador", refs=[E4, CA, NE], deficiency="Sin búsqueda de archivos",
        keep="Modo explorar de la ola 1; fondos, emoji, esquemas y variantes sin cambios de contrato", deps="Apps, Actions, Files (plocate)",
        risks="Código de salida de plocate sin coincidencias; índice viejo", qa=">files con 1, 2 y muchas letras; consulta cambiada en curso; sin base de plocate"),
    "modules/bar/popouts/": dict(
        surface="Popouts del Hub", refs=[CA, NE],
        deficiency="Teclado y Bloq Mayús fuera de la familia; filas de lectura que reaccionaban al puntero",
        keep="Popouts de red, Bluetooth, audio, bandeja y vista previa VERIFIED en la fase 4; energía rediseñada en la ola 1",
        deps="CortetsuPopoutHeader", risks="—", qa="Abrir desde el Hub en los ocho anclajes"),
    "modules/drawers/": dict(
        surface="Cajones heredados", refs=[CA], deficiency="—",
        keep="Ventana compartida, regiones e interacciones de la fase 4 (bandeja e islas VERIFIED); no se reabren", deps="—", risks="—", qa="Regresión de fase 4"),
    "modules/dashboard/": dict(
        surface="Dashboard", refs=[CA, NE], deficiency="Sin visualizador sin cava; selector de reproductor sin teclado",
        keep="Rediseño y correcciones de la ola 1 (GPU sin lectura, pestañas accesibles)", deps="Players, PwNodePeakMonitor", risks="Frecuencia de actualización de los picos",
        qa="Medidor con música; selector con dos reproductores"),
    "modules/overview/": dict(
        surface="Vista general", refs=[E4, CA], deficiency="Sin forma de filtrar ventanas; cabecera oculta muerta",
        keep="WindowCard y Wrapper sin cambios: tarjetas y miniaturas ya probadas", deps="CortetsuHypr", risks="/ en la distribución latam (Mayús+7)",
        qa="Filtrar, Enter, Abajo, Escape doble"),
    "modules/clipboard/": dict(
        surface="Portapapeles", refs=[E4, NE], deficiency="Filtros y limpiar sin teclado; limpiar sin confirmación; acciones solo icono sin texto; colores al revés en Washi",
        keep="Wrapper sin cambios", deps="Clipse", risks="—", qa="Limpiar armado y desarmado; Washi; lector de pantalla"),
    "modules/calendar/": dict(
        surface="Calendario", refs=[E4, CA, NE], deficiency="—",
        keep="Fechas por CortetsuRegional, «Hoy», teclado por día y mes, estados de sincronización", deps="CalendarService", risks="—", qa="Regresión"),
    "modules/pomodoro/": dict(
        surface="Pomodoro", refs=[E4], deficiency="—", keep="Servicio sin interfaz propia; su tarjeta vive en el calendario", deps="—", risks="—", qa="—"),
    "modules/wallpaper/": dict(
        surface="Wallpaper Orbital", refs=[E4, CA, NE], deficiency="Fichas anónimas para el lector de pantalla",
        keep="Superficie propia con órbita, cuadrícula, prefetch y teclado completo; ENERGY 2 permitido por la skill de producto",
        deps="CortetsuWallpapers", risks="—", qa="Lector de pantalla sobre órbita y cuadrícula"),
    "modules/display/": dict(
        surface="Gestor de pantallas", refs=[CA], deficiency="—",
        keep="Aloja la página de Pantalla de Ajustes (disposición, color, presets) en su ventana", deps="DisplayModel, DisplayTransaction", risks="—", qa="Regresión"),
    "modules/hardware/": dict(
        surface="Centro de hardware", refs=[CA], deficiency="—",
        keep="Rediseñado y probado antes de 3.0 (docs/HARDWARE_CENTER_QA.md); sus páginas ya siguen la regla de una pregunta por superficie",
        deps="cortetsu-hardware", risks="—", qa="Revisión contra ADR-008 en la misión de QA"),
    "modules/keyboards/": dict(
        surface="Atajos y teclados", refs=[E4], deficiency="Dibujo de tecla duplicable",
        keep="Editor con captura, conflictos y dispositivos; pruebas propias", deps="cortetsu-keybinds", risks="—", qa="Regresión del editor y de la hoja"),
    "modules/lock/": dict(
        surface="Bloqueo", refs=[CA, NE], deficiency="—",
        keep="Rediseñado en la fase 7 (emblema que sigue a PAM). Sin prueba manual inmediata no se toca: un error deja fuera de la sesión",
        deps="Pam.qml", risks="—", qa="Bloqueo y desbloqueo a mano con una TTY abierta"),
    "base/modules/lock/": dict(
        surface="Bloqueo (PAM)", refs=[CA], deficiency="—", keep="Ruta de autenticación; intocable sin autorización y prueba manual", deps="PAM", risks="—", qa="—"),
    "modules/polkit/": dict(
        surface="Polkit", refs=[E4], deficiency="—", keep="Corregido en la ola 1 (Bloq Mayús, «Comprobando…»); la lógica de autenticación no se toca",
        deps="PolkitAgent", risks="—", qa="AuthFlow falso"),
    "modules/prompt/": dict(
        surface="Secretos", refs=[], deficiency="—", keep="Pedido de secretos con su contrato y fixture; superficie sensible sin cambios de lógica",
        deps="SecretPromptHost", risks="—", qa="Fixture SecretPromptFixture.qml"),
    "modules/session/": dict(
        surface="Sesión", refs=[E4, CA], deficiency="—", keep="Rediseñada en la ola 1 (grupos, cuenta atrás, Escape)", deps="CortetsuSession", risks="—", qa="Regresión"),
    "modules/screenshare/": dict(
        surface="Compartir pantalla", refs=[CA], deficiency="Fichas sin rol accesible",
        keep="Selector del portal con pestañas, región y teclado completo", deps="xdg-desktop-portal-hyprland", risks="—", qa="Lector de pantalla"),
    "modules/areapicker/": dict(
        surface="Captura de área", refs=[E4, CA, NE], deficiency="—",
        keep="Selector, congelado y vista previa ya completos; se abren ahora también desde el centro de control", deps="grim, wl-copy", risks="—", qa="Captura desde el mosaico"),
    "modules/CortetsuRecorder.qml": dict(
        surface="Grabación", refs=[CA], deficiency="No exponía la carpeta de grabaciones", keep="", deps="cortetsu-record", risks="Divergencia con la regla de Rust", qa="Carpeta por preferencia, ~ y por defecto"),
    "modules/": dict(
        surface="Núcleo del shell (controladores, hosts, Hub)", refs=[CA],
        deficiency="—",
        keep="Infraestructura sin interfaz propia o Hub certificado en la fase 4 (VERIFIED): anclajes, islas, edición, bandeja, foco; no se reescribe lo estable",
        deps="—", risks="—", qa="Regresión de fase 4 y registro de superficies"),
    "services/": dict(
        surface="Servicios", refs=[CA, NE],
        deficiency="—", keep="Dueño de datos sin cambios de contrato en esta ola", deps="—", risks="—", qa="Pruebas de servicio existentes"),
    "components/": dict(
        surface="Biblioteca Premium sobria", refs=[E4, CA], deficiency="—",
        keep="Primitiva compartida ya conforme a ADR-008; visible en Ajustes → Biblioteca de componentes", deps="CortetsuDesign", risks="—", qa="Galería en los tres temas"),
    "theme/": dict(
        surface="Tokens (generado)", refs=[], deficiency="—", keep="Generado por platform-rs; no se edita a mano", deps="theme compile", risks="—", qa="cortetsu theme check"),
    "base/": dict(
        surface="Compatibilidad", refs=[CA], deficiency="—", keep="Archivos de origen Caelestia conservados por contrato", deps="—", risks="—", qa="—"),
    "utils/": dict(
        surface="Utilidades", refs=[], deficiency="—", keep="Rutas e iconos compartidos", deps="—", risks="—", qa="—"),
    "integrations/": dict(
        surface="Integración externa (Spicetify)", refs=[], deficiency="—",
        keep="Extensión que publica la letra de Spotify al puente Lyrics; no es una superficie del shell", deps="Spicetify", risks="—", qa="—"),
    "shell.qml": dict(
        surface="Raíz del shell", refs=[], deficiency="—", keep="", deps="—", risks="Nuevos controladores al arrancar", qa="Arranque limpio y recarga suave"),
}

# Files certified or redesigned before the construction waves.
EARLIER = [
    (("modules/BottomHub", "modules/CortetsuBottomHub", "modules/Hub", "modules/StatusPill", "modules/CortetsuIsland",
      "modules/CortetsuTraySegment", "modules/CortetsuStatusSegment", "modules/CortetsuModeSegment",
      "modules/CortetsuWorkspaceDots", "modules/CortetsuAppRail", "modules/drawers/",
      "modules/bar/popouts/CortetsuNetworkPopup", "modules/bar/popouts/CortetsuBluetoothPopup",
      "modules/bar/popouts/CortetsuAudioPopup", "modules/bar/popouts/CortetsuTrayMenu",
      "modules/bar/popouts/CortetsuWindowPreview", "modules/bar/popouts/CortetsuPopoutHeader",
      "modules/bar/popouts/Wrapper", "modules/bar/popouts/ClipWrapper", "components/CortetsuTooltip"), "VERIFIED (fase 4)"),
    (("modules/settings/network/", "modules/settings/bluetooth/", "modules/settings/pages/HomePage",
      "modules/settings/sections/BottomHubSection", "modules/settings/controls/HubAnchorPicker",
      "components/CortetsuDivider", "components/CortetsuHero", "components/CortetsuFact", "components/CortetsuTabBar"),
     "Rediseñado en las fases 1-3"),
    (("modules/lock/",), "Rediseñado en la fase 7 (sin verificar en sesión física)"),
    (("modules/hardware/",), "Rediseñado y probado antes de 3.0"),
]

# What wave 2 did to each file it touched.
CHANGES = {
    "modules/desktop/DesktopLayout.js": "Geometría pura: centro en fracciones, área sin el borde del Hub, encaje a guías, validación, migración del reloj 2.x",
    "modules/desktop/DesktopWidget.qml": "Nueve tipos con datos reales y estados «Leyendo…» / «No disponible»",
    "modules/desktop/DesktopWidgetLayer.qml": "Capa por monitor sobre el fondo; muestreo solo con el escritorio visible",
    "modules/desktop/Editor.qml": "Editor: arrastre con guías y fantasma, teclas, tamaño, otro monitor, notas, deshacer, galería",
    "modules/desktop/EditorWrapper.qml": "Host del editor en las superficies retenidas",
    "modules/desktop/ServiceUse.qml": "Contador de consumidores de un servicio de muestreo",
    "modules/DesktopWidgetsController.qml": "Atajo e IPC desktopWidgets",
    "modules/cheatsheet/Columns.js": "Reparto de grupos en columnas equilibradas",
    "modules/cheatsheet/Content.qml": "Hoja con búsqueda, conflictos, RePág/AvPág, Escape doble",
    "modules/cheatsheet/Wrapper.qml": "Host de la hoja",
    "modules/CheatsheetController.qml": "Atajo e IPC cheatsheet",
    "modules/background/Background.qml": "Reloj sustituido por la capa de widgets",
    "modules/background/Visualiser.qml": "Modelo por número de barras, no por muestra",
    "modules/settings/PageRegistry.qml": "Páginas widgets y library; grabaciones en Capturas",
    "modules/settings/SettingsController.qml": "Entradas y palabras clave nuevas para la búsqueda",
    "modules/settings/bluetooth/DeviceDetailPanel.qml": "Divisores por token",
    "modules/settings/controls/EqCurve.qml": "Curva real del ecualizador y salida tras el preamp",
    "modules/settings/display/DisplayColour.qml": "Luz nocturna programada; aviso de cambio manual",
    "modules/settings/sections/AudioSection.qml": "Curva, aviso de grafo antiguo, margen con un decimal",
    "modules/settings/sections/ComponentGallerySection.qml": "Biblioteca de componentes en todos sus estados",
    "modules/settings/sections/NotificationsSection.qml": "Aplicaciones silenciadas",
    "modules/settings/sections/RecordingsSection.qml": "Grabaciones recientes con reproducir y abrir carpeta",
    "modules/settings/sections/ShortcutsSection.qml": "Acceso a la hoja de atajos",
    "modules/settings/sections/WallpaperSection.qml": "El reloj pasa a enlace a Widgets",
    "modules/settings/sections/DiagnosticsSection.qml": "cortetsu doctor --json a demanda",
    "modules/settings/sections/WidgetsSection.qml": "Widgets por monitor, quitar con confirmación, galería con motivo de no disponible",
    "modules/osd/FullContent.qml": "Lo que suena, mezclador por app, luz nocturna, captura",
    "modules/sidebar/Content.qml": "Silenciar la app desde su grupo",
    "modules/launcher/AppList.qml": "Estado files con la celda de acción",
    "modules/launcher/ContentList.qml": "Estados vacíos de la búsqueda de archivos",
    "modules/launcher/services/Actions.qml": "Acciones Buscar archivos, Editar el escritorio, Hoja de atajos",
    "modules/launcher/services/Files.qml": "Búsqueda con plocate: espera, reinicio, descarte de respuestas viejas",
    "modules/bar/popouts/CortetsuKeyboardPopup.qml": "Cabecera común con enlace a Teclado",
    "modules/bar/popouts/CortetsuLockStatusPopup.qml": "Lecturas en vez de filas pulsables; cabecera común",
    "base/modules/bar/popouts/Content.qml": "Pasa popouts a teclado y Bloq Mayús",
    "modules/dashboard/DashLevelMeter.qml": "Medidor de picos por PipeWire",
    "modules/dashboard/DashMediaPlayer.qml": "Medidor; selector de reproductor con botones",
    "modules/overview/Content.qml": "Filtro de ventanas; cabecera muerta retirada",
    "modules/clipboard/Content.qml": "Pestañas y limpiar armado; divisor por token; Washi",
    "modules/clipboard/ClipboardItem.qml": "Acciones como botones con tecla; rol de elemento",
    "modules/wallpaper/WallpaperTile.qml": "Rol, nombre y selección accesibles",
    "modules/keyboards/KeyCap.qml": "Tecla compartida",
    "modules/keyboards/KeyCaps.qml": "Usa KeyCap",
    "modules/screenshare/ScreenSharePanel.qml": "Fichas con rol y acción",
    "modules/CortetsuRecorder.qml": "recordingsDir con la regla del runtime",
    "modules/CortetsuConfig.qml": "desktopWidgets (con migración), horario de luz nocturna, apps silenciadas",
    "modules/CortetsuRegional.qml": "Comentario actualizado",
    "modules/CortetsuScreenState.qml": "Banderas cheatsheet y desktopWidgets",
    "modules/RetainedSurfacesHost.qml": "Aloja la hoja y el editor",
    "modules/SurfaceRegistry.js": "Superficies cheatsheet y desktopWidgets",
    "components/ScreenState.qml": "Propiedades cheatsheet y desktopWidgets",
    "services/CortetsuEqualizer.qml": "Preamp lineal sobre mixer; compatibilidad con el grafo anterior",
    "services/EqResponse.js": "Respuesta de la cascada con las fórmulas de PipeWire 1.6.11",
    "services/CortetsuSpectrum.qml": "Configuración propia de cava",
    "services/DesktopWidgets.qml": "Dueño de los widgets e historial de edición",
    "services/DisplayCalibration.qml": "Horario y retención manual",
    "services/NightLight.js": "Rango horario y siguiente cambio",
    "services/Notifs.qml": "Sin emergente para apps silenciadas salvo críticas",
    "services/Weather.qml": "Descripción vacía en español",
    "shell.qml": "Controladores de hoja y editor; picker expuesto",
}

WAVE2_FAMILY_CREATIVE = {
    "Widgets de escritorio": "Centro relativo por monitor; borde del Hub reservado; muestreo dormido con ventanas encima",
    "Hoja de atajos": "Búsqueda y conflictos; mismo ayudante que el editor",
    "OSD y centro de control": "Mezclador y reproductor a demanda en el mismo pliegue",
    "Lanzador": "Archivos sin dependencias nuevas",
    "Ajustes": "Biblioteca viva para QA de temas; continuidad Ajustes → editor",
    "Vista general": "Filtro que no roba la F de flotante",
}


def git_lines(*args):
    return subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True, check=True).stdout.split()


def family_for(path):
    best = None
    for prefix in FAMILIES:
        if path == prefix or path.startswith(prefix):
            if best is None or len(prefix) > len(best):
                best = prefix
    return best


def main():
    inventory = json.loads(subprocess.run(
        [sys.executable, str(REPO / "scripts/verification/qml-inventory.py"), "--json"],
        capture_output=True, text=True, check=True).stdout)
    active = sorted(item["file"] for item in inventory if item["owner"] != "harness/test")
    js = sorted(p.relative_to(REPO / "cortetsu").as_posix()
                for p in (REPO / "cortetsu").rglob("*.js")
                if "tests" not in p.parts and "node_modules" not in p.parts)
    files = sorted(set(active) | set(js))
    strip = lambda paths: {p.removeprefix("cortetsu/") for p in paths}
    wave1 = strip(git_lines("diff", "--name-only", "--diff-filter=AM", f"{WAVE1[0]}..{WAVE1[1]}", "--", "cortetsu"))
    wave2 = strip(git_lines("diff", "--name-only", "--diff-filter=AM", f"{WAVE2_BASE}..HEAD", "--", "cortetsu"))
    added2 = strip(git_lines("diff", "--name-only", "--diff-filter=A", f"{WAVE2_BASE}..HEAD", "--", "cortetsu"))
    head = git_lines("rev-parse", "--short", "HEAD")[0]

    rows, counts = [], {}
    for path in files:
        prefix = family_for(path)
        fam = FAMILIES.get(prefix) if prefix else None
        if fam is None:
            state, fam = "PENDIENTE", dict(surface="?", refs=[], deficiency="Sin revisar", keep="", deps="", risks="", qa="")
            previous, change = "—", "—"
        else:
            previous = ("No existía (nuevo en la ola 2)" if path in added2
                        else "IMPLEMENTADO_SIN_VERIFICAR (ola 1)" if path in wave1
                        else next((label for prefixes, label in EARLIER if path.startswith(prefixes)), "Sin cambios en 3.0 hasta esta ola"))
            if path in wave2:
                state = "IMPLEMENTADO_SIN_VERIFICAR"
                change = CHANGES.get(path, "Cambio de la ola 2 (ver REGISTRO.md)")
            elif path in wave1:
                state = "IMPLEMENTADO_SIN_VERIFICAR"
                change = "Ola 1; revisado en la ola 2 sin cambios"
            else:
                state = "CONSERVADO_JUSTIFICADO"
                change = "—"
        counts[state] = counts.get(state, 0) + 1
        keep = fam["keep"] if state == "CONSERVADO_JUSTIFICADO" else ""
        creative = WAVE2_FAMILY_CREATIVE.get(fam["surface"], "—") if path in wave2 else "—"
        name = Path(path).stem
        rows.append(f"| `{path}` | {name} | {fam['surface']} | {previous} | {', '.join(fam['refs']) or '—'} | "
                    f"{fam['deficiency'] if path in wave2 or path in wave1 else (keep or '—')} | {change} | {creative} | "
                    f"{fam['deps'] or '—'} | **{state}** | {fam['risks'] or '—'} | {fam['qa'] or '—'} |")

    out = [
        "# Cobertura final de QML y JS de Cortetsu 3.0",
        "",
        f"Generado por `scripts/verification/qml-coverage.py` sobre `{head}`; no se edita a mano.",
        "Ningún estado está verificado en ejecución: las dos olas de construcción no",
        "ejecutaron pruebas, builds, lints ni el shell (ver `QA_POSTERIOR.md`).",
        "",
        "Archivos activos: todo QML que no es de prueba según `qml-inventory.py`, más los",
        "`.js` del shell fuera de `tests/`. Para un archivo conservado, la columna de",
        "deficiencias dice por qué ya cumple; para uno cambiado, qué le faltaba.",
        "",
        "| Estado | Archivos |",
        "| --- | --- |",
        *[f"| {state} | {counts[state]} |" for state in sorted(counts)],
        "",
        "Borrados en la ola 2 (sin referencias desde la fase 0, o sustituidos):",
        "`components/CAnim.qml`, `modules/background/DesktopClock.qml`,",
        "`modules/bar/components/Clock.qml`, `modules/bar/components/StatusIcons.qml`,",
        "`services/UsageFmt.qml`, `utils/CortetsuUtils.qml`, `utils/NetworkConnection.qml`,",
        "`utils/SysInfo.qml`.",
        "",
        "| Ruta | Componente | Superficie | Estado previo | Referencias | Deficiencias o motivo | Cambios | Mejora creativa | Dependencias | Estado final | Riesgos | QA pendiente |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        *rows,
        "",
    ]
    sys.stdout.write("\n".join(out))
    return 1 if counts.get("PENDIENTE") else 0


if __name__ == "__main__":
    sys.exit(main())
