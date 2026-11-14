pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../../components"
import "../../../theme"
import "../.."
import "../../CortetsuTypography.js" as CortetsuTypography
import "../../WindowPreview.js" as WindowPreview

// The windows of one App Rail app: a card per window with its thumbnail (or
// its icon when there is none), title and workspace. A click or Enter goes
// to that window; the cross, the middle button or Delete closes it. Opened
// by hover it only follows the pointer; opened from the keyboard (Menu on
// the icon) the Hub passes it the keys typed there (handleKey).
//
// Everything comes from the Hub of this monitor, live: a window that closes
// while the preview is open takes its card with it, and the preview closes
// with the last one. Thumbnails are one frame each (ScreencopyView,
// live: false), taken while the preview exists and dropped with it.
CortetsuPopupSurface {
    id: root

    required property var popouts
    // The app shown. Kept while the popout fades out, when the popout name
    // is already empty.
    property string appKey: WindowPreview.appKeyOf(popouts.currentName)
    readonly property string liveKey: WindowPreview.appKeyOf(popouts.currentName)
    onLiveKeyChanged: if (liveKey.length > 0) {
        appKey = liveKey;
        selected = -1;
    }

    readonly property var hub: CortetsuShellState.forScreen(popouts.screen)?.cortetsuState?.bottomHub ?? null
    readonly property var app: hub?.dockViewItems.find(item => item.key === root.appKey) ?? null
    readonly property var group: hub?.dockItemForKey(root.appKey) ?? null
    readonly property var cards: WindowPreview.describe(group?.windows ?? [], hub?.activeAddress ?? "")
    readonly property int cardCount: cards.length
    readonly property bool thumbnails: CortetsuConfig.bottomHub.windowThumbnails
    readonly property int columns: (hub?.hubVertical ?? false) ? 1 : Math.max(1, Math.min(3, cards.length))
    // The card the keyboard is on; -1 until a key is typed.
    property int selected: -1

    readonly property real cardWidth: 200
    readonly property real thumbHeight: 112

    implicitWidth: Math.max(272, columns * cardWidth + (columns - 1) * grid.columnSpacing) + CortetsuDesign.spacingComfortable * 2
    implicitHeight: body.implicitHeight + CortetsuDesign.spacingComfortable * 2

    // The last window closed under the preview (or the app left the rail).
    onCardCountChanged: {
        if (cardCount === 0 && appKey.length > 0 && popouts.currentName === WindowPreview.popoutName(appKey))
            popouts.hasCurrent = false;
        else if (selected >= cardCount)
            selected = cardCount - 1;
    }

    // From the keyboard the preview starts on the active window, else the
    // first one, so Enter right away goes somewhere visible.
    function selectInitial(): void {
        const active = root.cards.findIndex(card => card.active);
        root.selected = root.cards.length === 0 ? -1 : Math.max(0, active);
    }

    function activate(index: int): void {
        const card = root.cards[index];
        if (!card)
            return;
        root.hub?.focusWindow(card.client);
        root.popouts.hasCurrent = false;
    }

    function closeWindow(index: int): void {
        const card = root.cards[index];
        if (card)
            root.hub?.closeWindow(card.client);
    }

    // One key typed on the rail icon; true when used.
    function handleKey(key: int, modifiers: int): bool {
        const names = {
            [Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "up", [Qt.Key_Down]: "down",
            [Qt.Key_Home]: "home", [Qt.Key_End]: "end", [Qt.Key_Backtab]: "backtab"
        };
        const name = key === Qt.Key_Tab ? ((modifiers & Qt.ShiftModifier) ? "backtab" : "tab") : names[key];
        if (name) {
            root.selected = WindowPreview.step(root.cards.length, root.columns, root.selected, name);
            return true;
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            root.activate(root.selected < 0 ? 0 : root.selected);
            return true;
        }
        if (key === Qt.Key_Delete) {
            root.closeWindow(root.selected);
            return true;
        }
        if (key === Qt.Key_Escape) {
            root.popouts.hasCurrent = false;
            return true;
        }
        return false;
    }

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingStandard

        CortetsuPopoutHeader {
            title: root.app?.title ?? ""
            detail: root.cardCount === 1 ? qsTr("1 ventana") : qsTr("%1 ventanas").arg(root.cardCount)

            CortetsuButton {
                objectName: "previewNewWindow"
                visible: !!root.group?.entry
                compact: true
                icon: "add"
                label: ""
                tooltipText: qsTr("Nueva ventana")
                Accessible.name: qsTr("Abrir otra ventana de %1").arg(root.app?.title ?? "")
                onClicked: {
                    root.hub?.launchDockKey(root.appKey);
                    root.popouts.hasCurrent = false;
                }
            }

            CortetsuButton {
                objectName: "previewPin"
                visible: !!root.group?.entry
                compact: true
                icon: root.app?.pinned ? "keep_off" : "keep"
                label: ""
                tooltipText: root.app?.pinned ? qsTr("Quitar de fijadas") : qsTr("Fijar en el Hub")
                onClicked: root.hub?.togglePinnedKey(root.appKey)
            }
        }

        GridLayout {
            id: grid
            Layout.fillWidth: true
            columns: root.columns
            columnSpacing: CortetsuDesign.spacingCompact
            rowSpacing: CortetsuDesign.spacingCompact

            Repeater {
                model: ScriptModel {
                    values: root.cards
                    objectProp: "address"
                }

                CortetsuSurface {
                    id: card

                    required property var modelData
                    required property int index
                    readonly property bool chosen: root.selected === index
                    readonly property bool canBringHere: !modelData.special && (root.hub?.activeWsId ?? 0) > 0
                        && modelData.workspaceId !== root.hub.activeWsId

                    objectName: `preview-${modelData.address}`
                    Layout.preferredWidth: root.cardWidth
                    implicitHeight: content.implicitHeight + CortetsuDesign.spacingCompact * 2
                    radiusValue: CortetsuDesign.radiusMedium
                    baseColor: modelData.active ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.42) : "transparent"
                    hoverColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.84)
                    hovered: cardMouse.containsMouse
                    pressed: cardMouse.pressed
                    focused: card.chosen
                    outlined: card.chosen
                    outlineColor: Qt.alpha(CortetsuDesign.colorWashi, 0.72)

                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("%1, %2").arg(modelData.title).arg(modelData.workspace)

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.selected = card.index
                        onClicked: event => {
                            if (event.button === Qt.MiddleButton)
                                root.closeWindow(card.index);
                            else
                                root.activate(card.index);
                        }
                    }

                    ColumnLayout {
                        id: content
                        anchors.fill: parent
                        anchors.margins: CortetsuDesign.spacingCompact
                        spacing: CortetsuDesign.spacingCompact

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.thumbHeight

                            Rectangle {
                                anchors.fill: parent
                                radius: CortetsuDesign.radiusSmall
                                color: Qt.alpha(CortetsuDesign.colorSumi, 0.5)
                                border.width: 1
                                border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.08)
                            }

                            // A frame of the window, shaped like it. Nothing
                            // is drawn until the compositor answers.
                            ScreencopyView {
                                id: shot
                                anchors.centerIn: parent
                                captureSource: root.thumbnails ? (card.modelData.client?.wayland ?? null) : null // qmllint disable unresolved-type
                                live: false
                                constraintSize.width: Math.min(parent.width - 4, (parent.height - 4) * card.modelData.aspect)
                                constraintSize.height: Math.min(parent.height - 4, (parent.width - 4) / card.modelData.aspect)
                            }

                            // No thumbnail (switched off, or not captured):
                            // the app's icon, never a made-up picture.
                            Image {
                                anchors.centerIn: parent
                                visible: !shot.hasContent
                                width: 40
                                height: 40
                                source: root.app?.iconSource ?? ""
                                sourceSize.width: 64
                                sourceSize.height: 64
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: CortetsuDesign.spacingUnit

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                CortetsuText {
                                    Layout.fillWidth: true
                                    text: card.modelData.title
                                    textSize: CortetsuTypography.labelMediumPx
                                    color: CortetsuDesign.colorOnSurface
                                    elide: Text.ElideRight
                                }

                                CortetsuText {
                                    Layout.fillWidth: true
                                    text: card.modelData.workspace
                                    textSize: CortetsuTypography.labelSmallPx
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }

                            CortetsuButton {
                                objectName: `previewBringHere-${card.modelData.address}`
                                visible: card.canBringHere
                                compact: true
                                icon: "input"
                                label: ""
                                tooltipText: qsTr("Traer a este espacio")
                                Accessible.name: qsTr("Traer %1 a este espacio").arg(card.modelData.title)
                                onClicked: CortetsuHypr.moveWindow(card.modelData.address, root.hub.activeWsId, true)
                            }

                            CortetsuButton {
                                objectName: `previewClose-${card.modelData.address}`
                                compact: true
                                icon: "close"
                                label: ""
                                tooltipText: qsTr("Cerrar ventana")
                                Accessible.name: qsTr("Cerrar %1").arg(card.modelData.title)
                                onClicked: root.closeWindow(card.index)
                            }
                        }
                    }
                }
            }
        }
    }
}
