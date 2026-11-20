pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../services"
import "../.."
import "../../ThemePreferences.js" as Preferences
import "../controls"

SettingsGroup {
    id: root
    title: qsTr("Material, tipografía y geometría")
    icon: "architecture"
    detail: qsTr("Cada tema conserva sus ajustes. Restaurar recupera sus valores originales.")
    readonly property var families: Qt.fontFamilies()
    Repeater {
        model: [{token: "fontUi", title: qsTr("Fuente de interfaz")}, {token: "fontHeading", title: qsTr("Fuente de títulos")},
            {token: "fontInk", title: qsTr("Fuente de tinta")}, {token: "fontKanji", title: qsTr("Fuente de sellos y kanji")}]
        SettingTextRow {
            id: fontRow
            required property var modelData
            // A family that is not installed would fall back silently; it is
            // refused here and the row says why. Read once per open page.
            property string refused: ""
            objectName: "themeToken-" + modelData.token
            title: modelData.title
            detail: qsTr("Nombre de una familia instalada en el sistema")
            status: refused.length > 0 ? "error" : ""
            statusText: refused.length > 0 ? qsTr("«%1» no está instalada").arg(refused) : ""
            value: CortetsuDesign[modelData.token]
            disabled: CortetsuThemes.previewId.length > 0 || CortetsuThemes.busy
            onCommitted: next => {
                const family = next.trim();
                if (family.length > 0 && !root.families.includes(family)) {
                    fontRow.refused = family;
                    return;
                }
                fontRow.refused = "";
                CortetsuConfig.setThemeToken(modelData.token, family);
            }
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
