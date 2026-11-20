.pragma library

// What a digit key does in the overview. Pure: the caller passes the key,
// the modifiers and this screen's ten workspace ids (rail order).
// The values are Qt's (Qt.Key_0..Key_9, Qt.*Modifier), stable across Qt 6.

var KEY_0 = 0x30;
var KEY_1 = 0x31;
var KEY_9 = 0x39;
var SHIFT = 0x02000000;
var CONTROL = 0x04000000;
var ALT = 0x08000000;
var META = 0x10000000;

// 1..9 are the first nine workspaces, 0 the tenth. -1 for any other key.
function slotForKey(key) {
    if (key === KEY_0)
        return 9;
    if (key >= KEY_1 && key <= KEY_9)
        return key - KEY_1;
    return -1;
}

// { action: "open" | "move" | "", workspace }. A plain digit opens the
// workspace; Alt+digit sends the selected window there; Ctrl, Shift or
// Super with a digit belong to someone else and do nothing here.
function digitAction(key, modifiers, ids) {
    var slot = slotForKey(key);
    var workspace = slot >= 0 && ids && ids[slot] !== undefined ? ids[slot] : -1;
    if (workspace <= 0 || (modifiers & (CONTROL | SHIFT | META)))
        return { action: "", workspace: -1 };
    return { action: (modifiers & ALT) ? "move" : "open", workspace: workspace };
}
