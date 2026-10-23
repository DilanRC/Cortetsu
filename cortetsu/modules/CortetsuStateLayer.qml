import QtQuick
import "../components" as Native

// Compatibility adapter: one owner for pointer, disabled and hover state.
// Retain the historical module's stronger press feedback and flat radius.
Native.CortetsuStateLayer {
    hoverOpacity: 0.08
    pressedOpacity: 0.16
    radius: 0
}
