import QtQuick
import QtQuick.Controls
import "../theme"
import "../modules/CortetsuTypography.js" as CortetsuTypography

ToolTip {
    id: root

    property Item target: null
    property bool hovered: false
    property bool focused: false
    // "above" centres it over the target and "below" under it; "right" and
    // "left" set it beside the target, for side navigation and a lateral Hub,
    // where above would cover the previous row.
    property string placement: "above"
    readonly property bool beside: placement === "right" || placement === "left"

    readonly property bool wanted: root.target !== null
        && root.text.length > 0
        && (root.hovered || root.focused)
        && !(root.host?.tooltipsSuppressed ?? false)
    // The nearest ancestor that declares `tooltipExtent` (the Hub view): it
    // keeps room for these tooltips and may ask them to step aside while a
    // popout of its own is showing, so none lands on the popout.
    property Item host: null
    // Shown without delay or fade because another tooltip was just open.
    property bool warm: false
    // How long a closed tooltip keeps the next one warm.
    readonly property int warmGraceMs: CortetsuDesign.tooltipDelayMs * 2

    parent: root.target
    // From the implicit size, which a hidden Popup already knows.
    readonly property point place: !root.target ? Qt.point(0, 0) : Qt.point(
        root.placement === "right" ? root.target.width + CortetsuDesign.spacingCompact
            : root.placement === "left" ? -root.implicitWidth - CortetsuDesign.spacingCompact
            : Math.round((root.target.width - root.implicitWidth) / 2),
        root.beside ? Math.round((root.target.height - root.implicitHeight) / 2)
            : root.placement === "below" ? root.target.height + CortetsuDesign.spacingCompact / 2
            : -root.implicitHeight - CortetsuDesign.spacingCompact / 2)
    x: root.place.x
    y: root.place.y
    delay: 0
    visible: false
    leftPadding: CortetsuDesign.spacingStandard
    rightPadding: CortetsuDesign.spacingStandard
    topPadding: CortetsuDesign.spacingCompact
    bottomPadding: CortetsuDesign.spacingCompact

    // A window only as large as its controls (the Hub) cannot hold a tooltip
    // beside them: the Popup keeps itself inside the window and lands on its
    // own control, where it takes the click. The nearest ancestor declaring
    // `tooltipExtent` keeps the largest size its tooltips can take, so it can
    // reserve that room for good: room that appears on hover would resize the
    // window under a still pointer, and Hyprland drops the next click.
    readonly property real maxWidth: 320
    // A lookup, not a binding: a binding would depend on the extent it sets.
    function reportExtent(): void {
        let host = root.target;
        while (host && !("tooltipExtent" in host))
            host = host.parent;
        root.host = host;
        if (!host || root.text.length === 0)
            return;
        const extent = host.tooltipExtent;
        if (root.implicitWidth > extent.width || root.implicitHeight > extent.height)
            host.tooltipExtent = Qt.size(Math.max(extent.width, root.implicitWidth),
                                         Math.max(extent.height, root.implicitHeight));
    }

    onImplicitWidthChanged: reportExtent()
    onImplicitHeightChanged: reportExtent()
    onTargetChanged: reportExtent()

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

    Component.onCompleted: {
        Qt.callLater(root.reportExtent);
        if (root.wanted)
            delayTimer.start();
    }

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

    implicitWidth: Math.min(root.maxWidth, implicitContentWidth + leftPadding + rightPadding)
    contentItem: CortetsuText {
        text: root.text
        textSize: CortetsuTypography.labelSmallPx
        color: CortetsuDesign.colorWashi
        elide: Text.ElideRight
    }
}
