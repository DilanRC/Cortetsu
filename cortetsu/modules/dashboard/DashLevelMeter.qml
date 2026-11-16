pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire
import "../../theme"
import ".."

// What the default output is playing, as two thin peak bars (left and
// right). PipeWire's own peak monitor, so nothing is installed for it
// (cava is optional and absent on many systems). It exists only while
// `running`: the dashboard is open and the player is playing.
Item {
    id: root

    property bool running: false

    implicitHeight: 2 * 3 + 2
    visible: running
    Accessible.ignored: true

    PwNodePeakMonitor {
        id: monitor
        node: CortetsuAudio.sink
        enabled: root.running
    }

    Column {
        anchors.fill: parent
        spacing: 2

        Repeater {
            model: 2
            delegate: Item {
                id: bar
                required property int index
                readonly property real level: {
                    const peaks = monitor.peaks ?? [];
                    const value = peaks.length > bar.index ? peaks[bar.index] : peaks.length > 0 ? peaks[0] : 0;
                    return Math.max(0, Math.min(1, Number(value) || 0));
                }
                width: parent.width
                height: 3

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.alpha(CortetsuDesign.colorWashi, 0.08)
                }
                Rectangle {
                    width: parent.width * bar.level
                    height: parent.height
                    radius: height / 2
                    color: bar.level > 0.95 ? CortetsuDesign.colorVermillion : CortetsuDesign.colorIndicator
                    Behavior on width { NumberAnimation { duration: CortetsuDesign.motionFastMs } }
                }
            }
        }
    }
}
