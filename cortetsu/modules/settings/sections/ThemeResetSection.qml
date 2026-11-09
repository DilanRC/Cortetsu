pragma ComponentBehavior: Bound
import QtQuick
import "../../../services"
import "../controls"

SettingsGroup {
    title: qsTr("Recuperación")
    icon: "settings_backup_restore"
    detail: qsTr("Devuelve el tema activo a sus valores de fábrica; antes se guarda una copia")

    SettingActionRow {
        objectName: "resetThemeTokens"
        title: qsTr("Restaurar colores, material y geometría del tema")
        actionLabel: qsTr("Restaurar tema")
        confirm: true
        actionDisabled: CortetsuThemes.previewId.length > 0 || CortetsuThemes.busy
        onActivated: CortetsuThemes.resetTheme()
    }
}
