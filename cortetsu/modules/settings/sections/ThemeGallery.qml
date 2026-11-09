pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../theme"
import "../../../services"
import "../.."
import "../../CortetsuTypography.js" as CortetsuTypography
import "../controls"

// The three themes side by side, each drawn in its own material. A card can
// be tried on (a reversible preview of the whole shell) or applied. While a
// preview shows, a bar says so and offers to keep it or go back.
SettingsGroup {
    id: root

    readonly property var themes: [
        { id: "ink", name: "Ink", line: qsTr("Tinta, índigo y bermellón sobre carbón") },
        { id: "washi", name: "Washi", line: qsTr("Papel claro, serif editorial y sombra suave") },
        { id: "kurogane", name: "Kurogane", line: qsTr("Acero mate, contornos precisos y densidad técnica") }
    ]
    readonly property string previewName: themes.find(item => item.id === CortetsuThemes.previewId)?.name ?? ""

    title: qsTr("Tema")
    icon: "style"
    detail: qsTr("Material, tipografía, geometría y densidad de todo el escritorio")
    panel: false

    Component.onDestruction: CortetsuThemes.cancelPreview()

    GridLayout {
        id: grid
        Layout.fillWidth: true
        columns: width >= 660 ? 3 : width >= 440 ? 2 : 1
        columnSpacing: CortetsuDesign.spacingStandard
        rowSpacing: CortetsuDesign.spacingStandard

        Repeater {
            model: root.themes

            Item {
                id: card

                required property var modelData
                readonly property bool active: CortetsuConfig.themeId === modelData.id
                readonly property bool previewing: CortetsuThemes.previewId === modelData.id
                // Applying is the card's own action: a click anywhere on it.
                signal clicked()
                onClicked: CortetsuThemes.select(modelData.id)

                objectName: "theme-" + modelData.id
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: cardColumn.implicitHeight + CortetsuDesign.spacingStandard * 2
                property bool selected: active
                property bool disabled: active || CortetsuThemes.busy

                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.name
                Accessible.description: modelData.line
                Accessible.checked: active

                CortetsuSurface {
                    anchors.fill: parent
                    radiusValue: CortetsuDesign.radiusLarge
                    active: card.active || card.previewing
                    hovered: hover.hovered
                    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.7)
                    activeColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.55)
                    outlineColor: card.active || card.previewing ? CortetsuDesign.colorIndicator
                        : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.6)
                    border.width: card.active || card.previewing ? 2 : 1
                }

                HoverHandler { id: hover }

                ColumnLayout {
                    id: cardColumn
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingStandard
                    spacing: CortetsuDesign.spacingCompact

                    ThemePreview {
                        Layout.fillWidth: true
                        themeId: card.modelData.id
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: CortetsuDesign.spacingCompact

                        CortetsuText {
                            Layout.fillWidth: true
                            text: card.modelData.name
                            textSize: CortetsuTypography.titleSmallPx
                            font.family: CortetsuDesign.fontHeading
                            font.weight: CortetsuDesign.headingWeight
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            visible: card.active || card.previewing
                            implicitWidth: badge.implicitWidth + 14
                            implicitHeight: badge.implicitHeight + 6
                            radius: CortetsuDesign.materialStyle === 2 ? CortetsuDesign.radiusSmall : height / 2
                            color: CortetsuDesign.colorPrimaryContainer

                            CortetsuText {
                                id: badge
                                anchors.centerIn: parent
                                text: card.previewing ? qsTr("Vista previa") : qsTr("Activo")
                                textSize: CortetsuTypography.labelSmallPx
                                font.weight: Font.DemiBold
                                color: CortetsuDesign.colorOnPrimaryContainer
                            }
                        }
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: card.modelData.line
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: CortetsuDesign.spacingCompact

                        CortetsuButton {
                            objectName: "themePreview-" + card.modelData.id
                            Layout.fillWidth: true
                            compact: true
                            icon: "visibility"
                            label: qsTr("Probar")
                            tooltipText: qsTr("Ver todo el escritorio con %1 sin guardarlo").arg(card.modelData.name)
                            disabled: card.active || card.previewing || CortetsuThemes.busy
                            function request(): void { if (!disabled) CortetsuThemes.previewTheme(card.modelData.id); }
                            onClicked: request()
                        }

                        CortetsuButton {
                            objectName: "themeApply-" + card.modelData.id
                            Layout.fillWidth: true
                            compact: true
                            active: true
                            icon: card.active ? "check" : "format_paint"
                            label: card.active ? qsTr("Activo") : qsTr("Aplicar")
                            disabled: card.disabled
                            onClicked: card.clicked()
                        }
                    }
                }
            }
        }
    }

    // The preview is the whole shell, so it needs a way out that is always
    // in reach while it lasts.
    CortetsuSurface {
        objectName: "themePreviewBar"
        Layout.fillWidth: true
        visible: CortetsuThemes.previewId.length > 0
        implicitHeight: previewRow.implicitHeight + CortetsuDesign.spacingStandard * 2
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.8)
        outlined: true
        outlineColor: CortetsuDesign.colorIndicator

        RowLayout {
            id: previewRow
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingStandard

            CortetsuIcon {
                text: "visibility"
                iconSize: CortetsuTypography.iconSmallPx
                color: CortetsuDesign.colorOnPrimaryContainer
            }

            CortetsuText {
                Layout.fillWidth: true
                text: qsTr("Vista previa de %1. No se ha guardado nada.").arg(root.previewName)
                textSize: CortetsuTypography.bodyPx
                color: CortetsuDesign.colorOnPrimaryContainer
                wrapMode: Text.WordWrap
            }

            CortetsuButton {
                objectName: "themePreviewCancel"
                compact: true
                icon: "undo"
                label: qsTr("Volver al guardado")
                function request(): void { CortetsuThemes.cancelPreview(); }
                onClicked: request()
            }

            CortetsuButton {
                objectName: "themePreviewKeep"
                compact: true
                active: true
                icon: "check"
                label: qsTr("Aplicar %1").arg(root.previewName)
                disabled: CortetsuThemes.busy
                onClicked: CortetsuThemes.select(CortetsuThemes.previewId)
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
