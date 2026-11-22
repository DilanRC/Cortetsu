import QtQuick
import QtTest
import "../../../modules/BottomHubTray.js" as TrayPolicy
import "../../../utils/TrayIconName.js" as TrayIconName

TestCase {
    name: "BottomHubTrayPolicy"

    function test_passive_and_hidden_items_are_filtered() {
        const items = [
            { id: "active", status: 1 },
            { id: "attention", status: 2 },
            { id: "passive", status: 0 },
            { id: "hidden", status: 1 }
        ];
        const result = TrayPolicy.visibleItems(items, ["hidden"], 0);
        compare(result.length, 2);
        compare(result[0].id, "active");
        compare(result[1].id, "attention");
        compare(TrayPolicy.visibleItems(items, ["active", "attention", "hidden"], 0).length, 0);
    }

    // The magenta checker in the tray came from handing image://icon/NAME
    // straight to Image when the theme lacks NAME; the name and the app's
    // folder are read apart so they can be looked up.
    function test_named_tray_icons_are_split_into_name_and_folder() {
        const spotify = TrayIconName.namedIcon("image://icon/spotify-linux-32?path=/opt/spotify/icons");
        compare(spotify.name, "spotify-linux-32");
        compare(spotify.dir, "/opt/spotify/icons");
        const themed = TrayIconName.namedIcon("image://icon/nm-signal-75");
        compare(themed.name, "nm-signal-75");
        compare(themed.dir, "");
        compare(TrayIconName.namedIcon("image://icon/").name, "");
        compare(TrayIconName.namedIcon("image://qspixmap/zapzap/0"), null);
        compare(TrayIconName.namedIcon("file:///tmp/a.png"), null);
        compare(TrayIconName.namedIcon(""), null);
        compare(TrayIconName.namedIcon("image://icon/a%20b?path=/x%20y").dir, "/x y");
        // Seen live: an item with no pixmap arrives at revision 0.
        verify(TrayIconName.emptyPixmap("image://qspixmap/1/0"));
        verify(!TrayIconName.emptyPixmap("image://qspixmap/2/1"));
        verify(!TrayIconName.emptyPixmap("image://qspixmap/3/10"));
        verify(!TrayIconName.emptyPixmap("image://icon/x"));
    }

    function test_tooltip_prefers_localized_title_and_falls_back_safely() {
        compare(TrayPolicy.tooltipFor({
            id: "service-id",
            title: "Aplicación",
            tooltipTitle: "  Estado  ",
            tooltipDescription: "Sincronizado"
        }), "Estado\nSincronizado");
        compare(TrayPolicy.tooltipFor({ id: "fallback-id", title: " ", tooltipTitle: "" }), "fallback-id");
    }

    function test_primary_and_context_menu_contract() {
        compare(TrayPolicy.primaryAction({ onlyMenu: false, hasMenu: false }), "activate");
        compare(TrayPolicy.primaryAction({ onlyMenu: true, hasMenu: true }), "menu");
        compare(TrayPolicy.primaryAction({ onlyMenu: true, hasMenu: false }), "none");
        compare(TrayPolicy.contextAction({ hasMenu: true }), "menu");
        compare(TrayPolicy.contextAction({ hasMenu: false }), "none");
    }

    function test_menu_identity_survives_tray_reordering() {
        const steam = { id: "same-id" };
        const browser = { id: "same-id" };
        const before = [steam, browser].map(TrayPolicy.instanceKey).map(TrayPolicy.menuName);
        const after = [browser, steam].map(TrayPolicy.instanceKey).map(TrayPolicy.menuName);
        compare(before[0], after[1]);
        compare(before[1], after[0]);
        verify(before[0] !== before[1]);
    }

    function test_keys_survive_filtering_by_another_tray() {
        const active = { id: "active", status: 1 };
        const passive = { id: "passive", status: 0 };
        const all = [active, passive];
        const first = TrayPolicy.instanceKey(passive);
        // The bar shows only active items; the hub may show both.
        TrayPolicy.visibleEntries(all, [], 0);
        TrayPolicy.visibleEntries(all, [], 0);
        compare(TrayPolicy.instanceKey(passive), first);
        // An item that left the tray loses its key.
        TrayPolicy.visibleEntries([active], [], 0);
        verify(TrayPolicy.instanceKey(passive) !== first);
    }
}
