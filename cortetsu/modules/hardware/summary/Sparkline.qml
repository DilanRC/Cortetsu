pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "../../../theme"

// Recent history of one metric, newest sample at the right edge. It redraws
// once per sample: `values` is replaced when a reading arrives and never
// animates between frames.
Shape {
    id: root

    property var values: []
    property int capacity: 72
    property real maxValue: 100
    property color lineColor: CortetsuDesign.colorPrimary

    readonly property var points: {
        const list = root.values ?? [];
        const out = [];
        if (list.length < 2 || root.width <= 0 || root.height <= 0)
            return out;
        const step = root.width / Math.max(1, root.capacity - 1);
        const first = root.capacity - list.length;
        for (let i = 0; i < list.length; ++i) {
            const ratio = Math.max(0, Math.min(1, Number(list[i] ?? 0) / root.maxValue));
            out.push(Qt.point((first + i) * step, root.height - 1 - ratio * (root.height - 2)));
        }
        return out;
    }
    readonly property var area: root.points.length < 2
        ? []
        : [Qt.point(root.points[0].x, root.height)]
            .concat(root.points)
            .concat([Qt.point(root.width, root.height), Qt.point(root.points[0].x, root.height)])

    visible: root.points.length >= 2
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: "transparent"
        fillColor: Qt.alpha(root.lineColor, 0.16)
        PathPolyline { path: root.area }
    }

    ShapePath {
        strokeColor: root.lineColor
        strokeWidth: 1.5
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.RoundCap
        PathPolyline { path: root.points }
    }
}
