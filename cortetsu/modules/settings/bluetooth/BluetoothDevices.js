.pragma library

// Pure helpers for the Bluetooth page: grouping, order, labels and icons.
// They read only what BlueZ reports through Quickshell.Bluetooth.

// BlueZ "Icon" values (freedesktop names) to Material Symbols.
const ICONS = {
    "audio-headset": "headset_mic",
    "audio-headphones": "headphones",
    "audio-card": "speaker",
    "input-keyboard": "keyboard",
    "input-mouse": "mouse",
    "input-gaming": "sports_esports",
    "input-tablet": "stylus",
    "phone": "smartphone",
    "computer": "computer",
    "camera-video": "videocam",
    "camera-photo": "photo_camera",
    "printer": "print",
    "multimedia-player": "music_note",
    "video-display": "tv",
    "scanner": "scanner",
    "network-wireless": "router"
};

const KINDS = {
    "audio-headset": "Auriculares con micrófono",
    "audio-headphones": "Auriculares",
    "audio-card": "Altavoz",
    "input-keyboard": "Teclado",
    "input-mouse": "Ratón",
    "input-gaming": "Mando",
    "input-tablet": "Tableta",
    "phone": "Teléfono",
    "computer": "Ordenador",
    "camera-video": "Cámara",
    "camera-photo": "Cámara",
    "printer": "Impresora",
    "multimedia-player": "Reproductor",
    "video-display": "Pantalla",
    "scanner": "Escáner",
    "network-wireless": "Punto de acceso"
};

function icon(device) {
    return ICONS[String(device?.icon ?? "")] ?? "bluetooth";
}

// Empty when BlueZ reports no class: the inspector then hides the row.
function kind(device) {
    return KINDS[String(device?.icon ?? "")] ?? "";
}

// "connected" before "paired" before "available", the order the list uses.
function group(device) {
    if (device?.connected) return "connected";
    if (device?.paired || device?.bonded) return "paired";
    return "available";
}

const RANK = { connected: 0, paired: 1, available: 2 };

function displayName(device) {
    const name = String(device?.name ?? "").trim();
    return name.length > 0 ? name : String(device?.address ?? "");
}

// filter: "all" | "paired" (connected or paired) | "new" (never paired)
function matches(device, filter) {
    if (filter === "paired") return group(device) !== "available";
    if (filter === "new") return group(device) === "available";
    return true;
}

function visible(devices, filter, query) {
    const needle = String(query ?? "").trim().toLowerCase();
    return (devices ?? []).filter(device => {
        if (!matches(device, filter)) return false;
        if (!needle) return true;
        return displayName(device).toLowerCase().includes(needle)
            || String(device.address ?? "").toLowerCase().includes(needle);
    }).sort((left, right) => {
        const byGroup = RANK[group(left)] - RANK[group(right)];
        if (byGroup !== 0) return byGroup;
        // Unnamed devices (only an address) go last inside their group.
        const leftNamed = String(left.name ?? "").trim().length > 0;
        const rightNamed = String(right.name ?? "").trim().length > 0;
        if (leftNamed !== rightNamed) return leftNamed ? -1 : 1;
        return displayName(left).localeCompare(displayName(right));
    });
}

function count(devices, filter) {
    return (devices ?? []).filter(device => matches(device, filter)).length;
}

// Battery is reported by BlueZ Battery1 as 0..1 through Quickshell; anything
// else means there is no reliable reading and nothing is shown.
function batteryPercent(device) {
    if (!device?.batteryAvailable) return -1;
    const value = Number(device.battery);
    if (!isFinite(value) || value < 0 || value > 1) return -1;
    return Math.round(value * 100);
}
