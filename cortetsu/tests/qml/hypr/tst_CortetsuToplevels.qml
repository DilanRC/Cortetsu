import QtQuick
import QtTest
import "../../../modules/CortetsuToplevels.js" as Toplevels

TestCase {
    name: "CortetsuToplevels"

    readonly property string clients: JSON.stringify([
        { address: "0x564638307770", class: "com.anthropic.Claude" },
        { address: "0x5646381D1E80", class: "kitty" }
    ])

    function test_closed_window_is_not_live() {
        const live = Toplevels.liveAddresses(clients);
        // Addresses the shell kept after Steam and its launcher closed.
        verify(!Toplevels.isLive(live, "0x5646383c7e40"));
        verify(!Toplevels.isLive(live, "564638331270"));
    }

    function test_open_window_matches_either_address_form() {
        const live = Toplevels.liveAddresses(clients);
        verify(Toplevels.isLive(live, "0x564638307770"));
        verify(Toplevels.isLive(live, "564638307770"));
        verify(Toplevels.isLive(live, "5646381d1e80"));
    }

    function test_window_without_address_is_not_live() {
        const live = Toplevels.liveAddresses(clients);
        verify(!Toplevels.isLive(live, ""));
        verify(!Toplevels.isLive(live, undefined));
    }

    function test_no_windows_hides_every_leftover() {
        const live = Toplevels.liveAddresses("[]");
        verify(live !== null);
        verify(!Toplevels.isLive(live, "0x564638307770"));
    }

    function test_unusable_probe_is_told_apart_from_no_windows() {
        compare(Toplevels.liveAddresses(""), null);
        compare(Toplevels.liveAddresses("{\"error\":1}"), null);
        verify(Toplevels.isLive(null, "0x5646383c7e40"));
    }
}
