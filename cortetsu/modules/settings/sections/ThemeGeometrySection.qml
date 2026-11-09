pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../services"
import "../.."
import "../../ThemePreferences.js" as Preferences
import "../controls"

SettingsGroup {
    title: qsTr("Material, tipografía y geometría")
    icon: "architecture"
    detail: qsTr("Cada tema conserva sus ajustes. Restaurar recupera sus valores originales.")
    Repeater {
        model: [{token: "fontUi", title: qsTr("Fuente de interfaz")}, {token: "fontHeading", title: qsTr("Fuente de títulos")},
            {token: "fontInk", title: qsTr("Fuente de tinta")}, {token: "fontKanji", title: qsTr("Fuente de sellos y kanji")}]
        SettingTextRow {
            required property var modelData
            objectName: "themeToken-" + modelData.token
            title: modelData.title
            detail: qsTr("Nombre de una familia instalada en el sistema")
            value: CortetsuDesign[modelData.token]
            disabled: CortetsuThemes.previewId.length > 0 || CortetsuThemes.busy
            onCommitted: next => CortetsuConfig.setThemeToken(modelData.token, next)
        }
    }
    Repeater {
        model: [
            {token: "radiusSmall", title: qsTr("Radio de controles pequeños"), step: 1},
            {token: "radiusMedium", title: qsTr("Radio de tarjetas"), step: 1},
            {token: "radiusSurface", title: qsTr("Radio de paneles"), step: 1},
            {token: "rowHeight", title: qsTr("Altura de filas"), step: 2},
            {token: "spacingSection", title: qsTr("Separación de secciones"), step: 4},
            {token: "materialGroundAlpha", title: qsTr("Opacidad del material"), step: 0.01},
            {token: "materialGrain", title: qsTr("Textura del material"), step: 0.01},
            {token: "materialHairlineAlpha", title: qsTr("Intensidad del borde del material"), step: 0.01}
        ]
        SettingSliderRow {
            required property var modelData
            objectName: "themeToken-" + modelData.token
            title: modelData.title
            disabled: CortetsuThemes.previewId.length > 0 || CortetsuThemes.busy
            from: Preferences.limits[modelData.token][0]
            to: Preferences.limits[modelData.token][1]
            step: modelData.step
            value: CortetsuDesign[modelData.token]
            valueText: Preferences.limits[modelData.token][1] <= 1 ? qsTr("%1 %").arg(Math.round(value * 100)) : qsTr("%1 px").arg(Math.round(value))
            onMoved: next => CortetsuConfig.setThemeToken(modelData.token, next)
        }
    }
}
