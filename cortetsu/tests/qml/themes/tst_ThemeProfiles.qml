import QtQuick
import QtTest
import "../../../theme"
import "../../../theme/ThemeProfiles.js" as Profiles
import "../../../theme/CortetsuDesignDefaults.js" as Defaults

TestCase {
    name: "ThemeProfiles"
    function cleanup() {
        CortetsuDesign.themeTokens = ({});
        CortetsuDesign.scheme = ({});
        CortetsuDesign.reducedMotion = false;
    }
    function test_ink_keeps_compiled_defaults() {
        CortetsuDesign.themeTokens = Profiles.tokens("ink");
        compare(CortetsuDesign.radiusSurface, Defaults.radiusSurface);
        compare(CortetsuDesign.fontUi, Defaults.fontUi);
        compare(CortetsuDesign.materialGrain, Defaults.materialGrain);
        verify(Qt.colorEqual(CortetsuDesign.colorSurface, Defaults.colorSurface));
    }
    function test_washi_overrides_a_dark_scheme_and_updates_live() {
        CortetsuDesign.scheme = ({surface: "101010", onSurface: "ffffff"});
        CortetsuDesign.themeTokens = Profiles.tokens("washi");
        verify(CortetsuDesign.luminance(CortetsuDesign.colorSurface) > 0.7);
        verify(CortetsuDesign.contrast(CortetsuDesign.colorOnSurface, CortetsuDesign.colorSurface) >= 4.5);
        compare(CortetsuDesign.fontUi, "Noto Sans");
        compare(CortetsuDesign.radiusSurface, 18);
        CortetsuDesign.themeTokens = Profiles.tokens("kurogane");
        verify(CortetsuDesign.luminance(CortetsuDesign.colorSurface) < 0.1);
        compare(CortetsuDesign.rowHeight, 46);
        compare(CortetsuDesign.materialGrain, 0.035);
    }
    function test_reduced_motion_wins_over_theme() {
        CortetsuDesign.themeTokens = Profiles.tokens("kurogane");
        compare(CortetsuDesign.motionStandardMs, 140);
        CortetsuDesign.reducedMotion = true;
        compare(CortetsuDesign.motionStandardMs, 0);
        compare(CortetsuDesign.motionPanelMs, 0);
    }
    function test_unknown_theme_falls_back_to_ink() {
        compare(Object.keys(Profiles.tokens("unknown")).length, 0);
    }
}
