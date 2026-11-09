pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../services"
import "../../../theme"
import "../.."
import "../controls"
import "../../CortetsuTypography.js" as CortetsuTypography
import "DisplayLayout.js" as Arrange

// Sistema → Pantalla. The arrangement on top, the selected output's
// properties and colour below it, and the safe apply flow beside them:
// validate (dry run) → preview for 15 s → keep or revert → save. Controls
// appear only for what the probe reports; unknown capabilities stay hidden.
ColumnLayout {
    id: root

    required property var context

    readonly property var selected: model.selected
    readonly property var live: model.selectedLive
    readonly property var modes: live?.available_modes ?? []
    readonly property var mode: Arrange.parseMode(selected?.mode)
    readonly property bool nvidiaOutput: String(live?.gpu_vendor ?? "").toUpperCase() === "NVIDIA"
    readonly property bool vibrance: Nvibrant.available && Nvibrant.connector === (selected?.name ?? "")
    readonly property bool calibrating: DisplayCalibration.state === "applying"
    // Set by previewSelected(): the plan's answer decides whether to preview.
    property bool pendingPreview: false

    function capability(value): string {
        if (value === true || Number(value) === 1) return qsTr("Sí");
        if (value === false || Number(value) === 0) return qsTr("No");
        return qsTr("Sin datos");
    }

    // Validate first; preview only a proposal the planner accepted.
    function previewSelected(): void {
        pendingPreview = true;
        model.runPlan();
    }

    spacing: CortetsuDesign.spacingSection

    DisplayModel {
        id: model
        // Logic only: invisible items take no place (nor spacing) in the layout.
        visible: false
        onPlanFinished: ok => {
            if (root.pendingPreview && ok)
                transaction.preview();
            root.pendingPreview = false;
        }
    }

    DisplayTransaction {
        id: transaction
        // Logic only: invisible items take no place (nor spacing) in the layout.
        visible: false
        candidateOutputs: model.candidateOutputs
        // What was kept or restored is the new live state.
        onPhaseChanged: {
            if (phase === "confirmed")
                model.refresh(false);
            else if (phase === "reverted" || phase === "saved")
                model.refresh(true);
        }
    }

    DisplayPresetStore {
        id: presets
        // Logic only: invisible items take no place (nor spacing) in the layout.
        visible: false
        onLoaded: (outputs, name) => {
            if (outputs.length)
                model.replace(outputs.map(item => Object.assign({}, item)), qsTr("Cargada «%1». Previsualízala para aplicarla.").arg(name));
        }
    }

    SettingsGroup {
        objectName: "displayArrangementGroup"
        title: qsTr("Disposición")
        icon: "monitor"
        detail: model.candidateOutputs.length > 1
            ? qsTr("%1 pantallas · arrastra para colocarlas").arg(model.candidateOutputs.length)
            : model.candidateOutputs.length === 1 ? qsTr("1 pantalla") : ""

        DisplayArrangement {
            objectName: "displayArrangement"
            Layout.fillWidth: true
            Layout.margins: CortetsuDesign.spacingStandard
            model: model
        }

        SettingChoiceChips {
            objectName: "displaySelect"
            visible: model.candidateOutputs.length > 1
            title: qsTr("Pantalla que se edita")
            options: model.candidateOutputs.map((output, index) => ({
                value: index,
                label: `${index + 1} · ${output.name}${output.enabled ? "" : qsTr(" (apagada)")}`,
                name: "displaySelect-" + output.name
            }))
            current: model.selectedIndex
            onChosen: value => model.selectedIndex = value
        }

        SettingChoiceChips {
            objectName: "displayPreset"
            visible: model.candidateOutputs.length > 1
            title: qsTr("Distribución rápida")
            options: [
                { value: "extend", label: qsTr("Extender"), icon: "splitscreen_left" },
                { value: "laptop", label: qsTr("Solo portátil"), icon: "laptop" },
                { value: "external", label: qsTr("Solo externa"), icon: "tv" }
            ]
            current: ""
            detail: model.message
            onChosen: value => model.preset(value)
        }

        SettingValueRow {
            objectName: "displayMessage"
            visible: model.candidateOutputs.length <= 1 && model.message.length > 0
            title: qsTr("Aviso")
            detail: model.message
        }
    }

    SettingsColumns {
        SettingsGroup {
            objectName: "displayProperties"
            visible: !!root.selected
            title: root.selected ? qsTr("Pantalla %1 · %2").arg(model.selectedIndex + 1).arg(root.selected.name) : ""
            icon: root.selected && Arrange.internal(root.selected) ? "laptop" : "monitor"
            detail: root.live?.description ?? ""

            SettingToggleRow {
                objectName: "displayEnabled"
                visible: model.candidateOutputs.length > 1
                title: qsTr("Usar esta pantalla")
                detail: !(root.selected?.enabled ?? true) ? qsTr("Apagada: no muestra escritorio")
                    : model.enabledCount <= 1 ? qsTr("Es la única activa: no se puede apagar")
                    : qsTr("Encendida")
                checked: root.selected?.enabled ?? true
                disabled: model.enabledCount <= 1 && (root.selected?.enabled ?? true)
                onToggled: value => model.setEnabled(value)
            }

            SettingChoiceChips {
                objectName: "displayResolution"
                title: qsTr("Resolución")
                options: Arrange.resolutions(root.modes).map(size => ({
                    value: size, label: size.replace("x", " × "), name: "resolution-" + size
                }))
                current: `${root.mode.width}x${root.mode.height}`
                disabled: !(root.selected?.enabled ?? true)
                onChosen: value => model.setResolution(value)
            }

            SettingChoiceChips {
                objectName: "displayRefresh"
                title: qsTr("Frecuencia de actualización")
                options: Arrange.rates(root.modes, `${root.mode.width}x${root.mode.height}`).map(rate => ({
                    value: rate, label: qsTr("%1 Hz").arg(Math.round(rate * 100) / 100), name: "refresh-" + rate
                }))
                current: root.mode.refresh
                disabled: !(root.selected?.enabled ?? true)
                onChosen: value => model.setRefresh(value)
            }

            SettingChoiceChips {
                objectName: "displayScale"
                title: qsTr("Escala")
                options: [1, 1.25, 1.5, 1.75, 2].map(scale => ({ value: scale, label: `${scale * 100} %`, name: "scale-" + scale }))
                current: Number(root.selected?.scale ?? 1)
                disabled: !(root.selected?.enabled ?? true)
                onChosen: value => model.update("scale", value)
            }

            SettingChoiceChips {
                objectName: "displayRotation"
                title: qsTr("Orientación")
                options: [
                    { value: 0, label: qsTr("Horizontal") },
                    { value: 1, label: qsTr("Vertical") },
                    { value: 2, label: qsTr("Horizontal invertida") },
                    { value: 3, label: qsTr("Vertical invertida") }
                ]
                current: Number(root.selected?.transform ?? 0)
                disabled: !(root.selected?.enabled ?? true)
                onChosen: value => model.update("transform", value)
            }

            // Shown only when the output reports variable refresh support.
            SettingToggleRow {
                objectName: "displayVrr"
                visible: root.live?.vrr_capable === true
                title: qsTr("Frecuencia variable (VRR)")
                detail: qsTr("Ajusta la frecuencia a los fotogramas en pantalla completa")
                checked: Number(root.selected?.vrr ?? (root.live?.vrr ? 1 : 0)) > 0
                onToggled: value => model.update("vrr", value ? 1 : 0)
            }
        }

        SettingsGroup {
            objectName: "displayColour"
            title: qsTr("Brillo y color")
            icon: "brightness_6"
            detail: qsTr("Se aplican al momento, sin vista previa")

            SettingSliderRow {
                objectName: "brightness"
                visible: root.context.brightnessValue >= 0
                title: root.context.screen?.name ? qsTr("Brillo · %1").arg(root.context.screen.name) : qsTr("Brillo")
                valueText: qsTr("%1 %").arg(Math.round(root.context.brightnessValue * 100))
                value: root.context.brightnessValue
                onMoved: next => root.context.brightnessMonitor?.setBrightness(next)
            }

            SettingValueRow {
                objectName: "brightnessUnavailable"
                visible: root.context.brightnessValue < 0
                title: root.context.screen?.name ? qsTr("Brillo · %1").arg(root.context.screen.name) : qsTr("Brillo")
                detail: qsTr("Esta pantalla no ofrece control de brillo al sistema")
                value: qsTr("No disponible")
            }

            // nVibrant drives NVIDIA's Digital Vibrance on the selected output.
            SettingSliderRow {
                objectName: "displayVibrance"
                visible: root.vibrance
                title: qsTr("Saturación (NVIDIA) · %1").arg(Nvibrant.connector)
                valueText: Nvibrant.busy ? qsTr("Aplicando %1").arg(Nvibrant.requested)
                    : Nvibrant.known && Nvibrant.requested === Nvibrant.value ? qsTr("%1 · confirmado").arg(Nvibrant.value)
                    : Nvibrant.desiredKnown ? qsTr("%1 guardado · sin confirmar en este arranque").arg(Nvibrant.desired)
                    : qsTr("Sin confirmar")
                from: Nvibrant.minimum
                to: Nvibrant.maximum
                step: 1
                value: Nvibrant.requested
                status: Nvibrant.error.length > 0 ? "error" : ""
                statusText: Nvibrant.error
                onMoved: next => Nvibrant.setValue(next)
            }

            SettingValueRow {
                objectName: "displayVibranceUnsupported"
                visible: !!root.selected && !root.vibrance
                title: qsTr("Saturación")
                detail: root.nvidiaOutput
                    ? qsTr("nVibrant no encuentra esta salida NVIDIA conectada")
                    : qsTr("Solo las salidas de la GPU NVIDIA la admiten (nVibrant). Esta la controla %1.").arg(root.live?.gpu_vendor ?? qsTr("otra GPU"))
                value: qsTr("No compatible")
            }

            SettingToggleRow {
                objectName: "colourFilter"
                title: qsTr("Filtro de color")
                detail: CortetsuConfig.colorCalibrationEnabled
                    ? qsTr("Activo en todas las pantallas: %1 K, gamma %2 %").arg(CortetsuConfig.colorTemperature).arg(CortetsuConfig.colorGamma)
                    : qsTr("Apagado: colores nativos (hyprsunset, todas las pantallas)")
                checked: CortetsuConfig.colorCalibrationEnabled
                status: root.calibrating ? "busy" : DisplayCalibration.state === "failed" ? "error" : ""
                statusText: root.calibrating ? qsTr("Aplicando…") : DisplayCalibration.error
                onToggled: value => DisplayCalibration.setEnabled(value)
            }

            SettingSliderRow {
                visible: CortetsuConfig.colorCalibrationEnabled
                title: qsTr("Temperatura de color")
                valueText: qsTr("%1 K").arg(CortetsuConfig.colorTemperature)
                from: 2500
                to: 6500
                step: 100
                value: CortetsuConfig.colorTemperature
                onMoved: next => DisplayCalibration.setTemperature(next)
            }

            SettingSliderRow {
                visible: CortetsuConfig.colorCalibrationEnabled
                title: qsTr("Gamma")
                valueText: qsTr("%1 %").arg(CortetsuConfig.colorGamma)
                from: 50
                to: 150
                step: 1
                value: CortetsuConfig.colorGamma
                onMoved: next => DisplayCalibration.setGamma(next)
            }
        }

        aside: [
            SettingsGroup {
                objectName: "displayApply"
                title: qsTr("Aplicar cambios")
                icon: "fact_check"
                detail: qsTr("Se prueban %1 s y se deshacen solos si no confirmas").arg(transaction.previewSeconds)

                SettingValueRow {
                    objectName: "displayApplyState"
                    title: transaction.active ? qsTr("Vista previa en curso")
                        : model.planning ? qsTr("Validando la propuesta…")
                        : model.planState === "blocked" || model.planState === "error" ? qsTr("La propuesta no es válida")
                        : transaction.phase === "confirmed" ? qsTr("Conservada")
                        : transaction.phase === "saved" ? qsTr("Guardada")
                        : model.changed ? qsTr("Hay cambios sin aplicar") : qsTr("Sin cambios")
                    detail: transaction.active ? qsTr("Se revierte en %1 s si no la conservas").arg(Math.ceil(transaction.remaining))
                        : model.planState === "blocked" || model.planState === "error"
                            ? ((model.planResult?.errors ?? []).join(" · ") || qsTr("El planificador la rechazó"))
                        : transaction.message
                    attention: transaction.active || model.planState === "blocked" || transaction.phase === "failed"
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: CortetsuDesign.spacingStandard
                    spacing: CortetsuDesign.spacingCompact

                    CortetsuButton {
                        objectName: "displayPreview"
                        visible: !transaction.active
                        compact: true
                        icon: "visibility"
                        label: model.planning ? qsTr("Validando…") : qsTr("Previsualizar")
                        active: model.changed
                        disabled: !model.changed || model.planning || transaction.working
                        onClicked: root.previewSelected()
                    }
                    CortetsuButton {
                        objectName: "displayKeep"
                        visible: transaction.active
                        compact: true
                        icon: "check"
                        label: qsTr("Conservar")
                        active: true
                        disabled: transaction.working
                        onClicked: transaction.confirm()
                    }
                    CortetsuButton {
                        objectName: "displayRevert"
                        visible: transaction.active
                        compact: true
                        danger: true
                        icon: "undo"
                        label: qsTr("Revertir")
                        disabled: transaction.working
                        onClicked: transaction.revert()
                    }
                    CortetsuButton {
                        objectName: "displaySave"
                        visible: transaction.canSave
                        compact: true
                        icon: "save"
                        label: qsTr("Guardar")
                        active: true
                        disabled: transaction.working
                        onClicked: transaction.save()
                    }
                    Item { Layout.fillWidth: true }
                    CortetsuButton {
                        objectName: "displayReset"
                        visible: model.changed && !transaction.active
                        compact: true
                        icon: "restart_alt"
                        label: qsTr("Descartar")
                        disabled: transaction.working
                        onClicked: model.reset()
                    }
                }
            },

            SettingsGroup {
                objectName: "displayDiagnostics"
                visible: !!root.selected
                title: qsTr("Diagnóstico")
                icon: "info"
                detail: qsTr("Lo que informan Hyprland y el kernel")
                collapsible: true

                SettingValueRow { title: qsTr("GPU"); value: root.live?.gpu_vendor ?? qsTr("Sin datos") }
                SettingValueRow { title: qsTr("Conector DRM"); value: root.live?.drm_connector ?? qsTr("Sin datos") }
                SettingValueRow { title: qsTr("Modo actual"); value: root.live?.width ? qsTr("%1 × %2 a %3 Hz").arg(root.live.width).arg(root.live.height).arg(Number(root.live.refresh_hz ?? 0).toFixed(2)) : qsTr("Sin datos") }
                SettingValueRow { title: qsTr("Formato de color"); value: root.live?.current_format ?? qsTr("Sin datos") }
                SettingValueRow { title: qsTr("VRR / HDR / gama amplia"); value: `${root.capability(root.live?.vrr_capable)} / ${root.capability(root.live?.hdr_capable)} / ${root.capability(root.live?.wide_color_capable)}` }
                SettingValueRow { title: qsTr("Driver NVIDIA"); visible: root.nvidiaOutput && Nvibrant.driver.length > 0; value: Nvibrant.driver }
            }
        ]
    }

    SettingsGroup {
        objectName: "displayPresets"
        title: qsTr("Distribuciones guardadas")
        icon: "bookmarks"
        detail: presets.state === "error" ? presets.message
            : presets.presets.length ? qsTr("Cargar una solo rellena la propuesta") : qsTr("Todavía no hay ninguna")

        Repeater {
            model: presets.presets

            delegate: SettingActionRow {
                required property var modelData
                title: modelData?.name ?? ""
                readonly property int count: (modelData?.candidate?.outputs ?? modelData?.outputs ?? []).length
                detail: count === 1 ? qsTr("1 pantalla") : count > 1 ? qsTr("%1 pantallas").arg(count) : ""
                actionLabel: qsTr("Cargar")
                actionIcon: "download"
                actionDisabled: presets.state === "busy" || transaction.active
                onActivated: presets.load(modelData?.name ?? "")
            }
        }

        SettingTextRow {
            objectName: "displayPresetName"
            title: qsTr("Guardar la propuesta actual")
            detail: qsTr("Escribe un nombre y pulsa Intro")
            placeholderText: qsTr("Escritorio, presentación…")
            onCommitted: value => {
                if (value.trim().length)
                    presets.save(value.trim(), model.candidateOutputs);
            }
        }
    }
}
