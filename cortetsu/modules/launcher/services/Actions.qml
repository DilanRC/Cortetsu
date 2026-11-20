pragma Singleton

import ".."
import "../.."
import QtQuick
import Quickshell
import "../../../services"
import "../../../utils"

Searcher {
    id: root

    function transformSearch(search: string): string {
        return search.slice(CortetsuConfig.actionPrefix.length);
    }

    list: variants.instances

    readonly property var builtins: {
        const ipc = (...args) => ["cortetsu", "shell", "ipc", ...args];
        const surface = name => ipc("drawers", "toggle", name);
        return [
            { name: qsTr("Captura de área"), icon: "screenshot_region", description: qsTr("Selecciona un área o una ventana y la captura"), command: ipc("picker", "open") },
            { name: qsTr("Captura congelada"), icon: "photo_camera", description: qsTr("Congela la pantalla antes de elegir el área"), command: ipc("picker", "openFreeze") },
            { name: qsTr("Grabar área"), icon: "screen_record", description: qsTr("Elige un área y empieza a grabarla"), command: ipc("picker", "record") },
            { name: CortetsuRecorder.running ? qsTr("Detener grabación") : qsTr("Grabar pantalla"), icon: CortetsuRecorder.running ? "stop_circle" : "radio_button_checked", description: CortetsuRecorder.running ? qsTr("Termina y guarda la grabación en curso") : qsTr("Graba la pantalla completa"), command: ["cortetsu-record", CortetsuRecorder.running ? "stop" : "start"] },
            { name: qsTr("Selector de color"), icon: "colorize", description: qsTr("Elige un color de la pantalla y lo copia"), command: ["hyprpicker", "--autocopy"] },
            { name: qsTr("Fondo aleatorio"), icon: "shuffle", description: qsTr("Aplica un fondo al azar de tu carpeta"), command: ipc("cortetsu-wallpaper", "random") },
            { name: qsTr("Fondos de pantalla"), icon: "wallpaper", description: qsTr("Abre el selector de fondos"), command: surface("wallpaperManager") },
            { name: qsTr("Fondos animados de Steam"), icon: "animation", description: qsTr("Wallpaper Engine en Orbital: aplicar, detener y perfiles por monitor"), command: ["orbital-steam"] },
            { name: qsTr("Ajustes"), icon: "settings", description: qsTr("Abre los ajustes de Cortetsu"), command: surface("settings") },
            { name: qsTr("Hardware"), icon: "memory", description: qsTr("Rendimiento, sensores, energía y procesos"), command: surface("hardware") },
            { name: qsTr("Pantallas"), icon: "monitor", description: qsTr("Resolución, escala y posición de los monitores"), command: surface("displayManager") },
            { name: qsTr("Teclados"), icon: "keyboard", description: qsTr("Distribuciones y atajos"), command: surface("keyboards") },
            { name: qsTr("Buscar archivos"), icon: "folder_open", description: qsTr("Por nombre, en tu carpeta personal (índice de plocate)"), command: ["autocomplete", "files"] },
            { name: qsTr("Editar el escritorio"), icon: "widgets", description: qsTr("Añadir, mover y quitar widgets"), command: surface("desktopWidgets") },
            { name: qsTr("Hoja de atajos"), icon: "keyboard_command_key", description: qsTr("Todas las combinaciones, con búsqueda (SUPER+F1)"), command: surface("cheatsheet") },
            { name: qsTr("Portapapeles"), icon: "content_paste", description: qsTr("Historial del portapapeles"), command: surface("clipboard") },
            { name: qsTr("Calendario"), icon: "calendar_month", description: qsTr("Calendario y pomodoro"), command: surface("calendar") },
            { name: qsTr("Vista general"), icon: "overview", description: qsTr("Todas las ventanas y espacios de trabajo"), command: surface("overview") },
            { name: qsTr("No molestar"), icon: "do_not_disturb_on", description: qsTr("Activa o desactiva las notificaciones"), command: ["cortetsu-notifications", "dnd", "toggle"] },
            { name: qsTr("Limpiar notificaciones"), icon: "clear_all", description: qsTr("Descarta todas las notificaciones"), command: ["cortetsu-notifications", "clear"] },
            { name: qsTr("Mantener despierto"), icon: "coffee", description: qsTr("Impide que la pantalla se apague o se bloquee"), command: ipc("keepAwake", "toggle") },
            { name: qsTr("Recargar Cortetsu"), icon: "refresh", description: qsTr("Recarga el shell sin cerrar las ventanas"), command: ["cortetsu", "shell", "reload"] },
            { name: qsTr("Recargar Hyprland"), icon: "sync", description: qsTr("Vuelve a leer la configuración y los atajos"), command: ["hyprctl", "reload"] }
        ];
    }
    useFuzzy: CortetsuConfig.useFuzzyActions

    Variants {
        id: variants

        // Built-ins first, then the user's own. User entries inherited from
        // the upstream defaults that Cortetsu cannot run (caelestia CLI,
        // light/dark switch) are dropped instead of listed as dead rows, and
        // a user entry with a built-in's name replaces nothing: built-ins win.
        model: {
            const builtinNames = root.builtins.map(a => a.name);
            const user = CortetsuConfig.actions.filter(a => (a.enabled ?? true)
                && (CortetsuConfig.enableDangerousActions || !(a.dangerous ?? false))
                && !["caelestia", "setMode"].includes(a.command?.[0])
                && !builtinNames.includes(a.name));
            // One entry per context; the active one reads as its way back.
            const contexts = CortetsuContexts.contexts.map(c => CortetsuContexts.activeId === c.id
                ? { name: qsTr("Salir de %1").arg(c.name), icon: c.icon, description: qsTr("Desactiva el contexto y restaura los ajustes anteriores"), command: ["context", c.id] }
                : { name: qsTr("Contexto: %1").arg(c.name), icon: c.icon, description: c.summary || qsTr("Activa este contexto"), command: ["context", c.id] });
            return [...root.builtins, ...contexts, ...user];
        }

        Action {}
    }

    component Action: QtObject {
        required property var modelData
        readonly property string name: modelData.name ?? qsTr("Sin nombre")
        // Sleep actions are named modes, not programs; logind decides
        // whether they can run here.
        readonly property string sleepMode: ["suspend", "hibernate", "suspendThenHibernate"].includes(command[0] ?? "")
            ? command[0] : ""
        // Light/dark actions inherited from the upstream defaults never get
        // here: the model above drops every "setMode" entry (no Cortetsu
        // command switches the mode of the current scheme).
        readonly property bool available: !sleepMode || CortetsuSession.available(sleepMode)
        readonly property string desc: available
            ? (modelData.description ?? qsTr("Sin descripción"))
            : CortetsuSession.reason(sleepMode)
        readonly property string icon: modelData.icon ?? "help_outline"
        readonly property list<string> command: modelData.command ?? []
        readonly property bool enabled: modelData.enabled ?? true
        readonly property bool dangerous: modelData.dangerous ?? false

        function onClicked(list: AppList): void {
            if (command.length === 0 || !available)
                return;

            if (command[0] === "autocomplete" && command.length > 1) {
                list.search.text = `${CortetsuConfig.actionPrefix}${command[1]} `;
            } else if (command[0] === "orbital-steam") {
                list.screenState.launcher = false;
                Orbital.requestSteam();
                WallpaperController.openActive();
            } else if (command[0] === "context" && command.length > 1) {
                list.screenState.launcher = false;
                CortetsuContexts.toggle(command[1]);
            } else if (sleepMode) {
                list.screenState.launcher = false;
                CortetsuSession.request(sleepMode);
            } else {
                list.screenState.launcher = false;
                CortetsuProcessLauncher.launchPersistent(command, "", name);
            }
        }
    }
}
