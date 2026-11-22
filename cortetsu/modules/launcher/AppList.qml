pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import "../../utils"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "../CortetsuSurface.qml"
import "../CortetsuText.qml"
import "../CortetsuIcon.qml"
import "../CortetsuStateLayer.qml"
import "../../services"
import "services"

GridView {
    id: root

    required property TextField search
    required property var screenState
    // Browse mode narrows the empty search to one category ("home" is
    // favourites, recent, then everything).
    property string category: "home"

    /*
     * IMPORTANT:
     * This grid uses the live search text directly.
     *
     * Upstream keeps a separate displayText because its ListView transition
     * swaps the delegate first, updates displayText in a ScriptAction, and
     * then restores the delegate. Our grid does not use that transition.
     * Keeping that split without the transition can pair an "actions"
     * delegate with an old "apps" model (or vice versa).
     */
    readonly property string requestedState: stateForText(search.text)

    readonly property int columns: {
        switch (state) {
        case "actions":
        case "files":
            return 2;
        case "calc":
            return 1;
        case "emoji":
            return 8;
        case "scheme":
        case "variant":
            return 3;
        default:
            return root.listView ? 2 : width >= 700 ? 6 : width >= 570 ? 5 : 4;
        }
    }

    // List view (03-launcher's «Ver»): two columns of rows, icon beside name.
    readonly property bool listView: CortetsuConfig.launcherListView && state !== "actions" && state !== "files"
        && state !== "calc" && state !== "emoji" && state !== "scheme" && state !== "variant"
    readonly property int visibleRows: state === "calc" ? 1 : root.listView ? 8 : 4

    function stateForText(text: string): string {
        const prefix = CortetsuConfig.actionPrefix;

        if (text.startsWith(prefix)) {
            for (const action of ["calc", "emoji", "scheme", "variant", "files"])
                if (text.startsWith(`${prefix}${action} `))
                    return action;

            return "actions";
        }

        return "apps";
    }

    function resultsForText(text: string): var {
        switch (stateForText(text)) {
        case "actions":
            return Actions.query(text);
        case "calc":
            return [0];
        case "files":
            return Files.results;
        case "emoji":
            return Emojis.query(text);
        case "scheme":
            return Schemes.query(text);
        case "variant":
            if (!M3Variants.variantAvailable)
                return [];
            return M3Variants.query(text);
        default:
            if (text.length > 0)
                return Apps.search(text);
            // «Ordenar»: by name, or what was opened recently first.
            const browsed = Apps.browse(root.category);
            if (CortetsuConfig.launcherSort === "recent")
                return Apps.recentFirst(browsed);
            const byName = browsed.slice().sort((a, b) => String(a.name).localeCompare(String(b.name), undefined, { sensitivity: "base" }) || String(a.id).localeCompare(String(b.id)));
            return CortetsuConfig.launcherSort === "name-desc" ? byName.reverse() : byName;
        }
    }

    function clampIndex(index: int): int {
        if (count <= 0)
            return -1;
        return Math.max(0, Math.min(index, count - 1));
    }

    function moveGridLeft(): void {
        if (count <= 0)
            return;
        currentIndex = currentIndex <= 0 ? count - 1 : currentIndex - 1;
        positionViewAtIndex(currentIndex, GridView.Contain);
    }

    function moveGridRight(): void {
        if (count <= 0)
            return;
        currentIndex = currentIndex >= count - 1 ? 0 : currentIndex + 1;
        positionViewAtIndex(currentIndex, GridView.Contain);
    }

    function moveGridUp(): void {
        if (count <= 0)
            return;

        let next = currentIndex - columns;
        if (next < 0) {
            const col = currentIndex % columns;
            const lastRowStart = Math.floor((count - 1) / columns) * columns;
            next = Math.min(lastRowStart + col, count - 1);
        }

        currentIndex = next;
        positionViewAtIndex(currentIndex, GridView.Contain);
    }

    function moveGridDown(): void {
        if (count <= 0)
            return;

        let next = currentIndex + columns;
        if (next >= count)
            next = currentIndex % columns;

        currentIndex = Math.min(next, count - 1);
        positionViewAtIndex(currentIndex, GridView.Contain);
    }

    // Content.qml usa estas para Tab / Ctrl+J / Ctrl+K.
    function incrementCurrentIndex(): void {
        moveGridRight();
    }

    function decrementCurrentIndex(): void {
        moveGridLeft();
    }

    function toggleFavourite(entry): void {
        if (!entry)
            return;

        const apps = CortetsuConfig.favouriteApps;
        const id = entry.id;

        if (apps.includes(id))
            CortetsuConfig.setFavouriteApps(apps.filter(a => a !== id));
        else if (!Strings.testRegexList(apps, id))
            CortetsuConfig.setFavouriteApps([...apps, id]);
    }

    // File search runs in its own owner; it hears every edit and acts only
    // on ">files texto".
    Connections {
        target: root.search
        function onTextChanged(): void { Files.update(root.search.text); }
    }

    // Query the selection was last reset for.
    property string selectionQuery: ""

    model: ScriptModel {
        // A rescan returns a new object for an entry it read again. Keyed by
        // id, the cell stays and only its data changes.
        objectProp: "id"
        values: root.resultsForText(root.search.text)

        // A new query selects the first result. A refresh of the same query
        // (a rescan, a hidden app) leaves the selection to the view, which
        // follows the selected application through row changes.
        // ponytail: a query that changes no result is not recorded, so the
        // next refresh still selects the first result. Recording it needs a
        // handler on search.text that runs after this binding.
        onValuesChanged: {
            const refreshed = root.search.text === root.selectionQuery;
            root.selectionQuery = root.search.text;
            if (!refreshed || root.currentIndex < 0)
                root.currentIndex = root.count > 0 ? 0 : -1;
        }
    }

    // Model and delegate/state always describe the SAME type of objects.
    state: requestedState

    onStateChanged: {
        if (state === "scheme" || state === "variant")
            Schemes.reload();

        currentIndex = count > 0 ? 0 : -1;
    }

    cellWidth: width / Math.max(1, columns)

    cellHeight: {
        switch (state) {
        case "actions":
        case "files":
            return 88;
        case "calc":
            return 118;
        case "emoji":
            return 88;
        case "scheme":
            return 154;
        case "variant":
            return 116;
        default:
            // The icon and two lines of name; a row in the list view.
            return root.listView ? 56 : 116;
        }
    }

    implicitWidth: 760
    implicitHeight: {
        if (count <= 0)
            return 0;

        const rows = Math.ceil(count / Math.max(1, columns));
        return Math.min(rows, visibleRows) * cellHeight;
    }

    clip: true
    boundsBehavior: Flickable.StopAtBounds
    keyNavigationWraps: true

    delegate: root.state === "actions" || root.state === "files"
        ? actionDelegate
        : root.state === "calc"
            ? calcDelegate
            : root.state === "emoji"
                ? emojiDelegate
                : root.state === "scheme"
                ? schemeDelegate
                : root.state === "variant"
                    ? variantDelegate
                    : appDelegate

    ScrollBar.vertical: ScrollBar {
    }

    Component {
        id: appDelegate

        Item {
            id: app

            required property DesktopEntry modelData
            required property int index

            width: root.cellWidth
            height: root.cellHeight

            readonly property bool selected: GridView.isCurrentItem
            readonly property bool favourite:
                modelData &&
                Strings.testRegexList(
                    CortetsuConfig.favouriteApps,
                    modelData.id
                )

            CortetsuSurface {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingUnit
                radius: CortetsuDesign.radiusLarge
                color: app.selected
                    ? CortetsuDesign.colorSecondaryContainer
                    : "transparent"
                // Premium sobria: a cell has an edge only while it is the selection.
                outlined: app.selected
            }

            CortetsuStateLayer {
                id: appState

                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingUnit
                radius: CortetsuDesign.radiusLarge

                onEntered: root.currentIndex = index

                onClicked: {
                    Apps.launch(app.modelData);
                    root.screenState.launcher = false;
                }
            }

            IconImage {
                id: appIcon
                width: root.listView ? 34 : 52
                height: width
                x: root.listView ? 16 : (parent.width - width) / 2
                y: root.listView ? (parent.height - height) / 2 : 13

                source: Quickshell.iconPath(
                    app.modelData?.icon,
                    "application-x-executable"
                )
            }

            // A pinned app says so in its corner; right click toggles it.
            CortetsuIcon {
                visible: app.favourite
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 10
                anchors.rightMargin: 12
                text: "keep"
                iconSize: CortetsuTypography.labelMediumPx
                color: app.selected ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOnSurfaceVariant
                Accessible.ignored: true
            }

            CortetsuText {
                x: root.listView ? appIcon.x + appIcon.width + 12 : 9
                y: root.listView ? (parent.height - height) / 2 : parent.height - height - 6
                width: parent.width - x - (root.listView ? 36 : 9)

                objectName: "appName"
                text: app.modelData?.name ?? ""
                font.pixelSize: root.listView ? CortetsuTypography.bodySmallPx : CortetsuTypography.labelSmallPx

                // A long name takes a second line before it is cut short; a
                // row keeps it on one.
                horizontalAlignment: root.listView ? Text.AlignLeft : Text.AlignHCenter
                verticalAlignment: root.listView ? Text.AlignVCenter : Text.AlignTop
                height: root.listView ? implicitHeight : Math.ceil(font.pixelSize * 2.6)
                wrapMode: root.listView ? Text.NoWrap : Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: root.listView ? 1 : 2
            }

            /*
             * Un único MouseArea controla ambos botones. En algunas versiones
             * de Qt/Quickshell el CortetsuStateLayer absorbía el botón derecho antes de
             * que llegara al MouseArea right-only, por eso pin/unpin no ocurría
             * desde el launcher aunque sí funcionara en el Dock.
             */
            MouseArea {
                id: appMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor

                onEntered: root.currentIndex = index

                onClicked: event => {
                    root.currentIndex = index;

                    if (event.button === Qt.RightButton) {
                        root.toggleFavourite(app.modelData);
                        event.accepted = true;
                        return;
                    }

                    Apps.launch(app.modelData);
                    root.screenState.launcher = false;
                    event.accepted = true;
                }
            }
        }
    }

    Component {
        id: actionDelegate

        Item {
            id: action

            required property var modelData
            required property int index

            width: root.cellWidth
            height: root.cellHeight

            readonly property bool selected: GridView.isCurrentItem

            CortetsuSurface {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingUnit
                radius: CortetsuDesign.radiusLarge
                color: action.selected
                    ? CortetsuDesign.colorSecondaryContainer
                    : "transparent"
                // Premium sobria: a cell has an edge only while it is the selection.
                outlined: action.selected
            }

            CortetsuStateLayer {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingUnit
                radius: CortetsuDesign.radiusLarge

                onEntered: root.currentIndex = index
                onClicked: action.modelData?.onClicked(root)
            }

            CortetsuIcon {
                id: actionIcon

                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter

                text: action.modelData?.icon ?? "help_outline"
                color: action.modelData?.dangerous
                    ? CortetsuDesign.colorVermillion
                    : CortetsuDesign.colorOnSurfaceVariant

                iconSize: CortetsuTypography.iconLargePx * 1.3
            }

            Column {
                anchors.left: actionIcon.right
                anchors.right: parent.right
                anchors.leftMargin: 13
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                CortetsuText {
                    width: parent.width
                    text: action.modelData?.name ?? ""
                    font.pixelSize: CortetsuTypography.bodyPx
                    elide: Text.ElideRight
                }

                CortetsuText {
                    width: parent.width
                    text: action.modelData?.desc ?? ""
                    font.pixelSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOutline
                    elide: Text.ElideRight
                }
            }
        }
    }

    Component {
        id: calcDelegate

        Item {
            id: calc

            required property var modelData
            required property int index

            width: root.cellWidth
            height: root.cellHeight

            readonly property string math:
                root.search.text.slice(
                    `${CortetsuConfig.actionPrefix}calc `.length
                )

            function onClicked(): void {
                if (calc.math.length > 0)
                    Quickshell.execDetached([
                        "wl-copy",
                        Qalculator.rawResult
                    ]);

                root.screenState.launcher = false;
            }

            onMathChanged: {
                if (math.length > 0)
                    Qalculator.evalAsync(math);
            }

            CortetsuStateLayer {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingUnit
                radius: CortetsuDesign.radiusLarge

                onEntered: root.currentIndex = index
                onClicked: calc.onClicked()
            }

            CortetsuIcon {
                id: calcIcon

                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter

                text: "function"
                iconSize: CortetsuTypography.iconLargePx
            }

            Column {
                anchors.left: calcIcon.right
                anchors.right: openCalc.left
                anchors.leftMargin: 15
                anchors.rightMargin: 15
                anchors.verticalCenter: parent.verticalCenter

                CortetsuText {
                    width: parent.width

                    text: calc.math.length > 0
                        ? (Qalculator.result || qsTr("Calculando…"))
                        : qsTr("Escribe una expresión para calcular")

                    color: text.includes("error: ") ||
                        text.includes("warning: ")
                        ? CortetsuDesign.colorVermillion
                        : calc.math
                            ? CortetsuDesign.colorOnSurface
                            : CortetsuDesign.colorOnSurfaceVariant

                    font.pixelSize: CortetsuTypography.bodyPx
                    elide: Text.ElideLeft
                }

                CortetsuText {
                    width: parent.width
                    text: qsTr("Enter: copiar resultado")
                    color: CortetsuDesign.colorOutline
                    font.pixelSize: CortetsuTypography.labelSmallPx
                }
            }

            CortetsuSurface {
                id: openCalc

                anchors.right: parent.right
                anchors.rightMargin: 17
                anchors.verticalCenter: parent.verticalCenter

                visible: calc.math.length > 0

                implicitWidth: 46
                implicitHeight: 46
                radius: CortetsuDesign.radiusLarge
                color: CortetsuDesign.colorPrimaryContainer

                CortetsuStateLayer {
                    radius: parent.radius

                    onClicked: {
                    CortetsuProcessLauncher.launchPersistent([
                        ...CortetsuConfig.terminalCommand,
                        "qalc",
                        "-i",
                        calc.math
                    ], "", "qalc");

                        root.screenState.launcher = false;
                    }
                }

                CortetsuIcon {
                    anchors.centerIn: parent
                    text: "open_in_new"
                iconSize: CortetsuTypography.iconMediumPx
                }
            }
        }
    }

    Component {
        id: emojiDelegate

        Item {
            id: emoji

            required property var modelData
            required property int index

            width: root.cellWidth
            height: root.cellHeight

            readonly property bool selected: GridView.isCurrentItem

            CortetsuSurface {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingUnit
                radius: CortetsuDesign.radiusLarge
                color: emoji.selected
                    ? CortetsuDesign.colorSecondaryContainer
                    : "transparent"
                // Premium sobria: a cell has an edge only while it is the selection.
                outlined: emoji.selected
            }

            CortetsuStateLayer {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingUnit
                radius: CortetsuDesign.radiusLarge

                onEntered: root.currentIndex = index
                onClicked: emoji.modelData?.onClicked(root)
            }

            // Kaomoji and glyph runs are wider than one emoji: they shrink
            // to the cell instead of spilling into the next one.
            CortetsuText {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.topMargin: 12
                height: 42

                text: emoji.modelData?.glyph ?? ""
                font.pixelSize: 34
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                maximumLineCount: 1
            }

            CortetsuText {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 7
                anchors.rightMargin: 7
                anchors.bottomMargin: 9

                text: emoji.modelData?.name ?? ""
                color: CortetsuDesign.colorOutline
                font.pixelSize: CortetsuTypography.labelSmallPx
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    Component {
        id: schemeDelegate

        Item {
            id: scheme

            required property var modelData
            required property int index

            width: root.cellWidth
            height: root.cellHeight

            readonly property bool selected: GridView.isCurrentItem
            readonly property bool current:
                `${modelData?.name} ${modelData?.flavour}` === Schemes.currentScheme

            readonly property var previewSwatches: [
                modelData?.colours?.surface,
                modelData?.colours?.primary,
                modelData?.colours?.secondary,
                modelData?.colours?.tertiary,
                modelData?.colours?.error,
                modelData?.colours?.onSurface
            ]

            readonly property bool previewLight: {
                const raw = String(modelData?.colours?.surface ?? "").replace("#", "");
                if (raw.length !== 6)
                    return false;
                const r = parseInt(raw.slice(0, 2), 16);
                const g = parseInt(raw.slice(2, 4), 16);
                const b = parseInt(raw.slice(4, 6), 16);
                return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.56;
            }

            CortetsuSurface {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingUnit
                radius: CortetsuDesign.radiusLarge
                color: scheme.selected
                    ? CortetsuDesign.colorSecondaryContainer
                    : CortetsuDesign.colorSurface
                border.width: scheme.current ? 1 : 0
                border.color: CortetsuDesign.colorPrimary
            }

            CortetsuStateLayer {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingUnit
                radius: CortetsuDesign.radiusLarge
                onEntered: root.currentIndex = index
                onClicked: scheme.modelData?.onClicked(root)
            }

            Row {
                id: swatches
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 17
                spacing: 6

                Repeater {
                    model: scheme.previewSwatches

                    delegate: Rectangle {
                        required property var modelData
                        width: Math.max(15, (swatches.width - 30) / 6)
                        height: 24
                        radius: CortetsuDesign.radiusSmall
                        color: modelData
                            ? `#${modelData}`
                            : CortetsuDesign.colorSurfaceHigh
                        border.width: 1
                        border.color: Qt.alpha(CortetsuDesign.colorOutline, 0.34)
                    }
                }
            }

            CortetsuText {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: swatches.bottom
                anchors.topMargin: 13
                anchors.leftMargin: 14
                anchors.rightMargin: 14

                text: scheme.modelData?.name ?? ""
                    font.pixelSize: CortetsuTypography.bodyPx
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            CortetsuText {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 102
                anchors.leftMargin: 12
                anchors.rightMargin: 12

                        text: `${scheme.modelData?.flavour ?? "predeterminado"} · ${scheme.previewLight ? qsTr("Claro") : qsTr("Oscuro")}`
                color: CortetsuDesign.colorOnSurfaceVariant
                    font.pixelSize: CortetsuTypography.labelSmallPx
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            CortetsuIcon {
                visible: scheme.current
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 9
                anchors.rightMargin: 10
                text: "check_circle"
                color: CortetsuDesign.colorPrimary
                iconSize: CortetsuTypography.iconSmallPx
            }
        }
    }

    Component {
        id: variantDelegate

        Item {
            id: variant

            required property var modelData
            required property int index

            width: root.cellWidth
            height: root.cellHeight

            readonly property bool selected: GridView.isCurrentItem

            CortetsuSurface {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingUnit
                radius: CortetsuDesign.radiusLarge
                color: variant.selected
                    ? CortetsuDesign.colorSecondaryContainer
                    : "transparent"
                // Premium sobria: a cell has an edge only while it is the selection.
                outlined: variant.selected
            }

            CortetsuStateLayer {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingUnit
                radius: CortetsuDesign.radiusLarge

                onEntered: root.currentIndex = index
                onClicked: variant.modelData?.onClicked(root)
            }

            CortetsuIcon {
                id: variantIcon

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 11

                text: variant.modelData?.icon ?? ""
                iconSize: CortetsuTypography.iconLargePx
            }

            CortetsuText {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: variantIcon.bottom
                anchors.topMargin: 5
                anchors.leftMargin: 8
                anchors.rightMargin: 8

                text: variant.modelData?.name ?? ""
                    font.pixelSize: CortetsuTypography.labelSmallPx
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            CortetsuText {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 7
                anchors.leftMargin: 9
                anchors.rightMargin: 9

                text: variant.modelData?.description ?? ""
                color: CortetsuDesign.colorOutline
                font.pixelSize: CortetsuTypography.labelSmallPx
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            CortetsuIcon {
                visible:
                    variant.modelData?.variant ===
                    Schemes.currentVariant

                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 7
                anchors.rightMargin: 8

                text: "check"
                color: CortetsuDesign.colorPrimary
            }
        }
    }

}
