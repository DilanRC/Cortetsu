import QtQuick
import QtTest
import "../../../modules/WindowPreview.js" as WindowPreview

// The App Rail's window preview as data: names, labels, the cards it shows
// and how the keyboard walks them.
TestCase {
    name: "WindowPreview"

    function client(address, title, workspace, size) {
        return { title: title, lastIpcObject: { address: address, title: title, workspace: workspace, size: size } };
    }

    function test_popout_name_round_trip() {
        compare(WindowPreview.popoutName("firefox"), "apppreview:firefox");
        compare(WindowPreview.appKeyOf("apppreview:org.kde.dolphin"), "org.kde.dolphin");
        compare(WindowPreview.appKeyOf("apppreview:"), "");
        compare(WindowPreview.appKeyOf("traymenu3"), "");
        compare(WindowPreview.appKeyOf(undefined), "");
    }

    function test_workspace_labels() {
        compare(WindowPreview.workspaceLabel({ id: 3, name: "3" }).text, "Espacio 3");
        compare(WindowPreview.workspaceLabel({ id: 4, name: "code" }).text, "code");
        compare(WindowPreview.workspaceLabel({ id: -98, name: "special:scratch" }), { text: "Especial", special: true });
        compare(WindowPreview.workspaceLabel(undefined).text, "");
    }

    function test_describe_keeps_real_windows_only() {
        const cards = WindowPreview.describe([
            client("0xa", "Uno", { id: 1, name: "1" }, [1600, 900]),
            client("", "Sin dirección", { id: 1, name: "1" }, [10, 10]),
            null,
            client("0xb", "Dos", { id: 2, name: "2" }, [0, 0])
        ], "0xb");
        compare(cards.length, 2);
        compare(cards[0].address, "0xa");
        compare(cards[0].title, "Uno");
        compare(cards[0].workspace, "Espacio 1");
        compare(cards[0].aspect, 16 / 9);
        verify(!cards[0].active);
        verify(cards[1].active);
        // No size yet: the thumbnail keeps a 16:9 frame.
        compare(cards[1].aspect, 16 / 9);
    }

    function test_describe_empty() {
        compare(WindowPreview.describe([], "").length, 0);
        compare(WindowPreview.describe(undefined, "").length, 0);
    }

    function test_step_data() {
        // Five cards three wide:   0 1 2
        //                          3 4
        return [
            { tag: "first key down", index: -1, key: "down", want: 0 },
            { tag: "first key up", index: -1, key: "up", want: 4 },
            { tag: "right", index: 0, key: "right", want: 1 },
            { tag: "right stops at the row end", index: 2, key: "right", want: 2 },
            { tag: "right stops at the last card", index: 4, key: "right", want: 4 },
            { tag: "left stops at the row start", index: 3, key: "left", want: 3 },
            { tag: "down", index: 1, key: "down", want: 4 },
            { tag: "down with nothing below", index: 2, key: "down", want: 2 },
            { tag: "up", index: 4, key: "up", want: 1 },
            { tag: "tab wraps", index: 4, key: "tab", want: 0 },
            { tag: "backtab wraps", index: 0, key: "backtab", want: 4 },
            { tag: "home", index: 3, key: "home", want: 0 },
            { tag: "end", index: 0, key: "end", want: 4 },
            { tag: "unknown key", index: 2, key: "x", want: 2 },
            { tag: "stale index", index: 9, key: "right", want: 0 }
        ];
    }

    function test_step(data) {
        compare(WindowPreview.step(5, 3, data.index, data.key), data.want);
    }

    function test_step_single_column_and_empty() {
        compare(WindowPreview.step(3, 1, 0, "down"), 1);
        compare(WindowPreview.step(3, 1, 0, "right"), 0);
        compare(WindowPreview.step(0, 3, 0, "down"), -1);
    }
}
