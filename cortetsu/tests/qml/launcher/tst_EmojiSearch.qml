import QtQuick
import QtTest
import "../../../modules/launcher/services/EmojiSearch.js" as EmojiSearch

// The launcher's emoji mode filters cortetsu-emoji's "glyph words…" lines.
TestCase {
    name: "EmojiSearch"

    readonly property string data: "😀 :D grinning face smile happy\n"
        + "😂 joy face laugh tears\n"
        + "\n"
        + "   \n"
        + "nofields\n"
        + "  󰈹  nf-md-firefox\n"
        + "¿? question upside down reversed spanish\n"

    function test_parse_skips_lines_without_words() {
        const list = EmojiSearch.parse(data);
        compare(list.map(e => e.glyph), ["😀", "😂", "󰈹", "¿?"]);
        compare(list[0].words, ":D grinning face smile happy");
        compare(list[2].words, "nf-md-firefox");
    }

    function test_every_word_must_match_in_any_order() {
        const list = EmojiSearch.parse(data);
        compare(EmojiSearch.filter(list, "face", 10).length, 2);
        compare(EmojiSearch.filter(list, "SMILE face", 10).map(e => e.glyph), ["😀"]);
        compare(EmojiSearch.filter(list, "face  tears", 10).map(e => e.glyph), ["😂"]);
        compare(EmojiSearch.filter(list, "face rocket", 10).length, 0);
    }

    function test_glyph_and_emoticon_are_searchable() {
        const list = EmojiSearch.parse(data);
        compare(EmojiSearch.filter(list, "😂", 10).map(e => e.words), ["joy face laugh tears"]);
        compare(EmojiSearch.filter(list, ":d", 10).map(e => e.glyph), ["😀"]);
    }

    function test_empty_query_lists_in_order_up_to_the_limit() {
        const list = EmojiSearch.parse(data);
        compare(EmojiSearch.filter(list, "", 3).map(e => e.glyph), ["😀", "😂", "󰈹"]);
        compare(EmojiSearch.filter(list, "   ", 10).length, 4);
    }
}
