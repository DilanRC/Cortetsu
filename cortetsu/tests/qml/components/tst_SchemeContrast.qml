import QtQuick
import QtTest
import "../../../theme"

// CortetsuDesign keeps secondary text readable whatever scheme is active.
// Role values copied from `cortetsu-scheme list` and a dynamic scheme
// (2026-10-23): onSurfaceVariant on surface was 1.7:1 in nebula and
// papercolor/dark and 2.4:1 in circus; onSurface itself 3.0 and 3.9:1 in
// nebula and papercolor/dark.
TestCase {
    name: "SchemeContrast"

    readonly property var schemes: {
        "nebula": {
            "surface": "414f60",
            "surfaceContainerHigh": "4b5867",
            "onSurface": "a4a6a9",
            "onSurfaceVariant": "6e6f72"
        },
        "papercolorDark": {
            "surface": "363636",
            "surfaceContainerHigh": "404040",
            "onSurface": "9e9e9e",
            "onSurfaceVariant": "585858"
        },
        "circus": {
            "surface": "202020",
            "surfaceContainerHigh": "2e2e2e",
            "onSurface": "a7a7a7",
            "onSurfaceVariant": "5f5a60"
        },
        "dynamicDark": {
            "surface": "1b1b1f",
            "surfaceContainerHigh": "292a2d",
            "onSurface": "e3e2e6",
            "onSurfaceVariant": "c4c6d0"
        }
    }

    function cleanup() { CortetsuDesign.scheme = ({}); }

    function test_text_role_reaches_aa_on_both_surfaces() {
        for (const name of ["nebula", "papercolorDark", "circus"]) {
            CortetsuDesign.scheme = schemes[name];
            const text = CortetsuDesign.colorOnSurfaceVariant;
            verify(CortetsuDesign.contrast(text, CortetsuDesign.colorSurface) >= 4.5, name);
            verify(CortetsuDesign.contrast(text, CortetsuDesign.colorSurfaceHigh) >= 4.5, name);
            verify(CortetsuDesign.contrast(CortetsuDesign.colorOnSurface, CortetsuDesign.colorSurfaceHigh) >= 4.5, `${name} primary text`);
            verify(CortetsuDesign.contrast(text, CortetsuDesign.colorOnSurface) > 1.01, `${name} keeps secondary text distinct from primary text`);
        }
    }

    // A light scheme moves secondary text toward black, not white.
    function test_light_surfaces_darken_the_text() {
        CortetsuDesign.scheme = ({ surface: "fdfbff", surfaceContainerHigh: "ece7ef", onSurface: "1b1b1f", onSurfaceVariant: "a0a0a8" });
        const text = CortetsuDesign.colorOnSurfaceVariant;
        verify(CortetsuDesign.contrast(text, CortetsuDesign.colorSurfaceHigh) >= 4.5);
        verify(CortetsuDesign.luminance(text) < CortetsuDesign.luminance("#a0a0a8"));
        compare(String(CortetsuDesign.colorOnSurface), "#1b1b1f", "dark text on light surfaces already passes");
    }

    function test_a_scheme_that_passes_is_untouched() {
        CortetsuDesign.scheme = schemes.dynamicDark;
        compare(String(CortetsuDesign.colorOnSurfaceVariant), "#" + schemes.dynamicDark.onSurfaceVariant.replace("#", ""));
        CortetsuDesign.scheme = ({});
        verify(CortetsuDesign.contrast(CortetsuDesign.colorOnSurfaceVariant, CortetsuDesign.colorSurface) >= 4.5, "defaults");
    }
}
