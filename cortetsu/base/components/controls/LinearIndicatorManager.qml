import QtQuick

// First-party linear-indicator manager.
// It models a single looping segment and splits it when it crosses an edge.
QtObject {
    id: root
    property real progress: 0
    property real completeEndProgress: 0
    property int gap: 0

    readonly property real duration: 1400
    readonly property real completeEndDuration: 350
    readonly property real segmentLength: Math.max(0.12, Math.min(0.45, 0.28 + completeEndProgress * 0.35))
    readonly property real segmentStart: Math.max(0, Math.min(1, progress)) * (1 + segmentLength) - segmentLength
    readonly property real segmentEnd: segmentStart + segmentLength
    readonly property LinearIndicatorSegment segmentA: LinearIndicatorSegment {
        startFraction: root.segmentStart < 0 || root.segmentEnd > 1 ? 0 : root.segmentStart
        endFraction: root.segmentStart < 0 ? root.segmentEnd : root.segmentEnd > 1 ? root.segmentEnd - 1 : root.segmentEnd
        gapSize: root.gap
    }
    readonly property LinearIndicatorSegment segmentB: LinearIndicatorSegment {
        startFraction: root.segmentStart < 0 ? root.segmentStart + 1 : root.segmentStart
        endFraction: 1
        gapSize: root.gap
    }
    readonly property list<LinearIndicatorSegment> activeIndicators: root.segmentStart < 0 || root.segmentEnd > 1 ? [segmentA, segmentB] : [segmentA]
}
