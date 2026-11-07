import QtQuick
import QtTest
import "../../../modules"
import "../../../theme"
import "../../../theme/ThemeProfiles.js" as Profiles
import "../../../theme/CortetsuDesignDefaults.js" as Defaults

TestCase {
    name: "ThemeProfiles"
    width: 120
    height: 60

    CortetsuIsland {
        id: bottomHubIsland
        objectName: "bottomHubThemeIsland"
        anchors.fill: parent
    }

    function cleanup() {
        CortetsuDesign.themeTokens = ({});
        CortetsuDesign.scheme = ({});
        CortetsuDesign.reducedMotion = false;
        bottomHubIsland.transparencyFactor = 1;
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
    function test_bottom_hub_island_radius_follows_theme_and_preserves_ink() {
        CortetsuDesign.themeTokens = Profiles.tokens("ink");
        compare(bottomHubIsland.radius, bottomHubIsland.height / 2, "Ink keeps the existing capsule shape");

        CortetsuDesign.themeTokens = Profiles.tokens("washi");
        compare(bottomHubIsland.radius, 18, "Washi applies its compiled surface radius to Bottom Hub");

        CortetsuDesign.themeTokens = Profiles.tokens("kurogane");
        compare(bottomHubIsland.radius, 14, "Kurogane applies its technical surface radius to Bottom Hub");
    }
    function test_bottom_hub_island_material_follows_theme_and_transparency() {
        bottomHubIsland.transparencyFactor = 1;
        CortetsuDesign.themeTokens = Profiles.tokens("ink");
        compare(bottomHubIsland.color.a, 0.82, "Ink keeps the existing island opacity");

        CortetsuDesign.themeTokens = Profiles.tokens("washi");
        verify(Math.abs(bottomHubIsland.color.a - 0.82 * 0.97 / Defaults.materialGroundAlpha) < 0.001,
            "Washi applies its compiled ground material opacity");

        CortetsuDesign.themeTokens = Profiles.tokens("kurogane");
        verify(Math.abs(bottomHubIsland.color.a - 0.82 * 0.98 / Defaults.materialGroundAlpha) < 0.001,
            "Kurogane applies its compiled ground material opacity");

        bottomHubIsland.transparencyFactor = CortetsuDesign.materialTransparencyFactor;
        verify(Math.abs(bottomHubIsland.color.a - 0.82 * 0.98 / Defaults.materialGroundAlpha
            * CortetsuDesign.materialTransparencyFactor) < 0.001,
            "the transparency factor thins the island material");
    }
    function test_unknown_theme_falls_back_to_ink() {
        compare(Object.keys(Profiles.tokens("unknown")).length, 0);
    }
}
