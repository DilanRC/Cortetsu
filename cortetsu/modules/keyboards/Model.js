.pragma library

// Pure data shaping for «Atajos y teclados»: what each list shows for the
// selected keyboard. No QML objects, so it is tested without a window.

var KIND_ICONS = {
    "internal": "laptop_chromebook",
    "vendor-hotkeys": "smart_button",
    "usb": "keyboard",
    "bluetooth": "bluetooth",
    "virtual": "keyboard_keys",
    "system-buttons": "power_settings_new",
    "other": "keyboard"
};

var STATE_LABELS = {
    "DECLARED": "Declarada",
    "VERIFIED": "Comprobada",
    "ASSIGNED": "Con acción",
    "CANDIDATE": "Libre",
    "RESERVED": "Reservada",
    "UNKNOWN": "Sin determinar"
};

var CONFIDENCE_LABELS = {
    "verified": "Pulsada en una prueba",
    "model": "Prevista para este modelo (hwdb de udev)",
    "declared": "Solo la declara el controlador"
};

// Keys that type, move or modify: not «teclas especiales».
var ORDINARY = ["typing", "modifier", "navigation", "function"];

function kindIcon(kind) {
    return KIND_ICONS[kind] || "keyboard";
}

function stateLabel(state) {
    return STATE_LABELS[state] || state;
}

function confidenceLabel(confidence) {
    return CONFIDENCE_LABELS[confidence] || "";
}

function parts(chord) {
    return String(chord || "").split("+").map(function (part) { return part.trim(); }).filter(Boolean);
}

function chordKey(chord) {
    var list = parts(chord);
    return list.length ? list[list.length - 1] : "";
}

function deviceEntry(deviceKeys, id) {
    for (var i = 0; i < deviceKeys.length; i++)
        if (deviceKeys[i].device && deviceKeys[i].device.id === id)
            return deviceKeys[i];
    return null;
}

// Keysyms this keyboard can produce, lower-cased (Hyprland compares names
// case-insensitively), plus code:N for binds written by keycode.
function producible(entry) {
    var names = {};
    var keys = (entry && entry.keys) || [];
    for (var i = 0; i < keys.length; i++) {
        if (keys[i].keysym)
            names[String(keys[i].keysym).toLowerCase()] = true;
        names["code:" + (keys[i].code + 8)] = true;
    }
    return names;
}

function matchesQuery(binding, query) {
    if (!query)
        return true;
    var q = query.toLowerCase();
    return [binding.label, binding.chord, binding.description].some(function (text) {
        return String(text || "").toLowerCase().indexOf(q) >= 0;
    });
}

// The shortcuts a selected keyboard can press: those whose key it produces.
// With no keyboard selected (or no key data yet), every shortcut.
function shortcutsFor(bindings, deviceKeys, deviceId, query) {
    var entry = deviceId ? deviceEntry(deviceKeys, deviceId) : null;
    var names = entry ? producible(entry) : null;
    return bindings.filter(function (binding) {
        if (!matchesQuery(binding, query))
            return false;
        if (!names)
            return true;
        var key = chordKey(binding.chord).toLowerCase();
        return key.length > 0 && names[key] === true;
    });
}

// «Teclas especiales»: the non-typing keys of one keyboard or of all.
function specialKeys(deviceKeys, deviceId) {
    var rows = [];
    for (var i = 0; i < deviceKeys.length; i++) {
        var entry = deviceKeys[i];
        if (deviceId && entry.device.id !== deviceId)
            continue;
        var keys = entry.keys || [];
        for (var j = 0; j < keys.length; j++) {
            if (ORDINARY.indexOf(keys[j].category) >= 0)
                continue;
            rows.push(withDevice(keys[j], entry.device));
        }
    }
    return rows;
}

function withDevice(key, device) {
    var row = {};
    for (var field in key)
        row[field] = key[field];
    row.device = device.id;
    row.deviceLabel = device.label;
    return row;
}

function spareFor(spare, deviceId) {
    return spare.filter(function (key) { return !deviceId || key.device === deviceId; });
}

// What a key does now, in one line.
function currentFunction(key) {
    var assignments = key.assignments || [];
    if (!assignments.length)
        return "Sin acción en Hyprland";
    return assignments.map(function (a) { return a.description ? a.chord + " · " + a.description : a.chord; }).join("; ");
}

// The desktop entry an application shortcut launches: by its stored appId,
// else by the executable it runs (an id equal to it or ending in ".<it>").
// `executable` is what to look up by name when no id matches; empty for a
// shortcut that runs nothing.
function appMatch(binding, apps) {
    var command = (binding.command || "").trim();
    var idOf = function (app) { return app.id.replace(/\.desktop$/, "").toLowerCase(); };
    var wanted = (binding.appId || "").replace(/\.desktop$/, "").toLowerCase();
    if (wanted) {
        var exact = apps.find(function (app) { return idOf(app) === wanted; });
        if (exact)
            return { entry: exact, executable: "" };
    }
    if (!command)
        return { entry: null, executable: "" };
    var executable = command.split(/\s+/)[0].split("/").pop();
    var query = executable.toLowerCase();
    var byId = apps.find(function (app) { return idOf(app) === query || idOf(app).endsWith("." + query); });
    return { entry: byId || null, executable: byId ? "" : executable };
}
