import QtQuick
import QtTest
import "../../../modules/settings/Navigation.js" as Navigation

TestCase {
    name: "SettingsNavigation"

    readonly property var categories: [
        { id: "home", title: "Inicio", keywords: "resumen", pages: [] },
        { id: "system", title: "Sistema", keywords: "equipo", pages: [
            { id: "sound", title: "Sonido", icon: "volume_up", keywords: "audio altavoces", settings: ["Volumen de salida", "Dispositivo de entrada"] },
            { id: "power", title: "Energía y batería", icon: "battery", keywords: "reposo", settings: ["Bloquear antes de suspender"] }
        ] },
        { id: "personalization", title: "Personalización", keywords: "apariencia", pages: [
            { id: "indicators", title: "Indicadores", icon: "schedule", keywords: "osd", settings: ["Reloj de 12 horas"] },
            { id: "colors", title: "Colores", icon: "palette", keywords: "tema", settings: ["Esquema de color"] }
        ] }
    ]

    function test_an_empty_query_keeps_every_category() {
        compare(Navigation.matchingIds(categories, ""), ["home", "system", "personalization"]);
        compare(Navigation.matchingIds(categories, "   "), ["home", "system", "personalization"]);
        compare(Navigation.results(categories, ""), []);
    }

    function test_accents_and_case_are_ignored() {
        compare(Navigation.matchingIds(categories, "energia"), ["system"]);
        compare(Navigation.matchingIds(categories, "ENERGÍA"), ["system"]);
        compare(Navigation.matchingIds(categories, "bateria"), ["system"]);
    }

    function test_a_setting_is_offered_with_its_place() {
        const found = Navigation.results(categories, "reloj");
        compare(found.length, 1);
        compare(found[0].page, "indicators");
        compare(found[0].setting, "Reloj de 12 horas");
        compare(found[0].path, "Personalización › Indicadores");
        compare(Navigation.matchingIds(categories, "suspender"), ["system"]);
    }

    function test_settings_come_before_pages() {
        const found = Navigation.results(categories, "color");
        compare(found[0].setting, "Esquema de color");
        verify(found.every(result => result.page !== "colors" || result.setting !== ""));
    }

    function test_a_page_found_by_name_or_keyword_opens_without_a_setting() {
        const found = Navigation.results(categories, "altavoces");
        compare(found.length, 1);
        compare(found[0].page, "sound");
        compare(found[0].setting, "");
        compare(found[0].path, "Sistema");
    }

    function test_a_category_without_pages_is_its_own_result() {
        const found = Navigation.results(categories, "inicio");
        compare(found.length, 1);
        compare(found[0].page, "home");
    }

    function test_nothing_matches_nonsense() {
        compare(Navigation.matchingIds(categories, "zzz"), []);
        compare(Navigation.results(categories, "zzz"), []);
    }

    function test_neighbour_stops_at_the_ends() {
        const ids = ["home", "system", "personalization"];
        compare(Navigation.neighbour(ids, "home", 1), "system");
        compare(Navigation.neighbour(ids, "personalization", 1), "personalization");
        compare(Navigation.neighbour(ids, "home", -1), "home");
        compare(Navigation.neighbour([], "home", 1), "");
    }

    function test_a_hidden_selection_enters_the_visible_list() {
        compare(Navigation.neighbour(["system", "personalization"], "home", 1), "system");
        compare(Navigation.neighbour(["system", "personalization"], "home", -1), "personalization");
    }
}
