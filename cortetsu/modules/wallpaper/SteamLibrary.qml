pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../../components"
import "../../theme"
import "../../services"

FocusScope {
    id: root
    signal back()
    property var entries: []
    property var assets: []
    property bool favoritesOnly: false
    property string collection: ""
    property string errorText: ""
    property var scannedRoots: []
    property string query: ""
    property string kind: "all"
    property var selected: null
    readonly property var filtered: entries.filter(entry =>
        (!favoritesOnly || (Orbital.preferences.favorites || []).includes(entry.location)) &&
        (!collection || (Orbital.preferences.collections?.[collection] || []).includes(entry.location)) &&
        (kind === "all" || entry.type === kind) &&
        String(entry.title || entry.location || "").toLocaleLowerCase().includes(query.toLocaleLowerCase()))

    function reload(): void {
        if (scan.running) return;
        errorText = "";
        scannedRoots = (Orbital.preferences.libraryRoots || []).slice();
        scan.running = true;
    }

    Component.onCompleted: { Orbital.ensure(); reload(); search.forceActiveFocus(); }
    // Library folders saved by the supervisor may arrive after the first scan.
    Connections {
        target: Orbital
        function onPreferencesChanged(): void {
            if (JSON.stringify(Orbital.preferences.libraryRoots || []) !== JSON.stringify(root.scannedRoots)) root.reload();
        }
    }
    Keys.onEscapePressed: back()

    // startup inventory: cortetsu:orbital-steam-catalog (on open only)
    Process {
        id: scan
        command: [Quickshell.env("HOME") + "/.local/bin/cortetsu-orbital", "catalog"].concat(root.scannedRoots)
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onExited: code => {
            // Folders changed while this scan ran: read the catalog again.
            if (JSON.stringify(Orbital.preferences.libraryRoots || []) !== JSON.stringify(root.scannedRoots)) Qt.callLater(root.reload);
            if (code !== 0) {
                root.errorText = errors.text.trim() || qsTr("No se pudo leer el catálogo Steam. Comprueba que el runtime de Orbital esté instalado.");
                return;
            }
            try {
                const result = JSON.parse(output.text);
                if (!Array.isArray(result.entries)) throw new Error("entries");
                root.entries = result.entries;
                root.assets = result.assets || [];
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

    Flow {
        id: libraryTools
        anchors.top: filters.bottom
        anchors.topMargin: CortetsuDesign.spacingCompact
        width: parent.width
        spacing: CortetsuDesign.spacingCompact
        CortetsuButton { compact: true; icon: "star"; label: qsTr("Favoritos"); active: root.favoritesOnly; onClicked: root.favoritesOnly = !root.favoritesOnly }
        CortetsuButton { compact: true; icon: "collections_bookmark"; label: root.collection || qsTr("Colecciones"); tooltipText: qsTr("Cambia de colección; la última vuelve a mostrar todo"); onClicked: { const names = [""].concat(Object.keys(Orbital.preferences.collections || {})); root.collection = names[(names.indexOf(root.collection) + 1) % names.length]; } }
        OrbitalField { id: libraryPath; width: Math.max(120, Math.min(280, root.width - 220)); placeholderText: qsTr("Directorio adicional de fondos"); maximumLength: 4096 }
        CortetsuButton { compact: true; icon: "create_new_folder"; label: qsTr("Añadir carpeta"); disabled: !libraryPath.text.startsWith("/") || !Orbital.available; onClicked: { Orbital.send({op: "library", roots: [...new Set((Orbital.preferences.libraryRoots || []).concat([libraryPath.text]))]}); libraryPath.text = ""; } }
        Repeater {
            model: Orbital.preferences.libraryRoots || []
            delegate: CortetsuButton {
                required property string modelData
                compact: true; label: qsTr("Quitar %1").arg(modelData.split("/").pop()); tooltipText: modelData
                onClicked: Orbital.send({op: "library", roots: Orbital.preferences.libraryRoots.filter(p => p !== modelData)})
            }
        }
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
        anchors.top: libraryTools.bottom
        anchors.topMargin: CortetsuDesign.spacingStandard
        width: parent.width
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        text: scan.running ? qsTr("Leyendo bibliotecas de Steam…") : root.errorText || (root.entries.length ? qsTr("%1 fondos descargados · Selecciona un fondo para reproducirlo").arg(root.entries.length) : qsTr("No se encontraron fondos descargados de Wallpaper Engine."))
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
            CortetsuText { width: parent.width; wrapMode: Text.Wrap; text: root.selected ? qsTr("Tipo: %1\nFuente: %2\nCompatibilidad: %3").arg(root.selected.type || qsTr("Desconocido")).arg(root.selected.source === "steam" ? "Steam Workshop" : qsTr("Carpeta personalizada")).arg(root.selected.compatibility === "read-error" ? qsTr("Error de lectura")
                : Orbital.inspections[root.selected.location]?.supported === true ? qsTr("Reproducible con Almamu Wayland")
                : Orbital.inspections[root.selected.location] ? qsTr("No reproducible") : qsTr("Comprobando…")) : "" }
            CortetsuText { width: parent.width; wrapMode: Text.WrapAnywhere; text: root.selected?.location || ""; color: CortetsuDesign.colorOnSurfaceVariant }
            CortetsuText { width: parent.width; wrapMode: Text.Wrap; text: (root.selected?.errors || []).join("\n") }
            SteamPlayback { width: parent.width; entry: root.selected; assets: root.assets }
        }
    }
}
