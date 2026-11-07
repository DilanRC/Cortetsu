pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../modules"

Singleton {
    id: root
    readonly property bool busy: apply.running || projection.running
    property string pending: ""
    property string error: ""
    property bool slowNoticeShown: false
    property bool stateReady: false
    property bool reconciled: false
    property string savedTheme: ""

    function reconcile(): void {
        if (reconciled || !stateReady || !CortetsuConfig.loaded)
            return;
        // The native scheme commit precedes the preference write. Recover a
        // process interruption between them from the committed native state.
        if (["ink", "washi", "kurogane"].includes(savedTheme))
            CortetsuConfig.selectTheme(savedTheme);
        reconciled = true;
    }

    Connections {
        target: CortetsuConfig
        function onLoadedChanged(): void { root.reconcile(); }
    }
    FileView {
        path: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/cortetsu/scheme.json`
        printErrors: false
        onLoaded: {
            try { root.savedTheme = JSON.parse(text()).themeId || ""; } catch (_) {}
            root.stateReady = true;
            root.reconcile();
        }
        onLoadFailed: { root.stateReady = true; root.reconcile(); }
    }

    function select(id: string): void {
        if (!reconciled || busy || !["ink", "washi", "kurogane"].includes(id) || id === CortetsuConfig.themeId)
            return;
        error = "";
        slowNoticeShown = false;
        pending = id;
        apply.command = ["cortetsu-scheme", "theme", id, "--from", CortetsuConfig.themeId, "--defer-projections"];
        apply.running = true;
    }

    Timer {
        interval: Number(Quickshell.env("CORTETSU_THEME_ACK_TIMEOUT_MS") || 15000)
        running: root.busy
        onTriggered: {
            root.slowNoticeShown = true;
            root.error = qsTr("El cambio sigue esperando; no cierres Ajustes mientras termina");
        }
    }

    Process {
        id: apply
        stderr: StdioCollector { id: errors }
        stdout: StdioCollector { id: result }
        onExited: code => {
            let response = null;
            try { response = JSON.parse(result.text); } catch (_) {}
            const committed = code === 0 && response?.committed === true && response.themeId === root.pending;
            if (committed) {
                root.error = "";
                CortetsuConfig.selectTheme(root.pending);
                projection.command = ["cortetsu-scheme", "sync-projections"];
                projection.running = true;
            } else {
                root.error = errors.text.trim() || qsTr("No se pudo confirmar el esquema del tema");
            }
            root.pending = "";
        }
    }

    Process {
        id: projection
        stderr: StdioCollector { id: projectionErrors }
        onExited: code => {
            if (code === 0)
                root.error = "";
            else
                root.error = projectionErrors.text.trim() || qsTr("Tema activo en Cortetsu; no se confirmó Hyprland y Kitty");
        }
    }
}
