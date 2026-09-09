pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import ".."
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
    readonly property int visibleLimit: Math.max(1, Math.min(12, Math.floor((width - 104) / 102)))
    readonly property int orbitExcludedIndex: animating ? windowIndex : currentIndex
    readonly property var orbitEntries: Orbit.satellites(filteredEntries, windowIndex, orbitExcludedIndex, visibleLimit)
    readonly property var prefetchEntries: Orbit.prefetch(filteredEntries, currentIndex, visibleLimit + 6)
    readonly property var currentEntry: currentIndex >= 0 ? filteredEntries[currentIndex] : null
    readonly property string currentPath: currentEntry?.path ?? ""
    readonly property bool currentApplied: !!currentPath && currentPath === CortetsuWallpapers.actualCurrent
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
        const stableOrbitCount = Math.max(1, orbitEntries.length);
        animating = true;
        currentIndex = target;
        updateHero();
        queuePreview();
        orbitMotion.to = -steps * Orbit.angularStep(stableOrbitCount);
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
        if (!currentPath)
            return;
        previewTimer.stop();
        pendingPreviewPath = "";
        if (CortetsuWallpapers.actualCurrent !== currentPath) {
            if (CortetsuConfig.smartScheme)
                CortetsuWallpapers.previewColourLock = true;
            if (previewActive || CortetsuWallpapers.showPreview)
                CortetsuWallpapers.stopPreview();
            previewActive = false;
            CortetsuWallpapers.setWallpaper(currentPath);
        } else {
            cancelPreview();
        }
        screenState.cortetsuState?.setRetained("wallpaperManager", false);
    }

    function cancel(): void {
        cancelPreview();
        screenState.cortetsuState?.setRetained("wallpaperManager", false);
    }

    function random(): void {
        cancelPreview();
        CortetsuWallpapers.setRandom();
        screenState.cortetsuState?.setRetained("wallpaperManager", false);
    }

    function openManager(): void {
        presentationReady = false;
        resync();
        Qt.callLater(updatePresentationReady);
        forceActiveFocus();
    }

    function closeManager(): void { cancelPreview(); }

    component OrbitButton: CortetsuSurface {
        id: button

        required property string label
        property string icon
        property bool checked: false
        property bool primary: false
        signal clicked()

        outlined: false
        active: checked || primary
        baseColor: "transparent"
        implicitWidth: buttonRow.implicitWidth + CortetsuDesign.spacingStandard * 2
        implicitHeight: 34

        Row {
            id: buttonRow
            anchors.centerIn: parent
            spacing: CortetsuDesign.spacingCompact

            CortetsuIcon {
                visible: button.icon.length > 0
                text: button.icon
                iconSize: CortetsuTypography.iconSmallPx
                color: CortetsuDesign.colorOnSurface
            }
            CortetsuText {
                text: button.label
                textSize: CortetsuTypography.labelMediumPx
                color: CortetsuDesign.colorOnSurface
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: button.hovered = containsMouse
            onPressedChanged: button.pressed = pressed
            onClicked: button.clicked()
        }
    }

    onCurrentPathChanged: updateHero()
    Component.onDestruction: cancelPreview()

    Timer {
        id: previewTimer
        interval: 260
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
        duration: 340
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

    ParallelAnimation {
        id: heroCrossfade
        NumberAnimation { target: root; property: "newHeroOpacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "oldHeroOpacity"; to: 0; duration: 240; easing.type: Easing.OutCubic }
        onStopped: root.outgoingHeroPath = ""
    }

    Connections {
        target: CortetsuWallpapers
        function onActualCurrentChanged(): void { root.resync(); }
        function onListChanged(): void { root.resync(); }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) { requestMove(-1); event.accepted = true; }
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) { requestMove(1); event.accepted = true; }
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
            anchors.top: parent.top
            anchors.topMargin: 0
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
                    delegate: OrbitButton {
                        required property string modelData
                        label: modelData
                        checked: root.selectedCategory === modelData
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
                scale: root.animating ? 0.985 : 1
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

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

                Rectangle {
                    z: 5
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 12
                    implicitWidth: heroStateLabel.implicitWidth + 16
                    implicitHeight: 26
                    radius: 13
                    color: root.currentApplied ? Qt.alpha(CortetsuDesign.colorSuccess, 0.92) : Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.94)
                    border.width: 1
                    border.color: Qt.alpha(root.currentApplied ? CortetsuDesign.colorSuccess : CortetsuDesign.colorPrimary, 0.82)
                    CortetsuText {
                        id: heroStateLabel
                        anchors.centerIn: parent
                        text: heroImage.status === Image.Loading ? qsTr("Loading") : (root.currentApplied ? qsTr("Applied") : qsTr("Selected"))
                        textSize: CortetsuTypography.labelSmallPx
                        font.weight: Font.DemiBold
                        color: CortetsuDesign.colorOnSurface
                    }
                }

                Shape {
                    id: heroOutline
                    anchors.fill: parent
                    z: 4
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: root.currentApplied ? Qt.alpha(CortetsuDesign.colorSuccess, 0.9) : Qt.alpha(CortetsuDesign.colorPrimary, 0.84)
                        strokeWidth: root.currentApplied ? 1.8 : 1.25
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
                    readonly property bool selected: satellite.modelData.index === root.currentIndex
                    readonly property bool applied: satellite.modelData.entry.path === CortetsuWallpapers.actualCurrent
                    width: 82
                    height: 82
                    scale: selected ? 1.18 : (hovered ? 1.12 : 0.68 + depth * 0.40)
                    opacity: selected || hovered ? 1 : 0.36 + depth * 0.64
                    z: selected ? 14 : 2 + Math.round(depth * 8)
                    x: orbitRegion.width / 2 + Math.cos(angle) * radiusX - width / 2
                    y: orbitRegion.height / 2 + Math.sin(angle) * radiusY - height / 2
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

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
                            strokeColor: satellite.selected ? CortetsuDesign.colorTertiary : (satellite.applied ? CortetsuDesign.colorSuccess : (satellite.hovered ? CortetsuDesign.colorPrimary : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.72)))
                            strokeWidth: satellite.selected ? 2 : (satellite.applied || satellite.hovered ? 1.5 : 1)
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
                    Rectangle {
                        visible: satellite.selected || satellite.applied
                        z: 4
                        width: 10
                        height: 10
                        radius: 5
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 5
                        color: satellite.selected ? CortetsuDesign.colorTertiary : CortetsuDesign.colorSuccess
                        border.width: 2
                        border.color: CortetsuDesign.colorSurface
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
                text: root.currentEntry ? qsTr("%1  ·  %2  ·  %3/%4").arg(root.currentApplied ? qsTr("Applied") : (root.previewActive ? qsTr("Previewing") : qsTr("Selected"))).arg(root.categoryFor(root.currentEntry)).arg(root.currentIndex + 1).arg(root.filteredEntries.length) : qsTr("Add images to the native wallpaper directory")
                horizontalAlignment: Text.AlignHCenter
                color: CortetsuDesign.colorOnSurfaceVariant
                textSize: CortetsuTypography.labelMediumPx
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                OrbitButton { label: qsTr("Cancel"); onClicked: root.cancel() }
                OrbitButton { icon: "shuffle"; label: qsTr("Random"); onClicked: root.random() }
                OrbitButton { label: root.currentApplied ? qsTr("Applied") : qsTr("Apply"); primary: !root.currentApplied; checked: root.currentApplied; onClicked: root.apply() }
            }
        }
    }
}
