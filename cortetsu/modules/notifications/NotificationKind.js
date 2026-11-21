.pragma library

// Which presentation a notification gets, from what the sender declares:
// the freedesktop category, its hints, its urgency, and whether it comes
// from the app of an MPRIS player. Titles are never searched for words: an
// unknown sender gets the general card.
//
// note: { urgency, hints: { category, value, "desktop-entry" }, image, appName }
// playerEntries: desktop entries of the running MPRIS players.
// Returns "error" | "progress" | "message" | "media" | "device" | "image" | "general".
function classify(note, playerEntries) {
    const hints = note?.hints ?? {};
    const category = String(hints.category ?? "").toLowerCase();
    const entry = String(hints["desktop-entry"] ?? "").toLowerCase();
    if ((note?.urgency ?? 0) >= 2 || category.endsWith(".error"))
        return "error";
    if (progress(note) >= 0 || category.startsWith("transfer"))
        return "progress";
    if (category.startsWith("im") || category.startsWith("email"))
        return "message";
    if (entry.length > 0 && (playerEntries ?? []).some(name => String(name ?? "").toLowerCase() === entry))
        return "media";
    if (category.startsWith("device") || category.startsWith("network") || category === "x-gnome.power")
        return "device";
    if (String(note?.image ?? "").length > 0)
        return "image";
    return "general";
}

// The progress a sender reports in the "value" hint, 0..100, or -1.
function progress(note) {
    const value = note?.hints?.value;
    const number = typeof value === "number" ? value : Number.parseInt(String(value ?? ""), 10);
    return Number.isFinite(number) && number >= 0 && number <= 100 ? number : -1;
}

// The glyph for a kind; a device notification names its subsystem.
function icon(kind, note) {
    const category = String(note?.hints?.category ?? "").toLowerCase();
    switch (kind) {
    case "error": return "error";
    case "progress": return category === "transfer.complete" ? "download_done" : "downloading";
    case "message": return category.startsWith("email") ? "mail" : "chat";
    case "media": return "music_note";
    case "image": return "image";
    case "device":
        if (category.startsWith("network"))
            return category.endsWith("disconnected") ? "wifi_off" : "wifi";
        if (category === "x-gnome.power")
            return "battery_alert";
        return category.endsWith("removed") ? "usb_off" : "devices";
    default: return "notifications";
    }
}
