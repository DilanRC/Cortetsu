.pragma library

// Chord capture rules for the shortcut editor. Pure functions so the listening
// state can be tested without a keyboard.

var MODIFIER_ORDER = ["CTRL", "ALT", "SHIFT", "SUPER"];

var NAMED_KEYS = (function () {
    var names = {};
    names[Qt.Key_Space] = "Space";
    names[Qt.Key_Return] = "Return";
    names[Qt.Key_Enter] = "Return";
    names[Qt.Key_Tab] = "Tab";
    names[Qt.Key_Backtab] = "Tab";
    names[Qt.Key_Backspace] = "Backspace";
    names[Qt.Key_Delete] = "Delete";
    names[Qt.Key_Insert] = "Insert";
    names[Qt.Key_Left] = "Left";
    names[Qt.Key_Right] = "Right";
    names[Qt.Key_Up] = "Up";
    names[Qt.Key_Down] = "Down";
    names[Qt.Key_PageUp] = "Page_Up";
    names[Qt.Key_PageDown] = "Page_Down";
    names[Qt.Key_Home] = "Home";
    names[Qt.Key_End] = "End";
    names[Qt.Key_Print] = "Print";
    names[Qt.Key_Comma] = "Comma";
    names[Qt.Key_Period] = "Period";
    names[Qt.Key_Slash] = "Slash";
    names[Qt.Key_Backslash] = "Backslash";
    names[Qt.Key_Minus] = "Minus";
    names[Qt.Key_Equal] = "Equal";
    // Dedicated keys, under their XF86 keysym names (Hyprland's spelling).
    names[Qt.Key_MonBrightnessUp] = "XF86MonBrightnessUp";
    names[Qt.Key_MonBrightnessDown] = "XF86MonBrightnessDown";
    names[Qt.Key_VolumeUp] = "XF86AudioRaiseVolume";
    names[Qt.Key_VolumeDown] = "XF86AudioLowerVolume";
    names[Qt.Key_VolumeMute] = "XF86AudioMute";
    names[Qt.Key_MicMute] = "XF86AudioMicMute";
    names[Qt.Key_MediaPlay] = "XF86AudioPlay";
    names[Qt.Key_MediaTogglePlayPause] = "XF86AudioPlay";
    names[Qt.Key_MediaNext] = "XF86AudioNext";
    names[Qt.Key_MediaPrevious] = "XF86AudioPrev";
    names[Qt.Key_MediaStop] = "XF86AudioStop";
    names[Qt.Key_Calculator] = "XF86Calculator";
    return names;
})();

function modifiers(mask) {
    var held = [];
    if (mask & Qt.ControlModifier) held.push("CTRL");
    if (mask & Qt.AltModifier) held.push("ALT");
    if (mask & Qt.ShiftModifier) held.push("SHIFT");
    if (mask & Qt.MetaModifier) held.push("SUPER");
    return held;
}

function isModifierKey(key) {
    return key === Qt.Key_Control || key === Qt.Key_Alt || key === Qt.Key_AltGr
        || key === Qt.Key_Shift || key === Qt.Key_Meta || key === Qt.Key_Super_L
        || key === Qt.Key_Super_R;
}

function isFunctionKey(key) {
    return key >= Qt.Key_F1 && key <= Qt.Key_F24;
}

function keyName(key, mask) {
    if ((mask & Qt.KeypadModifier) && key >= Qt.Key_0 && key <= Qt.Key_9)
        return "KP_" + String.fromCharCode(key);
    if (key >= Qt.Key_A && key <= Qt.Key_Z)
        return String.fromCharCode(key);
    if (key >= Qt.Key_0 && key <= Qt.Key_9)
        return String.fromCharCode(key);
    if (isFunctionKey(key))
        return "F" + (key - Qt.Key_F1 + 1);
    return NAMED_KEYS[key] || "";
}

// Returns { kind, chord, held }:
//   "modifier"     only modifiers are down; keep listening and echo them
//   "unsupported"  the key has no Hyprland name this editor can write
//   "bare"         a plain key without a modifier would hijack typing
//   "chord"        a complete combination, ready to save
function resolve(key, mask) {
    var held = modifiers(mask);
    if (isModifierKey(key))
        return { kind: "modifier", chord: "", held: held };
    var name = keyName(key, mask);
    if (!name)
        return { kind: "unsupported", chord: "", held: held };
    // Alone: dedicated hardware keys, Print and F13-F24. F1-F12 belong to
    // applications and games.
    var solo = name.indexOf("XF86") === 0 || key === Qt.Key_Print || (key >= Qt.Key_F13 && key <= Qt.Key_F24);
    if (held.length === 0 && !solo)
        return { kind: "bare", chord: "", held: held };
    return { kind: "chord", chord: held.concat([name]).join(" + "), held: held };
}

function parts(chord) {
    return String(chord || "").split("+").map(function (part) { return part.trim(); }).filter(Boolean);
}
