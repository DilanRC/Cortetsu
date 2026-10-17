import QtQuick
import QtTest
import "../../../modules/CortetsuFullscreen.js" as Fullscreen

// The OMEN key (cortetsu:hardwareKey) opens the Hardware Center unless the
// focused monitor shows a fullscreen window.
TestCase {
    name: "OmenFullscreen"

    function monitor(focused, ...fullscreenStates) {
        return { focused, activeWorkspace: { toplevels: fullscreenStates.map(fullscreen => ({ fullscreen })) } };
    }

    function test_normal_windows_open_the_center() {
        verify(!Fullscreen.focusedHasFullscreen([monitor(true, 0, 0)]));
        verify(!Fullscreen.focusedHasFullscreen([monitor(true)]));
    }

    function test_maximized_window_is_not_fullscreen() {
        verify(!Fullscreen.focusedHasFullscreen([monitor(true, 1)]));
    }

    function test_fullscreen_game_blocks_the_key() {
        verify(Fullscreen.focusedHasFullscreen([monitor(true, 0, 2)]));
        verify(Fullscreen.focusedHasFullscreen([monitor(true, 3)]));
    }

    function test_fullscreen_on_another_monitor_does_not_block() {
        verify(!Fullscreen.focusedHasFullscreen([monitor(false, 2), monitor(true, 0)]));
    }

    function test_fullscreen_on_the_focused_monitor_blocks_with_two_monitors() {
        verify(Fullscreen.focusedHasFullscreen([monitor(false, 0), monitor(true, 2)]));
    }

    function test_unknown_state_never_blocks() {
        verify(!Fullscreen.focusedHasFullscreen([]));
        verify(!Fullscreen.focusedHasFullscreen(undefined));
        verify(!Fullscreen.focusedHasFullscreen([monitor(false, 2)]));
        verify(!Fullscreen.focusedHasFullscreen([{ focused: true }]));
        verify(!Fullscreen.focusedHasFullscreen([{ focused: true, activeWorkspace: { toplevels: [null, {}] } }]));
    }
}
