.pragma library

// Hyprland prints addresses as "0x55d0...", Quickshell exposes them without
// the prefix. Both forms must land on the same key.
function addressKey(address) {
    return String(address ?? "").replace(/^0x/i, "").toLowerCase();
}

// Parses `hyprctl -j clients` into an object keyed by address. Returns null
// when the answer is unusable, so the caller can tell that from "no windows".
function liveAddresses(raw) {
    let clients = null;
    try {
        clients = JSON.parse(raw);
    } catch (_) {}
    if (!Array.isArray(clients))
        return null;
    const live = {};
    for (const client of clients) {
        const key = addressKey(client?.address);
        if (key)
            live[key] = true;
    }
    return live;
}

// Without a list yet, every window counts as open.
function isLive(live, address) {
    return !live || live[addressKey(address)] === true;
}
