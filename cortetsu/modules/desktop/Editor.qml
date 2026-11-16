pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import ".."
import "../../components"
import "../../services"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "../HubAnchor.js" as HubAnchor
import "DesktopLayout.js" as DesktopLayout

// The desktop editor of one monitor: its widgets drawn over everything,
// movable with the pointer (they snap to the area's edges and middle and
// to each other) or with the keys, and a side panel to add widgets, size
// them, move them to another monitor and write notes. Every change is
// saved as it happens; Ctrl+Z walks back through this session.
FocusScope {
    id: root

    required property ShellScreen screen
    required property var screenState

    readonly property string screenName: screen?.name ?? ""
    readonly property var ids: DesktopWidgets.idsFor(screenName)
    readonly property var selectedItem: DesktopWidgets.entry(DesktopWidgets.selected)
    readonly property var reserved: DesktopWidgets.reservedFor(screenName)
    // The panel sits on the side the Hub does not use.
    readonly property bool panelOnLeft: HubAnchor.describe(CortetsuConfig.bottomHub.anchorFor(screenName)).edge === "right"
    property var guides: []
    // Where the dragged box will land once released (snapped).
    property var ghost: null
    readonly property var sizeTabs: [
        { label: qsTr("Pequeño"), size: "s" }, { label: qsTr("Mediano"), size: "m" }, { label: qsTr("Grande"), size: "l" }
    ]

    function openSurface(): void {
        DesktopWidgets.beginSession();
        root.forceActiveFocus();
    }

    function close(): void {
        root.screenState?.cortetsuState?.setRetained("desktopWidgets", false);
    }

    function otherRects(id: string): var {
        return root.ids.filter(other => other !== id)
            .map(other => DesktopWidgets.rectOf(DesktopWidgets.entry(other), root.screen));
    }

    function nudge(dx: int, dy: int): void {
        const item = root.selectedItem;
        if (!item)
            return;
        const rect = DesktopWidgets.rectOf(item, root.screen);
        DesktopWidgets.placeAt(item.id, { x: rect.x + dx, y: rect.y + dy, w: rect.w, h: rect.h }, root.screen);
    }

    function cycle(step: int): void {
        if (root.ids.length === 0)
            return;
        const index = root.ids.indexOf(DesktopWidgets.selected);
        const next = index < 0 ? (step > 0 ? 0 : root.ids.length - 1) : (index + step + root.ids.length) % root.ids.length;
        DesktopWidgets.selected = root.ids[next];
    }

    // Keys act on the selected widget unless a text field has the keyboard.
    Keys.onPressed: event => {
        if (noteField.activeFocus)
            return;
        const ctrl = event.modifiers & Qt.ControlModifier;
        const shift = event.modifiers & Qt.ShiftModifier;
        const step = shift ? 32 : DesktopLayout.gridStep;
        if (ctrl && event.key === Qt.Key_Z) {
            shift ? DesktopWidgets.redo() : DesktopWidgets.undo();
        } else if (ctrl && event.key === Qt.Key_Y) {
            DesktopWidgets.redo();
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.cycle(event.key === Qt.Key_Backtab ? -1 : 1);
        } else if (event.key === Qt.Key_Left) {
            root.nudge(-step, 0);
        } else if (event.key === Qt.Key_Right) {
            root.nudge(step, 0);
        } else if (event.key === Qt.Key_Up) {
            root.nudge(0, -step);
        } else if (event.key === Qt.Key_Down) {
            root.nudge(0, step);
        } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
            DesktopWidgets.resize(DesktopWidgets.selected, 1);
        } else if (event.key === Qt.Key_Minus) {
            DesktopWidgets.resize(DesktopWidgets.selected, -1);
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            DesktopWidgets.remove(DesktopWidgets.selected);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.close();
        } else {
            return;
        }
        event.accepted = true;
    }

    // A press on the empty desktop clears the selection.
    TapHandler {
        onTapped: {
            DesktopWidgets.selected = "";
            root.forceActiveFocus();
        }
    }

    // The usable area, so the edges the widgets snap to are visible.
    Rectangle {
        readonly property var area: DesktopLayout.area(root.width, root.height, root.reserved)
        x: area.x0
        y: area.y0
        width: area.x1 - area.x0
        height: area.y1 - area.y0
        color: "transparent"
        radius: CortetsuDesign.radiusLarge
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.22)
    }

    // Snap guides of the box being dragged.
    Repeater {
        model: root.guides
        delegate: Rectangle {
            required property var modelData
            x: modelData.vertical ? modelData.at : 0
            y: modelData.vertical ? 0 : modelData.at
            width: modelData.vertical ? 1 : root.width
            height: modelData.vertical ? root.height : 1
            color: CortetsuDesign.colorIndicator
            opacity: 0.8
        }
    }

    Rectangle {
        visible: !!root.ghost
        x: root.ghost?.x ?? 0
        y: root.ghost?.y ?? 0
        width: root.ghost?.w ?? 0
        height: root.ghost?.h ?? 0
        radius: CortetsuDesign.radiusLarge
        color: Qt.alpha(CortetsuDesign.colorIndicator, 0.12)
        border.width: 1
        border.color: CortetsuDesign.colorIndicator
    }

    Repeater {
        model: ScriptModel { values: root.ids }

        delegate: Item {
            id: frame
            required property string modelData
            readonly property var item: DesktopWidgets.entry(modelData)
            readonly property var rect: DesktopWidgets.rectOf(item, root.screen)
            readonly property bool selected: DesktopWidgets.selected === modelData
            property bool dragging: false

            width: rect.w
            height: rect.h
            // While dragging the frame follows the pointer; at rest it follows
            // the stored position.
            // RestoreNone: when a drag starts the frame stays where it is
            // instead of jumping back to the value x had before the binding.
            Binding on x { value: frame.rect.x; when: !frame.dragging; restoreMode: Binding.RestoreNone }
            Binding on y { value: frame.rect.y; when: !frame.dragging; restoreMode: Binding.RestoreNone }
            z: selected ? 2 : 1

            DesktopWidget {
                anchors.fill: parent
                item: frame.item
                editing: true
                live: true
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: CortetsuDesign.radiusLarge + 4
                color: "transparent"
                border.width: frame.selected ? 2 : 1
                border.color: frame.selected ? CortetsuDesign.colorIndicator : Qt.alpha(CortetsuDesign.colorWashi, 0.35)
            }

            CortetsuText {
                anchors.bottom: parent.top
                anchors.bottomMargin: 8
                anchors.left: parent.left
                visible: frame.selected
                text: qsTr("%1 · %2").arg(DesktopWidgets.info(frame.item?.type)?.title ?? "").arg(
                    root.sizeTabs.find(tab => tab.size === frame.item?.size)?.label ?? "")
                textSize: CortetsuTypography.labelMediumPx
                color: CortetsuDesign.colorWashi
            }

            MouseArea {
                id: grip
                anchors.fill: parent
                cursorShape: frame.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                drag.target: frame
                drag.threshold: 4
                // A press that never moves only selects.
                property bool moved: false
                onPressed: {
                    moved = false;
                    frame.dragging = true;
                    DesktopWidgets.selected = frame.modelData;
                    root.forceActiveFocus();
                }
                onPositionChanged: {
                    if (!drag.active)
                        return;
                    moved = true;
                    const snapped = DesktopLayout.snap({ x: frame.x, y: frame.y, w: frame.width, h: frame.height },
                        root.otherRects(frame.modelData), root.width, root.height, root.reserved);
                    root.guides = snapped.guides;
                    root.ghost = { x: snapped.x, y: snapped.y, w: frame.width, h: frame.height };
                }
                onReleased: {
                    if (moved && root.ghost)
                        DesktopWidgets.placeAt(frame.modelData, root.ghost, root.screen);
                    frame.dragging = false;
                    root.guides = [];
                    root.ghost = null;
                }
                onCanceled: {
                    frame.dragging = false;
                    root.guides = [];
                    root.ghost = null;
                }
            }

            Accessible.role: Accessible.Button
            Accessible.name: DesktopWidgets.info(frame.item?.type)?.title ?? ""
            Accessible.description: qsTr("Arrastra o usa las flechas para moverlo")
        }
    }

    // --- Side panel -------------------------------------------------------
    Item {
        id: panel
        width: Math.min(340, root.width * 0.3)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: CortetsuDesign.spacingSection
        anchors.topMargin: CortetsuDesign.spacingSection + root.reserved.top
        anchors.bottomMargin: CortetsuDesign.spacingSection + root.reserved.bottom
        x: root.panelOnLeft ? CortetsuDesign.spacingSection + root.reserved.left
            : root.width - width - CortetsuDesign.spacingSection - root.reserved.right

        // Clicks on the panel never reach the desktop's tap handler.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        CortetsuInkPanel {
            anchors.fill: parent
            radius: CortetsuDesign.radiusSurface
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingComfortable
            spacing: CortetsuDesign.spacingStandard

            RowLayout {
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingCompact

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    CortetsuText {
                        text: qsTr("Escritorio")
                        textSize: CortetsuTypography.titleMediumPx
                        font.family: CortetsuDesign.fontHeading
                        font.weight: CortetsuDesign.headingWeight
                    }
                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.ids.length === 1 ? qsTr("%1 · 1 widget").arg(root.screenName)
                            : qsTr("%1 · %2 widgets").arg(root.screenName).arg(root.ids.length)
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                CortetsuButton {
                    compact: true; icon: "undo"; label: ""
                    tooltipText: qsTr("Deshacer (Ctrl+Z)")
                    disabled: !DesktopWidgets.canUndo
                    onClicked: DesktopWidgets.undo()
                }
                CortetsuButton {
                    compact: true; icon: "redo"; label: ""
                    tooltipText: qsTr("Rehacer (Ctrl+Mayús+Z)")
                    disabled: !DesktopWidgets.canRedo
                    onClicked: DesktopWidgets.redo()
                }
                CortetsuButton {
                    objectName: "desktopEditorDone"
                    compact: true; active: true; icon: "check"
                    label: qsTr("Listo")
                    tooltipText: qsTr("Guardar y salir (Intro o Escape)")
                    onClicked: root.close()
                }
            }

            CortetsuDivider { Layout.fillWidth: true }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: panelBody.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: panelBody
                    width: parent.width
                    spacing: CortetsuDesign.spacingStandard

                    // The selected widget.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !!root.selectedItem
                        spacing: CortetsuDesign.spacingCompact

                        RowLayout {
                            Layout.fillWidth: true
                            CortetsuIcon {
                                text: DesktopWidgets.info(root.selectedItem?.type)?.icon ?? "widgets"
                                iconSize: CortetsuTypography.iconSmallPx
                                color: CortetsuDesign.colorPrimary
                            }
                            CortetsuText {
                                Layout.fillWidth: true
                                text: DesktopWidgets.info(root.selectedItem?.type)?.title ?? ""
                                textSize: CortetsuTypography.titleSmallPx
                                font.weight: Font.DemiBold
                            }
                            CortetsuButton {
                                objectName: "desktopEditorRemove"
                                compact: true; danger: true; icon: "delete"
                                label: qsTr("Quitar")
                                tooltipText: qsTr("Quitar del escritorio (Supr). Ctrl+Z lo devuelve")
                                onClicked: DesktopWidgets.remove(DesktopWidgets.selected)
                            }
                        }

                        CortetsuTabBar {
                            Layout.fillWidth: true
                            accessibleName: qsTr("Tamaño")
                            model: root.sizeTabs
                            currentIndex: root.sizeTabs.findIndex(tab => tab.size === root.selectedItem?.size)
                            onSelected: index => DesktopWidgets.setSize(DesktopWidgets.selected, root.sizeTabs[index].size)
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.selectedItem?.type === "clock"
                            CortetsuText {
                                Layout.fillWidth: true
                                text: qsTr("Mostrar la fecha")
                                textSize: CortetsuTypography.bodyPx
                            }
                            CortetsuToggle {
                                accessibleName: qsTr("Mostrar la fecha")
                                checked: root.selectedItem?.showDate !== false
                                onToggled: value => {
                                    DesktopWidgets.update(DesktopWidgets.selected, { showDate: value });
                                    DesktopWidgets.record();
                                }
                            }
                        }

                        TextArea {
                            id: noteField
                            objectName: "desktopEditorNote"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 140
                            visible: root.selectedItem?.type === "note"
                            wrapMode: TextEdit.Wrap
                            placeholderText: qsTr("Escribe la nota")
                            font.family: CortetsuDesign.fontUi
                            font.pixelSize: CortetsuTypography.bodyPx
                            color: CortetsuDesign.colorOnSurface
                            placeholderTextColor: CortetsuDesign.colorOnSurfaceVariant
                            selectionColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.56)
                            Accessible.name: qsTr("Texto de la nota")
                            background: Rectangle {
                                radius: CortetsuDesign.radiusMedium
                                color: Qt.alpha(CortetsuDesign.colorSurface, 0.6)
                                border.width: noteField.activeFocus ? 2 : 1
                                border.color: noteField.activeFocus ? CortetsuDesign.colorWashi : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.6)
                            }
                            // The field shows the stored text while it is not
                            // being edited; typing writes it back.
                            Binding on text { value: root.selectedItem?.text ?? ""; when: !noteField.activeFocus }
                            onTextChanged: if (activeFocus && root.selectedItem?.type === "note")
                                DesktopWidgets.setNoteText(DesktopWidgets.selected, text.slice(0, DesktopLayout.maxNoteLength))
                            Keys.onEscapePressed: event => {
                                root.forceActiveFocus();
                                event.accepted = true;
                            }
                        }

                        // Another monitor: the widget keeps its relative place.
                        Flow {
                            Layout.fillWidth: true
                            visible: Quickshell.screens.length > 1
                            spacing: CortetsuDesign.spacingUnit
                            Repeater {
                                model: Quickshell.screens.filter(screen => screen.name !== root.screenName)
                                delegate: CortetsuButton {
                                    required property ShellScreen modelData
                                    compact: true
                                    icon: "move_down"
                                    label: qsTr("Llevar a %1").arg(modelData.name)
                                    tooltipText: qsTr("Mismo lugar relativo en %1").arg(modelData.name)
                                    onClicked: {
                                        DesktopWidgets.update(DesktopWidgets.selected, { screen: modelData.name });
                                        DesktopWidgets.record();
                                        DesktopWidgets.selected = "";
                                    }
                                }
                            }
                        }

                        CortetsuDivider { Layout.fillWidth: true; Layout.topMargin: CortetsuDesign.spacingUnit }
                    }

                    // The gallery: what this machine can feed.
                    CortetsuText {
                        Layout.fillWidth: true
                        text: CortetsuDesign.labelCaps ? qsTr("AÑADIR") : qsTr("Añadir")
                        textSize: CortetsuDesign.labelCaps ? CortetsuTypography.labelLargePx : CortetsuTypography.titleSmallPx
                        font.family: CortetsuDesign.fontHeading
                        font.weight: CortetsuDesign.headingWeight
                        font.letterSpacing: CortetsuDesign.labelTracking
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        visible: DesktopWidgets.full
                        text: qsTr("Hay %1 widgets, el máximo. Quita uno para añadir otro.").arg(DesktopLayout.maxWidgets)
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: DesktopWidgets.catalogue.filter(kind => kind.available)
                        delegate: CortetsuListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            compact: true
                            icon: modelData.icon
                            title: modelData.title
                            subtitle: modelData.detail
                            disabled: DesktopWidgets.full
                            tooltipText: qsTr("Añadir %1 en %2").arg(modelData.title).arg(root.screenName)
                            onClicked: DesktopWidgets.add(modelData.type, root.screenName)
                        }
                    }
                }
            }

            CortetsuText {
                Layout.fillWidth: true
                text: qsTr("Tab elige · flechas mueven (Mayús, más) · + y − cambian el tamaño · Supr quita")
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }
    }

    CortetsuStateMessage {
        anchors.centerIn: parent
        width: Math.min(420, root.width - panel.width - CortetsuDesign.spacingSection * 4)
        visible: root.ids.length === 0
        kind: "empty"
        icon: "widgets"
        title: qsTr("Sin widgets en %1").arg(root.screenName)
        detail: qsTr("Añade uno desde el panel; aparecerá aquí y podrás moverlo.")
    }
}
