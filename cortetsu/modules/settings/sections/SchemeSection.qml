pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../components"
import "../../../theme"
import "../../../services"
import "../.."
import "../../launcher/services"
import "../../CortetsuSearchBar.qml"
import "../../CortetsuTypography.js" as CortetsuTypography
import "../controls"
import "../Navigation.js" as Navigation

// The palette inside the theme: where it comes from, how Material derives
// its tones, and the installed schemes to choose from.
ColumnLayout {
    id: root

    required property var context

    property string query: ""
    property bool previewSchemes: false
    readonly property int columns: Math.max(2, Math.floor((grid.width + CortetsuDesign.spacingCompact) / 200))
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
    Component.onDestruction: CortetsuThemes.cancelPreview()

    SettingsColumns {
        SettingsGroup {
            title: qsTr("Esquema de color")
            icon: "palette"
            detail: Schemes.loading
                ? qsTr("Leyendo el catálogo…")
                : qsTr("%1 instalados").arg(Schemes.catalogCount)

            SettingValueRow {
                objectName: "activeScheme"
                title: Schemes.applying ? qsTr("Aplicando") : qsTr("Esquema activo")
                detail: Schemes.applyStatus === "applied" ? qsTr("Aplicado a todas las superficies") : ""
                status: Schemes.applyError ? "error" : ""
                statusText: Schemes.applyError
                value: Schemes.applying ? Schemes.pendingScheme : Schemes.currentScheme
            }

            SettingToggleRow {
                title: qsTr("Esquema según el fondo")
                detail: qsTr("Al cambiar de fondo, derivar el esquema de la imagen")
                checked: CortetsuConfig.smartScheme && CortetsuColours.origin !== "manual"
                disabled: CortetsuThemes.busy
                onToggled: value => CortetsuThemes.setSource(value)
            }

            SettingToggleRow {
                objectName: "schemePreviewMode"
                title: qsTr("Previsualizar esquemas antes de aplicar")
                detail: qsTr("Pulsar una paleta muestra sus colores sin guardarlos")
                checked: root.previewSchemes
                onToggled: enabled => { root.previewSchemes = enabled; if (!enabled) CortetsuThemes.cancelPreview(); }
            }

            SettingActionRow {
                objectName: "schemePreviewApply"
                visible: root.previewSchemes
                title: qsTr("Guardar el esquema de la vista previa")
                actionLabel: qsTr("Aplicar esquema")
                actionDisabled: !CortetsuThemes.previewSchemeName || CortetsuThemes.busy
                onActivated: {
                    Schemes.apply(CortetsuThemes.previewSchemeName, CortetsuThemes.previewSchemeFlavour);
                    root.previewSchemes = false;
                }
            }
        }

        aside: SettingsGroup {
            objectName: "paletteVariants"
            title: qsTr("Variante de paleta")
            icon: "colors"
            detail: CortetsuConfig.themeId !== "ink"
                ? qsTr("En %1 la variante tiñe los acentos; el fondo es el del tema").arg(CortetsuConfig.themeId === "washi" ? "Washi" : "Kurogane")
                : qsTr("Cómo el color del fondo genera los tonos Material")

            SettingChoiceChips {
                options: M3Variants.list.map(item => ({ value: item.variant, label: item.name, name: `variant-${item.variant}` }))
                current: M3Variants.list.find(item => Schemes.variantIsCurrent(item.variant))?.variant
                pending: Schemes.pendingVariant
                disabled: !Schemes.variantAvailable || Schemes.variantStatus === "applying"
                status: Schemes.variantError.length > 0 ? "error" : Schemes.variantStatus === "applying" ? "busy" : ""
                statusText: Schemes.variantError.length > 0 ? Schemes.variantError : qsTr("Guardando en el sistema…")
                detail: !Schemes.variantAvailable
                    ? qsTr("Aplica primero un esquema de color para generar una paleta")
                    : M3Variants.list.find(item => Schemes.variantIsCurrent(item.variant))?.description ?? ""
                onChosen: value => Schemes.applyVariant(value)
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: CortetsuDesign.spacingCompact

        CortetsuIcon {
            text: "grid_view"
            iconSize: CortetsuTypography.iconSmallPx
            color: CortetsuDesign.colorPrimary
        }

        CortetsuText {
            text: CortetsuDesign.labelCaps ? qsTr("ESQUEMAS INSTALADOS") : qsTr("Esquemas instalados")
            textSize: CortetsuDesign.labelCaps ? CortetsuTypography.labelLargePx : CortetsuTypography.titleSmallPx
            font.family: CortetsuDesign.fontHeading
            font.weight: CortetsuDesign.headingWeight
            font.letterSpacing: CortetsuDesign.labelTracking
        }

        Item { Layout.fillWidth: true }

        CortetsuSearchBar {
            objectName: "schemeFilter"
            Layout.preferredWidth: 260
            compact: true
            placeholderText: qsTr("Filtrar esquemas")
            Accessible.name: placeholderText
            onTextChanged: root.query = text
        }

        CortetsuText {
            Layout.minimumWidth: 64
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
        Layout.topMargin: -CortetsuDesign.spacingStandard
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
                subtitle: CortetsuColours.showPreview && card.key === `${CortetsuThemes.previewSchemeName} ${CortetsuThemes.previewSchemeFlavour}`
                    ? qsTr("%1 · vista previa").arg(modelData.flavour)
                    : card.key === Schemes.currentScheme
                    ? qsTr("%1 · activo").arg(modelData.flavour)
                    : card.key === Schemes.pendingScheme && Schemes.applying
                        ? qsTr("%1 · aplicando").arg(modelData.flavour)
                        : modelData.flavour
                selected: card.key === Schemes.currentScheme
                disabled: Schemes.applying || CortetsuThemes.busy
                swatches: root.swatches(modelData.colours)
                swatchFallback: qsTr("Colores tomados del fondo")
                Accessible.role: Accessible.RadioButton
                Accessible.name: card.key
                Accessible.checked: selected
                onClicked: root.previewSchemes
                    ? CortetsuThemes.previewScheme(modelData.name, modelData.flavour)
                    : Schemes.apply(modelData.name, modelData.flavour)
            }
        }
    }
}
