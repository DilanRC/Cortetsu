import QtQuick
import QtTest
import "../../../modules/keyboards/Model.js" as Model

TestCase {
    name: "KeyboardsModel"

    readonly property var deviceKeys: [
        { device: { id: "at", label: "Teclado integrado" }, keys: [
            { code: 16, keysym: "q", category: "typing", states: ["DECLARED", "RESERVED"] },
            { code: 140, keysym: "XF86Calculator", category: "launch", states: ["DECLARED", "CANDIDATE"] }
        ] },
        { device: { id: "wmi", label: "Teclas especiales HP" }, keys: [
            { code: 149, keysym: "XF86Launch2", category: "programmable", states: ["DECLARED", "ASSIGNED"],
              assignments: [{ chord: "XF86Launch2", description: "" }] }
        ] }
    ]
    readonly property var bindings: [
        { label: "Cerrar ventana", chord: "SUPER + Q", description: "" },
        { label: "Hardware", chord: "XF86Launch2", description: "Tecla del equipo" },
        { label: "Raro", chord: "SUPER + code:156", description: "" }
    ]

    function test_shortcuts_follow_the_keys_a_keyboard_produces() {
        compare(Model.shortcutsFor(bindings, deviceKeys, "", "").length, 3);
        compare(Model.shortcutsFor(bindings, deviceKeys, "at", "").map(b => b.label), ["Cerrar ventana"]);
        compare(Model.shortcutsFor(bindings, deviceKeys, "wmi", "").map(b => b.label), ["Hardware"]);
        compare(Model.shortcutsFor(bindings, deviceKeys, "unplugged", "").length, 3, "unknown device: no filter");
        compare(Model.shortcutsFor(bindings, deviceKeys, "", "hard").map(b => b.label), ["Hardware"]);
    }

    function test_keycode_binds_match_by_scan_code() {
        const withCode = [{ device: { id: "x", label: "X" }, keys: [{ code: 148, keysym: "", category: "launch" }] }];
        compare(Model.shortcutsFor(bindings, withCode, "x", "").map(b => b.label), ["Raro"]);
    }

    function test_special_keys_leave_typing_keys_out() {
        const all = Model.specialKeys(deviceKeys, "");
        compare(all.map(k => k.code), [140, 149]);
        compare(all[1].deviceLabel, "Teclas especiales HP");
        compare(Model.specialKeys(deviceKeys, "wmi").length, 1);
    }

    function test_labels() {
        compare(Model.stateLabel("CANDIDATE"), "Libre");
        compare(Model.confidenceLabel("declared"), "Solo la declara el controlador");
        compare(Model.kindIcon("usb"), "keyboard");
        compare(Model.parts("SUPER + ALT + I"), ["SUPER", "ALT", "I"]);
        compare(Model.currentFunction(deviceKeys[1].keys[0]), "XF86Launch2");
        compare(Model.currentFunction(deviceKeys[0].keys[1]), "Sin acción en Hyprland");
    }

    function test_spare_filter() {
        const spare = [{ device: "at", code: 140 }, { device: "usb", code: 183 }];
        compare(Model.spareFor(spare, "").length, 2);
        compare(Model.spareFor(spare, "usb").map(k => k.code), [183]);
    }

    function test_app_match_by_id_then_executable() {
        const apps = [{ id: "org.mozilla.firefox.desktop" }, { id: "kitty.desktop" }, { id: "calc" }];
        compare(Model.appMatch({ appId: "calc.desktop", command: "kitty" }, apps).entry.id, "calc", "the stored id wins");
        compare(Model.appMatch({ command: "/usr/bin/firefox --new-window" }, apps).entry.id, "org.mozilla.firefox.desktop");
        compare(Model.appMatch({ command: "kitty -e htop" }, apps).entry.id, "kitty.desktop");
        const unknown = Model.appMatch({ appId: "gone", command: "spotify-launcher" }, apps);
        compare(unknown.entry, null);
        compare(unknown.executable, "spotify-launcher", "looked up by name next");
        compare(Model.appMatch({ command: "" }, apps), { entry: null, executable: "" });
    }
}
