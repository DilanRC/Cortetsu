import QtQuick
import QtTest
import "../../../modules/BottomHubTray.js" as TrayPolicy

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
