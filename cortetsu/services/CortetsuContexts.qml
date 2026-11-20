pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../modules"
import "ContextModel.js" as Model

// Contexts (Universidad, Desarrollo, Gaming, Batería and the user's own).
// A context is not a new authority: it writes each setting through the
// owner that already has it, remembers what was there before, and on
// deactivation puts back only what still holds the context's value. The
// state lives in $XDG_STATE_HOME/cortetsu/contexts.json:
//   custom    the user's contexts
//   active    the id of the active context, "" for none
//   applied   what the active context changed
//   restore   the values those settings had before
//   skipped   settings left to the automation coordinator
// A shell restart reads the file and keeps the context active; preferences
// already hold the applied values, and Orbital's hold is set again.
Singleton {
    id: root

    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/cortetsu/contexts.json`
    readonly property var keys: Model.KEYS
    readonly property var builtin: Model.BUILTIN

    property var record: Model.emptyState()
    // false until the file was read; a broken file keeps it false so the
    // first write is a deliberate user action, never the startup.
    property bool loaded: false
    property string error: ""
    property string notice: ""

    readonly property var contexts: builtin.concat(record.custom)
    readonly property string activeId: record.active
    readonly property var active: contexts.find(c => c.id === record.active) ?? null
    readonly property var skipped: record.skipped
    readonly property var custom: record.custom

    function describe(key: string): string { return Model.describe(key); }

    // The automation coordinator, when the shell has one. Its enabled
    // domains own notifications, game mode and power.
    readonly property var policies: ShellState.shellRoot?.policyBridge ?? null

    function ownedDomains(): var {
        if (!policies)
            return [];
        return ["notifications", "gamemode", "power"].filter(d => policies.activation(d)?.enabled === true);
    }

    function profileName(profile): string {
        return profile === PowerProfile.PowerSaver ? "power-saver"
            : profile === PowerProfile.Performance ? "performance" : "balanced";
    }

    // A CortetsuConfig setting by its dotted key: the object that holds it
    // and the property's name ("bottomHub.spacing" → bottomHub, "spacing").
    function configSlot(key: string): var {
        const path = key.split(".");
        let target = CortetsuConfig;
        for (let i = 0; i < path.length - 1; i++)
            target = target[path[i]];
        return [target, path[path.length - 1]];
    }

    function read(key: string): var {
        switch (key) {
        case "dnd": return Notifs.dnd;
        case "gameMode": return GameMode.desired ?? GameMode.enabled;
        case "powerProfile": return profileName(PowerProfiles.profile);
        case "orbitalHold": return Orbital.hold;
        }
        const [target, name] = configSlot(key);
        return target[name];
    }

    function write(key: string, value): void {
        switch (key) {
        case "themeId": CortetsuConfig.selectTheme(value); return;
        case "dnd": Notifs.setDnd(value); return;
        case "gameMode": GameMode.setEnabled(value); return;
        case "orbitalHold": Orbital.hold = value; return;
        case "powerProfile":
            if (value === "performance" && !PowerProfiles.hasPerformanceProfile)
                return;
            PowerProfiles.profile = value === "power-saver" ? PowerProfile.PowerSaver
                : value === "performance" ? PowerProfile.Performance : PowerProfile.Balanced;
            return;
        }
        const [target, name] = configSlot(key);
        target[name] = value;
    }

    function currentValues(keys: var): var {
        const out = ({});
        for (const key of keys)
            out[key] = read(key);
        return out;
    }

    function writeAll(values: var): void {
        for (const key of Model.ORDER)
            if (key in values)
                write(key, values[key]);
        CortetsuConfig.save();
    }

    // Deactivate, then activate: switching contexts never stacks two
    // snapshots, and the second context starts from the user's own values.
    function activate(id: string): bool {
        const context = contexts.find(c => c.id === id);
        if (!context || !loaded)
            return false;
        // Notifications and game mode answer asynchronously: what deactivate
        // just asked for counts as current, or a second context wanting the
        // same value would think it is already there.
        const pending = record.active.length > 0 ? deactivate() : ({});
        const settings = context.settings;
        const current = Object.assign(currentValues(Object.keys(settings)), pending);
        const step = Model.plan(settings, current, ownedDomains());
        writeAll(step.apply);
        commit(Object.assign({}, record, { active: id, applied: step.apply, restore: step.restore, skipped: step.skipped }));
        notice = step.skipped.length > 0
            ? qsTr("%1 activo. La automatización conserva: %2").arg(context.name).arg(step.skipped.map(Model.describe).join(", "))
            : qsTr("%1 activo").arg(context.name);
        CortetsuToaster.toast(qsTr("Contexto"), notice, context.icon);
        return true;
    }

    function deactivate(): var {
        if (!loaded || record.active.length === 0)
            return ({});
        const back = Model.undo(record.applied, record.restore, currentValues(Object.keys(record.applied)));
        const name = active?.name ?? "";
        writeAll(back);
        commit(Object.assign({}, record, { active: "", applied: ({}), restore: ({}), skipped: [] }));
        notice = qsTr("%1 desactivado; se restauraron %2 ajustes").arg(name).arg(Object.keys(back).length);
        return back;
    }

    function toggle(id: string): void {
        if (record.active === id)
            deactivate();
        else
            activate(id);
    }

    // Saves the current values of `keys` as a new context, or copies one.
    function duplicate(id: string): string {
        const source = contexts.find(c => c.id === id);
        if (!source || record.custom.length >= 32)
            return "";
        const copy = Model.clean({ name: qsTr("%1 (copia)").arg(source.name), icon: source.icon,
                                   summary: source.summary, settings: source.settings }, Model.newId(record.custom));
        commit(Object.assign({}, record, { custom: record.custom.concat([copy]) }));
        return copy.id;
    }

    function update(id: string, changes: var): bool {
        const index = record.custom.findIndex(c => c.id === id);
        if (index < 0)
            return false;
        const next = Model.clean(Object.assign({}, record.custom[index], changes), id);
        if (!next)
            return false;
        const custom = record.custom.slice();
        custom[index] = next;
        commit(Object.assign({}, record, { custom }));
        // Editing the active context applies the edit now: it is undone and
        // applied again, so what it changed stays exactly what it holds.
        if (record.active === id && JSON.stringify(changes.settings ?? null) !== "null")
            activate(id);
        return true;
    }

    // One setting of a custom context: a value sets it, undefined drops it.
    function setSetting(id: string, key: string, value): bool {
        const context = record.custom.find(c => c.id === id);
        if (!context || !keys[key])
            return false;
        const settings = Object.assign({}, context.settings);
        if (value === undefined)
            delete settings[key];
        else if (Model.validValue(key, value))
            settings[key] = value;
        else
            return false;
        return update(id, { settings });
    }

    function remove(id: string): void {
        if (record.active === id)
            deactivate();
        commit(Object.assign({}, record, { custom: record.custom.filter(c => c.id !== id) }));
    }

    function exportTo(id: string, path: string): void {
        const context = contexts.find(c => c.id === id);
        error = "";
        if (!context || !path.startsWith("/")) {
            error = qsTr("Elige una ruta absoluta");
            return;
        }
        transfer.mode = "export";
        transfer.path = path;
        transfer.setText(Model.exportText(context));
    }

    function importFrom(path: string): void {
        error = "";
        if (!path.startsWith("/")) {
            error = qsTr("Elige una ruta absoluta");
            return;
        }
        transfer.mode = "import";
        transfer.path = path;
        transfer.reload();
    }

    function commit(next: var): void {
        record = next;
        loaded = true;
        store.setText(JSON.stringify(next, null, 2) + "\n");
    }

    FileView {
        id: store
        path: root.statePath
        printErrors: false
        onLoaded: {
            const parsed = Model.parseState(text());
            if (parsed === null) {
                root.error = qsTr("contexts.json no se pudo leer; no se modificará hasta que cambies un contexto");
                return;
            }
            root.record = parsed;
            root.loaded = true;
            // Hold is runtime-only in Orbital; it comes back from here.
            if (parsed.active.length > 0 && "orbitalHold" in parsed.applied)
                Orbital.hold = parsed.applied.orbitalHold;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                root.loaded = true;
            else
                root.error = FileViewError.toString(err);
        }
        onSaveFailed: err => root.error = qsTr("No se pudo guardar contexts.json: %1").arg(FileViewError.toString(err))
    }

    FileView {
        id: transfer
        property string mode: ""
        printErrors: false
        blockLoading: false
        onLoaded: {
            if (mode !== "import")
                return;
            mode = "";
            const context = Model.importText(text(), root.record.custom);
            if (!context || root.record.custom.length >= 32) {
                root.error = qsTr("El archivo no es un contexto de Cortetsu válido");
                return;
            }
            root.commit(Object.assign({}, root.record, { custom: root.record.custom.concat([context]) }));
            root.notice = qsTr("Contexto «%1» importado").arg(context.name);
        }
        onLoadFailed: err => {
            if (mode === "import")
                root.error = FileViewError.toString(err);
            mode = "";
        }
        onSaved: {
            root.notice = qsTr("Contexto exportado a %1").arg(path);
            mode = "";
        }
        onSaveFailed: err => {
            root.error = FileViewError.toString(err);
            mode = "";
        }
    }

    IpcHandler {
        target: "contexts"
        function list(): string { return JSON.stringify(root.contexts.map(c => ({ id: c.id, name: c.name, active: c.id === root.activeId }))); }
        function active(): string { return root.activeId; }
        function activate(id: string): bool { return root.activate(id); }
        function deactivate(): void { root.deactivate(); }
        function toggle(id: string): void { root.toggle(id); }
    }
}
