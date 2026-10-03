pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import ".."
import "../settings"
import "../../services"
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "../CortetsuWallpaperSearch.js" as WallpaperSearch
import "OrbitModel.js" as Orbit

FocusScope {
    id: root

    required property var screen
    required property var screenState
    property var entries: []
    property var filteredEntries: []
    property var categoryCounts: [{ name: "ALL", count: 0 }]
    property string selectedCategory: "ALL"
    property string query: ""
    property bool gridMode: false
    property int currentIndex: -1
    property int windowIndex: -1
    property int queuedDirection: 0
    property bool animating: false
    // Turn of the wheel, in slots, while a move animates. It returns to zero
    // in the same handler that re-anchors the model, so nothing jumps.
    property real orbitPhase: 0
    property real wheelAccumulator: 0
    property string pendingPreviewPath: ""
    property bool previewActive: false
    property string heroPath: ""
    property string outgoingHeroPath: ""
    property real newHeroOpacity: 1
    property real oldHeroOpacity: 0
    readonly property string pendingApplyPath: CortetsuWallpapers.pendingApplyPath
    readonly property bool applying: CortetsuWallpapers.applying
    readonly property bool randomApply: CortetsuWallpapers.randomApply
    readonly property bool applyFailed: CortetsuWallpapers.applyFailed
    readonly property string applyStatus: CortetsuWallpapers.applyStatus
    property bool cosmicPulse: false
    // Satellites on each side of the selected one. One more per side stays in
    // the model, invisible, so a turn has something to bring in.
    readonly property int arcHalf: Orbit.clamp(Math.floor(panel.width / 236), 2, 7)
    readonly property real arcSpan: Math.PI * 0.39
    readonly property int visibleLimit: arcHalf * 2 + 1
    // The arc stays anchored to the last settled selection while a turn is
    // running, so the wallpaper being selected travels to the centre instead
    // of the model changing under it.
    readonly property var orbitEntries: Orbit.arc(filteredEntries, windowIndex, arcHalf + 1)
    readonly property var prefetchEntries: Orbit.prefetch(filteredEntries, currentIndex, visibleLimit + 6)
    readonly property var currentEntry: currentIndex >= 0 ? filteredEntries[currentIndex] : null
    readonly property string currentPath: currentEntry?.path ?? ""
    readonly property bool currentIsApplied: !!currentPath && currentPath === CortetsuWallpapers.actualCurrent
    // A failure belongs to the wallpaper that failed, not to whichever is selected.
    readonly property bool currentFailed: applyFailed && currentPath === CortetsuWallpapers.applyStatusPath
    readonly property bool libraryEmpty: entries.length === 0
    readonly property bool noResults: !libraryEmpty && filteredEntries.length === 0
    readonly property string currentStateLabel: applyStatus === "applying"
        ? qsTr("Aplicando")
        : currentFailed
            ? qsTr("No se pudo aplicar")
            : currentIsApplied
                ? qsTr("Actual")
                : (previewActive ? qsTr("Vista previa") : qsTr("Seleccionado"))
    readonly property string markPhase: cosmicPulse
        ? "Cosmic"
        : applyStatus === "applying" || animating || (libraryEmpty && CortetsuWallpapers.scanning)
            ? "Awakening"
            : applyStatus === "failed"
                ? (currentIsApplied ? "Ascended" : "Human")
                : currentPath
                    ? "Ascended"
                    : "Human"
    property bool presentationReady: false

    function essentialReady(): bool {
        const count = Math.min(prefetchRepeater.count, 7);
        if (!count)
            return !currentPath;
        for (let i = 0; i < count; ++i) {
            const item = prefetchRepeater.itemAt(i);
            if (!item || (item.status !== Image.Ready && item.status !== Image.Error))
                return false;
        }
        return true;
    }

    function updatePresentationReady(): void {
        if (!presentationReady && (!currentPath || hero.status === Image.Ready || hero.status === Image.Error) && essentialReady())
            presentationReady = true;
    }

    readonly property string uncategorised: qsTr("Sin categoría")

    function categoryFor(entry): string { return CortetsuWallpapers.getCategoryFor(entry) || uncategorised; }

    function categoryLabel(name: string): string { return name === "ALL" ? qsTr("Todos") : name; }

    function matchesQuery(entry): bool {
        return WallpaperSearch.matches(`${entry.name ?? ""} ${entry.relativePath ?? entry.path}`, query, CortetsuConfig.useFuzzyWallpapers);
    }

    function cancelPreview(): void {
        previewTimer.stop();
        pendingPreviewPath = "";
        if (previewActive || CortetsuWallpapers.showPreview)
            CortetsuWallpapers.stopPreview();
        previewActive = false;
    }

    function updateHero(): void {
        if (!currentPath || currentPath === heroPath)
            return;
        outgoingHeroPath = heroPath;
        heroPath = currentPath;
        oldHeroOpacity = outgoingHeroPath ? 1 : 0;
        newHeroOpacity = outgoingHeroPath ? 0 : 1;
        if (outgoingHeroPath)
            heroCrossfade.restart();
    }

    // Settle on an entry without animating: used whenever the visible set
    // itself changes (catalog, category, search).
    function settle(index: int): void {
        queuedDirection = 0;
        orbitMotion.stop();
        animating = false;
        currentIndex = index;
        windowIndex = index;
        orbitPhase = 0;
        updateHero();
    }

    // Rebuild the visible set. The selection stays on `preferredPath` when it
    // survives the filter, then on the applied wallpaper, then on the first.
    function refilter(preferredPath: string): void {
        const scoped = Orbit.filtered(entries, selectedCategory, categoryFor);
        filteredEntries = query.trim() ? scoped.filter(matchesQuery) : scoped;
        let index = Orbit.resolveCurrentIndex(filteredEntries, preferredPath);
        if (index < 0)
            index = Orbit.resolveCurrentIndex(filteredEntries, CortetsuWallpapers.actualCurrent);
        settle(Orbit.normalize(index >= 0 ? index : 0, filteredEntries.length));
    }

    function resync(preferredPath: string): void {
        cancelPreview();
        entries = CortetsuWallpapers.list ? Array.from(CortetsuWallpapers.list) : [];
        categoryCounts = Orbit.categoryCounts(entries, categoryFor, uncategorised);
        if (!categoryCounts.some(category => category.name === selectedCategory))
            selectedCategory = "ALL";
        refilter(preferredPath);
    }

    function queuePreview(): void {
        pendingPreviewPath = currentPath;
        if (pendingPreviewPath)
            previewTimer.restart();
    }

    function requestMove(direction: int): void {
        if (filteredEntries.length < 2)
            return;
        requestTarget(Orbit.move(currentIndex, direction, filteredEntries.length), direction);
    }

    function requestTarget(target: int, replacementDirection: int): void {
        cancelPreview();
        if (animating) {
            queuedDirection = replacementDirection;
            return;
        }
        animateTo(target);
    }

    function consumeWheel(angleDelta: real, pixelDelta: real): void {
        const intent = Orbit.wheelIntent(wheelAccumulator, angleDelta, pixelDelta);
        wheelAccumulator = intent.accumulator;
        if (intent.direction)
            requestMove(intent.direction);
    }

    function animateTo(target: int): void {
        const count = filteredEntries.length;
        if (!count || target === currentIndex || animating)
            return;
        const steps = Orbit.arcSteps(currentIndex, target, count, arcHalf + 1);
        if (!steps)
            return;
        currentIndex = target;
        updateHero();
        queuePreview();
        // A jump past the visible arc has nothing to slide: re-anchor and
        // let the arc fade in at its new position.
        if (gridMode || Math.abs(steps) > arcHalf) {
            windowIndex = target;
            arcFade.restart();
            return;
        }
        animating = true;
        orbitMotion.to = steps;
        orbitMotion.restart();
    }

    function select(target: int): void {
        if (target === currentIndex || target < 0 || target >= filteredEntries.length)
            return;
        requestTarget(target, Math.sign(Orbit.arcSteps(currentIndex, target, filteredEntries.length, arcHalf + 1)));
    }

    function selectCategory(category: string): void {
        if (category === selectedCategory)
            return;
        const keep = currentPath;
        cancelPreview();
        selectedCategory = category;
        refilter(keep);
    }

    function cycleCategory(direction: int): void {
        const position = categoryCounts.findIndex(category => category.name === selectedCategory);
        selectCategory(categoryCounts[Orbit.normalize(position + direction, categoryCounts.length)].name);
    }

    function toggleGrid(): void {
        gridMode = !gridMode;
        if (gridMode)
            Qt.callLater(() => grid.positionViewAtIndex(root.currentIndex, GridView.Contain));
    }

    function apply(): void {
        if (!currentPath || applying)
            return;
        previewTimer.stop();
        pendingPreviewPath = "";
        if (CortetsuWallpapers.actualCurrent !== currentPath) {
            if (previewActive || CortetsuWallpapers.showPreview)
                CortetsuWallpapers.stopPreview();
            previewActive = false;
            const accepted = CortetsuWallpapers.apply(currentPath);
            if (accepted && CortetsuConfig.smartScheme)
                CortetsuWallpapers.previewColourLock = true;
            else if (!accepted)
                CortetsuWallpapers.previewColourLock = false;
        } else {
            cancelPreview();
            screenState.cortetsuState?.setRetained("wallpaperManager", false);
        }
    }

    function cancel(): void {
        CortetsuWallpapers.cancelApply();
        cosmicPulseTimer.stop();
        cosmicPulse = false;
        CortetsuWallpapers.previewColourLock = false;
        cancelPreview();
        screenState.cortetsuState?.setRetained("wallpaperManager", false);
    }

    // A click outside the panel. Nothing was applied, so say what happened
    // to the wallpaper the desktop was showing.
    function dismiss(): void {
        if (previewActive)
            CortetsuToaster.toast(qsTr("Vista previa descartada"), qsTr("El fondo anterior sigue aplicado"), "wallpaper");
        cancel();
    }

    function random(): void {
        if (applying)
            return;
        cancelPreview();
        const accepted = CortetsuWallpapers.applyRandom();
        if (accepted && CortetsuConfig.smartScheme)
            CortetsuWallpapers.previewColourLock = true;
        else if (!accepted)
            CortetsuWallpapers.previewColourLock = false;
    }

    function openFolder(): void {
        Quickshell.execDetached(["xdg-open", CortetsuWallpapers.wallsdir]);
        cancel();
    }

    function openManager(): void {
        // The catalog is read on demand; there is no background rescan.
        CortetsuWallpapers.reload();
        presentationReady = false;
        gridMode = false;
        query = "";
        searchBar.clear();
        resync(CortetsuWallpapers.actualCurrent);
        Qt.callLater(updatePresentationReady);
        keyTarget.forceActiveFocus();
    }

    function closeManager(): void { cancel(); }

    function returnToSettings(): void {
        cancelPreview();
        cosmicPulseTimer.stop();
        cosmicPulse = false;
        screenState.cortetsuState?.setRetained("wallpaperManager", false);
        SettingsController.select("wallpaper");
        Qt.callLater(() => root.screenState.settings = true);
    }

    onCurrentPathChanged: updateHero()
    onQueryChanged: {
        const keep = currentPath;
        cancelPreview();
        refilter(keep);
    }
    Component.onDestruction: {
        cosmicPulseTimer.stop();
        cancelPreview();
    }

    Timer {
        id: cosmicPulseTimer
        interval: CortetsuDesign.motionDeliberateMs
        repeat: false
        onTriggered: {
            root.cosmicPulse = false;
            root.screenState.cortetsuState?.setRetained("wallpaperManager", false);
        }
    }

    Timer {
        id: previewTimer
        interval: CortetsuDesign.wallUtilityOrbitMotionMs
        repeat: false
        onTriggered: {
            if (root.animating || root.queuedDirection) {
                restart();
                return;
            }
            if (Orbit.previewEligible(root.pendingPreviewPath, root.currentPath,
                                     root.screenState.cortetsuState?.wallpaperManager ?? false, root.animating, root.queuedDirection)) {
                CortetsuWallpapers.preview(root.pendingPreviewPath);
                root.previewActive = true;
            }
        }
    }

    NumberAnimation {
        id: orbitMotion
        target: root
        property: "orbitPhase"
        duration: CortetsuDesign.wallUtilityOrbitMotionMs
        easing.type: Easing.OutCubic
        onStopped: {
            root.windowIndex = root.currentIndex;
            root.orbitPhase = 0;
            root.animating = false;
            if (root.queuedDirection) {
                const direction = root.queuedDirection;
                root.queuedDirection = 0;
                root.requestMove(direction);
            }
        }
    }

    NumberAnimation {
        id: arcFade
        target: arcRegion
        property: "opacity"
        from: 0.2
        to: 1
        duration: CortetsuDesign.wallUtilityCrossfadeMotionMs
        easing.type: Easing.OutCubic
    }

    ParallelAnimation {
        id: heroCrossfade
        NumberAnimation { target: root; property: "newHeroOpacity"; to: 1; duration: CortetsuDesign.wallUtilityCrossfadeMotionMs; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "oldHeroOpacity"; to: 0; duration: CortetsuDesign.wallUtilityCrossfadeMotionMs; easing.type: Easing.OutCubic }
        onStopped: root.outgoingHeroPath = ""
    }

    Connections {
        target: CortetsuWallpapers
        // The applied wallpaper changed: follow it.
        function onActualCurrentChanged(): void { root.resync(CortetsuWallpapers.actualCurrent); }
        function onWallpaperApplySucceeded(path: string, generation: int): void {
            root.cosmicPulse = true;
            cosmicPulseTimer.restart();
            root.resync(CortetsuWallpapers.actualCurrent);
        }
        // The candidate stays selected so Reintentar has something to retry.
        function onWallpaperApplyFailed(path: string, generation: int): void { root.resync(root.currentPath); }
        function onListChanged(): void { root.resync(root.currentPath); }
    }

    Keys.onPressed: event => {
        const count = filteredEntries.length;
        const shift = event.modifiers & Qt.ShiftModifier;
        event.accepted = true;
        if (event.key === Qt.Key_Left) requestMove(-1);
        else if (event.key === Qt.Key_Right) requestMove(1);
        else if (event.key === Qt.Key_Up && gridMode && !shift) select(currentIndex - grid.columns);
        else if (event.key === Qt.Key_Down && gridMode && !shift) select(currentIndex + grid.columns);
        else if (event.key === Qt.Key_Up) cycleCategory(-1);
        else if (event.key === Qt.Key_Down) cycleCategory(1);
        else if (event.key === Qt.Key_Home) select(0);
        else if (event.key === Qt.Key_End) select(count - 1);
        else if (event.key === Qt.Key_PageUp) select(Math.max(0, currentIndex - visibleLimit));
        else if (event.key === Qt.Key_PageDown) select(Math.min(count - 1, currentIndex + visibleLimit));
        else if (event.key === Qt.Key_Tab) toggleGrid();
        else if (event.key === Qt.Key_Slash) searchBar.forceActiveFocus();
        else if (event.key === Qt.Key_R) random();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) apply();
        else if (event.key === Qt.Key_Escape) cancel();
        else event.accepted = false;
    }

    MouseArea { anchors.fill: parent; z: 0; onClicked: root.dismiss() }

    Repeater {
        id: prefetchRepeater
        model: root.prefetchEntries
        delegate: Image {
            required property var modelData
            width: 1
            height: 1
            opacity: 0
            source: modelData.path
            asynchronous: true
            sourceSize.width: 256
            sourceSize.height: 256
            cache: true
            onStatusChanged: root.updatePresentationReady()
        }
    }

    Rectangle {
        id: panelSurface
        z: 1
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 1040)
        height: Math.min(parent.height - 48, 760)
        radius: CortetsuDesign.wallUtilitySurfaceRadius
        color: Qt.alpha(CortetsuDesign.colorSurface, 0.84)
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.55)

        // Clicks and wheel turns inside the panel never reach the dismiss area.
        MouseArea {
            anchors.fill: parent
            onClicked: keyTarget.forceActiveFocus()
            onWheel: event => {
                if (!root.gridMode)
                    root.consumeWheel(event.angleDelta.y, event.pixelDelta.y);
                event.accepted = true;
            }
        }
    }

    Item {
        id: panel
        z: 2
        anchors.fill: panelSurface
        anchors.margins: CortetsuDesign.spacingComfortable

        Item { id: keyTarget; focus: true }

        Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 40

            CortetsuEvolvingMark {
                id: headerLogo
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                phase: root.markPhase
                monochrome: false
                accent: CortetsuColours.palette.m3primary
            }

            Column {
                anchors.left: headerLogo.right
                anchors.leftMargin: CortetsuDesign.spacingStandard
                anchors.right: searchBar.left
                anchors.rightMargin: CortetsuDesign.spacingStandard
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                CortetsuText {
                    text: qsTr("Wallpaper Orbital")
                    textSize: CortetsuTypography.titleMediumPx
                    font.weight: Font.DemiBold
                }
                CortetsuText {
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: root.libraryEmpty
                        ? (CortetsuWallpapers.scanning ? qsTr("Leyendo la biblioteca") : qsTr("Biblioteca vacía"))
                        : root.filteredEntries.length === root.entries.length
                            ? qsTr("%1 fondos").arg(root.entries.length)
                            : qsTr("%1 de %2 fondos").arg(root.filteredEntries.length).arg(root.entries.length)
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
            }

            CortetsuSearchBar {
                id: searchBar
                anchors.right: gridButton.left
                anchors.rightMargin: CortetsuDesign.spacingStandard
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(280, header.width * 0.3)
                compact: true
                enabled: !root.libraryEmpty
                placeholderText: qsTr("Buscar fondo")
                onTextChanged: root.query = text
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape && text.length > 0) {
                        clear();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
                        keyTarget.forceActiveFocus();
                        event.accepted = true;
                    }
                }
            }

            CortetsuButton {
                id: gridButton
                anchors.right: settingsButton.left
                anchors.rightMargin: CortetsuDesign.spacingCompact
                anchors.verticalCenter: parent.verticalCenter
                compact: true
                icon: root.gridMode ? "orbit" : "grid_view"
                label: ""
                active: root.gridMode
                disabled: root.libraryEmpty
                tooltipText: root.gridMode ? qsTr("Volver a la órbita") : qsTr("Ver la rejilla completa")
                onClicked: root.toggleGrid()
            }

            CortetsuButton {
                id: settingsButton
                anchors.right: closeButton.left
                anchors.rightMargin: CortetsuDesign.spacingCompact
                anchors.verticalCenter: parent.verticalCenter
                compact: true
                icon: "tune"
                label: ""
                tooltipText: qsTr("Ajustes de fondo")
                onClicked: root.returnToSettings()
            }

            CortetsuButton {
                id: closeButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                compact: true
                icon: "close"
                label: ""
                tooltipText: qsTr("Cerrar gestor de fondos")
                onClicked: root.cancel()
            }
        }

        Flickable {
            id: categoryStrip
            anchors.top: header.bottom
            anchors.topMargin: CortetsuDesign.spacingStandard
            anchors.left: parent.left
            anchors.right: parent.right
            height: 36
            visible: !root.libraryEmpty
            contentWidth: categoryRow.width
            contentHeight: height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: categoryRow
                spacing: CortetsuDesign.wallUtilityCategoryGap
                Repeater {
                    model: root.categoryCounts
                    delegate: CortetsuButton {
                        required property var modelData
                        compact: true
                        label: qsTr("%1  %2").arg(root.categoryLabel(modelData.name)).arg(modelData.count)
                        active: root.selectedCategory === modelData.name
                        onClicked: root.selectCategory(modelData.name)
                    }
                }
            }
        }

        Item {
            id: body
            anchors.top: categoryStrip.bottom
            anchors.topMargin: CortetsuDesign.wallUtilityOrbitTopGap
            anchors.bottom: footer.top
            anchors.bottomMargin: CortetsuDesign.wallUtilityOrbitBottomGap
            anchors.left: parent.left
            anchors.right: parent.right

            // Library states that leave nothing to browse.
            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 520)
                spacing: CortetsuDesign.spacingStandard
                visible: root.libraryEmpty || root.noResults

                CortetsuIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.noResults ? "search_off" : CortetsuWallpapers.scanning ? "hourglass_top" : "wallpaper"
                    iconSize: CortetsuTypography.iconExtraLargePx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
                CortetsuText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: root.noResults
                        ? (root.query.trim() ? qsTr("Sin resultados para «%1»").arg(root.query.trim()) : qsTr("Esta categoría está vacía"))
                        : CortetsuWallpapers.scanning
                            ? qsTr("Leyendo la biblioteca")
                            : qsTr("No hay fondos en esta carpeta")
                    textSize: CortetsuTypography.titleSmallPx
                }
                CortetsuText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAnywhere
                    visible: root.libraryEmpty
                    text: CortetsuWallpapers.wallsdir
                    color: CortetsuDesign.colorOnSurfaceVariant
                    textSize: CortetsuTypography.labelMediumPx
                }
                CortetsuButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.noResults || !CortetsuWallpapers.scanning
                    compact: true
                    icon: root.noResults ? "backspace" : "folder_open"
                    label: root.noResults ? qsTr("Quitar filtros") : qsTr("Abrir carpeta")
                    onClicked: {
                        if (!root.noResults) {
                            root.openFolder();
                            return;
                        }
                        searchBar.clear();
                        root.selectCategory("ALL");
                        keyTarget.forceActiveFocus();
                    }
                }
            }

            Item {
                id: stageRegion
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: arcRegion.top
                anchors.bottomMargin: CortetsuDesign.spacingStandard
                visible: !root.gridMode && !!root.currentPath

                WallpaperStage {
                    id: hero
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height * 16 / 9)
                    height: width * 9 / 16
                    source: root.heroPath
                    outgoingSource: root.outgoingHeroPath
                    sourceOpacity: root.newHeroOpacity
                    outgoingOpacity: root.oldHeroOpacity
                    appliedSource: root.currentIsApplied ? "" : CortetsuWallpapers.actualCurrent
                    applied: root.currentIsApplied
                    failed: root.currentFailed
                    title: Orbit.basename(root.currentPath)
                    stateLabel: root.currentStateLabel
                    detail: root.currentEntry
                        ? qsTr("%1  ·  %2 de %3").arg(root.categoryFor(root.currentEntry)).arg(root.currentIndex + 1).arg(root.filteredEntries.length)
                        : ""
                    errorText: root.currentFailed ? CortetsuWallpapers.applyError : ""
                    onStatusChanged: root.updatePresentationReady()
                }
            }

            // The wheel turns under the stage: the selected wallpaper sits at
            // the top and its neighbours fall away along the rim.
            Item {
                id: arcRegion
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                readonly property real tileWidth: Orbit.clamp(width / root.visibleLimit, 92, 132)
                readonly property real tileHeight: tileWidth * 9 / 16
                readonly property real radiusX: (width - tileWidth * 0.6) / 2 / Math.sin(root.arcSpan)
                readonly property real radiusY: 64
                height: tileHeight * 1.16 + radiusY * 0.5
                visible: !root.gridMode && !!root.currentPath

                Repeater {
                    model: root.orbitEntries
                    delegate: Item {
                        id: satellite
                        required property var modelData
                        readonly property real slot: modelData.offset - root.orbitPhase
                        readonly property real angle: Orbit.arcAngle(modelData.offset, root.orbitPhase, root.arcHalf + 1, root.arcSpan)
                        readonly property real depth: Orbit.arcDepth(angle, root.arcSpan)
                        readonly property bool hovered: satelliteMouse.containsMouse
                        readonly property real visualScale: 0.52 + depth * 0.48 + Math.max(0, 1 - Math.abs(slot)) * 0.1 + (hovered ? 0.04 : 0)
                        width: arcRegion.tileWidth
                        height: arcRegion.tileHeight
                        // The hitbox keeps its size; the visual layer carries
                        // the depth through scale, opacity and stacking.
                        scale: 1
                        visible: depth > 0
                        z: 2 + Math.round(depth * 8)
                        x: arcRegion.width / 2 + Math.cos(angle) * arcRegion.radiusX - width / 2
                        y: arcRegion.tileHeight * 0.08 + arcRegion.radiusY + Math.sin(angle) * arcRegion.radiusY

                        WallpaperTile {
                            anchors.fill: parent
                            scale: satellite.visualScale
                            opacity: satellite.hovered ? 1 : Math.min(1, satellite.depth * 4) * (0.34 + satellite.depth * 0.66)
                            source: satellite.modelData.entry.path
                            selected: satellite.modelData.index === root.currentIndex
                            applied: satellite.modelData.entry.path === CortetsuWallpapers.actualCurrent
                            hovered: satellite.hovered
                        }
                        MouseArea {
                            id: satelliteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                keyTarget.forceActiveFocus();
                                root.select(satellite.modelData.index);
                            }
                        }
                    }
                }
            }

            GridView {
                id: grid
                readonly property int columns: Math.max(1, Math.floor(width / 196))
                anchors.fill: parent
                visible: root.gridMode && !!root.currentPath
                clip: true
                cellWidth: width / columns
                cellHeight: cellWidth * 9 / 16
                model: visible ? root.filteredEntries : []
                currentIndex: root.currentIndex
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false
                highlightFollowsCurrentItem: false
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight

                    WallpaperTile {
                        anchors.fill: parent
                        anchors.margins: 5
                        source: cell.modelData.path
                        selected: cell.index === root.currentIndex
                        applied: cell.modelData.path === CortetsuWallpapers.actualCurrent
                        hovered: cellMouse.containsMouse
                    }
                    MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            keyTarget.forceActiveFocus();
                            root.select(cell.index);
                        }
                        onDoubleClicked: root.apply()
                    }
                }
            }
        }

        Item {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 36

            CortetsuText {
                anchors.left: parent.left
                anchors.right: actions.left
                anchors.rightMargin: CortetsuDesign.spacingStandard
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: root.gridMode
                    ? qsTr("Flechas mover  ·  Mayús+↑↓ categoría  ·  / buscar  ·  Tab órbita  ·  Enter aplicar  ·  R aleatorio  ·  Esc cerrar")
                    : qsTr("← → mover  ·  ↑ ↓ categoría  ·  / buscar  ·  Tab rejilla  ·  Enter aplicar  ·  R aleatorio  ·  Esc cerrar")
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }

            Row {
                id: actions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: CortetsuDesign.wallUtilityFooterGap
                CortetsuButton { compact: true; label: qsTr("Cancelar"); onClicked: root.cancel() }
                CortetsuButton { compact: true; icon: "shuffle"; label: qsTr("Aleatorio"); disabled: root.applying || root.libraryEmpty; onClicked: root.random() }
                CortetsuButton {
                    compact: true
                    icon: root.currentFailed ? "refresh" : ""
                    label: root.applying ? qsTr("Aplicando") : root.currentFailed ? qsTr("Reintentar") : qsTr("Aplicar")
                    active: true
                    disabled: root.applying || !root.currentPath
                    onClicked: root.apply()
                }
            }
        }
    }
}
