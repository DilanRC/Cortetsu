pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// Content of the share picker, free of the layer-shell window so the
// headless harness can render and drive it. One choice shares: a click,
// Enter or 1-9. Tab and Shift+Tab switch between Pantallas, Ventanas and
// Región; arrows move; Alt+R toggles "Recordar"; Escape belongs to the host.
Item {
    id: win

    required property var controller
    signal cancelRequested()

    readonly property bool shown: controller.choosing
    // Room the card may use; the host window passes the screen size.
    property real maxWidth: 800
    property real maxHeight: 600

    implicitWidth: card.width
    implicitHeight: card.height
    focus: true

    // 0 screens, 1 windows, 2 region.
    property int tab: 0
    property int selected: 0
    property bool remember: false

    readonly property var outputs: CortetsuScreens.screens
    readonly property var windows: controller.windows
    readonly property int count: tab === 0 ? outputs.length : tab === 1 ? windows.length : 0

    function hyprToplevel(address: string): var {
        const want = String(address).replace(/^0x/, "").toLowerCase();
        if (want.length === 0 || want === "0")
            return null;
        return CortetsuHypr.toplevels.values.find(t =>
            String(t.address ?? t.lastIpcObject?.address ?? "").replace(/^0x/, "").toLowerCase() === want) ?? null;
    }

    function share(index: int): void {
        if (tab === 0 && index >= 0 && index < outputs.length)
            controller.shareScreen(outputs[index].name, remember);
        else if (tab === 1 && index >= 0 && index < windows.length)
            controller.shareWindow(windows[index].handle, remember);
        else if (tab === 2)
            controller.pickRegion(remember);
    }

    function selectTab(next: int): void {
        tab = (next + 3) % 3;
        selected = 0;
    }

    Keys.onPressed: event => {
        const columns = 3;
        if (event.key === Qt.Key_Tab) {
            win.selectTab(win.tab + 1);
        } else if (event.key === Qt.Key_Backtab) {
            win.selectTab(win.tab - 1);
        } else if (event.key === Qt.Key_Right) {
            win.selected = Math.min(win.count - 1, win.selected + 1);
        } else if (event.key === Qt.Key_Left) {
            win.selected = Math.max(0, win.selected - 1);
        } else if (event.key === Qt.Key_Down) {
            win.selected = Math.min(win.count - 1, win.selected + columns);
        } else if (event.key === Qt.Key_Up) {
            win.selected = Math.max(0, win.selected - columns);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            win.share(win.selected);
        } else if (event.key === Qt.Key_R && (event.modifiers & Qt.AltModifier)) {
            win.remember = !win.remember;
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            win.share(event.key - Qt.Key_1);
        } else {
            return;
        }
        event.accepted = true;
    }

    CortetsuSurface {
        id: card
        width: Math.min(win.maxWidth - CortetsuDesign.spacingSection * 2, 760)
        height: Math.min(win.maxHeight - CortetsuDesign.spacingSection * 2, column.implicitHeight + CortetsuDesign.spacingSpacious * 2)
        radiusValue: CortetsuDesign.radiusSurface
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, CortetsuDesign.overlayOpacity)
        outlined: true

        // Swallow clicks so only the scrim dismisses.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingSpacious
            spacing: CortetsuDesign.spacingComfortable

            CortetsuText {
                text: qsTr("Compartir pantalla")
                textSize: CortetsuTypography.bodyLargePx
                font.weight: Font.DemiBold
            }

            CortetsuText {
                Layout.fillWidth: true
                text: qsTr("Una aplicación quiere ver tu pantalla. Elige qué compartir.")
                color: CortetsuDesign.colorOnSurfaceVariant
                wrapMode: Text.WordWrap
            }

            RowLayout {
                spacing: CortetsuDesign.spacingCompact
                Repeater {
                    model: [
                        { label: qsTr("Pantallas"), icon: "monitor" },
                        { label: qsTr("Ventanas"), icon: "select_window" },
                        { label: qsTr("Región"), icon: "crop" }
                    ]
                    CortetsuTab {
                        // The panel owns every key here (see header).
                        activeFocusOnTab: false
                        required property var modelData
                        required index
                        count: 3
                        label: modelData.label
                        icon: modelData.icon
                        selected: win.tab === index
                        // A selected tab normally takes focus (roving tabindex); here
                        // the arrows move between tiles instead.
                        focus: false
                        onActivated: win.selectTab(index)
                        onPreviousRequested: win.selectTab(win.tab - 1)
                        onNextRequested: win.selectTab(win.tab + 1)
                    }
                }
            }

            GridView {
                id: grid
                visible: win.tab !== 2 && win.count > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(Math.ceil(win.count / 3), 2) * cellHeight
                clip: true
                cellWidth: width / 3
                cellHeight: cellWidth * 0.62 + CortetsuDesign.rowHeight
                currentIndex: win.selected
                model: win.tab === 0 ? win.outputs : win.windows
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property bool isScreen: win.tab === 0
                    readonly property var source: isScreen ? modelData : (win.hyprToplevel(modelData.address)?.wayland ?? null)
                    width: grid.cellWidth
                    height: grid.cellHeight

                    // Tonal tile, not a nested surface: the card is the one surface.
                    Rectangle {
                        readonly property bool current: win.selected === tile.index
                        anchors.fill: parent
                        anchors.margins: CortetsuDesign.spacingCompact / 2
                        radius: CortetsuDesign.radiusLarge
                        color: tileMouse.containsMouse || current
                            ? CortetsuDesign.colorSurfaceHigh
                            : Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.86)
                        border.width: current ? CortetsuDesign.outlineWidth * 2 : 0
                        border.color: CortetsuDesign.colorWashi
                        scale: tileMouse.pressed ? CortetsuDesign.pressScale : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: CortetsuDesign.motionFastMs
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: CortetsuDesign.easeOut
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: CortetsuDesign.motionFastMs
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: CortetsuDesign.easeOut
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: CortetsuDesign.spacingCompact
                            spacing: CortetsuDesign.spacingCompact

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: CortetsuDesign.radiusMedium
                                color: CortetsuDesign.colorSumi
                                clip: true

                                ScreencopyView {
                                    id: preview
                                    anchors.fill: parent
                                    captureSource: win.shown ? tile.source : null
                                    live: win.shown
                                    constraintSize: Qt.size(width, height)
                                }

                                CortetsuIcon {
                                    anchors.centerIn: parent
                                    visible: !preview.hasContent
                                    text: tile.isScreen ? "monitor" : "web_asset_off"
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: CortetsuDesign.spacingCompact

                                // The digit that picks this tile.
                                CortetsuText {
                                    Layout.alignment: Qt.AlignTop
                                    visible: tile.index < 9
                                    text: String(tile.index + 1)
                                    textSize: CortetsuTypography.labelSmallPx
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    CortetsuText {
                                        Layout.fillWidth: true
                                        text: tile.isScreen ? (tile.modelData.name || qsTr("Pantalla %1").arg(tile.index + 1)) : (tile.modelData.title || tile.modelData.class)
                                        elide: Text.ElideRight
                                    }
                                    CortetsuText {
                                        Layout.fillWidth: true
                                        text: tile.isScreen
                                            ? qsTr("%1 × %2").arg(tile.modelData.width).arg(tile.modelData.height)
                                            : !tile.source ? qsTr("%1 · sin vista previa").arg(tile.modelData.class) : tile.modelData.class
                                        textSize: CortetsuTypography.labelSmallPx
                                        color: CortetsuDesign.colorOnSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: win.selected = tile.index
                        onClicked: win.share(tile.index)
                    }
                }
            }

            CortetsuStateMessage {
                visible: win.tab !== 2 && win.count === 0
                Layout.fillWidth: true
                kind: "empty"
                icon: win.tab === 0 ? "desktop_access_disabled" : "select_window"
                title: win.tab === 0 ? qsTr("No hay pantallas") : qsTr("No hay ventanas para compartir")
                detail: win.tab === 0
                    ? qsTr("Hyprland no informa de ninguna salida.")
                    : qsTr("La aplicación solo pidió pantallas, o no hay ventanas abiertas.")
            }

            ColumnLayout {
                visible: win.tab === 2
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingStandard

                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Arrastra sobre la pantalla para elegir un rectángulo. Un clic sobre una ventana la ajusta a ella.")
                    color: CortetsuDesign.colorOnSurfaceVariant
                    wrapMode: Text.WordWrap
                }

                CortetsuButton {

                    // The panel owns every key here (see header).

                    activeFocusOnTab: false
                    label: qsTr("Elegir región")
                    icon: "crop"
                    active: true
                    onClicked: win.share(0)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingStandard

                CortetsuToggle {

                    // The panel owns every key here (see header).

                    activeFocusOnTab: false
                    accessibleName: qsTr("Recordar para esta app")
                    checked: win.remember
                    onToggled: value => win.remember = value
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Recordar para esta app (Alt+R)")
                    elide: Text.ElideRight
                }

                CortetsuButton {

                    // The panel owns every key here (see header).

                    activeFocusOnTab: false
                    label: qsTr("Cancelar")
                    onClicked: win.cancelRequested()
                }

                CortetsuButton {

                    // The panel owns every key here (see header).

                    activeFocusOnTab: false
                    label: qsTr("Compartir")
                    active: true
                    disabled: win.tab !== 2 && win.count === 0
                    onClicked: win.share(win.selected)
                }
            }
        }
    }
}
