pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../../components"
import "../../theme"
import "../../services"
import "../CortetsuTypography.js" as CortetsuTypography

FocusScope {
    id: root
    signal back()
    signal closeRequested()
    property var entries: []
    // One library: the static images of the wallpaper folder next to the
    // Steam Workshop projects, filtered and searched together.
    readonly property var staticEntries: CortetsuWallpapers.list.map(item => ({
        title: item.name.replace(/\.[^.]+$/, ""), type: "image", source: "static",
        location: item.path, preview: item.path }))
    readonly property var allEntries: root.staticEntries.concat(root.entries)
    property var assets: []
    property bool favoritesOnly: false
    property string collection: ""
    property string errorText: ""
    property var scannedRoots: []
    property string query: ""
    property string kind: "all"
    property var selected: null
    readonly property var filtered: allEntries.filter(entry =>
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
        CortetsuText {
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Fondos")
            textSize: CortetsuTypography.titleMediumPx
            font.weight: Font.DemiBold
            rightPadding: CortetsuDesign.spacingStandard
        }
        CortetsuSearchBar {
            id: search
            width: Math.max(160, Math.min(520, root.width - 760))
            compact: true
            placeholderText: qsTr("Buscar fondos")
            onTextChanged: root.query = text
        }
        CortetsuButton { compact: true; label: qsTr("Actualizar"); icon: "refresh"; disabled: scan.running; onClicked: { CortetsuWallpapers.reload(); root.reload(); } }
        // The Workshop itself lives in Steam: it opens there, where
        // subscribing downloads into the library this view reads.
        CortetsuButton {
            objectName: "steamWorkshop"
            compact: true
            label: qsTr("Steam Workshop")
            icon: "storefront"
            tooltipText: qsTr("Abre la Workshop de Wallpaper Engine en Steam; lo que suscribas aparece aquí al actualizar")
            onClicked: Quickshell.execDetached(["xdg-open", "steam://url/SteamWorkshopPage/431960"])
        }
        CortetsuButton { compact: true; label: qsTr("Vista compacta"); icon: "close_fullscreen"; onClicked: root.back() }
        CortetsuButton { compact: true; label: ""; icon: "close"; tooltipText: qsTr("Cerrar"); onClicked: root.closeRequested() }
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
        text: scan.running ? qsTr("Leyendo bibliotecas de Steam…") : root.errorText
            || qsTr("%1 imágenes · %2 de Steam Workshop · Pulsa un fondo para ver sus opciones; doble clic lo aplica")
                .arg(root.staticEntries.length).arg(root.entries.length)
        color: CortetsuDesign.colorOnSurfaceVariant
    }

    GridView {
        id: grid
        anchors.top: status.bottom
        anchors.topMargin: CortetsuDesign.spacingStandard
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: root.selected ? parent.width * 0.68 : parent.width
        clip: true
        cellWidth: width / Math.max(1, Math.floor(width / 280))
        cellHeight: cellWidth
        model: root.filtered
        // The whole card is the target: picture, title and type together.
        delegate: Item {
            id: cell
            required property var modelData
            readonly property bool isStatic: modelData.source === "static"
            readonly property bool current: isStatic && modelData.location === CortetsuWallpapers.actualCurrent
            readonly property bool chosen: root.selected === modelData
            width: grid.cellWidth
            height: grid.cellHeight

            Item {
                id: card
                anchors.fill: parent
                anchors.margins: 8
                scale: cardMouse.pressed ? 0.98 : 1
                Behavior on scale { NumberAnimation { duration: CortetsuDesign.motionFastMs } }

                CortetsuRoundedImage {
                    id: picture
                    anchors.fill: parent
                    radius: 16
                    source: cell.modelData.preview ? "file://" + cell.modelData.preview.split("/").map(encodeURIComponent).join("/") : ""
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 16
                    visible: picture.status !== Image.Ready
                    color: CortetsuDesign.colorSurfaceHigh
                    CortetsuText { anchors.centerIn: parent; text: qsTr("Sin portada"); color: CortetsuDesign.colorOnSurfaceVariant }
                }
                // The title over a dark fade at the foot of the picture.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 64
                    radius: 16
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.78) }
                    }
                }
                CortetsuText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 12
                    text: cell.modelData.title || qsTr("Sin título")
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                    color: "white"
                    elide: Text.ElideRight
                }
                // What it is, and a dot when it is the wallpaper now.
                Rectangle {
                    x: 10
                    y: 10
                    height: 22
                    width: kindText.implicitWidth + 16
                    radius: 11
                    color: Qt.rgba(0, 0, 0, 0.55)
                    CortetsuText {
                        id: kindText
                        anchors.centerIn: parent
                        text: ({ image: qsTr("Imagen"), scene: qsTr("Escena"), video: qsTr("Vídeo"), web: qsTr("Web") })[cell.modelData.type] ?? qsTr("Otro")
                        textSize: CortetsuTypography.labelSmallPx
                        color: "white"
                    }
                }
                Rectangle {
                    visible: cell.current
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 12
                    width: 10
                    height: 10
                    radius: 5
                    color: CortetsuDesign.colorSuccess
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 16
                    color: "transparent"
                    border.width: cell.chosen ? 3 : cardMouse.containsMouse ? 1.5 : 0
                    border.color: cell.chosen ? CortetsuDesign.colorPrimary : Qt.alpha(CortetsuDesign.colorWashi, 0.5)
                }
                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected = cell.modelData
                    // Double click applies: an image as the wallpaper, a Steam
                    // project on this monitor with its saved settings.
                    onDoubleClicked: {
                        if (cell.isStatic)
                            CortetsuWallpapers.apply(cell.modelData.location);
                        else {
                            root.selected = cell.modelData;
                            Qt.callLater(() => playback.applyWhenReady());
                        }
                    }
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
            CortetsuText { visible: root.selected?.source !== "static"; width: parent.width; wrapMode: Text.Wrap; text: root.selected ? qsTr("Tipo: %1\nFuente: %2\nCompatibilidad: %3").arg(root.selected.type || qsTr("Desconocido")).arg(root.selected.source === "steam" ? "Steam Workshop" : qsTr("Carpeta personalizada")).arg(root.selected.compatibility === "read-error" ? qsTr("Error de lectura")
                : Orbital.inspections[root.selected.location]?.supported === true ? qsTr("Reproducible con Almamu Wayland")
                : Orbital.inspections[root.selected.location] ? qsTr("No reproducible") : qsTr("Comprobando…")) : "" }
            CortetsuText { width: parent.width; wrapMode: Text.WrapAnywhere; text: root.selected?.location || ""; color: CortetsuDesign.colorOnSurfaceVariant }
            CortetsuText { width: parent.width; wrapMode: Text.Wrap; text: (root.selected?.errors || []).join("\n") }
            // A static image: shown large, applied as the wallpaper.
            CortetsuRoundedImage {
                visible: root.selected?.source === "static"
                width: parent.width
                height: width * 9 / 16
                radius: 14
                source: visible ? "file://" + String(root.selected?.location ?? "").split("/").map(encodeURIComponent).join("/") : ""
            }
            CortetsuButton {
                visible: root.selected?.source === "static"
                active: true
                icon: "wallpaper"
                label: root.selected?.location === CortetsuWallpapers.actualCurrent ? qsTr("Es el fondo actual") : qsTr("Aplicar")
                disabled: root.selected?.location === CortetsuWallpapers.actualCurrent || CortetsuWallpapers.applying
                onClicked: CortetsuWallpapers.apply(root.selected.location)
            }
            SteamPlayback { id: playback; visible: root.selected?.source !== "static"; width: parent.width; entry: root.selected?.source !== "static" ? root.selected : null; assets: root.assets }
        }
    }
}
