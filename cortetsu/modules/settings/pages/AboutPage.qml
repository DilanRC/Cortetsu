pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../theme"
import ".."
import "../../CortetsuTypography.js" as CortetsuTypography
import "../controls"

// Who Cortetsu is, what is running, how its parts stand, and who it owes.
SettingsPage {
    id: root

    required property var context

    readonly property var build: context.build
    readonly property bool known: (build.buildId ?? "").length > 0
    readonly property string builtAt: {
        const moment = new Date(build.builtAt ?? "");
        return isNaN(moment.getTime()) ? qsTr("No disponible") : Qt.formatDateTime(moment, "yyyy-MM-dd HH:mm");
    }
    // Each component with the service that answers for it right now.
    readonly property var components: [
        { name: qsTr("Red"), detail: "NetworkManager", value: context.summary.network, ok: !context.alert.network },
        { name: qsTr("Bluetooth"), detail: "BlueZ", value: context.summary.bluetooth, ok: !context.alert.bluetooth },
        { name: qsTr("Sonido"), detail: "PipeWire", value: context.summary.audio, ok: !context.alert.audio },
        { name: qsTr("Energía"), detail: "UPower", value: context.summary.power, ok: !context.alert.power },
        { name: qsTr("Automatización"), detail: qsTr("Coordinador de Cortetsu"), value: context.summary.automation, ok: !context.alert.automation,
          off: !(context.policies?.usable ?? false) },
        { name: qsTr("Tema"), detail: qsTr("Paleta y sincronización"), value: context.summary.theme, ok: !context.alert.theme }
    ]

    kind: "wide"

    // The mark and the name, set in the theme's own heading voice.
    CortetsuSurface {
        objectName: "aboutHero"
        Layout.fillWidth: true
        implicitHeight: hero.implicitHeight + CortetsuDesign.spacingSpacious * 2
        radiusValue: CortetsuDesign.radiusLarge
        baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.5)
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.5)

        RowLayout {
            id: hero
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingSpacious
            spacing: CortetsuDesign.spacingSpacious

            CortetsuEvolvingMark {
                Layout.preferredWidth: 88
                Layout.preferredHeight: 88
                phase: "Ascended"
                animated: false
                monochrome: true
                monochromeColor: CortetsuDesign.colorOnPrimaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                CortetsuText {
                    text: "Cortetsu"
                    textSize: CortetsuTypography.displayMediumPx
                    font.family: CortetsuDesign.fontHeading
                    font.weight: CortetsuDesign.headingWeight
                    color: CortetsuDesign.colorOnPrimaryContainer
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Escritorio para Hyprland y Quickshell. Cortés y tetsu, 鉄: tinta, acero, índigo y bermellón.")
                    textSize: CortetsuTypography.bodyLargePx
                    color: CortetsuDesign.colorOnPrimaryContainer
                    wrapMode: Text.WordWrap
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: CortetsuDesign.spacingCompact
                    spacing: 6

                    Repeater {
                        model: [
                            root.known ? qsTr("Revisión %1").arg(root.context.revision) : qsTr("Desde el código fuente"),
                            root.known ? qsTr("Generación %1").arg(root.build.buildId) : "",
                            root.known ? qsTr("Construida %1").arg(root.builtAt) : ""
                        ].filter(Boolean)

                        Rectangle {
                            id: fact
                            required property string modelData
                            implicitWidth: factText.implicitWidth + 16
                            implicitHeight: factText.implicitHeight + 8
                            radius: CortetsuDesign.materialStyle === 2 ? CortetsuDesign.radiusSmall : height / 2
                            color: Qt.alpha(CortetsuDesign.colorSurface, 0.75)

                            CortetsuText {
                                id: factText
                                anchors.centerIn: parent
                                text: fact.modelData
                                textSize: CortetsuTypography.labelMediumPx
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsColumns {
        SettingsGroup {
            title: qsTr("Componentes")
            icon: "memory"
            detail: qsTr("Cada parte, el servicio que la sostiene y su estado ahora")

            Repeater {
                model: root.components

                SettingValueRow {
                    required property var modelData
                    title: modelData.name
                    detail: modelData.detail
                    value: modelData.value || (modelData.ok ? qsTr("Correcto") : "")
                    attention: !modelData.ok
                    // A part that is simply not running is neither fine nor broken.
                    leadingIcon: !modelData.ok ? "error" : modelData.off === true ? "do_not_disturb_on" : "check_circle"
                }
            }
        }

        aside: [
            SettingsGroup {
                title: qsTr("Créditos")
                icon: "favorite"

                SettingValueRow {
                    title: "Quickshell"
                    detail: qsTr("El motor QML en que corre toda la interfaz")
                }
                SettingValueRow {
                    title: "Hyprland"
                    detail: qsTr("El compositor Wayland")
                }
                SettingValueRow {
                    title: "Caelestia Shell"
                    detail: qsTr("Procedencia congelada del staging (v2.4.0)")
                }
                SettingValueRow {
                    title: "end-4 / dots-hyprland"
                    detail: qsTr("Referencia visual de los controles de Ajustes; implementación propia, sin código copiado")
                }
                SettingValueRow {
                    title: "Material Symbols"
                    detail: qsTr("Iconografía de Google, licencia Apache 2.0")
                }
            },

            SettingsGroup {
                title: qsTr("Documentación")
                icon: "menu_book"

                SettingActionRow {
                    objectName: "openRepository"
                    title: qsTr("Repositorio y guías")
                    detail: "github.com/DilanRC/Cortetsu"
                    actionLabel: qsTr("Abrir")
                    actionIcon: "open_in_new"
                    onActivated: Qt.openUrlExternally("https://github.com/DilanRC/Cortetsu")
                }

                SettingNavRow {
                    title: qsTr("Diagnóstico")
                    detail: qsTr("Generación en uso y cómo recuperarse")
                    icon: "monitor_heart"
                    onActivated: SettingsController.select("diagnostics")
                }
            }
        ]
    }
}
