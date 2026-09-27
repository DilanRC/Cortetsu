import QtQuick
import QtTest
import "../../../modules/BottomHubTray.js" as Tray

TestCase {
    name: "TrayNavigation"

    function selectable(rows) {
        return index => rows[index].enabled && !rows[index].separator;
    }

    function test_leading_separator_and_disabled_entry() {
        const rows = [
            { separator: true, enabled: true },
            { separator: false, enabled: false },
            { separator: false, enabled: true },
            { separator: false, enabled: true }
        ];
        compare(Tray.nextSelectable(rows.length, -1, 1, selectable(rows)), 2);
    }

    function test_all_disabled_and_dynamic_update() {
        let rows = [
            { separator: false, enabled: false },
            { separator: true, enabled: false }
        ];
        compare(Tray.nextSelectable(rows.length, -1, 1, selectable(rows)), -1);

        rows = rows.concat({ separator: false, enabled: true });
        compare(Tray.nextSelectable(rows.length, -1, 1, selectable(rows)), 2);
    }

    function test_removed_focused_row_moves_to_next_selectable() {
        let rows = [
            { separator: false, enabled: true },
            { separator: false, enabled: true },
            { separator: false, enabled: true }
        ];
        rows = rows.filter((_, index) => index !== 1);
        compare(Tray.nextSelectable(rows.length, 0, 1, selectable(rows)), 1);
    }

    function test_stable_count_reorder_restores_same_entry() {
        const first = { enabled: true, separator: false };
        const focused = { enabled: true, separator: false };
        const third = { enabled: true, separator: false };
        let rows = [first, focused, third];
        compare(Tray.indexOfEntry(rows.length, index => rows[index], focused), 1);
        rows = [third, first, focused];
        compare(Tray.indexOfEntry(rows.length, index => rows[index], focused), 2);
    }

    function test_tab_can_leave_at_menu_edge() {
        const rows = [
            { separator: false, enabled: true },
            { separator: false, enabled: false }
        ];
        compare(Tray.nextSelectable(rows.length, 0, 1, selectable(rows)), -1);
        compare(Tray.nextSelectable(rows.length, 0, -1, selectable(rows)), -1);
    }

    function test_equal_application_ids_get_distinct_stable_instance_keys() {
        const first = { id: "same-app", title: "First" };
        const second = { id: "same-app", title: "Second" };
        const firstKey = Tray.instanceKey(first);
        const secondKey = Tray.instanceKey(second);
        const items = [first, second];
        verify(firstKey !== secondKey);
        compare(Tray.instanceKey(first), firstKey);
        compare(Tray.instanceKey(second), secondKey);
        compare(Tray.itemForKey(items, firstKey), first);
        compare(Tray.itemForKey(items, secondKey), second);
        compare(Tray.menuName(firstKey), "traymenu" + firstKey);
        compare(Tray.menuName(secondKey), "traymenu" + secondKey);
    }
}
