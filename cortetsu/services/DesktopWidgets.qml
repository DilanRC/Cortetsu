pragma Singleton

import QtQml
import Quickshell
import "../modules"
import "../theme"
import "../modules/HubAnchor.js" as HubAnchor
import "../modules/desktop/DesktopLayout.js" as DesktopLayout

// The one owner of desktop widgets. The list lives in the preferences
// (CortetsuConfig.desktopWidgets); this object adds, moves, resizes and
// removes entries, keeps the undo history of an edit session and says which
// widgets belong to which monitor. Views never write the list themselves.
QtObject {
    id: root

    // What can be placed, with whether this machine can feed it. A type
    // without data is not offered (a battery widget on a desktop PC).
    readonly property var catalogue: [
        { type: "clock", title: qsTr("Reloj"), icon: "schedule", detail: qsTr("Hora y fecha"), available: true },
        { type: "date", title: qsTr("Calendario"), icon: "calendar_month", detail: qsTr("El mes, con hoy marcado"), available: true },
        { type: "weather", title: qsTr("Clima"), icon: "partly_cloudy_day", detail: qsTr("Temperatura y cielo de Ajustes → Clima"), available: true },
        { type: "battery", title: qsTr("Batería"), icon: "battery_horiz_075", detail: qsTr("Carga y tiempo restante"), available: CortetsuPower.laptopBattery },
        { type: "system", title: qsTr("Sistema"), icon: "memory", detail: qsTr("CPU, memoria y GPU"), available: true },
        { type: "storage", title: qsTr("Almacenamiento"), icon: "hard_drive", detail: qsTr("Uso del disco principal"), available: true },
        { type: "network", title: qsTr("Red"), icon: "network_check", detail: qsTr("Descarga y subida en este momento"), available: true },
        { type: "media", title: qsTr("Multimedia"), icon: "music_note", detail: qsTr("Lo que suena, con sus controles"), available: true },
        { type: "note", title: qsTr("Nota"), icon: "sticky_note_2", detail: qsTr("Texto propio en el escritorio"), available: true }
    ]

    readonly property var items: CortetsuConfig.desktopWidgets
    readonly property bool full: items.length >= DesktopLayout.maxWidgets
    // The widget selected in the editor, by id ("" for none).
    property string selected: ""

    // Undo history of the current edit session: frozen lists, newest last.
    property var history: []
    property int historyIndex: -1
    readonly property bool canUndo: historyIndex > 0
    readonly property bool canRedo: historyIndex >= 0 && historyIndex < history.length - 1

    function info(type: string): var {
        return catalogue.find(item => item.type === type) ?? null;
    }

    function entry(id: string): var {
        return items.find(item => item.id === id) ?? null;
    }

    function screenConnected(name: string): bool {
        return Quickshell.screens.some(screen => screen.name === name);
    }

    // A widget whose monitor is not connected shows on the first one, so a
    // disconnected HDMI never hides a widget for good. Its own monitor is
    // kept and it returns there when the monitor does.
    function ownerScreen(item): string {
        if (item.screen && screenConnected(item.screen))
            return item.screen;
        return Quickshell.screens[0]?.name ?? "";
    }

    function idsFor(screenName: string): var {
        return items.filter(item => ownerScreen(item) === screenName).map(item => item.id);
    }

    // What the Hub takes from this monitor's edges, plus a gap.
    function reservedFor(screenName: string): var {
        return HubAnchor.reserved(CortetsuConfig.bottomHub.anchorFor(screenName), CortetsuDesign.bottomHubHeight + 8);
    }

    function rectOf(item, screen): var {
        if (!item || !screen)
            return { x: 0, y: 0, w: 0, h: 0 };
        return DesktopLayout.rectFor(item, screen.width, screen.height, reservedFor(screen.name));
    }

    function write(next: var): void {
        CortetsuConfig.desktopWidgets = next;
    }

    function add(type: string, screenName: string): string {
        const kind = info(type);
        if (!kind || !kind.available || full)
            return "";
        const centre = DesktopLayout.spawnCentre(idsFor(screenName).length);
        const item = DesktopLayout.sanitise({ id: DesktopLayout.newId(), type, screen: screenName, cx: centre.cx, cy: centre.cy, size: "m" });
        write(items.concat([item]));
        selected = item.id;
        record();
        return item.id;
    }

    function update(id: string, patch: var): void {
        const index = items.findIndex(item => item.id === id);
        if (index < 0)
            return;
        const next = items.slice();
        const merged = DesktopLayout.sanitise(Object.assign({}, items[index], patch));
        if (!merged)
            return;
        next[index] = merged;
        write(next);
    }

    // A move ends here: the box is stored as its centre on that monitor, and
    // the widget now belongs to it.
    function placeAt(id: string, rect: var, screen): void {
        if (!screen)
            return;
        const centre = DesktopLayout.centreFor(rect, screen.width, screen.height);
        update(id, { cx: centre.cx, cy: centre.cy, screen: screen.name });
        record();
    }

    function resize(id: string, step: int): void {
        const item = entry(id);
        if (!item)
            return;
        const index = DesktopLayout.sizes.indexOf(item.size);
        const next = DesktopLayout.sizes[Math.max(0, Math.min(DesktopLayout.sizes.length - 1, index + step))];
        if (next === item.size)
            return;
        update(id, { size: next });
        record();
    }

    function setSize(id: string, size: string): void {
        if (DesktopLayout.sizes.indexOf(size) < 0 || entry(id)?.size === size)
            return;
        update(id, { size });
        record();
    }

    function remove(id: string): void {
        if (!entry(id))
            return;
        write(items.filter(item => item.id !== id));
        if (selected === id)
            selected = "";
        record();
    }

    // Text edits are recorded once they settle, not per key.
    function setNoteText(id: string, text: string): void {
        update(id, { text });
        noteCommit.restart();
    }

    property Timer noteCommit: Timer {
        interval: 800
        onTriggered: root.record()
    }

    // --- Edit session ----------------------------------------------------
    // A widget chosen before opening (from Ajustes) stays selected.
    function beginSession(): void {
        if (!entry(selected))
            selected = "";
        history = [JSON.stringify(items)];
        historyIndex = 0;
    }

    function endSession(): void {
        noteCommit.stop();
        selected = "";
        history = [];
        historyIndex = -1;
    }

    function record(): void {
        if (historyIndex < 0)
            return;
        const frozen = JSON.stringify(items);
        if (history[historyIndex] === frozen)
            return;
        history = history.slice(0, historyIndex + 1).concat([frozen]).slice(-50);
        historyIndex = history.length - 1;
    }

    function step(delta: int): void {
        noteCommit.stop();
        record();
        const index = historyIndex + delta;
        if (index < 0 || index >= history.length)
            return;
        historyIndex = index;
        write(DesktopLayout.sanitiseList(JSON.parse(history[index])));
        if (selected && !entry(selected))
            selected = "";
    }

    function undo(): void { step(-1); }
    function redo(): void { step(1); }
}
