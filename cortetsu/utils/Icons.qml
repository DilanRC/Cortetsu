pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "TrayIconName.js" as TrayIconName

Singleton {
    readonly property var categoryIcons: ({WebBrowser:"web", Printing:"print", Security:"security", Network:"chat", Development:"code", IDE:"code", Audio:"music_note", Music:"music_note", Player:"music_note", Recorder:"mic", Game:"sports_esports", FileManager:"files", Settings:"settings", TerminalEmulator:"terminal", Utility:"build", Monitor:"monitor_heart", Video:"videocam", Graphics:"photo_library", TV:"tv", System:"host", Office:"content_paste"})

    function getAppIcon(name: string, fallback: string): string {
        const value = String(name ?? "");
        if (value.startsWith("file://") || value.startsWith("/"))
            return value.startsWith("/") ? `file://${value}` : value;

        const entry = DesktopEntries.heuristicLookup(value);
        const entryIcon = String(entry?.icon ?? "");
        const steamMatch = (value.match(/^(?:steam_app|steam_icon)_([0-9]+)$/i)
            ?? entryIcon.match(/^steam_icon_(\d+)$/i));
        if (steamMatch) {
            const iconName = `steam_icon_${steamMatch[1]}`;
            // Steam's generated desktop entries are not always visible to
            // Quickshell's icon theme lookup. Keep the user icon cache as a
            // deterministic fallback for taskbar/overview surfaces.
            const home = Quickshell.env("HOME") || "";
            const cachedIcon = `file://${home}/.local/share/icons/hicolor/128x128/apps/${iconName}.png`;
            return Quickshell.iconPath(iconName, cachedIcon);
        }

        return Quickshell.iconPath(entryIcon || value, fallback);
    }
    function getAppCategoryIcon(name: string, fallback: string): string {
        const categories = DesktopEntries.heuristicLookup(name)?.categories ?? [];
        for (const key of Object.keys(categoryIcons)) if (categories.includes(key)) return categoryIcons[key];
        return fallback;
    }
    function getNetworkIcon(strength: int, secure = false): string {
        const suffix = secure ? "_locked" : "";
        if (strength >= 80) return `network_wifi${suffix}`;
        if (strength >= 60) return `network_wifi_3_bar${suffix}`;
        if (strength >= 40) return `network_wifi_2_bar${suffix}`;
        if (strength >= 20) return `network_wifi_1_bar${suffix}`;
        return "signal_wifi_0_bar";
    }
    function getBluetoothIcon(icon: string): string {
        if (icon.includes("headset") || icon.includes("headphones")) return "headphones";
        if (icon.includes("audio")) return "speaker";
        if (icon.includes("phone")) return "smartphone";
        if (icon.includes("mouse")) return "mouse";
        if (icon.includes("keyboard")) return "keyboard";
        return "bluetooth";
    }
    function getNotifIcon(summary: string, urgency: int): string {
        const value = summary.toLowerCase();
        if (value.includes("reboot")) return "restart_alt";
        if (value.includes("recording")) return "screen_record";
        if (value.includes("battery")) return "power";
        if (value.includes("screenshot")) return "screenshot_monitor";
        if (value.includes("welcome")) return "waving_hand";
        if (value.includes("time") || value.includes("a break")) return "schedule";
        if (value.includes("installed")) return "download";
        if (value.includes("update")) return "update";
        if (value.includes("unable to")) return "deployed_code_alert";
        if (value.includes("profile")) return "person";
        if (value.includes("file")) return "folder_copy";
        return urgency === NotificationUrgency.Critical ? "release_alert" : "chat";
    }
    function getVolumeIcon(volume: real, muted: bool): string { return muted ? "no_sound" : volume >= 0.5 ? "volume_up" : volume > 0 ? "volume_down" : "volume_mute"; }
    function getMicVolumeIcon(volume: real, muted: bool): string { return !muted && volume > 0 ? "mic" : "mic_off"; }
    function getSpecialWsIcon(name: string): string {
        const value = name.toLowerCase().slice("special:".length);
        return ({special:"star", communication:"forum", music:"music_cast", todo:"checklist", sysmon:"monitor_heart"})[value] ?? (value ? value[0].toUpperCase() : "star");
    }
    // A tray item's icon as Qt can draw it. Quickshell hands a named icon
    // as image://icon/NAME, with ?path=DIR when the app ships its own theme
    // folder (IconThemePath). The icon provider paints a magenta checker
    // for a name it cannot find, so a name is looked up first: the theme,
    // then the app's folder (where SNI apps keep PNGs), then the app's
    // desktop entry. Pixmaps and files pass through untouched.
    // The first of `names` that the icon theme (or a desktop entry it
    // names) really has, as a path; "" when none does. Unlike iconPath with
    // a fallback, a missing name never reaches Image as image://icon/NAME.
    function existingIcon(names: var): string {
        for (const raw of names) {
            const name = String(raw ?? "").trim();
            if (!name)
                continue;
            // By id or class first, then by the name people see (a tray
            // tooltip says «Linux Wallpaper Engine», not its desktop id).
            const entry = DesktopEntries.heuristicLookup(name)
                ?? DesktopEntries.applications.values.find(app => app.name === name) ?? null;
            for (const candidate of [entry?.icon, name]) {
                const found = candidate ? Quickshell.iconPath(candidate, true) : "";
                if (found)
                    return found;
            }
            // An installed app whose icon is a loose file in the standard
            // pixmaps folder, outside every icon theme.
            const loose = String(entry?.icon ?? "");
            if (loose.startsWith("/"))
                return `file://${loose}`;
            if (loose)
                return `file:///usr/share/pixmaps/${loose}.png`;
        }
        return "";
    }

    // A tray item's icon as Qt can draw it. Quickshell hands a named icon as
    // image://icon/NAME (with ?path=DIR when the app ships its own folder);
    // the icon provider paints a magenta checker for a name it cannot find.
    // Order: the theme, the app's folder, then the app by id, tooltip title
    // and title (Electron apps such as Linux Wallpaper Engine send no icon
    // at all), then a generic application icon. Pixmaps and files pass.
    function getTrayIcon(id: string, icon: string, titles: var): string {
        const named = TrayIconName.namedIcon(icon);
        const fallback = () => existingIcon([id].concat(titles ?? []))
            || Quickshell.iconPath("application-x-executable", true) || "";
        if (!named)
            return String(icon ?? "").length > 0 && !TrayIconName.emptyPixmap(icon) ? String(icon) : fallback();
        const themed = named.name ? Quickshell.iconPath(named.name, true) : "";
        if (themed)
            return themed;
        if (named.name && named.dir)
            return `file://${named.dir}/${named.name}.png`;
        return fallback();
    }
    function getBatteryIcon(percentage: real, charging = false): string {
        if (percentage === 1) return charging ? "battery_charging_full" : "battery_full";
        let level = Math.floor(percentage * 7);
        if (charging && (level === 4 || level === 1)) level--;
        return charging ? `battery_charging_${(level + 3) * 10}` : `battery_${level}_bar`;
    }
}
