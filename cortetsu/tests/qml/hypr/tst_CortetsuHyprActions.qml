import QtQuick
import QtTest
import "../../../modules/CortetsuHyprActions.js" as HyprActions

TestCase {
    name: "CortetsuHyprActions"

    function test_lua_literals_escape_quotes_backslashes_and_controls() {
        compare(HyprActions.luaString('special:a"b'), '"special:a\\"b"');
        compare(HyprActions.luaString("x\\y"), '"x\\\\y"');
        compare(HyprActions.luaString("l1\nl2"), '"l1\\010l2"');
        compare(HyprActions.luaString("tab\t9"), '"tab\\0099"');
        compare(HyprActions.luaString("del\u007f1"), '"del\\1271"');
        compare(HyprActions.luaString("]]--"), '"]]--"');
        compare(HyprActions.luaString("ñandú 🎮"), '"ñandú 🎮"');

        let allControls = '"';
        for (let code = 0; code < 32; ++code)
            allControls += "\\" + ("00" + code).slice(-3);
        allControls += "\\127" + '"';
        let controls = "";
        for (let code = 0; code < 32; ++code)
            controls += String.fromCharCode(code);
        controls += String.fromCharCode(127);
        compare(HyprActions.luaString(controls), allControls);
        compare(HyprActions.luaString("\ud800"), null);
    }

    function test_workspace_and_special_name_actions_are_typed() {
        let action = HyprActions.focusWorkspace(7);
        compare(action.lua, "hl.dsp.focus({ workspace = 7 })");
        compare(action.legacy, "workspace 7");

        action = HyprActions.focusWorkspace('special:mañana "🎮"');
        compare(action.lua, 'hl.dsp.focus({ workspace = "special:mañana \\"🎮\\"" })');
        compare(action.legacy, "");

        action = HyprActions.focusWorkspace('name:work\n;hl.dsp.exit()');
        compare(action.lua, 'hl.dsp.focus({ workspace = "name:work\\010;hl.dsp.exit()" })');
        compare(action.legacy, "");

        action = HyprActions.focusWorkspace("name:mañana abierta");
        compare(action.lua, 'hl.dsp.focus({ workspace = "name:mañana abierta" })');
        compare(action.legacy, "workspace name:mañana abierta");

        action = HyprActions.toggleSpecialWorkspace('archivo "ñ"');
        compare(action.lua, 'hl.dsp.workspace.toggle_special("archivo \\"ñ\\"")');
        compare(action.legacy, "");

        action = HyprActions.toggleSpecialWorkspace("archivo ñ");
        compare(action.lua, 'hl.dsp.workspace.toggle_special("archivo ñ")');
        compare(action.legacy, "togglespecialworkspace archivo ñ");

        action = HyprActions.toggleSpecialWorkspace("");
        compare(action.lua, 'hl.dsp.workspace.toggle_special("special")');
        compare(action.legacy, "togglespecialworkspace special");
    }

    function test_window_addresses_are_validated_and_lua_escaped() {
        compare(HyprActions.focusWindow("0x1a2f").lua,
            'hl.dsp.focus({ window = "address:0x1a2f" })');
        compare(HyprActions.closeWindow("1A2F").lua,
            'hl.dsp.window.close({ window = "address:0x1A2F" })');
        compare(HyprActions.toggleFloat("0x1a2f").lua,
            'hl.dsp.window.float({ action = "toggle", window = "address:0x1a2f" })');
        compare(HyprActions.togglePin("0x1a2f").lua,
            'hl.dsp.window.pin({ action = "toggle", window = "address:0x1a2f" })');
        compare(HyprActions.killWindow("0x1a2f").lua,
            'hl.dsp.window.kill({ window = "address:0x1a2f" })');
        verify(HyprActions.focusWindow("address:0x1a2f") === null);
        verify(HyprActions.focusWindow("0x1a2f\n") === null);
        verify(HyprActions.closeWindow(1234) === null);
    }

    function test_move_window_uses_numeric_or_escaped_workspace_selectors() {
        let action = HyprActions.moveWindow("0xabcd", 3, true);
        compare(action.lua,
            'hl.dsp.window.move({ window = "address:0xabcd", workspace = 3, follow = true })');
        compare(action.legacy, "movetoworkspace 3,address:0xabcd");

        action = HyprActions.moveWindow("0xabcd", 'special:niño "x"', false);
        compare(action.lua,
            'hl.dsp.window.move({ window = "address:0xabcd", workspace = "special:niño \\"x\\"", follow = false })');
        compare(action.legacy, "");

        action = HyprActions.moveWindow("0xabcd", "special:niño proyectos", false);
        compare(action.lua,
            'hl.dsp.window.move({ window = "address:0xabcd", workspace = "special:niño proyectos", follow = false })');
        compare(action.legacy, "movetoworkspacesilent special:niño proyectos,address:0xabcd");
        verify(HyprActions.moveWindow("0xabcd", 3, "false") === null);
    }

    function test_cursor_dpms_and_exit_actions_have_safe_shapes() {
        let action = HyprActions.moveCursor(12.5, -2);
        compare(action.lua, "hl.dsp.cursor.move({ x = 12.5, y = -2 })");
        compare(action.legacy, "");
        compare(HyprActions.moveCursor(12, -2).legacy, "movecursor 12 -2");
        verify(HyprActions.moveCursor(NaN, 0) === null);
        verify(HyprActions.moveCursor(1, Infinity) === null);

        action = HyprActions.dpms(true);
        compare(action.lua, 'hl.dsp.dpms({ action = "on" })');
        compare(action.legacy, "dpms on");
        action = HyprActions.dpms(false);
        compare(action.lua, 'hl.dsp.dpms({ action = "off" })');
        compare(action.legacy, "dpms off");
        verify(HyprActions.dpms("on") === null);

        action = HyprActions.exit();
        compare(action.lua, "hl.dsp.exit()");
        compare(action.legacy, "exit");
    }
}
