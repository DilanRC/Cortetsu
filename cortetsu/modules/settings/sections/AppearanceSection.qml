pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../components"
import "../../../theme"
import "../../../theme/ThemeProfiles.js" as Profiles
import "../../../theme/CortetsuDesignDefaults.js" as Defaults
import "../../../services"
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
    property bool previewSchemes: false
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
    Component.onDestruction: CortetsuThemes.cancelPreview()
    SettingsGroup {
        title: qsTr("Tema de Cortetsu")
        detail: qsTr("Colores base, materiales, tipografía y densidad")
        Flow {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact
            Repeater {
            model: [{ id: "ink", name: "Ink" }, { id: "washi", name: "Washi" }, { id: "kurogane", name: "Kurogane" }]
            CortetsuChoiceCard {
                required property var modelData
                readonly property var tokens: Profiles.tokens(modelData.id)
                objectName: "theme-" + modelData.id
                width: root.cardWidth
                title: modelData.name
                subtitle: selected ? qsTr("Activo") : qsTr("Aplicar tema")
                selected: CortetsuConfig.themeId === modelData.id
                disabled: selected || CortetsuThemes.busy
                swatches: [tokens.colorSumi || Defaults.colorSumi, tokens.colorSurface || Defaults.colorSurface,
                    tokens.colorPrimary || Defaults.colorPrimary, tokens.colorOnSurface || Defaults.colorOnSurface]
                onClicked: CortetsuThemes.select(modelData.id)
            }
            }
        }
        SettingValueRow {
            objectName: "themeStatus"
            visible: CortetsuThemes.error.length > 0 || CortetsuThemes.busy
            title: qsTr("Estado del tema")
            value: CortetsuThemes.pending || CortetsuConfig.themeId
            status: CortetsuThemes.busy ? "busy" : "error"
            statusText: CortetsuThemes.error || qsTr("Guardando tema y sincronizando aplicaciones")
        }
    }
    SettingsGroup {
        title: qsTr("Vista previa reversible")
        detail: qsTr("Prueba los colores y materiales sin guardar. Cerrar esta página cancela la vista previa.")
        Repeater {
            model: ["ink", "washi", "kurogane"]
            SettingActionRow {
                required property string modelData
                objectName: "themePreview-" + modelData
                title: modelData
                actionLabel: CortetsuThemes.previewId === modelData ? qsTr("En vista previa") : qsTr("Previsualizar")
                actionDisabled: CortetsuThemes.busy
                onActivated: CortetsuThemes.previewTheme(modelData)
            }
        }
        SettingActionRow {
            objectName: "themePreviewCancel"
            title: qsTr("Volver al tema guardado")
            actionLabel: qsTr("Cancelar vista previa")
            actionDisabled: CortetsuThemes.previewId.length === 0
            onActivated: CortetsuThemes.cancelPreview()
        }
    }
    SettingsGroup {
        title: qsTr("Sincronización de aplicaciones")
        detail: qsTr("La paleta se comparte con los destinos compatibles. Algunas aplicaciones deben abrirse de nuevo.")
        Repeater {
            model: [{id: "hyprland", title: qsTr("Compositor")}, {id: "kitty", title: qsTr("Terminal Kitty")},
                {id: "gtk", title: qsTr("GTK")}, {id: "qt", title: qsTr("Qt / KDE")}]
            SettingToggleRow {
                required property var modelData
                readonly property var result: CortetsuThemes.integrations[modelData.id] || ({status: "pending"})
                objectName: "themeIntegration-" + modelData.id
                title: modelData.title
                checked: CortetsuConfig.themeIntegrations[modelData.id] !== false
                disabled: CortetsuThemes.busy || CortetsuThemes.syncAfterSave
                status: result.status === "error" ? "error" : CortetsuThemes.busy ? "busy" : ""
                statusText: result.status === "error" ? result.detail || "" : ""
                detail: result.status === "applied" ? qsTr("Aplicado")
                    : result.status === "reopen" ? qsTr("Requiere reabrir la aplicación")
                    : result.status === "disabled" ? qsTr("Desactivado")
                    : result.status === "unavailable" ? qsTr("No disponible: %1").arg(result.detail || "")
                    : result.status === "error" ? qsTr("Error de sincronización") : qsTr("Pendiente de sincronización")
                onToggled: enabled => CortetsuThemes.setIntegration(modelData.id, enabled)
            }
        }
        SettingActionRow {
            objectName: "themeSync"
            title: qsTr("Volver a sincronizar")
            actionLabel: qsTr("Sincronizar")
            actionDisabled: CortetsuThemes.busy
            status: CortetsuThemes.error ? "error" : ""
            statusText: CortetsuThemes.error
            onActivated: CortetsuThemes.sync()
        }
    }
    SettingsGroup {
        title: qsTr("Esquema de color")
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
            objectName: "schemePreviewMode"
            title: qsTr("Previsualizar esquemas antes de aplicar")
            detail: qsTr("Pulsar una paleta muestra sus colores sin guardarlos")
            checked: root.previewSchemes
            onToggled: enabled => { root.previewSchemes = enabled; if (!enabled) CortetsuThemes.cancelPreview(); }
        }
        SettingActionRow {
            objectName: "schemePreviewApply"
            title: qsTr("Guardar el esquema de la vista previa")
            actionLabel: qsTr("Aplicar esquema")
            actionDisabled: !CortetsuThemes.previewSchemeName || CortetsuThemes.busy
            onActivated: {
                Schemes.apply(CortetsuThemes.previewSchemeName, CortetsuThemes.previewSchemeFlavour);
                root.previewSchemes = false;
            }
        }

        SettingToggleRow {
            title: qsTr("Esquema según el fondo")
            detail: qsTr("Al cambiar de fondo, derivar el esquema de la imagen")
            checked: CortetsuConfig.smartScheme && CortetsuColours.origin !== "manual"
            disabled: CortetsuThemes.busy
            onToggled: value => CortetsuThemes.setSource(value)
        }
        SettingToggleRow {
            objectName: "paletteLightMode"
            title: qsTr("Paleta clara")
            detail: qsTr("Regenera los tonos Material conservando el tema y la variante")
            checked: CortetsuColours.currentLight
            disabled: CortetsuThemes.busy
            onToggled: value => CortetsuThemes.setMode(value)
        }
    }

    SettingsGroup {
        objectName: "paletteVariants"
        title: qsTr("Variante de paleta")
        detail: Schemes.variantStatus === "applying"
            ? qsTr("Guardando en el sistema…")
            : Schemes.variantError
                ? Schemes.variantError
                : !Schemes.variantAvailable
                    ? qsTr("Aplica primero un esquema de color para generar una paleta")
                    : qsTr("Define cómo el color del fondo genera los tonos Material")

        Repeater {
            model: M3Variants.list

            SettingActionRow {
                required property var modelData
                objectName: `variant-${modelData.variant}`
                title: modelData.name
                detail: modelData.description
                actionLabel: Schemes.variantIsCurrent(modelData.variant)
                    ? Schemes.variantError ? qsTr("Reintentar") : qsTr("Activa")
                    : qsTr("Aplicar")
                actionDisabled: !Schemes.variantAvailable
                    || (Schemes.variantIsCurrent(modelData.variant) && Schemes.variantError.length === 0)
                    || Schemes.variantStatus === "applying"
                status: Schemes.variantError.length > 0 && Schemes.pendingVariant === modelData.variant
                    ? "error"
                    : Schemes.variantStatus === "applying" && Schemes.pendingVariant === modelData.variant
                        ? "busy" : ""
                statusText: status === "error" ? Schemes.variantError : ""
                onActivated: Schemes.applyVariant(modelData.variant)
            }
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
                Accessible.role: Accessible.RadioButton
                Accessible.name: card.key
                Accessible.checked: selected
                onClicked: root.previewSchemes
                    ? CortetsuThemes.previewScheme(modelData.name, modelData.flavour)
                    : Schemes.apply(modelData.name, modelData.flavour)
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

        SettingToggleRow {
            objectName: "reducedMotion"
            title: qsTr("Reducir movimiento")
            detail: qsTr("Los cambios de la interfaz ocurren sin animación")
            checked: CortetsuConfig.reducedMotion
            onToggled: value => { CortetsuConfig.reducedMotion = value; CortetsuConfig.save(); }
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

    ThemeGeometrySection {}
    ThemeProfileSection {}

    SettingsGroup {
        title: qsTr("Reloj y unidades")

        SettingToggleRow {
            objectName: "clockFormat"
            title: qsTr("Reloj de 12 horas")
            detail: CortetsuConfig.useTwelveHourClock ? qsTr("Se muestra como 3:45 p. m.") : qsTr("Se muestra como 15:45")
            checked: CortetsuConfig.useTwelveHourClock
            onToggled: value => { CortetsuConfig.useTwelveHourClock = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            objectName: "clockSeconds"
            title: qsTr("Mostrar segundos")
            detail: qsTr("Actualizar el reloj una vez por segundo")
            checked: CortetsuConfig.useSecondPrecision
            onToggled: value => { CortetsuConfig.useSecondPrecision = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            objectName: "useFahrenheit"
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
