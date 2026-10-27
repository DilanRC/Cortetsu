import QtQuick
import QtQuick.Controls
import "../theme"
import "../modules/CortetsuTypography.js" as CortetsuTypography

ToolTip {
    id: root

    property Item target: null
    property bool hovered: false
    property bool focused: false

    readonly property bool wanted: root.target !== null
        && root.text.length > 0
        && (root.hovered || root.focused)
    // Shown without delay or fade because another tooltip was just open.
    property bool warm: false
    // How long a closed tooltip keeps the next one warm.
    readonly property int warmGraceMs: CortetsuDesign.tooltipDelayMs * 2

    parent: root.target
    delay: 0
    visible: false
    leftPadding: CortetsuDesign.spacingStandard
    rightPadding: CortetsuDesign.spacingStandard
    topPadding: CortetsuDesign.spacingCompact
    bottomPadding: CortetsuDesign.spacingCompact

    function show(): void {
        delayTimer.stop();
        root.visible = true;
    }

    onWantedChanged: {
        if (!root.wanted) {
            delayTimer.stop();
            root.visible = false;
        } else if (Date.now() < CortetsuDesign.tooltipWarmUntil) {
            root.warm = true;
            root.show();
        } else {
            root.warm = false;
            delayTimer.restart();
        }
    }

    onVisibleChanged: {
        CortetsuDesign.tooltipWarmUntil = root.visible
            ? Number.MAX_VALUE
            : Date.now() + root.warmGraceMs;
    }

    Component.onCompleted: if (root.wanted) delayTimer.start()

    Component.onDestruction: {
        if (root.visible)
            CortetsuDesign.tooltipWarmUntil = Date.now() + root.warmGraceMs;
    }

    Timer {
        id: delayTimer
        interval: CortetsuDesign.tooltipDelayMs
        onTriggered: if (root.wanted) root.show()
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: root.warm ? 0 : CortetsuDesign.motionTooltipMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }

    exit: Transition {
        NumberAnimation {
            property: "opacity"
            to: 0
            duration: CortetsuDesign.motionInstantMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }

    background: CortetsuSurface {
        radiusValue: CortetsuDesign.radiusSmall
        baseColor: CortetsuDesign.colorTetsu
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.32)
        outlined: true
    }

    contentItem: CortetsuText {
        text: root.text
        textSize: CortetsuTypography.labelSmallPx
        color: CortetsuDesign.colorWashi
        elide: Text.ElideRight
    }
}
