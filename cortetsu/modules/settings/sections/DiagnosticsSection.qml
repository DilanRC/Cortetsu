pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../controls"

// What is running, read from the generation's own manifest, and where to
// look when something is wrong.
ColumnLayout {
    id: root

    required property var context

    readonly property var build: root.context.build
    readonly property bool known: (build.buildId ?? "").length > 0

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

        SettingValueRow {
            title: qsTr("Estado y diagnóstico")
            detail: qsTr("Desde una terminal: cortetsu status y cortetsu doctor")
        }

        SettingValueRow {
            title: qsTr("Volver a la generación anterior")
            detail: qsTr("Desde una terminal: cortetsu rollback restaura shell, dotfiles y helpers")
        }
    }
}
