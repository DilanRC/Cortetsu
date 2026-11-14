import QtQuick
import "."
import "../theme"
import "../theme/CortetsuDesignDefaults.js" as CortetsuDefaults

// One floating Hub island: translucent scheme surface, a faint edge and a
// light along its top, so it reads on light and busy wallpapers alike.
//
// States, from the segment that holds it:
//   rest       the scheme surface and a hairline
//   hovered    the pointer is over the island: the edge comes up
//   focused    the keyboard is on one of its controls: the edge is drawn
//   engaged    a popout or panel opened from this island is showing: indigo
//              edge and wash (the segment's `engaged`; the Hub view leans
//              the whole segment towards the popout)
// Nothing here runs at rest: each change is one short Behavior, and reduced
// motion makes every one of them instant (the motion tokens are 0).
Rectangle {
    id: root

    readonly property Item segment: parent
    readonly property bool engaged: segment?.engaged ?? false
    readonly property bool hovered: hover.hovered
    readonly property bool focused: {
        let item = root.Window.activeFocusItem;
        // A control whose focus came from a press shows no mark (HubButton).
        if (item?.focusVisible === false)
            return false;
        while (item) {
            if (item === root.segment)
                return true;
            item = item.parent;
        }
        return false;
    }

    anchors.fill: parent
    anchors.margins: 3
    z: -1
    // Preserve the current Ink island alpha, while letting theme ground
    // opacity and the global transparency setting affect the other profiles.
    property real transparencyFactor: CortetsuConfig.transparencyEnabled
        ? CortetsuDesign.materialTransparencyFactor
        : 1
    readonly property real materialAlpha:
        0.82 * CortetsuDesign.materialGroundAlpha / CortetsuDefaults.materialGroundAlpha * transparencyFactor
    readonly property real hairlineScale: CortetsuDesign.materialHairlineAlpha / CortetsuDefaults.materialHairlineAlpha
    radius: Math.min(height / 2, CortetsuDesign.radiusSurface)
    // The theme's material, exactly: a theme change repaints it at once.
    color: Qt.alpha(CortetsuDesign.colorSumi, materialAlpha)
    border.width: CortetsuConfig.borderThickness
    border.color: engaged ? Qt.alpha(CortetsuDesign.colorIndigo, 0.62)
        : focused ? Qt.alpha(CortetsuDesign.colorWashi, 0.42)
        : Qt.alpha(CortetsuDesign.colorWashi, (hovered ? 0.16 : 0.08) * hairlineScale)

    Behavior on border.color { ColorAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut } }

    // On the segment, not on this item: the segment's controls lie above
    // the island and would keep the pointer from it.
    HoverHandler {
        id: hover
        parent: root.segment
    }

    // Elevation as the theme states it (Washi casts a soft shadow; Ink and
    // Kurogane do not). Two offsets read softer than one.
    Rectangle {
        visible: CortetsuDesign.materialShadowAlpha > 0
        anchors.fill: parent
        anchors.topMargin: 2
        anchors.bottomMargin: -2
        z: -1
        radius: parent.radius
        color: Qt.alpha(CortetsuDesign.colorOnSurface, CortetsuDesign.materialShadowAlpha * 0.5)
    }
    Rectangle {
        visible: CortetsuDesign.materialShadowAlpha > 0
        anchors.fill: parent
        anchors.margins: -1
        anchors.topMargin: 3
        anchors.bottomMargin: -4
        z: -2
        radius: parent.radius + 1
        color: Qt.alpha(CortetsuDesign.colorOnSurface, CortetsuDesign.materialShadowAlpha * 0.25)
    }

    // Light along the top edge, inside the hairline.
    Rectangle {
        anchors.fill: parent
        anchors.margins: root.border.width
        radius: Math.max(0, parent.radius - root.border.width)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(CortetsuDesign.colorWashi, 0.06 * root.hairlineScale) }
            GradientStop { position: 0.45; color: "transparent" }
        }
    }

    // Hover or an open popout make the ground a little denser.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Qt.alpha(CortetsuDesign.colorSumi, 0.2)
        opacity: root.hovered || root.engaged ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut } }
    }

    // The indigo wash of an engaged island.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Qt.alpha(CortetsuDesign.colorIndigo, 0.14)
        opacity: root.engaged ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut } }
    }
}
