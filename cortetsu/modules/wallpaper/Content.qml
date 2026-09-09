pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import ".."
import "../../components"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import "OrbitModel.js" as Orbit

FocusScope {
    id: root

    required property var screen
    required property var screenState
    property var entries: CortetsuWallpapers.list ? Array.from(CortetsuWallpapers.list) : []
    property var filteredEntries: Orbit.filtered(entries, selectedCategory, categoryFor)
    property var categoryNames: Orbit.categories(entries, categoryFor)
    property string selectedCategory: "ALL"
    property int currentIndex: -1
    property int windowIndex: -1
    property int queuedDirection: 0
    property bool animating: false
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
    property bool cosmicPulse: false
    readonly property int visibleLimit: Math.max(1, Math.min(12, Math.floor((width - 104) / 102)))
    // Keep the orbit model anchored to the last settled selection while a
    // transition is running.  The newly selected wallpaper stays visible as
    // a satellite until the rotation has completed, instead of disappearing
    // when currentIndex changes.
    readonly property var orbitEntries: Orbit.satellites(filteredEntries, windowIndex, windowIndex, visibleLimit)
    readonly property var prefetchEntries: Orbit.prefetch(filteredEntries, currentIndex, visibleLimit + 6)
    readonly property var currentEntry: currentIndex >= 0 ? filteredEntries[currentIndex] : null
    readonly property string currentPath: currentEntry?.path ?? ""
    readonly property bool currentIsApplied: !!currentPath && currentPath === CortetsuWallpapers.actualCurrent
    readonly property string currentStateLabel: applying
        ? qsTr("Applying")
        : applyFailed
            ? qsTr("Apply failed")
            : currentIsApplied
                ? qsTr("Applied")
                : (previewActive ? qsTr("Previewing") : qsTr("Selected"))
    readonly property string markPhase: cosmicPulse
        ? "Cosmic"
        : currentIsApplied
            ? "Ascended"
            : currentPath
                ? "Awakening"
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
        if (!presentationReady && (heroImage.status === Image.Ready || heroImage.status === Image.Error) && essentialReady())
            presentationReady = true;
    }

    function categoryFor(entry): string { return CortetsuWallpapers.getCategoryFor(entry) || qsTr("Unsorted"); }

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

    function resync(): void {
        cancelPreview();
        entries = CortetsuWallpapers.list ? Array.from(CortetsuWallpapers.list) : [];
        categoryNames = Orbit.categories(entries, categoryFor);
        if (!categoryNames.includes(selectedCategory))
            selectedCategory = "ALL";
        filteredEntries = Orbit.filtered(entries, selectedCategory, categoryFor);
        const actual = Orbit.resolveCurrentIndex(filteredEntries, CortetsuWallpapers.actualCurrent);
        currentIndex = Orbit.normalize(actual >= 0 ? actual : 0, filteredEntries.length);
        windowIndex = currentIndex;
        queuedDirection = 0;
        orbitPhase = 0;
        updateHero();
    }

    function queuePreview(): void {
        pendingPreviewPath = currentPath;
        if (pendingPreviewPath)
            previewTimer.restart();
    }

    function requestMove(direction): void {
        if (filteredEntries.length < 2)
            return;
        requestTarget(Orbit.move(currentIndex, direction, filteredEntries.length), direction);
    }

    function requestTarget(target, replacementDirection): void {
        cancelPreview();
        if (animating) {
            queuedDirection = replacementDirection;
            return;
        }
        animateTo(target);
    }

    function consumeWheel(angleDelta, pixelDelta): void {
        const intent = Orbit.wheelIntent(wheelAccumulator, angleDelta, pixelDelta);
        wheelAccumulator = intent.accumulator;
        if (intent.direction)
            requestMove(intent.direction);
    }

    function animateTo(target): void {
        const count = filteredEntries.length;
        if (!count || target === currentIndex || animating)
            return;
        const steps = Orbit.shortestSteps(currentIndex, target, count);
        if (!steps)
            return;
        animating = true;
        currentIndex = target;
        updateHero();
        queuePreview();
        // Accumulate the phase. Resetting it after every move caused the
        // model reorder to snap back to its initial geometry.
        orbitMotion.to = orbitPhase - steps * Orbit.angularStep(Math.max(2, orbitEntries.length + 1));
        orbitMotion.restart();
    }

    function selectSatellite(target): void {
        const direction = Orbit.shortestSteps(currentIndex, target, filteredEntries.length);
        if (direction)
            requestTarget(target, Math.sign(direction));
    }

    function selectCategory(category): void {
        cancelPreview();
        selectedCategory = category;
        filteredEntries = Orbit.filtered(entries, category, categoryFor);
        const actual = Orbit.resolveCurrentIndex(filteredEntries, CortetsuWallpapers.actualCurrent);
        currentIndex = Orbit.normalize(actual >= 0 ? actual : 0, filteredEntries.length);
        windowIndex = currentIndex;
        queuedDirection = 0;
        orbitPhase = 0;
        updateHero();
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

    function openManager(): void {
        presentationReady = false;
        resync();
        Qt.callLater(updatePresentationReady);
        forceActiveFocus();
    }

    function closeManager(): void { cancel(); }

    onCurrentPathChanged: updateHero()
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
        interval: 220
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
        duration: 220
        easing.type: Easing.OutCubic
        onStopped: {
            root.windowIndex = root.currentIndex;
            root.animating = false;
            if (root.queuedDirection) {
                const direction = root.queuedDirection;
                root.queuedDirection = 0;
                root.requestMove(direction);
            }
        }
    }

    ParallelAnimation {
        id: heroCrossfade
        NumberAnimation { target: root; property: "newHeroOpacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "oldHeroOpacity"; to: 0; duration: 180; easing.type: Easing.OutCubic }
        onStopped: root.outgoingHeroPath = ""
    }

    Connections {
        target: CortetsuWallpapers
        function onActualCurrentChanged(): void {
            root.resync();
        }
        function onWallpaperApplySucceeded(path: string, generation: int): void {
            root.cosmicPulse = true;
            cosmicPulseTimer.restart();
            root.resync();
        }
        function onWallpaperApplyFailed(path: string, generation: int): void { root.resync(); }
        function onListChanged(): void { root.resync(); }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left) { requestMove(-1); event.accepted = true; }
        else if (event.key === Qt.Key_Right) { requestMove(1); event.accepted = true; }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { apply(); event.accepted = true; }
        else if (event.key === Qt.Key_Escape) { cancel(); event.accepted = true; }
    }

    MouseArea { anchors.fill: parent; z: 0; onClicked: root.cancel() }

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
            sourceSize.width: 128
            sourceSize.height: 128
            cache: true
            onStatusChanged: root.updatePresentationReady()
        }
    }

    Item {
        id: panel
        z: 1
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 900)
        height: Math.min(parent.height - 48, 680)

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
                monochromeColor: CortetsuDesign.colorWashi
            }

            Column {
                anchors.left: headerLogo.right
                anchors.leftMargin: CortetsuDesign.spacingStandard
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                CortetsuText {
                    text: qsTr("Wallpaper Forge")
                    textSize: CortetsuTypography.titleMediumPx
                    font.weight: Font.DemiBold
                }
                CortetsuText {
                    text: qsTr("Wallpaper-aware desktop surface")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
            }

            CortetsuButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                compact: true
                icon: "close"
                label: ""
                tooltipText: qsTr("Close Wallpaper Manager")
                onClicked: root.cancel()
            }
        }

        Rectangle {
            anchors.fill: categoryStrip
            anchors.leftMargin: -8
            anchors.rightMargin: -8
            anchors.topMargin: -8
            anchors.bottomMargin: -4
            radius: CortetsuDesign.radiusLarge
            color: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.68)
            border.width: 1
            border.color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.55)
        }

        Flickable {
            id: categoryStrip
            anchors.top: header.bottom
            anchors.topMargin: CortetsuDesign.spacingCompact
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(categoryRow.width, parent.width - 40)
            height: 36
            contentWidth: categoryRow.width
            contentHeight: height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: categoryRow
                spacing: 6
                Repeater {
                    model: root.categoryNames
                    delegate: CortetsuButton {
                        required property string modelData
                        compact: true
                        label: modelData
                        active: root.selectedCategory === modelData
                        onClicked: root.selectCategory(modelData)
                    }
                }
            }
        }

        Item {
            id: orbitRegion
            anchors.top: categoryStrip.bottom
            anchors.topMargin: 56
            anchors.bottom: footerSurface.top
            anchors.bottomMargin: 70
            anchors.left: parent.left
            anchors.right: parent.right

            MouseArea {
                anchors.fill: parent
                onWheel: event => {
                    root.consumeWheel(event.angleDelta.y, event.pixelDelta.y);
                    event.accepted = true;
                }
            }

            Shape {
                id: heroMask
                z: 1
                anchors.centerIn: hero
                width: hero.width
                height: hero.height
                layer.enabled: true
                visible: true
                ShapePath {
                    fillColor: CortetsuDesign.colorSurface
                    startX: heroMask.width * 0.28; startY: 0
                    PathLine { x: heroMask.width * 0.72; y: 0 }
                    PathLine { x: heroMask.width; y: heroMask.height * 0.28 }
                    PathLine { x: heroMask.width; y: heroMask.height * 0.72 }
                    PathLine { x: heroMask.width * 0.72; y: heroMask.height }
                    PathLine { x: heroMask.width * 0.28; y: heroMask.height }
                    PathLine { x: 0; y: heroMask.height * 0.72 }
                    PathLine { x: 0; y: heroMask.height * 0.28 }
                    PathLine { x: heroMask.width * 0.28; y: 0 }
                }
            }

            Item {
                id: hero
                z: 3
                anchors.centerIn: parent
                width: Math.min(parent.width * 0.38, 330)
                height: Math.min(parent.height * 0.76, 340)

                Image {
                    anchors.fill: parent
                    source: root.outgoingHeroPath
                    opacity: root.oldHeroOpacity
                    asynchronous: true
                    sourceSize.width: 640
                    sourceSize.height: 640
                    fillMode: Image.PreserveAspectCrop
                    cache: true
                    mipmap: true
                    retainWhileLoading: true
                    layer.enabled: true
                    layer.effect: CortetsuMask { maskSource: heroMask }
                }
                Image {
                    id: heroImage
                    anchors.fill: parent
                    source: root.heroPath
                    opacity: root.newHeroOpacity
                    asynchronous: true
                    sourceSize.width: 640
                    sourceSize.height: 640
                    fillMode: Image.PreserveAspectCrop
                    cache: true
                    mipmap: true
                    retainWhileLoading: true
                    layer.enabled: true
                    layer.effect: CortetsuMask { maskSource: heroMask }
                    onStatusChanged: root.updatePresentationReady()
                    CortetsuIcon {
                        anchors.centerIn: parent
                        visible: parent.status === Image.Error
                        text: "broken_image"
                        color: CortetsuDesign.colorOnSurfaceVariant
                        iconSize: CortetsuTypography.iconExtraLargePx
                    }
                }

                Shape {
                    id: heroOutline
                    anchors.fill: parent
                    z: 4
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: root.currentIsApplied ? CortetsuDesign.colorSecondary : CortetsuDesign.colorPrimary
                        strokeWidth: 2
                        startX: heroOutline.width * 0.28; startY: 0
                        PathLine { x: heroOutline.width * 0.72; y: 0 }
                        PathLine { x: heroOutline.width; y: heroOutline.height * 0.28 }
                        PathLine { x: heroOutline.width; y: heroOutline.height * 0.72 }
                        PathLine { x: heroOutline.width * 0.72; y: heroOutline.height }
                        PathLine { x: heroOutline.width * 0.28; y: heroOutline.height }
                        PathLine { x: 0; y: heroOutline.height * 0.72 }
                        PathLine { x: 0; y: heroOutline.height * 0.28 }
                        PathLine { x: heroOutline.width * 0.28; y: 0 }
                    }
                }

                CortetsuSurface {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    implicitWidth: heroStateText.implicitWidth + 24
                    implicitHeight: 30
                    radiusValue: CortetsuDesign.radiusSmall
                    baseColor: root.currentIsApplied
                        ? Qt.alpha(CortetsuDesign.colorSecondaryContainer, 0.92)
                        : Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.92)
                    outlined: true
                    outlineColor: root.currentIsApplied
                        ? Qt.alpha(CortetsuDesign.colorSecondary, 0.72)
                        : Qt.alpha(CortetsuDesign.colorPrimary, 0.72)
                    CortetsuText {
                        id: heroStateText
                        anchors.centerIn: parent
                        text: root.currentStateLabel
                        textSize: CortetsuTypography.labelSmallPx
                        color: root.currentIsApplied
                            ? CortetsuDesign.colorOnSecondaryContainer
                            : CortetsuDesign.colorOnPrimaryContainer
                    }
                }
            }

            Repeater {
                model: root.orbitEntries
                delegate: Item {
                    id: satellite
                    required property var modelData
                    required property int index
                    readonly property real angle: Orbit.satelliteAngle(index, root.orbitEntries.length, root.orbitPhase)
                    readonly property real depth: (Math.sin(angle) + 1) / 2
                    readonly property real radiusX: Math.min(orbitRegion.width * 0.42, 265)
                    readonly property real radiusY: Math.min(orbitRegion.height * 0.52, 195)
                    readonly property bool hovered: satelliteMouse.containsMouse
                    width: 78
                    height: 78
                    readonly property real visualScale: hovered ? 0.94 + depth * 0.24 : 0.78 + depth * 0.28
                    // The satellite keeps a fixed hitbox while its visual
                    // layer communicates orbital depth through scale.
                    scale: 1
                    opacity: 1
                    z: 2 + Math.round(depth * 8)
                    x: orbitRegion.width / 2 + Math.cos(angle) * radiusX - width / 2
                    y: orbitRegion.height / 2 + Math.sin(angle) * radiusY - height / 2

                    Item {
                        id: satelliteVisual
                        anchors.fill: parent
                        scale: satellite.visualScale
                        opacity: satellite.hovered ? 1 : 0.28 + satellite.depth * 0.72

                        Shape {
                            id: satelliteMask
                            z: 1
                            anchors.fill: parent
                            layer.enabled: true
                            visible: true
                            ShapePath {
                                fillColor: CortetsuDesign.colorSurface
                                startX: satelliteMask.width * 0.28; startY: 0
                                PathLine { x: satelliteMask.width * 0.72; y: 0 }
                                PathLine { x: satelliteMask.width; y: satelliteMask.height * 0.28 }
                                PathLine { x: satelliteMask.width; y: satelliteMask.height * 0.72 }
                                PathLine { x: satelliteMask.width * 0.72; y: satelliteMask.height }
                                PathLine { x: satelliteMask.width * 0.28; y: satelliteMask.height }
                                PathLine { x: 0; y: satelliteMask.height * 0.72 }
                                PathLine { x: 0; y: satelliteMask.height * 0.28 }
                                PathLine { x: satelliteMask.width * 0.28; y: 0 }
                            }
                        }
                        Image {
                            z: 2
                            anchors.fill: parent
                            source: satellite.modelData.entry.path
                            asynchronous: true
                            sourceSize.width: 128
                            sourceSize.height: 128
                            fillMode: Image.PreserveAspectCrop
                            cache: true
                            mipmap: true
                            retainWhileLoading: true
                            layer.enabled: true
                            layer.effect: CortetsuMask { maskSource: satelliteMask }
                        }
                        Shape {
                            id: satelliteOutline
                            anchors.fill: parent
                            z: 3
                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: satellite.hovered ? CortetsuDesign.colorPrimary : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.72)
                                strokeWidth: satellite.hovered ? 1.5 : 1
                                startX: satelliteOutline.width * 0.28; startY: 0
                                PathLine { x: satelliteOutline.width * 0.72; y: 0 }
                                PathLine { x: satelliteOutline.width; y: satelliteOutline.height * 0.28 }
                                PathLine { x: satelliteOutline.width; y: satelliteOutline.height * 0.72 }
                                PathLine { x: satelliteOutline.width * 0.72; y: satelliteOutline.height }
                                PathLine { x: satelliteOutline.width * 0.28; y: satelliteOutline.height }
                                PathLine { x: 0; y: satelliteOutline.height * 0.72 }
                                PathLine { x: 0; y: satelliteOutline.height * 0.28 }
                                PathLine { x: satelliteOutline.width * 0.28; y: 0 }
                            }
                        }
                    }
                    MouseArea {
                        id: satelliteMouse
                        z: 5
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectSatellite(satellite.modelData.index)
                    }
                }
            }
        }

        Rectangle {
            id: footerSurface
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            width: Math.min(500, parent.width - 40)
            height: footer.height + 24
            radius: CortetsuDesign.radiusLarge
            color: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.68)
            border.width: 1
            border.color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.55)
        }

        Column {
            id: footer
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 7

            CortetsuText {
                width: Math.min(440, panel.width - 48)
                text: root.currentPath ? root.currentPath.split("/").pop() : qsTr("No readable wallpapers found")
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                color: CortetsuDesign.colorOnSurface
                textSize: CortetsuTypography.titleSmallPx
            }
            CortetsuText {
                width: Math.min(440, panel.width - 48)
                text: root.currentEntry ? qsTr("%1  ·  %2  ·  %3/%4").arg(root.currentPath === CortetsuWallpapers.actualCurrent ? qsTr("Current") : qsTr("Preview")).arg(root.categoryFor(root.currentEntry)).arg(root.currentIndex + 1).arg(root.filteredEntries.length) : qsTr("Add images to the native wallpaper directory")
                horizontalAlignment: Text.AlignHCenter
                color: CortetsuDesign.colorOnSurfaceVariant
                textSize: CortetsuTypography.labelMediumPx
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                CortetsuButton { compact: true; label: qsTr("Cancel"); onClicked: root.cancel() }
                CortetsuButton { compact: true; icon: "shuffle"; label: qsTr("Random"); disabled: root.applying; onClicked: root.random() }
                CortetsuButton { compact: true; label: root.applying ? qsTr("Applying") : qsTr("Apply"); active: true; disabled: root.applying; onClicked: root.apply() }
            }
        }
    }
}
