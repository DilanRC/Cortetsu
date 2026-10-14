pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../components"
import "../../../theme"
import "../.."
import "../../launcher/services"
import "../../CortetsuSearchBar.qml"
import "../../CortetsuTypography.js" as CortetsuTypography
import "../controls"
import "../Navigation.js" as Navigation

ColumnLayout {
    id: root

    required property var context

    readonly property bool wide: true
    property string query: ""
    readonly property int columns: Math.max(2, Math.floor((grid.width + CortetsuDesign.spacingCompact) / 216))
    readonly property real cardWidth: Math.floor((grid.width - (columns - 1) * CortetsuDesign.spacingCompact) / columns)
    readonly property int shown: Schemes.list.filter(item => root.matches(item)).length
    readonly property var swatchRoles: ["primary", "secondary", "tertiary", "surface", "error"]

    function matches(item): bool {
        const needle = Navigation.normalise(root.query);
        return !needle || Navigation.normalise(`${item.name} ${item.flavour}`).includes(needle);
    }

    // The colours of a catalogue entry, not of the active theme: a preview
    // square does not change when the shell is recoloured.
    function swatches(colours): var {
        return root.swatchRoles.map(role => {
            const text = String(colours?.[role] ?? "").trim();
            return text.length === 0 ? "transparent" : text.startsWith("#") ? text : `#${text}`;
        });
    }

    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Esquema de color")
        detail: Schemes.loading
            ? qsTr("Leyendo el catálogo…")
            : qsTr("%1 instalados").arg(Schemes.catalogCount)

        SettingValueRow {
            objectName: "activeScheme"
            title: Schemes.applying ? qsTr("Aplicando") : qsTr("Esquema activo")
            detail: Schemes.applyStatus === "applied" ? qsTr("Aplicado a todas las superficies") : ""
            status: Schemes.applyStatus === "failed" ? "error" : ""
            statusText: qsTr("%1 no se aplicó: %2").arg(Schemes.pendingScheme).arg(Schemes.applyError)
            value: Schemes.applying ? Schemes.pendingScheme : Schemes.currentScheme
        }

        SettingToggleRow {
            title: qsTr("Esquema según el fondo")
            detail: qsTr("Al cambiar de fondo, derivar el esquema de la imagen")
            checked: CortetsuConfig.smartScheme
            onToggled: value => { CortetsuConfig.smartScheme = value; CortetsuConfig.save(); }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: CortetsuDesign.spacingCompact

        CortetsuSearchBar {
            objectName: "schemeFilter"
            Layout.fillWidth: true
            compact: true
            placeholderText: qsTr("Filtrar esquemas")
            Accessible.name: placeholderText
            onTextChanged: root.query = text
        }

        CortetsuText {
            Layout.minimumWidth: 72
            horizontalAlignment: Text.AlignRight
            text: qsTr("%1 de %2").arg(root.shown).arg(Schemes.catalogCount)
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }

        CortetsuButton {
            compact: true
            icon: "refresh"
            label: ""
            tooltipText: qsTr("Volver a leer el catálogo")
            Accessible.name: tooltipText
            disabled: Schemes.loading
            onClicked: Schemes.reload()
        }
    }

    CortetsuStateMessage {
        objectName: "schemeState"
        Layout.fillWidth: true
        Layout.topMargin: CortetsuDesign.spacingStandard
        visible: root.shown === 0
        kind: Schemes.error.length > 0 ? "error" : Schemes.loading ? "loading" : "empty"
        icon: Schemes.error.length > 0 ? "error_outline" : Schemes.loading ? "sync" : "palette"
        title: Schemes.error.length > 0
            ? Schemes.error
            : Schemes.loading
                ? qsTr("Leyendo el catálogo de esquemas")
                : Schemes.catalogCount === 0 ? qsTr("No hay esquemas instalados") : qsTr("Ningún esquema coincide")
        detail: Schemes.error.length > 0 ? qsTr("Pulsa el botón de recarga para intentarlo de nuevo") : ""
    }

    Flow {
        id: grid
        Layout.fillWidth: true
        spacing: CortetsuDesign.spacingCompact

        // The catalogue objects are stable and the model follows them one by
        // one, so a filter only hides cards, applying a scheme only moves the
        // selection, and a new scheme adds a single card.
        Repeater {
            id: cards
            model: ScriptModel { values: [...Schemes.list] }

            delegate: CortetsuChoiceCard {
                id: card

                required property var modelData
                readonly property string key: `${modelData.name} ${modelData.flavour}`

                objectName: `scheme-${modelData.name}-${modelData.flavour}`
                visible: root.matches(modelData)
                width: root.cardWidth
                height: 104
                title: modelData.name
                subtitle: card.key === Schemes.currentScheme
                    ? qsTr("%1 · activo").arg(modelData.flavour)
                    : card.key === Schemes.pendingScheme && Schemes.applying
                        ? qsTr("%1 · aplicando").arg(modelData.flavour)
                        : modelData.flavour
                selected: card.key === Schemes.currentScheme
                disabled: Schemes.applying
                swatches: root.swatches(modelData.colours)
                Accessible.role: Accessible.RadioButton
                Accessible.name: card.key
                Accessible.checked: selected
                onClicked: Schemes.apply(modelData.name, modelData.flavour)
            }
        }
    }

    SettingsGroup {
        title: qsTr("Superficies")

        SettingToggleRow {
            objectName: "transparency"
            title: qsTr("Superficies transparentes")
            detail: qsTr("Paneles y tarjetas dejan ver el fondo")
            checked: CortetsuConfig.transparencyEnabled
            onToggled: value => { CortetsuConfig.transparencyEnabled = value; CortetsuConfig.save(); }
        }

        SettingSliderRow {
            objectName: "borderThickness"
            title: qsTr("Grosor de bordes")
            valueText: qsTr("%1 px").arg(CortetsuConfig.borderThickness)
            from: 0
            to: 8
            step: 1
            value: CortetsuConfig.borderThickness
            onMoved: next => { CortetsuConfig.borderThickness = Math.round(next); CortetsuConfig.save(); }
        }
    }

    SettingsGroup {
        title: qsTr("Reloj y unidades")

        SettingToggleRow {
            title: qsTr("Reloj de 12 horas")
            detail: CortetsuConfig.useTwelveHourClock ? qsTr("Se muestra como 3:45 p. m.") : qsTr("Se muestra como 15:45")
            checked: CortetsuConfig.useTwelveHourClock
            onToggled: value => { CortetsuConfig.useTwelveHourClock = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Temperatura en Fahrenheit")
            detail: qsTr("En el clima y en las lecturas del equipo")
            checked: CortetsuConfig.useFahrenheit
            onToggled: value => { CortetsuConfig.useFahrenheit = value; CortetsuConfig.save(); }
        }
    }

    SettingsGroup {
        title: qsTr("Visualizador de audio")
        detail: qsTr("Barras sobre el fondo mientras suena algo")

        SettingToggleRow {
            title: qsTr("Visualizador de audio")
            checked: CortetsuConfig.visualiserEnabled
            onToggled: value => { CortetsuConfig.visualiserEnabled = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Solo con ventanas flotantes")
            detail: qsTr("Ocultarlo cuando el espacio no tiene ventanas flotantes")
            checked: CortetsuConfig.visualiserAutoHide
            disabled: !CortetsuConfig.visualiserEnabled
            onToggled: value => { CortetsuConfig.visualiserAutoHide = value; CortetsuConfig.save(); }
        }

        SettingSliderRow {
            title: qsTr("Número de barras")
            valueText: String(CortetsuConfig.visualiserBars)
            from: 8
            to: 128
            step: 4
            value: CortetsuConfig.visualiserBars
            disabled: !CortetsuConfig.visualiserEnabled
            onMoved: next => { CortetsuConfig.visualiserBars = Math.round(next / 4) * 4; CortetsuConfig.save(); }
        }
    }
}
