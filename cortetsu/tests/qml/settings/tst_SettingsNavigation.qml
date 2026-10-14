import QtQuick
import QtTest
import "../../../modules/settings/Navigation.js" as Navigation

TestCase {
    name: "SettingsNavigation"

    readonly property var categories: [
        { id: "audio", group: "Sistema", title: "Audio", keywords: "sonido altavoces", settings: ["Volumen de salida", "Dispositivo de entrada"] },
        { id: "power", group: "Sistema", title: "Energía", keywords: "batería reposo", settings: ["Bloquear antes de suspender"] },
        { id: "appearance", group: "Personalización", title: "Apariencia", keywords: "tema color", settings: ["Reloj de 12 horas", "Esquema de color"] }
    ]

    function test_an_empty_query_keeps_every_category() {
        compare(Navigation.matchingIds(categories, ""), ["audio", "power", "appearance"]);
        compare(Navigation.matchingIds(categories, "   "), ["audio", "power", "appearance"]);
    }

    function test_accents_and_case_are_ignored() {
        compare(Navigation.matchingIds(categories, "energia"), ["power"]);
        compare(Navigation.matchingIds(categories, "ENERGÍA"), ["power"]);
        compare(Navigation.matchingIds(categories, "bateria"), ["power"]);
    }

    function test_a_setting_finds_its_page_and_is_named() {
        const found = Navigation.match(categories[2], "reloj");
        verify(found.matches);
        compare(found.setting, "Reloj de 12 horas");
        compare(Navigation.matchingIds(categories, "suspender"), ["power"]);
    }

    function test_a_category_name_wins_over_its_settings() {
        compare(Navigation.match(categories[0], "audio").setting, "");
        compare(Navigation.matchingIds(categories, "sistema"), ["audio", "power"]);
    }

    function test_nothing_matches_nonsense() {
        compare(Navigation.matchingIds(categories, "zzz"), []);
        verify(!Navigation.match(categories[0], "zzz").matches);
    }

    function test_neighbour_stops_at_the_ends() {
        const ids = ["audio", "power", "appearance"];
        compare(Navigation.neighbour(ids, "audio", 1), "power");
        compare(Navigation.neighbour(ids, "appearance", 1), "appearance");
        compare(Navigation.neighbour(ids, "audio", -1), "audio");
        compare(Navigation.neighbour([], "audio", 1), "");
    }

    function test_a_hidden_selection_enters_the_visible_list() {
        compare(Navigation.neighbour(["power", "appearance"], "audio", 1), "power");
        compare(Navigation.neighbour(["power", "appearance"], "audio", -1), "appearance");
    }
}
