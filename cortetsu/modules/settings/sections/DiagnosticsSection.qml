pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../../theme"
import "../controls"

// What is running, read from the generation's own manifest, and where to
// look when something is wrong.
ColumnLayout {
    id: root

    required property var context

    readonly property var build: root.context.build
    readonly property bool known: (build.buildId ?? "").length > 0

    // `cortetsu doctor --json`, on request: read-only checks of packages,
    // runtime, dotfiles and services. idle | running | ready | error
    property string doctorState: "idle"
    property string doctorError: ""
    property var checks: []
    property date checkedAt: new Date()
    readonly property var attention: checks.filter(check => check.status !== "ok")
    readonly property int failures: checks.filter(check => check.status === "error" && check.required).length

    function runDoctor(): void {
        if (doctor.running)
            return;
        root.doctorState = "running";
        root.doctorError = "";
        doctor.running = true;
    }

    function receive(text: string): void {
        try {
            const data = JSON.parse(text);
            if (!Array.isArray(data.checks))
                throw new Error("invalid");
            root.checks = data.checks.filter(check => check && typeof check.name === "string");
            root.checkedAt = new Date();
            root.doctorState = "ready";
        } catch (failure) {
            root.doctorError = qsTr("La respuesta de cortetsu doctor no se pudo leer");
            root.doctorState = "error";
        }
    }

    // startup inventory: cortetsu:settings-doctor (on request only)
    Process {
        id: doctor
        command: ["cortetsu", "doctor", "--json"]
        stdout: StdioCollector { id: doctorOutput }
        // A failing check exits non-zero but still prints the report.
        onExited: code => {
            if (doctorOutput.text.trim().length > 0)
                root.receive(doctorOutput.text);
            else {
                root.doctorError = qsTr("cortetsu doctor terminó con el código %1 sin informe").arg(code);
                root.doctorState = "error";
            }
        }
    }

    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Generación en uso")
        icon: "deployed_code"

        SettingValueRow {
            objectName: "revision"
            title: qsTr("Revisión instalada")
            detail: root.known ? (root.build.repositoryRevision ?? "") : qsTr("Esta copia se ejecuta desde el código fuente, sin generación")
            value: root.known ? root.context.revision : qsTr("No disponible")
        }

        SettingValueRow {
            objectName: "generation"
            visible: root.known
            title: qsTr("Generación")
            value: root.build.buildId ?? ""
        }

        SettingValueRow {
            objectName: "runtimeManifest"
            visible: root.known
            title: qsTr("Manifiesto del runtime")
            value: String(root.build.runtimeManifestSha256 ?? "").slice(0, 12)
        }
    }

    SettingsGroup {
        title: qsTr("Mantenimiento")
        icon: "monitor_heart"

        SettingActionRow {
            objectName: "runDoctor"
            title: qsTr("Estado y diagnóstico")
            detail: root.doctorState === "idle" ? qsTr("Paquetes, runtime, dotfiles y servicios; no cambia nada")
                : root.doctorState === "running" ? qsTr("Comprobando…")
                : root.doctorState === "error" ? root.doctorError
                : root.attention.length === 0 ? qsTr("%1 comprobaciones correctas · %2").arg(root.checks.length).arg(Qt.formatTime(root.checkedAt, "HH:mm"))
                : root.failures > 0 ? qsTr("%1 errores obligatorios, %2 avisos · %3").arg(root.failures).arg(root.attention.length - root.failures).arg(Qt.formatTime(root.checkedAt, "HH:mm"))
                : qsTr("%1 avisos de %2 comprobaciones · %3").arg(root.attention.length).arg(root.checks.length).arg(Qt.formatTime(root.checkedAt, "HH:mm"))
            status: root.doctorState === "running" ? "busy" : root.doctorState === "error" || root.failures > 0 ? "error" : ""
            statusText: root.doctorState === "running" ? qsTr("Comprobando…") : root.doctorState === "error" ? root.doctorError
                : root.failures > 0 ? qsTr("%1 comprobaciones obligatorias fallan").arg(root.failures) : ""
            actionLabel: root.doctorState === "idle" ? qsTr("Comprobar") : qsTr("Repetir")
            actionIcon: "monitor_heart"
            actionDisabled: root.doctorState === "running"
            onActivated: root.runDoctor()
        }

        // Only what needs attention; a clean report is one line above.
        Repeater {
            model: root.doctorState === "ready" ? root.attention : []
            delegate: SettingValueRow {
                required property var modelData
                title: modelData.name
                detail: modelData.detail ?? ""
                value: modelData.status === "error" ? (modelData.required ? qsTr("Error") : qsTr("Error opcional")) : qsTr("Aviso")
                attention: modelData.status === "error" && modelData.required
            }
        }

        SettingValueRow {
            title: qsTr("Volver a la generación anterior")
            detail: qsTr("Desde una terminal: cortetsu rollback restaura shell, dotfiles y helpers")
        }
    }
}
