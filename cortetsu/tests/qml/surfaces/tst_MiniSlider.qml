import QtQuick
import QtTest
import "../../../modules/osd"

TestCase {
    name: "MiniSlider"

    MiniSlider {
        id: slider
        kind: "volume"
        value: 0.75
        maximum: 1.5
        available: true
        muted: false
    }

    function init() {
        slider.kind = "volume";
        slider.value = 0.75;
        slider.maximum = 1.5;
        slider.available = true;
        slider.muted = false;
    }

    function test_volume_displays_backend_value_and_scaled_range() {
        compare(slider.amount, "75%");
        compare(slider.progress, 0.5);
        compare(slider.icon, "volume_up");
    }

    function test_volume_above_one_hundred_percent_is_preserved() {
        slider.value = 1.4;
        compare(slider.amount, "140%");
        compare(slider.progress, 1.4 / 1.5);
    }

    function test_mute_and_unavailable_states_are_distinct() {
        slider.muted = true;
        compare(slider.icon, "volume_off");
        slider.kind = "brightness";
        slider.muted = false;
        compare(slider.icon, "light_mode");
        slider.available = false;
        compare(slider.amount, "No disponible");
        compare(slider.progress, 0);
    }
}
