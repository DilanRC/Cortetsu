pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../services"
import ".."
import "../launcher/services"
import "../CortetsuSearchBar.qml"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var screenState
    required property var screen
    required property var controller

    readonly property var selectedCategory: controller.categories.find(item => item.id === controller.selectedId) ?? null
    property string appearanceQuery: ""
    property bool navigationCollapsed: false
    readonly property var filteredSchemes: Schemes.list.filter(item => {
        const needle = root.appearanceQuery.trim().toLowerCase();
        return !needle || `${item.name} ${item.flavour}`.toLowerCase().includes(needle);
    })
    readonly property var activeSchemeData: Schemes.list.find(item =>
        `${item.name} ${item.flavour}` === Schemes.currentScheme) ?? null
    readonly property int schemeColumns: Math.max(2, Math.floor((schemeGrid.width + CortetsuDesign.spacingCompact) / 228))
    readonly property real schemeCardWidth: Math.floor(
        (schemeGrid.width - (root.schemeColumns - 1) * CortetsuDesign.spacingCompact) / root.schemeColumns)

    function schemeColour(value, fallback) {
        const text = String(value ?? "").trim();
        if (!text)
            return fallback;
        return text.startsWith("#") ? text : `#${text}`;
    }

    component AppearanceToggle: CortetsuSurface {
        id: appearanceToggle

        required property string title
        required property string detail
        required property string icon
        required property bool checked
        property bool disabled: false
        signal changed(bool value)

        Layout.fillWidth: true
        implicitHeight: 68
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlined: true
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)

        RowLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingStandard

            CortetsuIcon {
                text: appearanceToggle.icon
                iconSize: CortetsuTypography.iconMediumPx
                color: appearanceToggle.checked
                    ? CortetsuDesign.colorPrimary
                    : CortetsuDesign.colorOnSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                CortetsuText {
                    Layout.fillWidth: true
                    text: appearanceToggle.title
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: appearanceToggle.detail
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            CortetsuToggle {
                checked: appearanceToggle.checked
                disabled: appearanceToggle.disabled
                onToggled: value => appearanceToggle.changed(value)
            }
        }
    }

    Component.onCompleted: Schemes.reload()

    CortetsuText {
        id: title
        anchors.top: parent.top
        anchors.left: headerMark.right
        anchors.leftMargin: CortetsuDesign.spacingStandard
        text: qsTr("Ajustes de Cortetsu")
        textSize: CortetsuTypography.titleLargePx
        font.weight: Font.DemiBold
    }

    CortetsuEvolvingMark {
        id: headerMark
        anchors.left: parent.left
        anchors.top: parent.top
        width: 28
        height: 28
        phase: "Ascended"
        animated: false
        monochrome: true
        monochromeColor: CortetsuDesign.colorWashi
    }

    CortetsuText {
        anchors.top: title.bottom
        anchors.topMargin: CortetsuDesign.spacingUnit
        anchors.left: title.left
        text: qsTr("Un centro de control sereno para tu escritorio")
        textSize: CortetsuTypography.bodySmallPx
        color: CortetsuDesign.colorOnSurfaceVariant
    }

    CortetsuButton {
        anchors.right: parent.right
        anchors.top: parent.top
        compact: true
        icon: "close"
        label: qsTr("Cerrar")
        onClicked: root.screenState.settings = false
    }

    RowLayout {
        anchors.top: title.bottom
        anchors.topMargin: CortetsuDesign.spacingSection
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: CortetsuDesign.spacingSection

        CortetsuSurface {
            Layout.fillHeight: true
            Layout.preferredWidth: root.navigationCollapsed ? 82 : 278
            radiusValue: CortetsuDesign.radiusLarge
            baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
            outlined: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingCompact
                spacing: CortetsuDesign.spacingUnit

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: CortetsuDesign.spacingCompact
                    Layout.rightMargin: CortetsuDesign.spacingCompact
                    Layout.topMargin: CortetsuDesign.spacingCompact

                    CortetsuText {
                        Layout.fillWidth: true
                        visible: !root.navigationCollapsed
                        text: qsTr("SUPERFICIES DE CONTROL")
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        font.weight: Font.DemiBold
                    }

                    CortetsuButton {
                        compact: true
                        icon: root.navigationCollapsed ? "right_panel_open" : "left_panel_close"
                        label: ""
                        tooltipText: root.navigationCollapsed ? qsTr("Expandir navegación") : qsTr("Contraer navegación")
                        onClicked: root.navigationCollapsed = !root.navigationCollapsed
                    }
                }

                CortetsuSearchBar {
                    id: searchField
                    Layout.fillWidth: true
                    visible: !root.navigationCollapsed
                    compact: true
                    placeholderText: qsTr("Buscar ajustes")
                    onTextChanged: root.controller.search = text
                }

                ListView {
                    id: nav
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: root.controller.filteredCategories
                    section.property: "group"
                    section.criteria: ViewSection.FullString
                    section.delegate: CortetsuText {
                        required property string section
                        width: nav.width
                        text: root.navigationCollapsed ? "" : section.toUpperCase()
                        height: root.navigationCollapsed ? 0 : implicitHeight
                        topPadding: CortetsuDesign.spacingStandard
                        bottomPadding: CortetsuDesign.spacingUnit
                        leftPadding: CortetsuDesign.spacingCompact
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        font.weight: Font.DemiBold
                    }

                    delegate: CortetsuListRow {
                        required property var modelData
                        width: nav.width
                        icon: modelData.icon
                        compact: root.navigationCollapsed
                        tooltipText: root.navigationCollapsed ? modelData.title : ""
                        title: root.navigationCollapsed ? "" : modelData.title
                        subtitle: root.navigationCollapsed ? "" : modelData.detail
                        selected: root.controller.selectedId === modelData.id
                        onClicked: root.controller.select(modelData.id)
                    }

                    CortetsuStateMessage {
                        anchors.centerIn: parent
                        visible: nav.count === 0
                        kind: "empty"
                        title: qsTr("Sin resultados")
                        detail: qsTr("Prueba con una categoría, dispositivo o función")
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: scroller
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: Math.max(height, page.implicitHeight)
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: scroller.contentHeight > scroller.height
                        ? ScrollBar.AsNeeded
                        : ScrollBar.AlwaysOff
                }

                ColumnLayout {
                    id: page
                    width: scroller.width
                    spacing: CortetsuDesign.spacingSection

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: CortetsuDesign.spacingStandard

                        CortetsuEvolvingMark {
                            visible: root.controller.selectedId !== "network"
                            phase: "Ascended"
                            animated: false
                            monochrome: true
                            monochromeColor: CortetsuDesign.colorWashi
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                        }

                        CortetsuIcon {
                            visible: root.controller.selectedId === "network"
                            text: "wifi"
                            color: CortetsuDesign.colorPrimary
                            iconSize: 42
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            CortetsuText {
                                text: root.selectedCategory?.title ?? qsTr("Ajustes")
                                textSize: CortetsuTypography.titleLargePx
                                font.weight: Font.DemiBold
                            }

                            CortetsuText {
                                text: root.selectedCategory?.detail ?? ""
                                textSize: CortetsuTypography.bodySmallPx
                                color: CortetsuDesign.colorOnSurfaceVariant
                            }
                        }

                        RowLayout {
                            visible: root.controller.selectedId === "network"
                            Layout.alignment: Qt.AlignRight
                            spacing: CortetsuDesign.spacingCompact

                            CortetsuToggle {
                                checked: CortetsuSettingsNetwork.wifiEnabled
                                disabled: CortetsuSettingsNetwork.busy
                                onToggled: checked => CortetsuSettingsNetwork.setWifi(checked)
                            }

                            CortetsuButton {
                                compact: true
                                icon: "refresh"
                                label: qsTr("Actualizar")
                                tooltipText: qsTr("Buscar redes y volver a leer perfiles")
                                disabled: CortetsuSettingsNetwork.busy
                                onClicked: networkPage.refreshAll()
                            }
                        }
                    }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.controller.selectedId === "appearance"
                            spacing: CortetsuDesign.spacingSection

                        CortetsuSurface {
                            Layout.fillWidth: true
                            implicitHeight: 112
                            radiusValue: CortetsuDesign.radiusMedium
                            baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.42)
                            outlineColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.42)
                            outlined: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: CortetsuDesign.spacingStandard
                                spacing: CortetsuDesign.spacingStandard

                                CortetsuSurface {
                                    Layout.preferredWidth: 64
                                    Layout.preferredHeight: 64
                                    radiusValue: CortetsuDesign.radiusMedium
                                    baseColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.18)
                                    outlined: false
                                    CortetsuEvolvingMark {
                                        anchors.fill: parent
                                        phase: "Ascended"
                                        animated: false
                                        monochrome: true
                                        monochromeColor: CortetsuDesign.colorWashi
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    CortetsuText {
                                        Layout.fillWidth: true
                                        text: qsTr("Esquema activo")
                                        textSize: CortetsuTypography.titleMediumPx
                                        font.weight: Font.DemiBold
                                    }
                                    CortetsuText {
                                        Layout.fillWidth: true
                                        text: Schemes.currentScheme || qsTr("Sin esquema aplicado")
                                        textSize: CortetsuTypography.bodySmallPx
                                        color: CortetsuDesign.colorOnSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                    CortetsuText {
                                        Layout.fillWidth: true
                                        text: CortetsuConfig.transparencyEnabled
                                            ? qsTr("Superficies transparentes activas")
                                            : qsTr("Superficies opacas")
                                        textSize: CortetsuTypography.labelSmallPx
                                        color: CortetsuDesign.colorOnSurfaceVariant
                                    }
                                }

                                CortetsuText {
                                    text: qsTr("%1 familias").arg(Schemes.catalogCount)
                                    textSize: CortetsuTypography.bodySmallPx
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                }

                                Row {
                                    spacing: CortetsuDesign.spacingUnit
                                    Repeater {
                                        model: root.activeSchemeData
                                            ? ["primary", "secondary", "tertiary", "surface", "error"]
                                            : []
                                        delegate: Rectangle {
                                            required property string modelData
                                            width: 18
                                            height: 18
                                            radius: 4
                                            color: root.schemeColour(
                                                root.activeSchemeData?.colours[modelData],
                                                CortetsuDesign.colorOutlineVariant)
                                            border.width: 1
                                            border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.18)
                                        }
                                    }
                                }
                            }
                        }

                        CortetsuSectionHeader {
                            Layout.fillWidth: true
                            title: qsTr("Galería de esquemas")
                            detail: Schemes.error.length > 0
                                ? Schemes.error
                                : Schemes.loading
                                    ? qsTr("Leyendo familias de esquemas instaladas…")
                                    : qsTr("%1 instalados · %2 activo").arg(Schemes.catalogCount).arg(Schemes.currentScheme || qsTr("ninguno"))
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: CortetsuDesign.spacingCompact

                            CortetsuSearchBar {
                                Layout.fillWidth: true
                                placeholderText: qsTr("Filtrar por familia o variante")
                                onTextChanged: root.appearanceQuery = text
                            }

                            CortetsuText {
                                text: qsTr("%1 visibles").arg(root.filteredSchemes.length)
                                textSize: CortetsuTypography.bodySmallPx
                                color: CortetsuDesign.colorOnSurfaceVariant
                            }

                            CortetsuButton {
                                compact: true
                                icon: "refresh"
                                label: qsTr("Recargar")
                                tooltipText: qsTr("Volver a leer el catálogo de esquemas")
                                disabled: Schemes.loading
                                onClicked: Schemes.reload()
                            }
                        }

                        CortetsuSurface {
                            Layout.fillWidth: true
                            visible: Schemes.applying || Schemes.applyStatus === "applied" || Schemes.applyStatus === "failed"
                            implicitHeight: 64
                            radiusValue: CortetsuDesign.radiusMedium
                            baseColor: Schemes.applyStatus === "failed"
                                ? Qt.alpha(CortetsuDesign.colorWarning, 0.10)
                                : Schemes.applyStatus === "applied"
                                    ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.54)
                                    : Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
                            outlined: true
                            outlineColor: Schemes.applyStatus === "failed"
                                ? Qt.alpha(CortetsuDesign.colorWarning, 0.46)
                                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.46)

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: CortetsuDesign.spacingStandard
                                spacing: CortetsuDesign.spacingStandard

                                CortetsuIcon {
                                    text: Schemes.applying
                                        ? "sync"
                                        : Schemes.applyStatus === "failed"
                                            ? "error_outline"
                                            : "check_circle"
                                    iconSize: CortetsuTypography.iconMediumPx
                                    color: Schemes.applyStatus === "failed"
                                        ? CortetsuDesign.colorWarning
                                        : CortetsuDesign.colorPrimary
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    CortetsuText {
                                        Layout.fillWidth: true
                                        text: Schemes.applying
                                            ? qsTr("Aplicando esquema")
                                            : Schemes.applyStatus === "failed"
                                                ? qsTr("No se pudo aplicar el esquema")
                                                : qsTr("Esquema aplicado")
                                        textSize: CortetsuTypography.bodySmallPx
                                        font.weight: Font.DemiBold
                                    }

                                    CortetsuText {
                                        Layout.fillWidth: true
                                        text: Schemes.applyStatus === "failed"
                                            ? Schemes.applyError
                                            : Schemes.pendingScheme
                                        textSize: CortetsuTypography.labelSmallPx
                                        color: CortetsuDesign.colorOnSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        CortetsuSurface {
                            Layout.fillWidth: true
                            implicitHeight: 54
                            visible: Schemes.list.length === 0
                            radiusValue: CortetsuDesign.radiusMedium
                            baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.70)
                            outlined: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: CortetsuDesign.spacingStandard
                                spacing: CortetsuDesign.spacingStandard

                                CortetsuIcon {
                                    text: Schemes.loading ? "sync" : "palette"
                                    iconSize: CortetsuTypography.iconSmallPx
                                    color: Schemes.error.length > 0
                                        ? CortetsuDesign.colorWarning
                                        : CortetsuDesign.colorOnSurfaceVariant
                                }

                                CortetsuText {
                                    Layout.fillWidth: true
                                    text: Schemes.loading
                                        ? qsTr("Cargando catálogo de esquemas")
                                        : Schemes.error.length > 0
                                            ? Schemes.error
                                            : qsTr("No hay esquemas disponibles")
                                    textSize: CortetsuTypography.bodySmallPx
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                    wrapMode: Text.WordWrap
                                }

                                CortetsuButton {
                                    compact: true
                                    icon: "refresh"
                                    label: ""
                                    tooltipText: qsTr("Recargar esquemas")
                                    disabled: Schemes.loading
                                    onClicked: Schemes.reload()
                                }
                            }
                        }

                        Flow {
                            id: schemeGrid
                            Layout.fillWidth: true
                            Layout.preferredHeight: childrenRect.height
                            spacing: CortetsuDesign.spacingCompact

                            Repeater {
                                model: root.filteredSchemes

                                delegate: CortetsuChoiceCard {
                                    id: schemeCard
                                    required property var modelData

                                    readonly property var schemeData: modelData
                                    readonly property bool selectedScheme: `${modelData.name} ${modelData.flavour}` === Schemes.currentScheme

                                    width: root.schemeCardWidth
                                    height: 116
                                    title: schemeCard.schemeData.name

                                    subtitle: schemeCard.selectedScheme
                                        ? qsTr("%1 · activo").arg(schemeCard.schemeData.flavour)
                                        : schemeCard.schemeData.flavour
                                    selected: schemeCard.selectedScheme
                                    disabled: Schemes.applying

                                    swatches: ["primary", "secondary", "tertiary", "surface", "error"].map(key =>
                                        root.schemeColour(schemeCard.schemeData.colours[key], CortetsuDesign.colorOutlineVariant))

                                    onClicked: Schemes.apply(schemeCard.schemeData.name, schemeCard.schemeData.flavour)
                                }
                            }
                        }

                        CortetsuSectionHeader {
                            Layout.fillWidth: true
                            title: qsTr("Apariencia del shell")
                            detail: qsTr("Preferencias persistentes y calibración disponible del sistema")
                        }

                        CortetsuSectionHeader {
                            Layout.fillWidth: true
                            title: qsTr("Preferencias de superficie")
                            detail: qsTr("Cambios persistentes aplicados a todo Cortetsu")
                        }

                        AppearanceToggle {
                            title: qsTr("Esquema inteligente")
                            detail: qsTr("Permitir que el shell adapte el esquema a la superficie activa")
                            icon: "auto_awesome"
                            checked: CortetsuConfig.smartScheme
                            onChanged: value => { CortetsuConfig.smartScheme = value; CortetsuConfig.save(); }
                        }

                        AppearanceToggle {
                            title: qsTr("Integración del fondo")
                            detail: qsTr("Permitir que el fondo participe en la composición del shell")
                            icon: "wallpaper"
                            checked: CortetsuConfig.wallpaperEnabled
                            onChanged: value => { CortetsuConfig.wallpaperEnabled = value; CortetsuConfig.save(); }
                        }

                        AppearanceToggle {
                            title: qsTr("Superficies transparentes")
                            detail: qsTr("Aplicar transparencia calibrada a paneles y tarjetas")
                            icon: "blur_on"
                            checked: CortetsuConfig.transparencyEnabled
                            onChanged: value => { CortetsuConfig.transparencyEnabled = value; CortetsuConfig.save(); }
                        }

                        AppearanceToggle {
                            title: qsTr("Reloj de 12 horas")
                            detail: qsTr("Usar formato de 12 horas en reloj y avisos")
                            icon: "schedule"
                            checked: CortetsuConfig.useTwelveHourClock
                            onChanged: value => { CortetsuConfig.useTwelveHourClock = value; CortetsuConfig.save(); }
                        }

                        AppearanceToggle {
                            title: qsTr("Temperatura en Fahrenheit")
                            detail: qsTr("Mostrar temperatura en °F en Dashboard y métricas")
                            icon: "thermostat"
                            checked: CortetsuConfig.useFahrenheit
                            onChanged: value => { CortetsuConfig.useFahrenheit = value; CortetsuConfig.save(); }
                        }

                        AppearanceToggle {
                            title: qsTr("Visualizador de audio")
                            detail: qsTr("Mostrar el visualizador reactivo cuando hay audio")
                            icon: "graphic_eq"
                            checked: CortetsuConfig.visualiserEnabled
                            onChanged: value => { CortetsuConfig.visualiserEnabled = value; CortetsuConfig.save(); }
                        }

                        AppearanceToggle {
                            title: qsTr("Ocultar visualizador sin ventanas flotantes")
                            detail: qsTr("Liberar el visualizador cuando no hay contenido visible")
                            icon: "visibility_off"
                            checked: CortetsuConfig.visualiserAutoHide
                            disabled: !CortetsuConfig.visualiserEnabled
                            onChanged: value => { CortetsuConfig.visualiserAutoHide = value; CortetsuConfig.save(); }
                        }

                        CortetsuSectionHeader {
                            Layout.fillWidth: true
                            title: qsTr("Geometría de la interfaz")
                            detail: qsTr("Bordes y densidad del visualizador de audio")
                        }

                        CortetsuSurface {
                            Layout.fillWidth: true
                            implicitHeight: 112
                            radiusValue: CortetsuDesign.radiusMedium
                            baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
                            outlined: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: CortetsuDesign.spacingStandard
                                spacing: CortetsuDesign.spacingCompact
                                RowLayout {
                                    Layout.fillWidth: true
                                    CortetsuIcon { text: "rounded_corner"; color: CortetsuDesign.colorPrimary }
                                    CortetsuText { Layout.fillWidth: true; text: qsTr("Grosor de bordes"); font.weight: Font.DemiBold }
                                    CortetsuText { text: qsTr("%1 px").arg(CortetsuConfig.borderThickness); color: CortetsuDesign.colorOnSurfaceVariant }
                                }
                                CortetsuSlider {
                                    Layout.fillWidth: true
                                    from: 0; to: 8; step: 1
                                    value: CortetsuConfig.borderThickness
                                    onMoved: nextValue => {
                                        CortetsuConfig.borderThickness = Math.round(nextValue);
                                        CortetsuConfig.save();
                                    }
                                }
                            }
                        }

                        CortetsuSurface {
                            Layout.fillWidth: true
                            implicitHeight: 112
                            radiusValue: CortetsuDesign.radiusMedium
                            baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
                            outlined: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: CortetsuDesign.spacingStandard
                                spacing: CortetsuDesign.spacingCompact
                                RowLayout {
                                    Layout.fillWidth: true
                                    CortetsuIcon { text: "graphic_eq"; color: CortetsuDesign.colorPrimary }
                                    CortetsuText { Layout.fillWidth: true; text: qsTr("Barras del visualizador"); font.weight: Font.DemiBold }
                                    CortetsuText { text: qsTr("%1").arg(CortetsuConfig.visualiserBars); color: CortetsuDesign.colorOnSurfaceVariant }
                                }
                                CortetsuSlider {
                                    Layout.fillWidth: true
                                    from: 8; to: 128; step: 4
                                    value: CortetsuConfig.visualiserBars
                                    disabled: !CortetsuConfig.visualiserEnabled
                                    onMoved: nextValue => {
                                        CortetsuConfig.visualiserBars = Math.round(nextValue / 4) * 4;
                                        CortetsuConfig.save();
                                    }
                                }
                            }
                        }
                    }

                    SystemPage {
                        Layout.fillWidth: true
                        visible: root.controller.selectedId !== "appearance" && root.controller.selectedId !== "about"
                            && root.controller.selectedId !== "network"
                        section: root.controller.selectedId
                        screen: root.screen
                        screenState: root.screenState
                    }

                    NetworkPage {
                        id: networkPage
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        visible: root.controller.selectedId === "network"
                        screen: root.screen
                        screenState: root.screenState
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.controller.selectedId === "about"
                        spacing: CortetsuDesign.spacingStandard

                        CortetsuSectionHeader {
                            Layout.fillWidth: true
                            title: qsTr("Acerca de Cortetsu")
                            detail: qsTr("Shell de escritorio propio")
                        }

                        CortetsuSurface {
                            Layout.fillWidth: true
                            implicitHeight: 128
                            radiusValue: CortetsuDesign.radiusLarge
                            baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
                            outlined: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: CortetsuDesign.spacingSpacious
                                spacing: CortetsuDesign.spacingSpacious

                                CortetsuEvolvingMark {
                                    phase: "Ascended"
                                    animated: false
                                    monochrome: true
                                    monochromeColor: CortetsuDesign.colorWashi
                                    Layout.preferredWidth: 72
                                    Layout.preferredHeight: 72
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: CortetsuDesign.spacingUnit
                                    CortetsuText {
                                        text: qsTr("Cortetsu")
                                        textSize: 28
                                        font.weight: Font.DemiBold
                                    }
                                    CortetsuText {
                                        text: qsTr("Shell preciso para trabajo concentrado")
                                        textSize: CortetsuTypography.bodyPx
                                        color: CortetsuDesign.colorOnSurfaceVariant
                                    }
                                    CortetsuText {
                                        text: qsTr("Generación: Ascension · superficies propias")
                                        textSize: CortetsuTypography.labelMediumPx
                                        color: CortetsuDesign.colorOnSurfaceVariant
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: CortetsuDesign.spacingSpacious
                    }
                }
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.screenState.settings = false
    }
}
