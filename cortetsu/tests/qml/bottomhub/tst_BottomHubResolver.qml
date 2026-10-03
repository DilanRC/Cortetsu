import QtQuick
import QtTest
import "../../../modules/BottomHubResolver.js" as Resolver

TestCase {
    name: "BottomHubResolver"

    function lookup(entries) {
        return id => entries.find(entry => entry.id === id) ?? null;
    }

    function pinned(ids) {
        return entry => ids.includes(entry.id);
    }

    function resolve(window, entries, pinnedIds = []) {
        return Resolver.desktopEntryForWindow(window, entries, lookup(entries), pinned(pinnedIds));
    }

    function client(address, window) {
        const ipcWindow = {
            address: address
        };
        for (const key of Object.keys(window))
            ipcWindow[key] = window[key];
        return {
            lastIpcObject: ipcWindow
        };
    }

    function test_exact_desktop_id() {
        const entry = {
            id: "org.mozilla.firefox.desktop",
            startupClass: "firefox"
        };
        compare(resolve({
            initialClass: "org.mozilla.firefox.desktop"
        }, [entry]), entry);
    }

    function test_startup_class_and_id_match_uniquely() {
        const byStartupClass = {
            id: "org.example.editor.desktop",
            startupClass: "ExampleEditor"
        };
        const byId = {
            id: "org.example.terminal.desktop",
            startupClass: "terminal"
        };
        compare(resolve({
            initialClass: "exampleeditor"
        }, [byStartupClass]), byStartupClass);
        compare(resolve({
            class: "org.example.terminal"
        }, [byId]), byId);
        compare(resolve({
            class: "shared"
        }, [
            {
                id: "one.desktop",
                startupClass: "shared"
            },
            {
                id: "two.desktop",
                startupClass: "shared"
            }
        ]), null);
    }

    function test_steam_icon_command_and_pinned_disambiguation() {
        const iconMatch = {
            id: "steam-123.desktop",
            icon: "file:///home/dilan/.local/share/icons/hicolor/128x128/apps/steam_icon_123.png"
        };
        const commandMatch = {
            id: "steam-456.desktop",
            command: ["steam", "steam://rungameid/456"]
        };
        compare(resolve({
            class: "steam_app_123"
        }, [iconMatch]), iconMatch);
        compare(resolve({
            initialClass: "steam_app_456"
        }, [commandMatch]), commandMatch);

        const otherMatch = {
            id: "steam-123-other.desktop",
            icon: "steam_icon_123"
        };
        compare(resolve({
            class: "steam_app_123"
        }, [iconMatch, otherMatch]), null);
        compare(resolve({
            class: "steam_app_123"
        }, [iconMatch, otherMatch], [otherMatch.id]), otherMatch);
        compare(resolve({
            class: "steam_app_123"
        }, [
            {
                id: "steam-1234.desktop",
                command: ["steam", "steam://rungameid/1234"]
            }
        ]), null);
    }

    function test_executable_requires_a_unique_match() {
        const vlc = {
            id: "org.videolan.VLC.desktop",
            command: ["/usr/bin/vlc"]
        };
        compare(resolve({
            initialClass: "vlc"
        }, [vlc]), vlc);
        compare(resolve({
            initialClass: "player"
        }, [
            {
                id: "one.desktop",
                command: ["/usr/bin/player"]
            },
            {
                id: "two.desktop",
                command: ["/opt/player"]
            }
        ]), null);
    }

    function test_unknown_and_partial_window_data_are_safe() {
        compare(resolve({}, []), null);
        compare(resolve({
            initialClass: "",
            class: null
        }, []), null);
        compare(resolve({
            initialClass: "uninstalled-app"
        }, []), null);
    }

    function test_groups_multiple_windows_by_resolved_desktop_entry() {
        const entry = {
            id: "org.example.chat.desktop",
            startupClass: "chat"
        };
        const first = client("0x1", {
            initialClass: "chat",
            title: "Room one"
        });
        const second = client("0x2", {
            initialClass: "chat",
            title: "Room two"
        });
        const entries = [entry];
        const groups = Resolver.groupWindows([first, second], client => Resolver.desktopEntryForWindow(client.lastIpcObject, entries, lookup(entries), pinned([])));

        compare(groups.size, 1);
        compare(groups.get(entry.id).windows.length, 2);
        compare(groups.get(entry.id).windows[0], first);
    }

    function test_distinct_windows_do_not_group_by_title_or_ambiguous_executable() {
        const first = client("0x1", {
            initialClass: "editor-one",
            title: "Untitled"
        });
        const second = client("0x2", {
            initialClass: "editor-two",
            title: "Untitled"
        });
        const groups = Resolver.groupWindows([first, second], () => null);

        compare(groups.size, 2);
        verify(groups.has("editor-one"));
        verify(groups.has("editor-two"));
    }

    function test_group_identity_survives_reorder_and_window_close() {
        const entry = {
            id: "org.example.browser.desktop"
        };
        const first = client("0x1", {
            initialClass: "browser"
        });
        const second = client("0x2", {
            initialClass: "browser"
        });
        const third = client("0x3", {
            initialClass: "other"
        });
        const resolveEntry = window => window === third ? null : entry;
        const original = Resolver.groupWindows([first, second, third], resolveEntry);
        const reordered = Resolver.groupWindows([third, second, first], resolveEntry);
        const afterClose = Resolver.groupWindows([second, third], resolveEntry);

        compare(original.get(entry.id).windows.length, 2);
        compare(reordered.get(entry.id).windows.length, 2);
        compare(afterClose.get(entry.id).windows.length, 1);
        verify(original.has("other"));
        verify(reordered.has("other"));
    }

    function test_empty_desktop_id_falls_back_to_window_identity() {
        const window = client("0x1", {
            initialClass: "legacy-app"
        });
        const groups = Resolver.groupWindows([window], () => ({
                    id: ""
                }));
        verify(groups.has("legacy-app"));
        compare(groups.size, 1);
    }

    function test_unidentified_windows_keep_address_keys() {
        const first = client("0x1", {
            title: "Same title"
        });
        const second = client("0x2", {
            title: "Same title"
        });
        const groups = Resolver.groupWindows([first, second], () => null);

        compare(groups.size, 2);
        verify(groups.has("window:0x1"));
        verify(groups.has("window:0x2"));
    }

    function test_empty_addresses_use_distinct_anonymous_keys() {
        const first = client("0x1", {
            address: "",
            class: " ",
            initialClass: ""
        });
        const second = client("0x2", {
            address: "   ",
            class: "",
            initialClass: " "
        });
        const groups = Resolver.groupWindows([first, second], () => null);

        compare(groups.size, 2);
        const keys = Array.from(groups.values()).map(group => group.key);
        verify(keys.every(key => key.startsWith("window:anonymous:")));
        verify(keys[0] !== keys[1]);
    }

    function test_anonymous_window_identity_survives_reordering_until_address_arrives() {
        const first = { lastIpcObject: {} };
        const second = { lastIpcObject: {} };
        const clients = [first, second];
        const grouped = Resolver.groupWindows(clients, () => null);
        const firstKey = Array.from(grouped.values()).find(group => group.windows[0] === first).key;
        const secondKey = Array.from(grouped.values()).find(group => group.windows[0] === second).key;
        verify(firstKey !== secondKey);

        const reordered = Resolver.groupWindows([second, first], () => null);
        compare(Array.from(reordered.values()).find(group => group.windows[0] === first).key, firstKey);
        compare(Array.from(reordered.values()).find(group => group.windows[0] === second).key, secondKey);

        first.lastIpcObject.address = "0xabc";
        const reported = Resolver.groupWindows([first, second], () => null);
        const reportedGroups = Array.from(reported.values());
        compare(reported.size, 2);
        verify(reported.has("window:0xabc"));
        verify(reportedGroups.some(group => group.windows[0] === second && group.key === secondKey));
    }

    function test_resolved_partial_windows_do_not_shift_anonymous_keys() {
        const first = {
            lastIpcObject: {}
        };
        const resolved = {
            lastIpcObject: {}
        };
        const second = {
            lastIpcObject: {}
        };
        const entry = {
            id: "org.example.partial.desktop"
        };
        const resolveEntry = window => window === resolved ? entry : null;
        const before = Resolver.groupWindows([first, second], resolveEntry);
        const groups = Resolver.groupWindows([first, resolved, second], resolveEntry);

        const firstKey = Array.from(before.values()).find(group => group.windows[0] === first).key;
        const secondKey = Array.from(before.values()).find(group => group.windows[0] === second).key;
        verify(groups.has(firstKey));
        verify(groups.has(secondKey));
        verify(groups.has(entry.id));
        compare(groups.size, 3);
    }
}
