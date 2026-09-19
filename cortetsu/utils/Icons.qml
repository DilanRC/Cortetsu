pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    readonly property var weatherIcons: ({"0":"clear_day", "1":"clear_day", "2":"partly_cloudy_day", "3":"cloud", "45":"foggy", "48":"foggy", "51":"rainy", "53":"rainy", "55":"rainy", "61":"rainy", "63":"rainy", "65":"rainy", "71":"cloudy_snowing", "73":"cloudy_snowing", "75":"snowing_heavy", "80":"rainy", "81":"rainy", "82":"rainy", "85":"cloudy_snowing", "86":"snowing_heavy", "95":"thunderstorm", "96":"thunderstorm", "99":"thunderstorm"})
    readonly property var categoryIcons: ({WebBrowser:"web", Printing:"print", Security:"security", Network:"chat", Development:"code", IDE:"code", Audio:"music_note", Music:"music_note", Player:"music_note", Recorder:"mic", Game:"sports_esports", FileManager:"files", Settings:"settings", TerminalEmulator:"terminal", Utility:"build", Monitor:"monitor_heart", Video:"videocam", Graphics:"photo_library", TV:"tv", System:"host", Office:"content_paste"})

    function getAppIcon(name: string, fallback: string): string {
        const value = String(name ?? "");
        const entry = DesktopEntries.heuristicLookup(value);
        const entryIcon = String(entry?.icon ?? "");
        const steamMatch = (value.match(/^steam_app_(\d+)$/i)
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
    function getWeatherIcon(code: string): string { return weatherIcons[code] ?? "air"; }
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
    function getTrayIcon(id: string, icon: string): string {
        if (!icon.includes("?path=")) return icon;
        const parts = icon.split("?path="), file = parts[0].slice(parts[0].lastIndexOf("/") + 1);
        return Quickshell.iconPath(file, true) || Qt.resolvedUrl(`${parts[1]}/${file}`);
    }
    function getBatteryIcon(percentage: real, charging = false): string {
        if (percentage === 1) return charging ? "battery_charging_full" : "battery_full";
        let level = Math.floor(percentage * 7);
        if (charging && (level === 4 || level === 1)) level--;
        return charging ? `battery_charging_${(level + 3) * 10}` : `battery_${level}_bar`;
    }
}
