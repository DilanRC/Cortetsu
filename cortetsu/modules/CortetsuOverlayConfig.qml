pragma Singleton

import QtQml

// Interaction and overlay geometry defaults owned by Cortetsu.
QtObject {
    property QtObject border: QtObject {
        property real rounding: 8
        property real minThickness: 1
        property real thickness: CortetsuConfig.borderThickness
        property bool smoothing: CortetsuConfig.borderSmoothing
    }
    property QtObject general: QtObject { property bool showOverFullscreen: true }
    property QtObject appearance: QtObject { property real deformScale: 100 }
    property QtObject bar: QtObject {
        property bool showOnHover: CortetsuConfig.bar.showOnHover
        property real dragThreshold: CortetsuConfig.bar.dragThreshold
    }
    property QtObject launcher: QtObject {
        property bool enabled: CortetsuConfig.launcher.enabled
        property bool showOnHover: CortetsuConfig.launcher.showOnHover
        property real dragThreshold: CortetsuConfig.launcher.dragThreshold
    }
    property QtObject dashboard: QtObject {
        property bool enabled: CortetsuConfig.dashboard.enabled
        property bool showOnHover: CortetsuConfig.dashboard.showOnHover
        property real dragThreshold: CortetsuConfig.dashboard.dragThreshold
    }
    property QtObject session: QtObject { property bool enabled: true; property real dragThreshold: 24 }
    property QtObject sidebar: QtObject {
        property bool enabled: CortetsuConfig.sidebar.enabled
        property bool showOnHover: CortetsuConfig.sidebar.showOnHover
        property real dragThreshold: CortetsuConfig.sidebar.dragThreshold
        property real minHoverThreshold: CortetsuConfig.sidebar.minHoverThreshold
    }
    property QtObject utilities: QtObject { property bool enabled: CortetsuConfig.utilities.enabled }
}
