import QtQuick
import QtTest
import "../../../modules/CortetsuFullscreen.js" as Fullscreen

// OMEN, Fn+Esc and idle hold check the focused workspace's windows
// (CortetsuHypr.focusedFullscreen) for a fullscreen one.
TestCase {
    name: "OmenFullscreen"

    function windows(...states) {
        return states.map(fullscreen => ({ fullscreen }));
    }

    function test_normal_windows_open_the_center() {
        verify(!Fullscreen.hasFullscreen(windows(0, 0)));
        verify(!Fullscreen.hasFullscreen(windows()));
    }

    function test_maximized_window_is_not_fullscreen() {
        verify(!Fullscreen.hasFullscreen(windows(1)));
    }

    function test_fullscreen_game_blocks_the_key() {
        verify(Fullscreen.hasFullscreen(windows(0, 2)));
        verify(Fullscreen.hasFullscreen(windows(3)));
    }

    function test_unknown_state_never_blocks() {
        verify(!Fullscreen.hasFullscreen(undefined));
        verify(!Fullscreen.hasFullscreen([null, {}]));
    }
}
