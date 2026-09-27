import QtQuick
import QtTest
import "../../../modules"

TestCase {
    id: testCase
    name: "BottomHubDelegates"
    when: windowShown
    visible: true
    width: 640
    height: 480

    property var dockItems: []
    property var trayItems: []
    property int workspaceCount: 3

    Component {
        id: appRailComponent
        CortetsuAppRail {
            items: testCase.dockItems
            maxWidth: 500
        }
    }

    Component {
        id: trayComponent
        CortetsuTraySegment {
            items: testCase.trayItems
        }
    }

    Component {
        id: workspacesComponent
        CortetsuWorkspaceDots {
            workspaceCount: testCase.workspaceCount
            workspaceOffset: 0
            activeWsId: 1
            occupiedWorkspaceIds: [1]
        }
    }

    function dockItem(key, active = false, enabled = true) {
        return {
            key,
            title: key,
            active,
            pinned: false,
            running: true,
            windowCount: 1,
            iconSource: "",
            enabled
        };
    }

    function trayItem(id, title = id, enabled = true) {
        return {
            id,
            title,
            iconSource: "",
            onlyMenu: false,
            hasMenu: false,
            enabled
        };
    }

    function focusedDockCount(rail, items) {
        let count = 0;
        for (const item of items) {
            if (findChild(rail, `dock-${item.key}`)?.activeFocus)
                count++;
        }
        return count;
    }

    function test_dock_delegate_creation_does_not_steal_focus() {
        dockItems = [dockItem("one"), dockItem("two")];
        const rail = appRailComponent.createObject(testCase);
        verify(rail !== null);
        tryVerify(() => findChild(rail, "dock-one") !== null);
        tryVerify(() => findChild(rail, "dock-two") !== null);

        const first = findChild(rail, "dock-one");
        const second = findChild(rail, "dock-two");
        second.forceActiveFocus();
        tryCompare(second, "activeFocus", true);
        compare(focusedDockCount(rail, dockItems), 1);

        dockItems = [dockItem("one", true), dockItem("two"), dockItem("three")];
        tryVerify(() => findChild(rail, "dock-three") !== null);
        verify(findChild(rail, "dock-one") !== null);
        verify(findChild(rail, "dock-two") !== null);
        verify(!findChild(rail, "dock-three").activeFocus);
        compare(focusedDockCount(rail, dockItems), 0);
        rail.destroy();
    }

    function test_click_focus_then_tab_and_shift_tab_keep_one_delegate_focused() {
        dockItems = [dockItem("one"), dockItem("two"), dockItem("disabled", false, false), dockItem("four")];
        const rail = appRailComponent.createObject(testCase);
        verify(rail !== null);
        tryVerify(() => findChild(rail, "dock-four") !== null);

        const first = findChild(rail, "dock-one");
        const second = findChild(rail, "dock-two");
        const disabled = findChild(rail, "dock-disabled");
        const fourth = findChild(rail, "dock-four");
        mouseClick(second, second.width / 2, second.height / 2, Qt.LeftButton);
        tryCompare(second, "activeFocus", true);
        compare(focusedDockCount(rail, dockItems), 1);
        keyClick(Qt.Key_Tab);
        tryCompare(fourth, "activeFocus", true);
        compare(focusedDockCount(rail, dockItems), 1);
        verify(!disabled.activeFocus);
        keyClick(Qt.Key_Tab, Qt.ShiftModifier);
        tryCompare(second, "activeFocus", true);
        compare(focusedDockCount(rail, dockItems), 1);
        verify(!first.activeFocus);
        rail.destroy();
    }

    function test_tab_order_skips_disabled_and_shift_tab_returns() {
        dockItems = [dockItem("one"), dockItem("disabled", false, false), dockItem("three")];
        const rail = appRailComponent.createObject(testCase);
        verify(rail !== null);
        tryVerify(() => findChild(rail, "dock-three") !== null);

        const first = findChild(rail, "dock-one");
        const disabled = findChild(rail, "dock-disabled");
        const third = findChild(rail, "dock-three");
        first.forceActiveFocus();
        keyClick(Qt.Key_Tab);
        tryCompare(third, "activeFocus", true);
        verify(!disabled.activeFocus);
        keyClick(Qt.Key_Tab, Qt.ShiftModifier);
        tryCompare(first, "activeFocus", true);
        rail.destroy();
    }

    function test_tray_zero_to_n_and_model_change_do_not_focus_new_delegate() {
        trayItems = [];
        const tray = trayComponent.createObject(testCase);
        verify(tray !== null);
        tryCompare(tray, "visible", false);

        trayItems = [trayItem("alpha")];
        tryCompare(tray, "visible", true);
        tryVerify(() => findChild(tray, "tray-alpha") !== null);
        const alpha = findChild(tray, "tray-alpha");
        alpha.forceActiveFocus();

        trayItems = [trayItem("alpha", "updated tooltip"), trayItem("beta")];
        tryVerify(() => findChild(tray, "tray-beta") !== null);
        verify(findChild(tray, "tray-alpha") !== null);
        verify(!findChild(tray, "tray-beta").activeFocus);

        trayItems = [];
        tryCompare(tray, "visible", false);
        tryVerify(() => findChild(tray, "tray-alpha") === null);
        tray.destroy();
    }

    function test_tray_click_routes_only_menu_middle_and_context() {
        trayItems = [Object.assign(trayItem("plain"), { onlyMenu: false, hasMenu: false })];
        const tray = trayComponent.createObject(testCase);
        verify(tray !== null);
        tryVerify(() => findChild(tray, "tray-plain") !== null);

        let activated = 0;
        let menus = 0;
        let secondary = 0;
        tray.activateRequested.connect(() => activated++);
        tray.secondaryRequested.connect(() => menus++);
        tray.secondaryActivateRequested.connect(() => secondary++);
        const plain = findChild(tray, "tray-plain");
        mouseClick(plain, plain.width / 2, plain.height / 2, Qt.LeftButton);
        mouseClick(plain, plain.width / 2, plain.height / 2, Qt.RightButton);
        mouseClick(plain, plain.width / 2, plain.height / 2, Qt.MiddleButton);
        compare(activated, 1);
        compare(menus, 0);
        compare(secondary, 1);

        trayItems = [Object.assign(trayItem("menu"), { onlyMenu: true, hasMenu: true })];
        tryVerify(() => findChild(tray, "tray-menu") !== null);
        const menu = findChild(tray, "tray-menu");
        mouseClick(menu, menu.width / 2, menu.height / 2, Qt.LeftButton);
        compare(activated, 1);
        compare(menus, 1);
        mouseClick(menu, menu.width / 2, menu.height / 2, Qt.RightButton);
        compare(menus, 2);

        trayItems = [Object.assign(trayItem("menu"), { onlyMenu: true, hasMenu: false })];
        mouseClick(findChild(tray, "tray-menu"), menu.width / 2, menu.height / 2, Qt.LeftButton);
        compare(activated, 1);
        compare(menus, 2);
        tray.destroy();
    }

    function test_tray_wheel_forwards_vertical_and_horizontal_delta() {
        trayItems = [trayItem("scroll")];
        const tray = trayComponent.createObject(testCase);
        verify(tray !== null);
        tryVerify(() => findChild(tray, "tray-scroll") !== null);
        let deltas = [];
        tray.scrollRequested.connect((id, delta, horizontal) => deltas.push({ id, delta, horizontal }));
        const item = findChild(tray, "tray-scroll");

        mouseWheel(item, item.width / 2, item.height / 2, 0, 120);
        mouseWheel(item, item.width / 2, item.height / 2, -120, 0);
        compare(deltas.length, 2);
        compare(deltas[0].id, "scroll");
        compare(deltas[0].delta, 120);
        compare(deltas[0].horizontal, false);
        compare(deltas[1].delta, -120);
        compare(deltas[1].horizontal, true);
        tray.destroy();
    }

    function test_workspace_dots_have_one_stable_tab_chain() {
        const workspaces = workspacesComponent.createObject(testCase);
        verify(workspaces !== null);
        tryVerify(() => findChild(workspaces, "workspace-3") !== null);
        const first = findChild(workspaces, "workspace-1");
        const second = findChild(workspaces, "workspace-2");
        first.forceActiveFocus();
        keyClick(Qt.Key_Tab);
        tryCompare(second, "activeFocus", true);
        keyClick(Qt.Key_Tab, Qt.ShiftModifier);
        tryCompare(first, "activeFocus", true);
        workspaces.destroy();
    }
}
