pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtCore
import Quickshell
import Quickshell.Io
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

FocusScope {
    id: root

    required property ShellScreen screen
    required property var screenState
    required property bool clipboardVisible

    property var history: []
    property string query: ""
    property bool pinnedOnly: false
    property int selectedIndex: -1
    property string statusText: ""

    readonly property url historyPath:
        StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/clipse/clipboard_history.json"

    // Opaque first-party surfaces keep clipboard content readable over any wallpaper.
    readonly property color panelSurface: CortetsuDesign.colorSurfaceHigh
    readonly property color elevatedSurface: Qt.lighter(panelSurface, 1.08)
    readonly property color cardSurface: CortetsuDesign.colorSurface
    readonly property color hoverSurface: Qt.lighter(cardSurface, 1.12)
    readonly property color textPrimary: CortetsuDesign.colorOnSurface
    readonly property color textMuted: CortetsuDesign.colorOnSurfaceVariant
    readonly property color accent: CortetsuDesign.colorPrimary

    readonly property color accentSoft:
        Qt.alpha(accent, 0.14)

    readonly property color accentOutline:
        Qt.alpha(accent, 0.34)

    readonly property var filteredEntries: {
        const needle = query.trim().toLowerCase();
        const output = [];

        for (let i = 0; i < history.length; ++i) {
            const item = history[i];
            if (!item)
                continue;

            if (pinnedOnly && !item.pinned)
                continue;

            const value = String(item.value ?? "");
            const recorded = String(item.recorded ?? "");
            const isImage = item.filePath && item.filePath !== "null";
            const haystack =
                `${value} ${recorded} ${isImage ? "image" : "text"}`.toLowerCase();

            if (needle.length === 0 || haystack.includes(needle))
                output.push({ item: item, originalIndex: i });
        }

        return output;
    }

    readonly property var selectedEntry:
        selectedIndex >= 0 && selectedIndex < filteredEntries.length
            ? filteredEntries[selectedIndex]
            : null

    function reloadHistory(): void {
        if (!historyFile.loaded)
            return;

        try {
            const raw = historyFile.text();

            if (!raw || raw.trim().length === 0) {
                history = [];
                selectedIndex = -1;
                return;
            }

            const parsed = JSON.parse(raw);
            const input = Array.isArray(parsed.clipboardHistory)
                ? parsed.clipboardHistory
                : [];
            const valid = [];

            for (const item of input) {
                if (
                    !item ||
                    typeof item !== "object" ||
                    item.value === undefined ||
                    item.recorded === undefined
                ) {
                    continue;
                }

                valid.push({
                    value: item.value,
                    recorded: item.recorded,
                    pinned: Boolean(item.pinned),
                    filePath:
                        typeof item.filePath === "string"
                            ? item.filePath
                            : null
                });
            }

            valid.sort(
                (a, b) =>
                    String(b.recorded).localeCompare(String(a.recorded))
            );

            history = valid;

            if (filteredEntries.length === 0)
                selectedIndex = -1;
            else if (
                selectedIndex < 0 ||
                selectedIndex >= filteredEntries.length
            )
                selectedIndex = 0;
        } catch (error) {
            statusText = qsTr("Could not read Clipse history");
            console.warn(`Clipboard QML: failed to parse history: ${error}`);
        }
    }

    function saveHistory(): void {
        try {
            historyFile.setText(
                JSON.stringify({ clipboardHistory: history }, null, 2)
            );
        } catch (error) {
            statusText = qsTr("Could not save clipboard history");
            console.warn(`Clipboard QML: failed to save history: ${error}`);
        }
    }

    function normalizeSelection(): void {
        if (filteredEntries.length === 0) {
            selectedIndex = -1;
            return;
        }

        selectedIndex = Math.max(
            0,
            Math.min(
                selectedIndex < 0 ? 0 : selectedIndex,
                filteredEntries.length - 1
            )
        );

        Qt.callLater(
            () => list.positionViewAtIndex(selectedIndex, ListView.Contain)
        );
    }

    function moveSelection(delta): void {
        if (filteredEntries.length === 0)
            return;

        let idx = selectedIndex;

        if (idx < 0)
            idx = 0;
        else
            idx =
                (idx + delta + filteredEntries.length) %
                filteredEntries.length;

        selectedIndex = idx;

        Qt.callLater(
            () => list.positionViewAtIndex(selectedIndex, ListView.Contain)
        );
    }

    function copyEntry(entry): void {
        if (!entry)
            return;

        const item = entry.item;
        const path = String(item.filePath ?? "");

        if (path.length > 0 && path !== "null") {
            Quickshell.execDetached([
                "sh",
                "-c",
                'mime="$(file --brief --mime-type -- "$1")"; wl-copy --type "$mime" < "$1"',
                "sh",
                path
            ]);
        } else {
            Quickshell.clipboardText = String(item.value ?? "");
        }

        statusText = qsTr("Copied");
        screenState.cortetsuState?.setRetained("clipboard", false);
    }

    function deleteEntry(entry): void {
        if (!entry)
            return;

        const idx = entry.originalIndex;

        if (idx < 0 || idx >= history.length)
            return;

        const next = history.slice();
        next.splice(idx, 1);
        history = next;
        saveHistory();
        normalizeSelection();
        statusText = qsTr("Removed");
    }

    function togglePin(entry): void {
        if (!entry)
            return;

        const idx = entry.originalIndex;

        if (idx < 0 || idx >= history.length)
            return;

        const next = history.slice();
        const copy = Object.assign({}, next[idx]);
        copy.pinned = !Boolean(copy.pinned);
        next[idx] = copy;
        history = next;
        saveHistory();
        normalizeSelection();
        statusText = copy.pinned ? qsTr("Pinned") : qsTr("Unpinned");
    }

    function clearNonPinned(): void {
        history = history.filter(item => Boolean(item.pinned));
        saveHistory();
        selectedIndex = filteredEntries.length > 0 ? 0 : -1;
        statusText = qsTr("History cleared; pinned items kept");
    }

    function openClipboard(): void {
        historyFile.reload();
        normalizeSelection();

        Qt.callLater(() => {
            searchInput.forceActiveFocus();
            searchInput.selectAll();
        });
    }

    onClipboardVisibleChanged: {
        if (clipboardVisible)
            Qt.callLater(openClipboard);
    }

    onQueryChanged: {
        selectedIndex = filteredEntries.length > 0 ? 0 : -1;
        normalizeSelection();
    }

    onPinnedOnlyChanged: {
        selectedIndex = filteredEntries.length > 0 ? 0 : -1;
        normalizeSelection();
    }

    FileView {
        id: historyFile

        path: root.historyPath
        watchChanges: true
        atomicWrites: true
        printErrors: true

        onFileChanged: reload()
        onTextChanged: root.reloadHistory()
        onLoaded: root.reloadHistory()

        onSaveFailed: error => {
            root.statusText = qsTr("Failed to save history");
            console.warn(`Clipboard QML save error: ${error}`);
        }
    }

    Keys.onEscapePressed:
        screenState.cortetsuState?.setRetained("clipboard", false)

    Keys.onUpPressed:
        moveSelection(-1)

    Keys.onDownPressed:
        moveSelection(1)

    Keys.onReturnPressed:
        copyEntry(selectedEntry)

    Keys.onEnterPressed:
        copyEntry(selectedEntry)

    Keys.onDeletePressed:
        deleteEntry(selectedEntry)

    Keys.onPressed: event => {
        if (
            event.key === Qt.Key_F &&
            (event.modifiers & Qt.ControlModifier)
        ) {
            searchInput.forceActiveFocus();
            searchInput.selectAll();
            event.accepted = true;
            return;
        }

        if (
            event.key === Qt.Key_P &&
            !(event.modifiers & Qt.ControlModifier)
        ) {
            togglePin(selectedEntry);
            event.accepted = true;
        }
    }

    /*
     * Clicking the dimmed desktop closes Clipboard. This stays below the real
     * panel so touchpad/mouse interaction inside the panel remains native.
     */
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
            const outsidePanel =
                mouse.x < panel.x ||
                mouse.x >= panel.x + panel.width ||
                mouse.y < panel.y ||
                mouse.y >= panel.y + panel.height;

            if (outsidePanel)
                root.screenState.cortetsuState?.setRetained("clipboard", false);
        }
    }

    /*
     * One soft shadow + one accent halo. The actual panel surface below is
     * fully opaque; only these decorative layers use alpha.
     */
    Rectangle {
        x: panel.x + 2
        y: panel.y + 12
        width: panel.width
        height: panel.height
        radius: panel.radius
        color: Qt.alpha(CortetsuDesign.colorScrim, 0.44)
    }

    Rectangle {
        x: panel.x - 3
        y: panel.y - 3
        width: panel.width + 6
        height: panel.height + 6
        radius: panel.radius + 3
        color: Qt.alpha(root.accent, 0.08)
        border.width: 1
        border.color: Qt.alpha(root.accent, 0.22)
    }

    Rectangle {
        id: panel

        width: Math.min(910, parent.width - 88)
        height: Math.min(770, parent.height - 96)

        // True monitor center. The host already spans the monitor, so no side offset is needed.
        // ContentWindow already spans the monitor and the previous -105px bias
        // is exactly what pushed Clipboard to the left.
        x: Math.round((parent.width - width) / 2)

        y: Math.max(
            32,
            Math.round((parent.height - height) / 2)
        )

        radius: 30
        color: root.panelSurface
        border.width: 1
        border.color: root.accentOutline
        clip: true

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            propagateComposedEvents: false
        }

        Column {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 13

            Row {
                id: header

                width: parent.width
                height: 62
                spacing: 14

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 54
                    height: 54
                    radius: CortetsuDesign.radiusLarge
                    color: root.accentSoft
                    border.width: 1
                    border.color: Qt.alpha(root.accent, 0.26)

                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: "content_paste_search"
                        color: root.accent
                        iconSize: CortetsuTypography.iconExtraLargePx
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(
                        180,
                        parent.width -
                        filterBar.width -
                        82
                    )
                    spacing: 0

                    CortetsuText {
                        text: qsTr("Clipboard")
                        color: root.textPrimary
                        textSize: CortetsuTypography.titleLargePx
                    }

                    CortetsuText {
                        text:
                            qsTr("%1 items · Clipse backend")
                                .arg(root.filteredEntries.length)
                        color: root.textMuted
                        textSize: CortetsuTypography.labelMediumPx
                    }
                }

                Rectangle {
                    id: filterBar

                    anchors.verticalCenter: parent.verticalCenter
                    width: filterRow.implicitWidth + 12
                    height: 42
                    radius: 999
                    color: root.cardSurface
                    border.width: 1
                    border.color: Qt.alpha(root.textMuted, 0.18)

                    Row {
                        id: filterRow

                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            width: 66
                            height: 32
                            radius: 999
                            color:
                                !root.pinnedOnly
                                    ? root.accentSoft
                                    : "transparent"
                            border.width:
                                !root.pinnedOnly ? 1 : 0
                            border.color:
                                Qt.alpha(root.accent, 0.62)

                            CortetsuText {
                                anchors.centerIn: parent
                                text: qsTr("All")
                                color:
                                    !root.pinnedOnly
                                        ? root.accent
                                        : root.textMuted
                                textSize: CortetsuTypography.labelMediumPx
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked:
                                    root.pinnedOnly = false
                            }
                        }

                        Rectangle {
                            width: 100
                            height: 32
                            radius: 999
                            color:
                                root.pinnedOnly
                                    ? root.accentSoft
                                    : "transparent"
                            border.width:
                                root.pinnedOnly ? 1 : 0
                            border.color:
                                Qt.alpha(root.accent, 0.62)

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                CortetsuIcon {
                                    text: "keep"
                                    color:
                                        root.pinnedOnly
                                            ? root.accent
                                            : root.textMuted
                                    iconSize: CortetsuTypography.iconSmallPx
                                }

                                CortetsuText {
                                    text: qsTr("Pinned")
                                    color:
                                        root.pinnedOnly
                                            ? root.accent
                                            : root.textMuted
                                    textSize: CortetsuTypography.labelMediumPx
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked:
                                    root.pinnedOnly = true
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 1
                            height: 20
                            color: Qt.alpha(root.textMuted, 0.20)
                        }

                        Rectangle {
                            width: 86
                            height: 32
                            radius: 999
                            color:
                                clearMouse.containsMouse
                                    ? Qt.alpha(
                                        CortetsuDesign.colorVermillion,
                                        0.12
                                    )
                                    : "transparent"

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                CortetsuIcon {
                                    text: "delete_sweep"
                                    color:
                                        clearMouse.containsMouse
                                            ? CortetsuDesign.colorVermillion
                                            : root.textMuted
                                    iconSize: CortetsuTypography.iconSmallPx
                                }

                                CortetsuText {
                                    text: qsTr("Clear")
                                    color:
                                        clearMouse.containsMouse
                                            ? CortetsuDesign.colorVermillion
                                            : root.textMuted
                                    textSize: CortetsuTypography.labelMediumPx
                                }
                            }

                            MouseArea {
                                id: clearMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked:
                                    root.clearNonPinned()
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: searchHost

                width: parent.width
                height: 52
                radius: CortetsuDesign.radiusLarge
                color: root.cardSurface
                border.width: searchInput.activeFocus ? 2 : 1
                border.color:
                    searchInput.activeFocus
                        ? Qt.alpha(root.accent, 0.78)
                        : Qt.alpha(root.textMuted, 0.18)

                Behavior on border.color {
                    ColorAnimation {
                        duration: 110
                    }
                }

                CortetsuIcon {
                    id: searchIcon

                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "search"
                    color:
                        searchInput.activeFocus
                            ? root.accent
                            : root.textMuted
                    iconSize: CortetsuTypography.iconMediumPx
                }

                TextInput {
                    id: searchInput

                    anchors.left: searchIcon.right
                    anchors.leftMargin: 11
                    anchors.right: searchShortcut.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter

                    height: 30
                    text: root.query
                    selectByMouse: true
                    clip: true
                    color: root.textPrimary
                    selectionColor: Qt.alpha(root.accent, 0.34)
                    selectedTextColor: root.textPrimary
                    font.pixelSize: CortetsuTypography.bodyLargePx

                    onTextChanged: {
                        if (root.query !== text)
                            root.query = text;
                    }

                    Keys.onUpPressed:
                        root.moveSelection(-1)

                    Keys.onDownPressed:
                        root.moveSelection(1)

                    Keys.onReturnPressed:
                        root.copyEntry(root.selectedEntry)

                    Keys.onEnterPressed:
                        root.copyEntry(root.selectedEntry)

                    Keys.onEscapePressed:
                        root.screenState.cortetsuState?.setRetained("clipboard", false)

                    Keys.onDeletePressed: {
                        if (
                            selectionStart === selectionEnd &&
                            text.length === 0
                        ) {
                            root.deleteEntry(root.selectedEntry);
                        }
                    }
                }

                CortetsuText {
                    visible: searchInput.text.length === 0
                    anchors.left: searchInput.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Search clipboard…")
                    color: root.textMuted
                    textSize: CortetsuTypography.bodyLargePx
                }

                Rectangle {
                    id: searchShortcut

                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: shortcutLabel.implicitWidth + 18
                    height: 28
                    radius: CortetsuDesign.radiusMedium
                    color: root.elevatedSurface
                    border.width: 1
                    border.color: Qt.alpha(root.textMuted, 0.18)

                    CortetsuText {
                        id: shortcutLabel

                        anchors.centerIn: parent
                        text: "Ctrl+F"
                        color: root.textMuted
                        textSize: CortetsuTypography.labelSmallPx
                    }
                }
            }

            ListView {
                id: list

                width: parent.width
                height:
                    Math.max(
                        180,
                        parent.height -
                        header.height -
                        searchHost.height -
                        footer.height -
                        52
                    )

                model: root.filteredEntries
                clip: true
                spacing: 10
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: root.selectedIndex

                ScrollBar.vertical: ScrollBar {
                    policy:
                        list.contentHeight > list.height
                            ? ScrollBar.AsNeeded
                            : ScrollBar.AlwaysOff
                }

                delegate: ClipboardItem {
                    required property var modelData
                    required property int index

                    width:
                        list.width -
                        (list.ScrollBar.vertical.visible ? 10 : 0)

                    entry: modelData.item
                    selected: index === root.selectedIndex

                    onSelectRequested:
                        root.selectedIndex = index

                    onActivateRequested:
                        root.copyEntry(modelData)

                    onDeleteRequested:
                        root.deleteEntry(modelData)

                    onPinRequested:
                        root.togglePin(modelData)
                }

                footer:
                    Item {
                        width: 1
                        height: 4
                    }
            }

            Row {
                id: footer

                width: parent.width
                height: 36
                spacing: 14

                CortetsuText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.statusText.length > 0
                    width: visible ? Math.min(180, implicitWidth) : 0
                    text: root.statusText
                    color: root.accent
                    textSize: CortetsuTypography.labelMediumPx
                    elide: Text.ElideRight
                }

                Repeater {
                    model: [
                        { key: "↑ ↓", label: qsTr("Navigate") },
                        { key: "Enter", label: qsTr("Copy") },
                        { key: "Delete", label: qsTr("Remove") },
                        { key: "P", label: qsTr("Pin") },
                        { key: "Ctrl+F", label: qsTr("Search") }
                    ]

                    Row {
                        required property var modelData

                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7

                        Rectangle {
                            width: keyLabel.implicitWidth + 16
                            height: 28
                            radius: CortetsuDesign.radiusMedium
                            color: root.elevatedSurface
                            border.width: 1
                            border.color:
                                Qt.alpha(root.accent, 0.26)

                            CortetsuText {
                                id: keyLabel

                                anchors.centerIn: parent
                                text: modelData.key
                                color: root.accent
                                textSize: CortetsuTypography.labelSmallPx
                            }
                        }

                        CortetsuText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: root.textMuted
                            textSize: CortetsuTypography.labelSmallPx
                        }
                    }
                }
            }
        }

        Item {
            anchors.centerIn: parent
            width: 320
            height: 110
            visible: root.filteredEntries.length === 0

            CortetsuIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text:
                    root.query.length > 0
                        ? "search_off"
                        : "content_paste_off"
                color: root.accent
                iconSize: CortetsuTypography.iconExtraLargePx
            }

            CortetsuText {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.verticalCenter
                anchors.topMargin: 12
                text:
                    root.query.length > 0
                        ? qsTr("No matching clipboard entries")
                        : qsTr("Clipboard history is empty")
                color: root.textMuted
                textSize: CortetsuTypography.bodyPx
            }
        }
    }
}
