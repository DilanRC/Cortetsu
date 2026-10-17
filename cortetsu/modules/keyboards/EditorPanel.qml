pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "Model.js" as Model

// The selected shortcut or key, and the capture flow acting on it. The panel
// only presents: Content owns the flow state and runs every effect.
Item {
    id: root

    property var binding: null
    property var key: null
    property var keyboards: []
    // The keyboard chosen in the list: what «Solo en…» and «Salvo en…» target.
    property var selectedKeyboard: null
    property var suggestedApps: []
    property var flow: ({ phase: "idle", held: [], chord: "", message: "", preview: null })
    property string targetLabel: qsTr("Todos los teclados")
    property real remaining: 1
    property string lastKeyDetail: ""
    property bool busy: false

    signal editRequested()
    signal confirmRequested()
    signal cancelRequested()
    signal resetRequested()
    signal deleteRequested()
    signal assignRequested(var app)
    signal scopeRequested(string mode)

    readonly property string phase: flow.phase
    readonly property bool inFlow: ["listening", "recovering", "review", "conflict", "applying"].indexOf(phase) >= 0
    readonly property string actionLabel: binding?.label ?? (key ? qsTr("%1 · %2").arg(key.label).arg(key.deviceLabel ?? "") : "")
    property bool deleteArmed: false
    property real deleteRemaining: 0
    property string appQuery: ""
    readonly property var apps: {
        const query = appQuery.trim().toLowerCase();
        if (!query)
            return [];
        return [...DesktopEntries.applications.values]
            .filter(app => app.name.toLowerCase().includes(query) || app.id.toLowerCase().includes(query))
            .sort((a, b) => a.name.localeCompare(b.name))
            .slice(0, 6);
    }

    function armDelete(): void {
        if (deleteArmed) {
            deleteArmed = false;
            deleteCountdown.stop();
            root.deleteRequested();
            return;
        }
        deleteArmed = true;
        deleteCountdown.restart();
    }

    onBindingChanged: { deleteArmed = false; appQuery = ""; }
    onKeyChanged: { deleteArmed = false; appQuery = ""; }

    NumberAnimation {
        id: deleteCountdown
        target: root
        property: "deleteRemaining"
        from: 1
        to: 0
        duration: 4000
        onFinished: root.deleteArmed = false
    }

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusLarge
        outlined: root.phase === "listening"
        outlineColor: CortetsuDesign.colorPrimary
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
    }

    CortetsuStateMessage {
        anchors.centerIn: parent
        width: parent.width - 48
        visible: !root.binding && !root.key && !root.inFlow
        kind: "empty"
        icon: "touch_app"
        title: qsTr("Elige un atajo o una tecla")
        detail: qsTr("Su combinación, de dónde viene y qué se puede cambiar aparecen aquí.")
    }

    Flickable {
        id: scroller
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: !!root.binding || !!root.key || root.inFlow

        Column {
            id: body
            width: scroller.width
            spacing: CortetsuDesign.spacingStandard

            // --- what is selected ------------------------------------------
            CortetsuText {
                width: parent.width
                text: root.phase === "listening" ? qsTr("Grabando nueva combinación")
                    : root.phase === "recovering" ? qsTr("Devolviendo el teclado a Hyprland…")
                    : root.phase === "review" ? qsTr("Revisar el cambio")
                    : root.phase === "conflict" ? qsTr("No se puede aplicar")
                    : root.phase === "applying" ? qsTr("Aplicando y comprobando en Hyprland…")
                    : root.key && !root.binding ? qsTr("Tecla") : qsTr("Atajo")
                textSize: CortetsuTypography.labelMediumPx
                font.weight: Font.DemiBold
                color: root.phase === "conflict" ? CortetsuDesign.colorVermillion
                    : root.inFlow ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOnSurfaceVariant
            }

            CortetsuText {
                width: parent.width
                text: root.actionLabel
                textSize: CortetsuTypography.titleMediumPx
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            CortetsuText {
                width: parent.width
                visible: text.length > 0
                text: qsTr("Teclado: %1").arg(root.targetLabel)
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }

            // --- recording ---------------------------------------------------
            Rectangle {
                visible: root.phase === "listening"
                width: parent.width
                height: 76
                radius: CortetsuDesign.radiusMedium
                color: Qt.alpha(CortetsuDesign.colorSumi, 0.55)
                border.width: 1
                border.color: Qt.alpha(CortetsuDesign.colorPrimary, 0.5)

                KeyCaps {
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - 24)
                    parts: root.flow.held ?? []
                    live: true
                    placeholder: qsTr("Pulsa la combinación")
                }
            }

            CortetsuText {
                visible: root.phase === "listening"
                width: parent.width
                text: root.flow.message?.length > 0 ? root.flow.message
                    : qsTr("Mantén los modificadores y pulsa la tecla. Mientras grabas, ningún atajo de Hyprland se activa.")
                wrapMode: Text.WordWrap
                textSize: CortetsuTypography.labelSmallPx
                color: root.flow.message?.length > 0 ? CortetsuDesign.colorWarning : CortetsuDesign.colorOnSurfaceVariant
            }

            CortetsuText {
                visible: root.phase === "listening" && root.lastKeyDetail.length > 0
                width: parent.width
                text: root.lastKeyDetail
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }

            CortetsuProgressBar {
                visible: root.phase === "listening"
                width: parent.width
                value: root.remaining
                barHeight: 3
                motionDuration: 0
                fillColor: CortetsuDesign.colorPrimary
            }

            // --- review --------------------------------------------------------
            Column {
                visible: root.phase === "review" || root.phase === "conflict"
                width: parent.width
                spacing: CortetsuDesign.spacingCompact

                CortetsuText {
                    text: qsTr("Antes")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
                KeyCaps {
                    width: parent.width
                    parts: Model.parts(root.flow.preview?.before ?? root.binding?.chord ?? "")
                    dim: true
                    placeholder: qsTr("Sin combinación")
                }
                CortetsuText {
                    text: qsTr("Después")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
                KeyCaps {
                    width: parent.width
                    parts: Model.parts(root.flow.preview?.after ?? root.flow.chord)
                }
                CortetsuText {
                    width: parent.width
                    text: root.flow.preview === null ? qsTr("Comprobando conflictos…")
                        : root.phase === "conflict" ? root.flow.message
                        : qsTr("Sin conflictos. Se guarda una copia, se aplica en Hyprland y se comprueba que el atajo nuevo funciona; si no, se restaura el anterior.")
                    wrapMode: Text.WordWrap
                    textSize: CortetsuTypography.labelSmallPx
                    color: root.phase === "conflict" ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
                    topPadding: CortetsuDesign.spacingUnit
                }
            }

            Row {
                visible: root.inFlow && root.phase !== "recovering" && root.phase !== "applying"
                spacing: CortetsuDesign.spacingCompact

                CortetsuButton {
                    objectName: "confirmApply"
                    visible: root.phase === "review"
                    disabled: !(root.flow.preview?.valid ?? false) || root.busy
                    active: true
                    icon: "check"
                    label: qsTr("Confirmar y aplicar")
                    onClicked: root.confirmRequested()
                }
                CortetsuButton {
                    objectName: "repeatCapture"
                    visible: (root.phase === "review" || root.phase === "conflict") && !!root.binding
                    icon: "replay"
                    label: qsTr("Repetir")
                    onClicked: root.editRequested()
                }
                CortetsuButton {
                    objectName: "cancelCapture"
                    icon: "close"
                    label: qsTr("Cancelar")
                    tooltipText: qsTr("Esc")
                    onClicked: root.cancelRequested()
                }
            }

            // --- result of the last change --------------------------------------
            Rectangle {
                visible: ["verified", "failed", "cancelled"].indexOf(root.phase) >= 0 && (root.flow.message ?? "").length > 0
                width: parent.width
                height: resultText.implicitHeight + CortetsuDesign.spacingStandard * 2
                radius: CortetsuDesign.radiusMedium
                color: Qt.alpha(root.phase === "failed" ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary, 0.12)

                Row {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingStandard
                    spacing: CortetsuDesign.spacingCompact
                    CortetsuIcon {
                        text: root.phase === "verified" ? "verified" : root.phase === "failed" ? "error" : "undo"
                        color: root.phase === "failed" ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
                        iconSize: CortetsuTypography.iconMediumPx
                    }
                    CortetsuText {
                        id: resultText
                        width: parent.width - 30
                        text: root.flow.message ?? ""
                        wrapMode: Text.WordWrap
                        textSize: CortetsuTypography.labelSmallPx
                    }
                }
            }

            // --- shortcut details -------------------------------------------------
            Column {
                visible: !!root.binding && !root.inFlow
                width: parent.width
                spacing: CortetsuDesign.spacingCompact

                KeyCaps {
                    width: parent.width
                    parts: Model.parts(root.binding?.chord ?? "")
                    placeholder: qsTr("Sin combinación")
                }

                FactLine { label: qsTr("Acción"); value: root.binding?.description ?? "" }
                FactLine {
                    label: qsTr("Origen")
                    value: ({ default: qsTr("Cortetsu (predeterminado)"), edited: qsTr("Cambiado por ti"), user: qsTr("hypr-user.lua"),
                              fixed: qsTr("Fijo en Cortetsu") })[root.binding?.origin ?? ""] ?? ""
                }
                FactLine { label: qsTr("Ámbito"); value: Model.scopeText(root.binding?.devices, root.keyboards) }
                FactLine {
                    label: qsTr("Conflicto")
                    value: (root.binding?.conflicts ?? []).join(", ")
                    warning: true
                }
                FactLine { label: qsTr("Nota"); value: root.binding?.note ?? "" }

                Row {
                    spacing: CortetsuDesign.spacingCompact
                    topPadding: CortetsuDesign.spacingCompact

                    CortetsuButton {
                        objectName: "editBinding"
                        visible: root.binding?.editable ?? false
                        disabled: root.busy
                        active: true
                        icon: "keyboard"
                        label: qsTr("Editar")
                        tooltipText: qsTr("Grabar una combinación nueva")
                        onClicked: root.editRequested()
                    }
                    CortetsuButton {
                        objectName: "resetBinding"
                        visible: root.binding?.resettable ?? false
                        disabled: root.busy
                        icon: "restart_alt"
                        label: qsTr("Restablecer")
                        onClicked: root.resetRequested()
                    }
                    CortetsuButton {
                        objectName: "deleteBinding"
                        visible: root.binding?.deletable ?? false
                        disabled: root.busy
                        danger: root.deleteArmed
                        icon: "delete"
                        label: root.deleteArmed ? qsTr("Confirmar (%1 s)").arg(Math.ceil(root.deleteRemaining * 4)) : qsTr("Eliminar")
                        onClicked: root.armDelete()
                    }
                }
            }

            // --- which keyboards ----------------------------------------------------
            Column {
                visible: (root.binding?.scopable ?? false) && !root.inFlow
                width: parent.width
                spacing: CortetsuDesign.spacingCompact

                CortetsuText {
                    width: parent.width
                    topPadding: CortetsuDesign.spacingCompact
                    text: qsTr("Teclados que lo usan")
                    textSize: CortetsuTypography.labelMediumPx
                    font.weight: Font.DemiBold
                }

                Flow {
                    width: parent.width
                    spacing: CortetsuDesign.spacingCompact

                    Repeater {
                        model: [
                            { mode: "all", label: qsTr("Todos"), icon: "keyboard" },
                            { mode: "only", label: qsTr("Solo este"), icon: "filter_1" },
                            { mode: "except", label: qsTr("Todos salvo este"), icon: "block" }
                        ]
                        delegate: CortetsuButton {
                            id: scopeButton
                            required property var modelData
                            readonly property var args: Model.scopeArgs(root.binding, root.selectedKeyboard, scopeButton.modelData.mode)
                            readonly property bool current:
                                Model.scopeIs(root.binding?.devices, scopeButton.modelData.mode, Model.hyprlandNames(root.selectedKeyboard))
                            objectName: "scope-" + scopeButton.modelData.mode
                            compact: true
                            active: scopeButton.current
                            disabled: root.busy || scopeButton.current || scopeButton.args === null
                            icon: scopeButton.modelData.icon
                            label: scopeButton.modelData.label
                            onClicked: root.scopeRequested(scopeButton.modelData.mode)
                        }
                    }
                }

                CortetsuText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    text: !root.selectedKeyboard ? qsTr("Elige un teclado a la izquierda para limitarlo a él.")
                        : !root.selectedKeyboard.hyprlandLinked ? qsTr("Hyprland no distingue %1 de otro igual; desconecta uno para elegirlo.").arg(root.selectedKeyboard.label)
                        : qsTr("«Este» es %1. El cambio se aplica y se comprueba en Hyprland.").arg(root.selectedKeyboard.label)
                }
            }

            // --- key details --------------------------------------------------------
            Column {
                visible: !!root.key && !root.binding && !root.inFlow
                width: parent.width
                spacing: CortetsuDesign.spacingCompact

                FactLine { label: qsTr("Teclado"); value: root.key?.deviceLabel ?? "" }
                FactLine { label: qsTr("Código Linux"); value: root.key ? `${root.key.name} (${root.key.code})` : "" }
                FactLine { label: qsTr("Keysym"); value: root.key?.keysym ?? qsTr("Ninguno en esta distribución") }
                FactLine { label: qsTr("Evidencia"); value: Model.confidenceLabel(root.key?.confidence ?? "") }
                FactLine { label: qsTr("Estado"); value: (root.key?.states ?? []).map(s => Model.stateLabel(s)).join(" · ") }
                FactLine { label: qsTr("Función actual"); value: root.key ? Model.currentFunction(root.key) : "" }
                FactLine { label: qsTr("Nota"); value: root.key?.note ?? "" }
                FactLine {
                    label: qsTr("Sugerencia")
                    value: root.key?.suggestion ? qsTr("%1, por su keysym %2").arg(root.key.suggestion.label).arg(root.key.keysym) : ""
                }

                Repeater {
                    model: root.suggestedApps
                    delegate: CortetsuListRow {
                        id: suggestedRow
                        required property DesktopEntry modelData
                        width: parent.width
                        compact: false
                        title: qsTr("Proponer %1").arg(suggestedRow.modelData.name)
                        subtitle: qsTr("Se revisa antes de aplicar")
                        disabled: root.busy
                        onClicked: root.assignRequested(suggestedRow.modelData)
                    }
                }

                CortetsuText {
                    visible: (root.key?.states ?? []).indexOf("CANDIDATE") >= 0
                    width: parent.width
                    topPadding: CortetsuDesign.spacingStandard
                    text: qsTr("Asignarla a una aplicación")
                    textSize: CortetsuTypography.labelMediumPx
                    font.weight: Font.DemiBold
                }

                CortetsuSearchBar {
                    visible: (root.key?.states ?? []).indexOf("CANDIDATE") >= 0
                    width: parent.width
                    compact: true
                    placeholderText: qsTr("Buscar aplicaciones instaladas")
                    text: root.appQuery
                    onTextChanged: root.appQuery = text
                }

                Repeater {
                    model: root.apps
                    delegate: CortetsuListRow {
                        id: appRow
                        required property DesktopEntry modelData
                        width: parent.width
                        compact: false
                        title: appRow.modelData.name
                        subtitle: appRow.modelData.execString
                        disabled: root.busy
                        onClicked: root.assignRequested(appRow.modelData)
                    }
                }
            }
        }
    }

    component FactLine: Row {
        id: fact
        property string label
        property string value
        property bool warning: false
        visible: value.length > 0
        width: parent ? parent.width : 0
        spacing: CortetsuDesign.spacingCompact

        CortetsuText {
            width: 110
            text: fact.label
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }
        CortetsuText {
            width: fact.width - 110 - fact.spacing
            text: fact.value
            wrapMode: Text.WordWrap
            textSize: CortetsuTypography.labelSmallPx
            color: fact.warning ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurface
        }
    }
}
