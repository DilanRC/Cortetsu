pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../../components"
import "../../theme"

FocusScope {
    id: root
    signal back()
    property var entries: []
    property string errorText: ""
    property string query: ""
    property string kind: "all"
    property var selected: null
    readonly property var filtered: entries.filter(entry =>
        (kind === "all" || entry.type === kind) &&
        String(entry.title || entry.location || "").toLocaleLowerCase().includes(query.toLocaleLowerCase()))

    function reload(): void {
        if (scan.running) return;
        errorText = "";
        scan.running = true;
    }

    Component.onCompleted: { reload(); search.forceActiveFocus(); }
    Keys.onEscapePressed: back()

    Process {
        id: scan
        command: [Quickshell.env("HOME") + "/.local/bin/cortetsu-orbital", "catalog"]
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onExited: code => {
            if (code !== 0) {
                root.errorText = errors.text.trim() || qsTr("No se pudo leer el catálogo Steam. Comprueba que el runtime de Orbital esté instalado.");
                return;
            }
            try {
                const result = JSON.parse(output.text);
                if (!Array.isArray(result.entries)) throw new Error("entries");
                root.entries = result.entries;
                root.selected = null;
                root.errorText = (result.errors || []).map(item => item.path + ": " + item.error).join("\n");
            } catch (_) {
                root.errorText = qsTr("El runtime devolvió un catálogo no válido.");
            }
        }
    }

    Row {
        id: toolbar
        spacing: CortetsuDesign.spacingCompact
        CortetsuButton { compact: true; label: qsTr("Volver"); icon: "arrow_back"; onClicked: root.back() }
        CortetsuSearchBar {
            id: search
            width: Math.max(120, root.width - 290)
            compact: true
            placeholderText: qsTr("Buscar en Steam")
            onTextChanged: root.query = text
        }
        CortetsuButton { compact: true; label: qsTr("Actualizar"); icon: "refresh"; disabled: scan.running; onClicked: root.reload() }
    }

    Row {
        id: filters
        anchors.top: toolbar.bottom
        anchors.topMargin: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingCompact
        Repeater {
            model: [{ key: "all", label: qsTr("Todos") }, { key: "scene", label: qsTr("Escenas") }, { key: "video", label: qsTr("Vídeos") }, { key: "web", label: qsTr("Web") }, { key: "image", label: qsTr("Imágenes") }]
            delegate: CortetsuButton {
                required property var modelData
                compact: true
                label: modelData.label
                active: root.kind === modelData.key
                onClicked: root.kind = modelData.key
            }
        }
    }

    CortetsuText {
        id: status
        anchors.top: filters.bottom
        anchors.topMargin: CortetsuDesign.spacingStandard
        width: parent.width
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        text: scan.running ? qsTr("Leyendo bibliotecas de Steam…") : root.errorText || (root.entries.length ? qsTr("%1 fondos descargados · La reproducción animada todavía no está integrada").arg(root.entries.length) : qsTr("No se encontraron fondos descargados de Wallpaper Engine."))
        color: CortetsuDesign.colorOnSurfaceVariant
    }

    GridView {
        id: grid
        anchors.top: status.bottom
        anchors.topMargin: CortetsuDesign.spacingStandard
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: root.selected ? parent.width * 0.58 : parent.width
        clip: true
        cellWidth: width / Math.max(1, Math.floor(width / 190))
        cellHeight: 150
        model: root.filtered
        delegate: Item {
            id: cell
            required property var modelData
            width: grid.cellWidth
            height: grid.cellHeight
            Image {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 12
                height: 104
                source: cell.modelData.preview ? "file://" + cell.modelData.preview.split("/").map(encodeURIComponent).join("/") : ""
                sourceSize.width: 320
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                CortetsuText { anchors.centerIn: parent; visible: parent.status !== Image.Ready; text: qsTr("Sin portada") }
            }
            CortetsuButton {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6
                compact: true
                label: ""
                tooltipText: cell.modelData.title || qsTr("Sin título")
                active: root.selected === cell.modelData
                onClicked: root.selected = cell.modelData
                CortetsuText {
                    anchors.fill: parent
                    anchors.margins: 6
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: cell.modelData.title || qsTr("Sin título")
                    color: root.selected === cell.modelData ? CortetsuDesign.colorOnPrimary : CortetsuDesign.colorOnSurface
                }
            }
        }
        CortetsuText {
            anchors.centerIn: parent
            visible: !scan.running && root.entries.length > 0 && root.filtered.length === 0
            text: qsTr("Ningún fondo coincide con los filtros")
        }
    }

    Flickable {
        anchors.top: grid.top
        anchors.left: grid.right
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: !!root.selected
        clip: true
        contentHeight: details.height
        Column {
            id: details
            width: parent.width
            spacing: CortetsuDesign.spacingStandard
            CortetsuText { width: parent.width; wrapMode: Text.Wrap; text: root.selected?.title || qsTr("Sin título"); font.bold: true }
            CortetsuText { width: parent.width; wrapMode: Text.Wrap; text: root.selected ? qsTr("Tipo: %1\nFuente: %2\nCompatibilidad: %3").arg(root.selected.type || qsTr("Desconocido")).arg(root.selected.source === "steam" ? "Steam Workshop" : qsTr("Carpeta personalizada")).arg(root.selected.compatibility === "read-error" ? qsTr("Error de lectura") : qsTr("No determinada")) : "" }
            CortetsuText { width: parent.width; wrapMode: Text.WrapAnywhere; text: root.selected?.location || ""; color: CortetsuDesign.colorOnSurfaceVariant }
            CortetsuText { width: parent.width; wrapMode: Text.Wrap; text: (root.selected?.errors || []).join("\n") }
            CortetsuText { width: parent.width; wrapMode: Text.Wrap; text: qsTr("Esta vista consulta los archivos descargados. Para aplicar un fondo estático, vuelve a la biblioteca de imágenes de Orbital."); color: CortetsuDesign.colorOnSurfaceVariant }
        }
    }
}
