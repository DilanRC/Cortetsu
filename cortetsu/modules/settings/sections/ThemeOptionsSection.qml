pragma ComponentBehavior: Bound

import QtQuick
import "../../../services"
import "../.."
import "../controls"

// The choices people change most after the theme itself. Washi is paper
// and Kurogane steel whatever the mode, so only Ink follows light or dark.
SettingsGroup {
    id: root

    readonly property bool modeFree: CortetsuConfig.themeId === "ink"

    title: qsTr("Opciones rápidas")
    icon: "tune"

    SettingChoiceChips {
        objectName: "paletteMode"
        title: qsTr("Modo")
        detail: root.modeFree
            ? qsTr("Regenera los tonos Material conservando el tema y la variante")
            : qsTr("%1 tiene su propio fondo; el modo claro u oscuro solo se aplica en Ink")
                .arg(CortetsuConfig.themeId === "washi" ? "Washi" : "Kurogane")
        disabled: !root.modeFree || CortetsuThemes.busy
        current: CortetsuColours.currentLight ? "light" : "dark"
        options: [
            { value: "light", label: qsTr("Claro"), icon: "light_mode", name: "paletteLightMode" },
            { value: "dark", label: qsTr("Oscuro"), icon: "dark_mode", name: "paletteDarkMode" }
        ]
        onChosen: value => CortetsuThemes.setMode(value === "light")
    }

    SettingToggleRow {
        objectName: "transparency"
        title: qsTr("Superficies transparentes")
        detail: qsTr("Paneles y tarjetas dejan ver el fondo")
        checked: CortetsuConfig.transparencyEnabled
        onToggled: value => { CortetsuConfig.transparencyEnabled = value; CortetsuConfig.save(); }
    }
}
