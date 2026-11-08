pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../modules"

Singleton {
    id: root
    readonly property bool busy: apply.running || projection.running || action.running || preview.running
    property string pending: ""
    property string error: ""
    property bool slowNoticeShown: false
    property bool stateReady: false
    property bool reconciled: false
    property string savedTheme: ""
    property var integrations: ({})
    property bool syncAfterSave: false
    property string previewId: ""
    property string previewRequested: ""
    property string previewSchemeName: ""
    property string previewSchemeFlavour: ""
    property var pendingPreviewScheme: ({})
    property string notice: ""
    property bool externalPending: false
    property string externalTheme: ""
    onBusyChanged: if (!busy) Qt.callLater(root.idleWork)
    function idleWork(): void {
        drainSync();
        if (externalPending && !busy && ["idle", "saved"].includes(CortetsuConfig.saveState)) {
            externalPending = false;
            externalTheme = savedTheme;
            CortetsuConfig.reloadPreferences();
        }
    }
    function drainSync(): void {
        if (syncAfterSave && !busy && CortetsuConfig.saveState === "saved") {
            syncAfterSave = false;
            sync();
        }
    }

    function profile(operation: string, path: string): void {
        if (busy || !["import", "export"].includes(operation)) return;
        if (CortetsuConfig.saveState === "pending" || CortetsuConfig.saveState === "saving") {
            error = qsTr("Espera a que se guarden los ajustes antes de gestionar perfiles");
            return;
        }
        cancelPreview();
        action.command = ["cortetsu-scheme", "profile", operation, path];
        action.running = true;
    }

    function cancelPreview(): void {
        previewRequested = "";
        previewId = "";
        previewSchemeName = "";
        previewSchemeFlavour = "";
        pendingPreviewScheme = ({});
        CortetsuColours.clearPreview();
    }
    function previewTheme(id: string): void {
        if (busy || !["ink", "washi", "kurogane"].includes(id)) return;
        previewRequested = id;
        pendingPreviewScheme = ({});
        preview.command = ["cortetsu-scheme", "preview-theme", id];
        preview.running = true;
    }
    function previewScheme(name: string, flavour: string): void {
        if (busy) return;
        previewRequested = CortetsuConfig.themeId;
        pendingPreviewScheme = {name, flavour};
        preview.command = ["cortetsu-scheme", "preview-scheme", name, flavour];
        preview.running = true;
    }
    function setMode(light: bool): void {
        if (busy) return;
        cancelPreview();
        action.command = ["cortetsu-scheme", "set", "--mode", light ? "light" : "dark"];
        action.running = true;
    }
    function resetTheme(): void {
        if (busy || previewId) return;
        action.command = ["cortetsu-scheme", "reset-theme"];
        action.running = true;
    }
    function setSource(automatic: bool): void {
        if (busy) return;
        if (["pending", "saving"].includes(CortetsuConfig.saveState)) {
            error = qsTr("Espera a que se guarden los ajustes antes de cambiar el origen de color");
            return;
        }
        action.command = ["cortetsu-scheme", "source", automatic ? "auto" : "manual"];
        action.running = true;
    }

    function setIntegration(id: string, enabled: bool): void {
        if (busy || !["hyprland", "kitty", "gtk", "qt"].includes(id)) return;
        CortetsuConfig.themeIntegrations = Object.assign({}, CortetsuConfig.themeIntegrations, {[id]: enabled});
        syncAfterSave = true;
        CortetsuConfig.save();
    }
    function sync(): void {
        if (busy) return;
        projection.command = ["cortetsu-scheme", "sync-projections"];
        projection.running = true;
    }

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
        function onLoadedChanged(): void {
            root.reconcile();
            if (CortetsuConfig.loaded && root.externalTheme) {
                const theme = root.externalTheme;
                root.externalTheme = "";
                CortetsuConfig.selectTheme(theme);
            }
        }
        function onSaveStateChanged(): void {
            root.idleWork();
        }
    }
    FileView {
        path: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/cortetsu/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        printErrors: false
        onLoaded: {
            try { root.savedTheme = JSON.parse(text()).themeId || ""; } catch (_) {}
            root.stateReady = true;
            if (root.reconciled) {
                root.externalPending = true;
                Qt.callLater(root.idleWork);
            }
            root.reconcile();
        }
        onLoadFailed: { root.stateReady = true; root.reconcile(); }
    }
    FileView {
        path: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/cortetsu/theme-sync.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.integrations = JSON.parse(text()).targets || ({});
                root.error = Object.entries(root.integrations).filter(([_, result]) => result.status === "error")
                    .map(([target, result]) => `${target}: ${result.detail}`).join("; ");
            } catch (_) {}
        }
    }

    function select(id: string): void {
        if (!reconciled || busy || !["ink", "washi", "kurogane"].includes(id) || id === CortetsuConfig.themeId)
            return;
        error = "";
        cancelPreview();
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
        id: preview
        stdout: StdioCollector { id: previewResult }
        stderr: StdioCollector { id: previewError }
        onExited: code => {
            if (!root.previewRequested) return;
            if (code === 0) {
                root.previewId = root.previewRequested;
                root.previewSchemeName = root.pendingPreviewScheme.name || "";
                root.previewSchemeFlavour = root.pendingPreviewScheme.flavour || "";
                CortetsuColours.load(previewResult.text, true);
            } else root.error = previewError.text.trim() || qsTr("No se pudo cargar la vista previa");
        }
    }
    Process {
        id: action
        stdout: StdioCollector { id: actionResult }
        stderr: StdioCollector { id: actionError }
        onExited: code => {
            try {
                const result = JSON.parse(actionResult.text);
                if (code !== 0 || result.committed !== true) throw new Error(actionError.text.trim());
                if (result.preferences) {
                    CortetsuConfig.load(JSON.stringify(result.preferences));
                    CortetsuConfig.saveState = "saved";
                    if (typeof result.smartScheme !== "boolean") root.sync();
                }
                if (result.reset === true) {
                    CortetsuConfig.resetThemeTokens();
                    CortetsuConfig.transparencyEnabled = false;
                    CortetsuConfig.reducedMotion = false;
                    CortetsuConfig.smartScheme = true;
                    CortetsuConfig.borderThickness = 1;
                    CortetsuConfig.save();
                }
                root.notice = result.reset ? qsTr("Tema restaurado. Respaldo: %1").arg(result.backup)
                    : result.path ? qsTr("Perfil exportado: %1").arg(result.path)
                    : result.backup ? qsTr("Perfil importado. Respaldo: %1").arg(result.backup) : "";
                root.error = result.projectionError || "";
            } catch (_) { root.error = actionError.text.trim() || qsTr("No se pudo confirmar el cambio de paleta"); }
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
        stdout: StdioCollector { id: projectionResult }
        onExited: code => {
            if (code === 0) {
                root.error = "";
                try {
                    root.integrations = JSON.parse(projectionResult.text).targets;
                    root.error = Object.entries(root.integrations).filter(([_, result]) => result.status === "error")
                        .map(([target, result]) => `${target}: ${result.detail}`).join("; ");
                } catch (_) { root.error = qsTr("No se pudo confirmar la sincronización de aplicaciones"); }
            } else
                root.error = projectionErrors.text.trim() || qsTr("Tema activo en Cortetsu; no se confirmó Hyprland y Kitty");
        }
    }
}
