.pragma library

// The App Rail's window preview as data: what each window of an app shows
// (title, workspace, size for the thumbnail's shape) and how the keyboard
// walks the cards. Pure, so it is testable without a compositor.

var prefix = "apppreview:";

function popoutName(appKey) {
    return prefix + appKey;
}

function appKeyOf(popoutName) {
    return typeof popoutName === "string" && popoutName.startsWith(prefix) ? popoutName.slice(prefix.length) : "";
}

// "special:scratch" is Hyprland's scratchpad: it has no number to show.
function workspaceLabel(workspace) {
    const name = String(workspace?.name ?? "");
    if (name.startsWith("special"))
        return { text: "Especial", special: true };
    const id = Number(workspace?.id);
    if (Number.isInteger(id) && id > 0)
        return { text: name.length > 0 && name !== String(id) ? name : `Espacio ${id}`, special: false };
    return { text: name, special: false };
}

// One entry per live window, in the order the rail cycles them. A window
// without an address is not one Hyprland can focus or close, so it is left
// out rather than shown as a card that does nothing.
function describe(windows, activeAddress) {
    const out = [];
    for (const client of windows ?? []) {
        const ipc = client?.lastIpcObject ?? {};
        const address = String(ipc.address ?? client?.address ?? "");
        if (address.length === 0)
            continue;
        const size = Array.isArray(ipc.size) ? ipc.size : [0, 0];
        const width = Number(size[0]) > 0 ? Number(size[0]) : 16;
        const height = Number(size[1]) > 0 ? Number(size[1]) : 9;
        const label = workspaceLabel(ipc.workspace);
        out.push({
            address: address,
            title: String(client?.title || ipc.title || ipc.class || ""),
            workspace: label.text,
            workspaceId: Number(ipc.workspace?.id ?? 0),
            special: label.special,
            aspect: width / height,
            active: address === activeAddress,
            client: client
        });
    }
    return out;
}

// The card the keyboard lands on from `index` (-1: none yet) in a grid of
// `count` cards, `columns` wide. Arrows move in the grid and stop at its
// edges; Tab and Backtab run through it in order and wrap.
function step(count, columns, index, key) {
    if (count <= 0)
        return -1;
    const cols = Math.max(1, Math.min(columns, count));
    if (index < 0 || index >= count)
        return key === "up" || key === "left" || key === "backtab" ? count - 1 : 0;
    switch (key) {
    case "left": return index % cols === 0 ? index : index - 1;
    case "right": return index % cols === cols - 1 || index + 1 >= count ? index : index + 1;
    case "up": return index - cols >= 0 ? index - cols : index;
    case "down": return index + cols < count ? index + cols : index;
    case "tab": return (index + 1) % count;
    case "backtab": return (index - 1 + count) % count;
    case "home": return 0;
    case "end": return count - 1;
    default: return index;
    }
}
