pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "../../CortetsuDesign.js" as CortetsuDesign

Row {
    id: bars
    property real signalValue: 0
    property color activeColor: CortetsuDesign.colorPrimary
    property int barCount: 5
    spacing: 3
    height: 24

    Repeater {
        model: bars.barCount
        delegate: Rectangle {
            required property int index
            width: 5
            height: 8 + index * 4
            y: bars.height - height
            radius: 2
            color: index < Math.ceil(Math.max(0, bars.signalValue) / (100 / bars.barCount))
                ? bars.activeColor
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)
        }
    }
}
