.pragma library

var pages = {
    summary: 0,
    performance: 1,
    processes: 2,
    sensors: 3,
    io: 4,
    power: 5,
    system: 9
};

// Index of the last tab (Sistema); 0 on the number row selects it.
var lastPage = 9;

function pageForKey(key, currentPage, key1, key9, key0) {
    if (key >= key1 && key <= key9)
        return key - key1;
    if (key === key0)
        return lastPage;
    return currentPage;
}

function handlesPageKey(key, key1, key9, key0) {
    return (key >= key1 && key <= key9) || key === key0;
}

function isEscape(key, keyEscape) {
    return key === keyEscape;
}

// What the Fn+Esc shortcut does with the Hardware Center:
// "open" when it is closed, "close" when it already shows `targetPage`
// (so the key toggles like OMEN), "switch" when it is open elsewhere.
function pageAction(isOpen, currentPage, targetPage) {
    if (!isOpen)
        return "open";
    return currentPage === targetPage ? "close" : "switch";
}

// One press of an HP WMI key can arrive twice (the event and a duplicate
// report) and a held key must not flap the panel. Presses closer than
// `windowMs` to the last accepted one are dropped. A clock that went back
// (lastMs in the future) accepts the press.
function acceptPress(lastMs, nowMs, windowMs) {
    if (!(lastMs > 0) || nowMs < lastMs)
        return true;
    return nowMs - lastMs >= windowMs;
}
