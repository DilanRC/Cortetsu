import QtQml

// Holds one `consumers` count on a sampling service (Cpu, Memory, Gpu,
// Storage, NetworkUsage) while `active` is true. The service samples while
// anyone holds a count, so a desktop widget covered by windows releases
// its count and the probe stops.
QtObject {
    id: root

    required property var target
    property bool active: false
    property bool counted: false

    function sync(): void {
        const wanted = root.active && !!root.target;
        if (wanted === root.counted)
            return;
        root.target.consumers += wanted ? 1 : -1;
        root.counted = wanted;
    }

    onActiveChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (root.counted) root.target.consumers -= 1
}
