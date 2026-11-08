pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../../services"
import "../controls"

SettingsGroup {
    id: root
    property string profilePath: (Quickshell.env("HOME") || "") + "/cortetsu-visual-profile.json"
    title: qsTr("Perfiles visuales")
    detail: qsTr("Incluye tema, paleta, materiales y preferencias visuales. Conserva comandos y ajustes de otras funciones.")
    SettingTextRow {
        objectName: "themeProfilePath"
        title: qsTr("Archivo del perfil")
        value: root.profilePath
        placeholderText: qsTr("Ruta absoluta a un archivo JSON")
        disabled: CortetsuThemes.busy
        onCommitted: value => root.profilePath = value.trim()
    }
    SettingActionRow {
        objectName: "themeProfileExport"
        title: qsTr("Exportar perfil actual")
        detail: qsTr("Crea un archivo nuevo; si ya existe, elige otra ruta")
        actionLabel: qsTr("Exportar")
        actionDisabled: CortetsuThemes.busy
        onActivated: CortetsuThemes.profile("export", root.profilePath)
    }
    SettingActionRow {
        objectName: "themeProfileImport"
        title: qsTr("Importar perfil visual")
        detail: CortetsuThemes.notice
        actionLabel: qsTr("Importar")
        confirm: true
        status: CortetsuThemes.error ? "error" : ""
        statusText: CortetsuThemes.error
        actionDisabled: CortetsuThemes.busy
        onActivated: CortetsuThemes.profile("import", root.profilePath)
    }
}
