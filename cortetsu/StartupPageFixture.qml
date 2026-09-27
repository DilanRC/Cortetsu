import QtQuick
import Quickshell
import "modules/hardware"

ShellRoot {
    StartupPage {
        id: page
        width: 900
        height: 520
        helperPath: "/usr/bin/true"
    }

    Timer {
        interval: 100
        running: true
        onTriggered: {
            page.entries = [
                { id: "discord", name: "Discord", sourceType: "xdg-user", configured: true, command: "discord --start-minimized", origin: "/home/test/.config/autostart/discord.desktop", description: "" },
                { id: "clock", name: "Clock", sourceType: "systemd-user", configured: false, command: "clockd", origin: "clock.service", description: "" },
                { id: "network", name: "Network", sourceType: "systemd-system", configured: true, command: "", origin: "NetworkManager.service", description: "" }
            ];
            page.query = "discord --start";
            if (page.visibleEntries.length !== 1 || page.visibleEntries[0].id !== "discord") {
                console.error("STARTUP_PAGE_FAIL search");
                Qt.quit();
                return;
            }
            page.query = "";
            page.sourceFilter = "user";
            if (page.visibleEntries.length !== 1 || page.visibleEntries[0].id !== "clock") {
                console.error("STARTUP_PAGE_FAIL source-filter");
                Qt.quit();
                return;
            }
            page.sourceFilter = "all";
            page.enabledFilter = "disabled";
            if (page.visibleEntries.length !== 1 || page.visibleEntries[0].id !== "clock") {
                console.error("STARTUP_PAGE_FAIL state-filter");
                Qt.quit();
                return;
            }
            console.log("STARTUP_PAGE_PASS search=1 source-filter=1 state-filter=1");
            Qt.quit();
        }
    }
}
