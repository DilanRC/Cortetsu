import QtQuick
import QtTest
import "../../../components"

TestCase {
    id: testCase
    name: "DisabledControlFocus"
    when: windowShown

    Component {
        id: buttonComponent
        CortetsuButton {
            label: "Button"
        }
    }

    Component {
        id: actionRowComponent
        CortetsuActionRow {
            index: 1
            title: "Action"
        }
    }

    Component {
        id: actionTileComponent
        CortetsuActionTile {
            label: "Tile"
        }
    }

    Component {
        id: choiceCardComponent
        CortetsuChoiceCard {
            title: "Choice"
        }
    }

    Component {
        id: listRowComponent
        CortetsuListRow {
            icon: "settings"
            title: "Row"
            subtitle: ""
        }
    }

    Component {
        id: sliderComponent
        CortetsuSlider {}
    }

    Component {
        id: tabComponent
        CortetsuTab {
            index: 0
            count: 2
            label: "Tab"
        }
    }

    Component {
        id: toggleComponent
        CortetsuToggle {}
    }

    function assertDisablingClearsFocus(component, initialProperties = {}) {
        const control = component.createObject(testCase, initialProperties);
        verify(control !== null);
        control.forceActiveFocus();
        tryCompare(control, "activeFocus", true);
        control.disabled = true;
        tryCompare(control, "activeFocus", false);
        verify(!control.enabled);
        verify(control.activeFocusOnTab);
        control.destroy();
    }

    function test_button() {
        assertDisablingClearsFocus(buttonComponent);
    }
    function test_action_row() {
        assertDisablingClearsFocus(actionRowComponent);
    }
    function test_action_tile() {
        assertDisablingClearsFocus(actionTileComponent);
    }
    function test_choice_card() {
        assertDisablingClearsFocus(choiceCardComponent);
    }
    function test_list_row() {
        assertDisablingClearsFocus(listRowComponent);
    }
    function test_slider() {
        assertDisablingClearsFocus(sliderComponent);
    }
    function test_tab() {
        assertDisablingClearsFocus(tabComponent);
    }
    function test_toggle() {
        assertDisablingClearsFocus(toggleComponent);
    }
}
