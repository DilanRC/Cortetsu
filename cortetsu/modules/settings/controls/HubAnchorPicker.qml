pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography
import "../../HubAnchor.js" as HubAnchor

// The Hub's eight anchors drawn on a small screen: each spot is where the Hub
// would sit. One Tab stop; the arrows walk the spots as they lie on the
// screen and Enter or Space chooses. The caller binds `current` to the real
// value, so a refused choice leaves the mark where it was.
Item {
    id: root

    property string current: HubAnchor.fallback
    property bool disabled: false
    signal chosen(string id)

    // The spots as rows of the screen; "" is its centre, where no Hub goes.
    readonly property var grid: [
        ["top-left", "top-center", "top-right"],
        ["middle-left", "", "middle-right"],
        ["bottom-left", "bottom-center", "bottom-right"]
    ]
    readonly property var names: ({
        "top-left": qsTr("Arriba a la izquierda"), "top-center": qsTr("Arriba, a lo ancho"),
        "top-right": qsTr("Arriba a la derecha"), "middle-left": qsTr("Lateral izquierdo"),
        "middle-right": qsTr("Lateral derecho"), "bottom-left": qsTr("Abajo a la izquierda"),
        "bottom-center": qsTr("Abajo, a lo ancho"), "bottom-right": qsTr("Abajo a la derecha")
    })
    readonly property string currentName: names[HubAnchor.normalize(current)]
    property string focused: HubAnchor.normalize(current)

    Layout.fillWidth: true
    Layout.margins: CortetsuDesign.spacingStandard
    implicitHeight: screen.height
    activeFocusOnTab: !disabled
    enabled: !disabled
    opacity: disabled ? 0.52 : 1

    Accessible.role: Accessible.RadioButton
    Accessible.name: qsTr("Posición del Hub: %1").arg(root.names[root.focused])
    Accessible.focusable: !root.disabled
    Accessible.onPressAction: root.chosen(root.focused)

    onActiveFocusChanged: if (activeFocus) root.focused = HubAnchor.normalize(root.current)

    function move(dx: int, dy: int): void {
        let row = root.grid.findIndex(line => line.includes(root.focused));
        let column = root.grid[row].indexOf(root.focused);
        for (let step = 0; step < 2; ++step) {
            row = Math.max(0, Math.min(2, row + dy));
            column = Math.max(0, Math.min(2, column + dx));
            if (root.grid[row][column] !== "") {
                root.focused = root.grid[row][column];
                return;
            }
        }
    }

    Keys.onLeftPressed: root.move(-1, 0)
    Keys.onRightPressed: root.move(1, 0)
    Keys.onUpPressed: root.move(0, -1)
    Keys.onDownPressed: root.move(0, 1)
    Keys.onReturnPressed: root.chosen(root.focused)
    Keys.onEnterPressed: root.chosen(root.focused)
    Keys.onSpacePressed: root.chosen(root.focused)

    Rectangle {
        id: screen
        objectName: "hubAnchorScreen"
        width: Math.min(root.width, 360)
        height: Math.round(width * 9 / 16)
        radius: CortetsuDesign.radiusMedium
        color: Qt.alpha(CortetsuDesign.colorSumi, 0.6)
        border.width: root.activeFocus ? 2 : CortetsuDesign.outlineWidth
        border.color: root.activeFocus ? Qt.alpha(CortetsuDesign.colorWashi, 0.82)
            : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.7)

        Repeater {
            model: HubAnchor.ids

            Item {
                id: spot
                required property string modelData
                readonly property var place: HubAnchor.describe(modelData)
                readonly property bool selected: HubAnchor.normalize(root.current) === modelData
                readonly property bool marked: root.activeFocus && root.focused === modelData
                // The bar the Hub would be: along its edge, spread or packed.
                readonly property real thick: 10
                readonly property real inset: 8
                // Three spots share an edge without touching: a third each.
                readonly property real span: place.vertical ? 0.56 : place.pack === "spread" ? 0.3 : 0.26

                objectName: `hubAnchor-${modelData}`
                width: place.vertical ? thick + 16 : screen.width * span
                height: place.vertical ? screen.height * span : thick + 16
                x: place.edge === "left" ? inset - 8
                    : place.edge === "right" ? screen.width - width - inset + 8
                    : place.pack === "start" ? inset
                    : place.pack === "end" ? screen.width - width - inset
                    : (screen.width - width) / 2
                y: place.edge === "top" ? inset - 8
                    : place.edge === "bottom" ? screen.height - height - inset + 8
                    : (screen.height - height) / 2

                Rectangle {
                    anchors.centerIn: parent
                    width: spot.place.vertical ? spot.thick : parent.width - 8
                    height: spot.place.vertical ? parent.height - 8 : spot.thick
                    radius: spot.thick / 2
                    color: spot.selected ? CortetsuDesign.colorIndicator
                        : Qt.alpha(CortetsuDesign.colorOnSurface, mouse.containsMouse || spot.marked ? 0.42 : 0.18)
                    border.width: spot.marked ? 2 : 0
                    border.color: CortetsuDesign.colorWashi
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.forceActiveFocus();
                        root.focused = spot.modelData;
                        root.chosen(spot.modelData);
                    }
                }

                CortetsuTooltip {
                    target: spot
                    hovered: mouse.containsMouse
                    text: root.names[spot.modelData]
                    placement: spot.place.edge === "top" ? "below" : "above"
                }
            }
        }

        CortetsuText {
            objectName: "hubAnchorName"
            anchors.centerIn: parent
            width: parent.width * 0.5
            horizontalAlignment: Text.AlignHCenter
            text: root.activeFocus ? root.names[root.focused] : root.currentName
            textSize: CortetsuTypography.labelMediumPx
            color: CortetsuDesign.colorOnSurfaceVariant
            wrapMode: Text.WordWrap
        }
    }
}
