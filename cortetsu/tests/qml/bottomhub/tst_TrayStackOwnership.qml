import QtQuick
import QtQuick.Controls
import QtTest

TestCase {
    id: testCase
    name: "TrayStackOwnership"
    when: windowShown
    visible: true
    width: 320
    height: 240

    property int created: 0
    property int destroyed: 0

    Component {
        id: pageComponent

        Item {
            property string label: "root"
            Component.onCompleted: testCase.created++
            Component.onDestruction: testCase.destroyed++
        }
    }

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: pageComponent
    }

    StackView {
        id: externallyOwnedStack
        initialItem: pageComponent
    }

    function test_pop_does_not_destroy_an_item_created_before_push() {
        const destroyedBefore = destroyed;
        const page = pageComponent.createObject(testCase, { label: "externally-owned" });
        verify(page !== null);
        externallyOwnedStack.push(page, {}, StackView.Immediate);
        compare(externallyOwnedStack.depth, 2);
        externallyOwnedStack.pop(StackView.Immediate);
        compare(externallyOwnedStack.depth, 1);
        compare(destroyed, destroyedBefore);
        page.destroy();
        tryCompare(testCase, "destroyed", destroyedBefore + 1);
    }

    function test_initial_and_popped_pages_are_stack_owned() {
        const createdBefore = created;
        const destroyedBefore = destroyed;
        compare(stack.depth, 1);
        compare(created - destroyed, stack.depth + externallyOwnedStack.depth);

        for (let iteration = 0; iteration < 25; iteration++) {
            stack.push(pageComponent, { label: "submenu-a" }, StackView.Immediate);
            compare(stack.depth, 2);
            compare(created - destroyed, stack.depth + externallyOwnedStack.depth);
            stack.push(pageComponent, { label: "submenu-b" }, StackView.Immediate);
            compare(stack.depth, 3);
            compare(created - destroyed, stack.depth + externallyOwnedStack.depth);
            stack.pop(StackView.Immediate);
            compare(stack.depth, 2);
            tryCompare(testCase, "destroyed", iteration * 2 + 1);
            compare(created - destroyed, stack.depth + externallyOwnedStack.depth);
            stack.pop(StackView.Immediate);
            compare(stack.depth, 1);
            tryCompare(testCase, "destroyed", iteration * 2 + 2);
            compare(created - destroyed, stack.depth + externallyOwnedStack.depth);
        }

        compare(created - createdBefore, 50);
        compare(destroyed - destroyedBefore, 50);
    }
}
