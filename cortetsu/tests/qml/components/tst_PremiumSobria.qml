import QtQuick
import QtTest
import "../../../components"
import "../../../theme"

// The Premium sobria primitives: a hero whose height follows its content, a
// hairline that reads its strength from the theme, and a tab bar that is one
// Tab stop and moves with the arrows.
TestCase {
    id: testCase
    name: "PremiumSobria"
    when: windowShown
    visible: true
    width: 480
    height: 320

    Component {
        id: heroFixture
        CortetsuHero {
            width: 300
            property alias block: block
            Rectangle { id: block; width: 10; height: 40 }
        }
    }

    Component {
        id: barFixture
        CortetsuTabBar {
            width: 320
            accessibleName: "Redes"
            model: [{ label: "Cercanas", icon: "wifi" }, { label: "Guardadas" }, { label: "Ocultas" }]
            property var requests: []
            onSelected: index => { requests = requests.concat([index]); currentIndex = index; }
        }
    }

    Component { id: dividerFixture; CortetsuDivider { width: 100 } }
    Component { id: factFixture; CortetsuFact { width: 120; label: "Seguridad"; value: "WPA2" } }

    function cleanup() {
        CortetsuDesign.themeTokens = ({});
    }

    function test_hero_height_follows_content() {
        const hero = createTemporaryObject(heroFixture, testCase);
        compare(hero.implicitHeight, 40 + hero.padding * 2);
        hero.block.height = 90;
        tryCompare(hero, "implicitHeight", 90 + hero.padding * 2);
    }

    function test_divider_reads_the_theme_token() {
        const divider = createTemporaryObject(dividerFixture, testCase);
        compare(divider.implicitHeight, CortetsuDesign.outlineWidth);
        fuzzyCompare(divider.color.a, CortetsuDesign.materialSeparatorAlpha, 0.01);
        CortetsuDesign.themeTokens = ({ materialSeparatorAlpha: 0.8 });
        fuzzyCompare(divider.color.a, 0.8, 0.01);
    }

    function test_fact_names_label_and_value() {
        const fact = createTemporaryObject(factFixture, testCase);
        compare(fact.Accessible.name, "Seguridad: WPA2");
    }

    function test_tab_bar_is_one_stop_and_arrows_move_it() {
        const bar = createTemporaryObject(barFixture, testCase);
        const first = bar.children[1].children[0];
        const second = bar.children[1].children[1];
        verify(first.activeFocusOnTab);
        verify(!second.activeFocusOnTab);
        first.forceActiveFocus();
        keyClick(Qt.Key_Right);
        compare(bar.requests, [1]);
        verify(second.activeFocus);
        verify(second.activeFocusOnTab);
        keyClick(Qt.Key_Left);
        compare(bar.requests, [1, 0]);
        // The ends do not wrap.
        keyClick(Qt.Key_Left);
        compare(bar.requests, [1, 0]);
    }

    function test_tab_bar_click_selects() {
        const bar = createTemporaryObject(barFixture, testCase);
        mouseClick(bar, bar.width - 20, bar.height / 2);
        compare(bar.requests, [2]);
        compare(bar.currentIndex, 2);
    }
}
