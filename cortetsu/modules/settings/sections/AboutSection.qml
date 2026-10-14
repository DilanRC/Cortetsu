pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../controls"

// What is installed and running, read from the generation's own manifest.
ColumnLayout {
    id: root

    required property var context

    readonly property var build: root.context.build
    readonly property bool known: (build.buildId ?? "").length > 0

    function builtAt(): string {
        const moment = new Date(build.builtAt ?? "");
        return isNaN(moment.getTime()) ? qsTr("No disponible") : Qt.formatDateTime(moment, "yyyy-MM-dd HH:mm");
    }

    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Cortetsu")
        detail: qsTr("Shell de escritorio sobre Quickshell y Hyprland")

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
            visible: root.known
            title: qsTr("Construida")
            value: root.builtAt()
        }
    }

    SettingsGroup {
        title: qsTr("Mantenimiento")

        SettingValueRow {
            title: qsTr("Estado y diagnóstico")
            detail: qsTr("Desde una terminal: cortetsu status y cortetsu doctor")
        }
    }
}
