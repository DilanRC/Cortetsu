import QtQuick
import QtTest
import "../../../components"
import "../../../modules/settings/controls"

// The same native controls used throughout Cortetsu must be reachable by
// keyboard and by an assistive client's semantic actions.
TestCase {
    id: testCase
    name: "AccessibleControls"
    when: windowShown
    visible: true
    width: 480
    height: 280

    Component {
        id: buttonFixture
        CortetsuButton {
            label: "Cerrar"
            tooltipText: "Cierra esta ventana"
            property int activations: 0
            onClicked: activations++
        }
    }
    Component {
        id: toggleFixture
        CortetsuToggle {
            accessibleName: "No molestar"
            property int requests: 0
            onToggled: requests++
        }
    }
    Component {
        id: choiceFixture
        CortetsuChoiceCard { title: "Oscuro"; subtitle: "Tema para la noche"; selected: true }
    }
    Component {
        id: tabFixture
        CortetsuTab { index: 0; count: 2; label: "Audio"; selected: true }
    }
    Component {
        id: listFixture
        CortetsuListRow { title: "Red"; subtitle: "Conectado"; selected: true }
    }
    Component {
        id: tileFixture
        CortetsuActionTile { label: "Información"; detail: "Solo estado"; clickable: false }
    }
    Component {
        id: actionFixture
        CortetsuActionRow { index: 1; title: "Abrir monitor"; subtitle: "Muestra rendimiento" }
    }

    Component {
        id: settingsSwitchFixture
        SettingToggleRow {
            width: 380
            title: "No molestar"
            checked: true
            property int requests: 0
            onToggled: requests++
        }
    }

    function test_settings_switch_has_one_semantic_owner() {
        const row = createTemporaryObject(settingsSwitchFixture, testCase);
        compare(row.Accessible.role, Accessible.Switch);
        compare(row.Accessible.name, "No molestar");
        verify(row.Accessible.checked);
        const knob = findChild(row, "switch");
        verify(knob !== null);
        verify(knob.Accessible.ignored);
        row.Accessible.toggleAction();
        compare(row.requests, 1);
        compare(row.checked, true);
        row.disabled = true;
        row.Accessible.pressAction();
        compare(row.requests, 1);
    }

    function test_accessible_focus_follows_keyboard_and_disabled_state() {
        const button = createTemporaryObject(buttonFixture, testCase);
        button.forceActiveFocus();
        tryCompare(button.Accessible, "focused", true);
        button.disabled = true;
        tryCompare(button.Accessible, "focused", false);
    }

    function test_button_exposes_and_executes_its_action() {
        const item = createTemporaryObject(buttonFixture, testCase);
        compare(item.Accessible.role, Accessible.Button);
        compare(item.Accessible.name, "Cerrar");
        compare(item.Accessible.description, "Cierra esta ventana");
        item.Accessible.pressAction();
        compare(item.activations, 1);
        item.disabled = true;
        item.Accessible.pressAction();
        compare(item.activations, 1);
    }

    function test_toggle_exposes_state_without_mutating_its_owner() {
        const item = createTemporaryObject(toggleFixture, testCase);
        compare(item.Accessible.role, Accessible.Switch);
        compare(item.Accessible.name, "No molestar");
        compare(item.Accessible.checked, false);
        item.Accessible.toggleAction();
        compare(item.requests, 1);
        compare(item.checked, false);
        item.disabled = true;
        item.Accessible.pressAction();
        compare(item.requests, 1);
    }

    function test_selection_controls_name_their_state() {
        const choice = createTemporaryObject(choiceFixture, testCase);
        compare(choice.Accessible.role, Accessible.RadioButton);
        compare(choice.Accessible.name, "Oscuro");
        verify(choice.Accessible.checked);
        const tab = createTemporaryObject(tabFixture, testCase);
        compare(tab.Accessible.role, Accessible.PageTab);
        verify(tab.Accessible.selected);
        const list = createTemporaryObject(listFixture, testCase);
        compare(list.Accessible.name, "Red");
        compare(list.Accessible.description, "Conectado");
        verify(list.Accessible.selected);
    }

    function test_status_tiles_and_action_rows_have_distinct_roles() {
        const tile = createTemporaryObject(tileFixture, testCase);
        compare(tile.Accessible.role, Accessible.StaticText);
        verify(!tile.Accessible.focusable);
        const action = createTemporaryObject(actionFixture, testCase);
        compare(action.Accessible.role, Accessible.Button);
        compare(action.Accessible.name, "Abrir monitor");
    }
}
