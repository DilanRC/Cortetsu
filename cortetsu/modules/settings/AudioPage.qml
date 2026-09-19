pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../services"
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import "../CortetsuSearchBar.qml"

// PipeWire is a workbench: the active route stays visible while the list and
// inspector expose outputs, inputs and per-application streams.
Item {
    id: root

    property string mode: "outputs"
    property string query: ""
    property int selectedIndex: -1

    readonly property bool compactLayout: width < 760
    readonly property var defaultNode: root.mode === "outputs" ? CortetsuAudio.sink : CortetsuAudio.source
    readonly property var nodes: root.mode === "outputs" ? CortetsuAudio.sinks : CortetsuAudio.sources
    readonly property var filteredNodes: {
        const needle = root.query.trim().toLowerCase();
        return root.nodes.filter(node => {
            const name = String(node?.description ?? node?.name ?? "").toLowerCase();
            return !needle || name.includes(needle);
        });
    }
    readonly property var selectedNode: root.selectedIndex >= 0
        ? root.filteredNodes[root.selectedIndex] ?? null
        : root.defaultNode
    readonly property bool defaultMuted: !!root.defaultNode?.audio?.muted
    readonly property real defaultVolume: root.defaultNode?.audio?.volume ?? 0
    readonly property int volumePercent: Math.round(root.defaultVolume * 100)

    implicitHeight: body.implicitHeight

    function nodeName(node): string {
        return node?.description ?? node?.name ?? qsTr("Dispositivo desconocido");
    }

    function nodeStatus(node): string {
        if (!node)
            return qsTr("No disponible");
        return node.ready === false ? qsTr("Preparando…") : qsTr("Disponible");
    }

    function nodeVolume(node): real {
        return Math.max(0, Math.min(1, Number(node?.audio?.volume ?? 0)));
    }

    function setNodeVolume(value): void {
        if (!root.selectedNode?.audio)
            return;
        const nextValue = Math.max(0, Math.min(CortetsuConfig.maxVolume, value));
        if (root.selectedNode?.id === root.defaultNode?.id) {
            if (root.mode === "outputs")
                CortetsuAudio.setVolume(nextValue);
            else
                CortetsuAudio.setSourceVolume(nextValue);
            return;
        }
        root.selectedNode.audio.muted = false;
        root.selectedNode.audio.volume = nextValue;
    }

    function toggleNodeMute(): void {
        if (root.selectedNode?.audio)
            root.selectedNode.audio.muted = !root.selectedNode.audio.muted;
    }

    function useSelectedNode(): void {
        if (!root.selectedNode)
            return;
        if (root.mode === "outputs")
            CortetsuAudio.setAudioSink(root.selectedNode);
        else
            CortetsuAudio.setAudioSource(root.selectedNode);
    }

    function selectNode(index): void {
        root.selectedIndex = index;
    }

    component DetailRow: RowLayout {
        id: detailRow

        required property string label
        required property string value
        Layout.fillWidth: true
        spacing: CortetsuDesign.spacingStandard

        CortetsuText {
            Layout.fillWidth: true
            text: detailRow.label
            textSize: CortetsuTypography.bodySmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }

        CortetsuText {
            Layout.minimumWidth: 150
            text: detailRow.value
            textSize: CortetsuTypography.bodySmallPx
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    ColumnLayout {
        id: body
        width: parent.width
        spacing: CortetsuDesign.spacingStandard

        CortetsuSectionHeader {
            Layout.fillWidth: true
            title: qsTr("Audio")
            detail: qsTr("Salidas, entradas y streams de PipeWire en vivo")
        }

        CortetsuSurface {
            Layout.fillWidth: true
            implicitHeight: 116
            radiusValue: CortetsuDesign.radiusMedium
            baseColor: root.defaultNode
                ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.58)
                : Qt.alpha(CortetsuDesign.colorWarning, 0.10)
            outlineColor: root.defaultNode
                ? Qt.alpha(CortetsuDesign.colorPrimary, 0.42)
                : Qt.alpha(CortetsuDesign.colorWarning, 0.42)
            outlined: true

            RowLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                CortetsuSurface {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    radiusValue: CortetsuDesign.radiusMedium
                    baseColor: root.defaultMuted
                        ? Qt.alpha(CortetsuDesign.colorVermillion, 0.18)
                        : Qt.alpha(CortetsuDesign.colorPrimary, 0.20)
                    outlined: false

                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: root.defaultMuted
                            ? "volume_off"
                            : root.mode === "outputs" ? "volume_up" : "mic"
                        iconSize: CortetsuTypography.iconLargePx
                        color: root.defaultMuted
                            ? CortetsuDesign.colorVermillion
                            : CortetsuDesign.colorPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.defaultNode
                            ? (root.mode === "outputs"
                                ? qsTr("Salida activa · %1").arg(root.nodeName(root.defaultNode))
                                : qsTr("Entrada activa · %1").arg(root.nodeName(root.defaultNode)))
                            : (root.mode === "outputs" ? qsTr("No hay salida activa") : qsTr("No hay entrada activa"))
                        textSize: CortetsuTypography.titleMediumPx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.defaultMuted
                            ? qsTr("Silenciado")
                            : qsTr("%1% · %2 salidas · %3 entradas · %4 streams")
                                .arg(root.volumePercent)
                                .arg(CortetsuAudio.sinks.length)
                                .arg(CortetsuAudio.sources.length)
                                .arg(CortetsuAudio.streams.length)
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }

                    CortetsuProgressBar {
                        Layout.fillWidth: true
                        value: root.defaultVolume
                        fillColor: root.defaultMuted
                            ? CortetsuDesign.colorVermillion
                            : CortetsuDesign.colorPrimary
                        barHeight: 5
                    }
                }

                CortetsuButton {
                    compact: true
                    icon: root.defaultMuted ? "volume_off" : "volume_up"
                    label: root.defaultMuted ? qsTr("Activar") : qsTr("Silenciar")
                    disabled: !root.defaultNode?.audio
                    onClicked: {
                        if (root.defaultNode?.audio)
                            root.defaultNode.audio.muted = !root.defaultNode.audio.muted;
                    }
                }
            }
        }

        Flow {
            id: workbench
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingSection
            property bool compact: root.compactLayout
            readonly property real workbenchHeight: compact
                ? listPanel.height + detailPanel.height + spacing
                : Math.max(listPanel.height, detailPanel.height)
            Layout.preferredHeight: workbench.workbenchHeight
            height: workbench.workbenchHeight

            Item {
                id: listPanel
                width: workbench.compact
                    ? workbench.width
                    : Math.min(390, Math.max(340, workbench.width * 0.36))
                height: workbench.compact ? 440 : 560

                CortetsuSurface {
                    anchors.fill: parent
                    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.66)
                    outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)
                    outlined: true
                    radiusValue: CortetsuDesign.radiusMedium
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingCompact
                    spacing: CortetsuDesign.spacingCompact

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: CortetsuDesign.spacingCompact

                        CortetsuButton {
                            Layout.fillWidth: true
                            compact: true
                            icon: "speaker"
                            label: qsTr("Salidas")
                            active: root.mode === "outputs"
                            onClicked: { root.mode = "outputs"; root.selectedIndex = -1; root.query = ""; }
                        }

                        CortetsuButton {
                            Layout.fillWidth: true
                            compact: true
                            icon: "mic"
                            label: qsTr("Entradas")
                            active: root.mode === "inputs"
                            onClicked: { root.mode = "inputs"; root.selectedIndex = -1; root.query = ""; }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuText {
                            Layout.fillWidth: true
                            text: root.mode === "outputs"
                                ? qsTr("%1 salidas disponibles").arg(root.filteredNodes.length)
                                : qsTr("%1 entradas disponibles").arg(root.filteredNodes.length)
                            textSize: CortetsuTypography.labelSmallPx
                            color: CortetsuDesign.colorOnSurfaceVariant
                        }
                        CortetsuText {
                            text: root.defaultNode ? qsTr("Conectado") : qsTr("Sin ruta")
                            textSize: CortetsuTypography.labelSmallPx
                            color: root.defaultNode ? CortetsuDesign.colorSuccess : CortetsuDesign.colorWarning
                        }
                    }

                    CortetsuSearchBar {
                        Layout.fillWidth: true
                        compact: true
                        placeholderText: root.mode === "outputs"
                            ? qsTr("Filtrar salidas…")
                            : qsTr("Filtrar entradas…")
                        onTextChanged: root.query = text
                    }

                    ListView {
                        id: nodeList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 3
                        model: root.filteredNodes
                        currentIndex: root.selectedIndex
                        onCurrentIndexChanged: if (currentIndex >= 0) root.selectedIndex = currentIndex

                        delegate: CortetsuListRow {
                            id: nodeDelegate
                            required property var modelData
                            required property int index
                            width: nodeList.width
                            title: root.nodeName(nodeDelegate.modelData)
                            subtitle: root.nodeStatus(nodeDelegate.modelData)
                            icon: root.mode === "outputs" ? "speaker" : "mic"
                            selected: nodeDelegate.index === root.selectedIndex
                                || (root.selectedIndex < 0 && nodeDelegate.modelData?.id === root.defaultNode?.id)
                            onClicked: root.selectNode(nodeDelegate.index)
                        }

                        CortetsuStateMessage {
                            anchors.centerIn: parent
                            visible: nodeList.count === 0
                            kind: root.query.length > 0 ? "empty" : "error"
                            icon: root.mode === "outputs" ? "speaker" : "mic"
                            title: root.query.length > 0
                                ? qsTr("No hay coincidencias")
                                : qsTr("No hay dispositivos disponibles")
                            detail: qsTr("PipeWire no expone una ruta lista en este momento")
                        }
                    }
                }
            }

            Item {
                id: detailPanel
                width: workbench.compact
                    ? workbench.width
                    : Math.max(0, workbench.width - listPanel.width - workbench.spacing)
                height: workbench.compact ? 520 : 560

                CortetsuSurface {
                    anchors.fill: parent
                    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.56)
                    outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)
                    outlined: true
                    radiusValue: CortetsuDesign.radiusMedium
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingStandard
                    spacing: CortetsuDesign.spacingStandard
                    visible: !!root.selectedNode

                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuSurface {
                            Layout.preferredWidth: 52
                            Layout.preferredHeight: 52
                            radiusValue: CortetsuDesign.radiusMedium
                            baseColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.16)
                            outlined: false
                            CortetsuIcon {
                                anchors.centerIn: parent
                                text: root.mode === "outputs" ? "speaker" : "mic"
                                iconSize: CortetsuTypography.iconLargePx
                                color: CortetsuDesign.colorPrimary
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            CortetsuText {
                                Layout.fillWidth: true
                                text: root.nodeName(root.selectedNode)
                                textSize: CortetsuTypography.titleMediumPx
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            CortetsuText {
                                Layout.fillWidth: true
                                text: root.selectedNode?.id ?? qsTr("Identificador no disponible")
                                textSize: CortetsuTypography.labelSmallPx
                                color: CortetsuDesign.colorOnSurfaceVariant
                                elide: Text.ElideMiddle
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuText {
                            Layout.fillWidth: true
                            text: root.selectedNode === root.defaultNode
                                ? qsTr("Ruta predeterminada")
                                : qsTr("Ruta disponible")
                            textSize: CortetsuTypography.bodySmallPx
                            color: root.selectedNode === root.defaultNode
                                ? CortetsuDesign.colorSuccess
                                : CortetsuDesign.colorOnSurfaceVariant
                        }
                        CortetsuButton {
                            compact: true
                            icon: "check_circle"
                            label: qsTr("En uso")
                            active: true
                            visible: root.selectedNode?.id === root.defaultNode?.id
                            disabled: true
                        }
                        CortetsuButton {
                            compact: true
                            icon: "play_arrow"
                            label: root.mode === "outputs" ? qsTr("Usar salida") : qsTr("Usar entrada")
                            visible: root.selectedNode?.id !== root.defaultNode?.id
                            onClicked: root.useSelectedNode()
                        }
                        CortetsuButton {
                            compact: true
                            icon: root.selectedNode?.audio?.muted ? "volume_off" : "volume_up"
                            label: root.selectedNode?.audio?.muted ? qsTr("Activar") : qsTr("Silenciar")
                            disabled: !root.selectedNode?.audio
                            onClicked: root.toggleNodeMute()
                        }
                    }

                    CortetsuSurface {
                        Layout.fillWidth: true
                        implicitHeight: 104
                        radiusValue: CortetsuDesign.radiusMedium
                        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.66)
                        outlined: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: CortetsuDesign.spacingStandard
                            spacing: CortetsuDesign.spacingCompact
                            RowLayout {
                                Layout.fillWidth: true
                                CortetsuText {
                                    Layout.fillWidth: true
                                    text: root.mode === "outputs" ? qsTr("Volumen de salida") : qsTr("Nivel de entrada")
                                    textSize: CortetsuTypography.bodyPx
                                    font.weight: Font.DemiBold
                                }
                                CortetsuText {
                                    text: qsTr("%1%").arg(Math.round(root.nodeVolume(root.selectedNode) * 100))
                                    textSize: CortetsuTypography.labelSmallPx
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                }
                            }
                            CortetsuSlider {
                                Layout.fillWidth: true
                                value: root.nodeVolume(root.selectedNode)
                                disabled: !root.selectedNode?.audio
                                onMoved: nextValue => root.setNodeVolume(nextValue)
                            }
                        }
                    }

                    DetailRow { label: qsTr("Estado"); value: root.nodeStatus(root.selectedNode) }
                    DetailRow { label: qsTr("Tipo"); value: root.mode === "outputs" ? qsTr("Salida") : qsTr("Entrada") }
                    DetailRow { label: qsTr("Identificador"); value: root.selectedNode?.name ?? qsTr("No disponible") }
                }

                CortetsuStateMessage {
                    anchors.centerIn: parent
                    visible: !root.selectedNode
                    kind: "empty"
                    icon: "volume_off"
                    title: qsTr("Selecciona una ruta de audio")
                    detail: qsTr("El detalle mostrará volumen, estado y dispositivo predeterminado")
                }
            }
        }

        CortetsuSectionHeader {
            Layout.fillWidth: true
            title: qsTr("Aplicaciones reproduciendo")
            detail: qsTr("Volumen independiente por stream detectado por PipeWire")
        }

        CortetsuStateMessage {
            Layout.fillWidth: true
            visible: CortetsuAudio.streams.length === 0
            kind: "empty"
            icon: "music_off"
            title: qsTr("Sin aplicaciones reproduciendo audio")
            detail: qsTr("Los controles por aplicación aparecerán cuando exista un stream")
        }

        Repeater {
            model: CortetsuAudio.streams
            delegate: CortetsuSurface {
                id: streamDelegate
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 78
                radiusValue: CortetsuDesign.radiusMedium
                baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
                outlined: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingStandard
                    spacing: CortetsuDesign.spacingStandard

                    CortetsuIcon {
                        text: CortetsuAudio.getStreamMuted(streamDelegate.modelData) ? "volume_off" : "music_note"
                        iconSize: CortetsuTypography.iconMediumPx
                        color: CortetsuDesign.colorPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        CortetsuText {
                            Layout.fillWidth: true
                            text: CortetsuAudio.getStreamName(streamDelegate.modelData)
                            textSize: CortetsuTypography.bodyPx
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        CortetsuSlider {
                            Layout.fillWidth: true
                            value: CortetsuAudio.getStreamVolume(streamDelegate.modelData)
                            disabled: CortetsuAudio.getStreamMuted(streamDelegate.modelData)
                            onMoved: nextValue => CortetsuAudio.setStreamVolume(streamDelegate.modelData, nextValue)
                        }
                    }

                    CortetsuToggle {
                        checked: !CortetsuAudio.getStreamMuted(streamDelegate.modelData)
                        onToggled: checked => CortetsuAudio.setStreamMuted(streamDelegate.modelData, !checked)
                    }
                }
            }
        }
    }
}
