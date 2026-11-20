.pragma library

// Contexts: named sets of existing settings that are applied together and
// undone together. This file is pure: it validates, plans and merges. The
// singleton CortetsuContexts applies the plan through each setting's own
// owner (CortetsuConfig, Notifs, GameMode, PowerProfiles, Orbital).

// Every setting a context may touch, with its validator. Anything else in a
// context or an imported file is dropped. `domain` names the automation
// coordinator domain that already owns the resource: while that domain is
// enabled the context leaves it alone, so there is never a second authority.
var KEYS = {
    themeId: { kind: "enum", values: ["ink", "washi", "kurogane"] },
    reducedMotion: { kind: "bool" },
    transparencyEnabled: { kind: "bool" },
    visualiserEnabled: { kind: "bool" },
    toastNowPlaying: { kind: "bool" },
    suppressNotificationsInFullscreen: { kind: "bool" },
    "bottomHub.windowPreviews": { kind: "bool" },
    "bottomHub.windowThumbnails": { kind: "bool" },
    "dashboard.showMedia": { kind: "bool" },
    "dashboard.showWeather": { kind: "bool" },
    "dashboard.showPerformance": { kind: "bool" },
    dashboardResourceUpdateInterval: { kind: "int", min: 500, max: 10000 },
    dnd: { kind: "bool", effect: true, domain: "notifications" },
    gameMode: { kind: "bool", effect: true, domain: "gamemode" },
    powerProfile: { kind: "enum", values: ["power-saver", "balanced", "performance"], effect: true, domain: "power" },
    orbitalHold: { kind: "bool", effect: true }
};

// The theme goes first: selecting a theme loads that theme's own motion and
// transparency, which the context's values must then override.
var ORDER = ["themeId"].concat(Object.keys(KEYS).filter(function (k) { return k !== "themeId"; }));

var BUILTIN = [
    { id: "university", builtin: true, name: "Universidad", icon: "school",
      summary: "Menos distracciones: sin visualizador ni avisos de lo que suena",
      settings: { visualiserEnabled: false, toastNowPlaying: false, suppressNotificationsInFullscreen: true,
                  "dashboard.showMedia": false, "dashboard.showWeather": true } },
    { id: "development", builtin: true, name: "Desarrollo", icon: "code",
      summary: "Vistas previas de ventanas y métricas del sistema a mano",
      settings: { "bottomHub.windowPreviews": true, "bottomHub.windowThumbnails": true,
                  "dashboard.showPerformance": true, toastNowPlaying: false } },
    { id: "gaming", builtin: true, name: "Gaming", icon: "sports_esports",
      summary: "Modo juego, No molestar y fondos animados en pausa",
      settings: { gameMode: true, dnd: true, orbitalHold: true, visualiserEnabled: false,
                  "bottomHub.windowThumbnails": false } },
    { id: "battery", builtin: true, name: "Batería", icon: "battery_saver",
      summary: "Ahorro de energía y menos trabajo en segundo plano; el tema no cambia",
      settings: { powerProfile: "power-saver", orbitalHold: true, visualiserEnabled: false,
                  "bottomHub.windowThumbnails": false, dashboardResourceUpdateInterval: 5000 } }
];

function validValue(key, value) {
    var spec = KEYS[key];
    if (!spec)
        return false;
    if (spec.kind === "bool")
        return typeof value === "boolean";
    if (spec.kind === "enum")
        return spec.values.indexOf(value) >= 0;
    if (spec.kind === "int")
        return Number.isInteger(value) && value >= spec.min && value <= spec.max;
    return false;
}

function cleanSettings(raw) {
    var out = {};
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
        return out;
    for (var key in raw)
        if (validValue(key, raw[key]))
            out[key] = raw[key];
    return out;
}

// A context read from disk or an import. Returns null when it is not one.
function clean(raw, id) {
    if (!raw || typeof raw !== "object")
        return null;
    var name = typeof raw.name === "string" ? raw.name.trim().slice(0, 48) : "";
    if (name.length === 0)
        return null;
    return {
        id: id,
        builtin: false,
        name: name,
        icon: typeof raw.icon === "string" && /^[a-z0-9_]{1,40}$/.test(raw.icon) ? raw.icon : "tune",
        summary: typeof raw.summary === "string" ? raw.summary.slice(0, 120) : "",
        settings: cleanSettings(raw.settings)
    };
}

function emptyState() {
    return { version: 1, custom: [], active: "", applied: {}, restore: {}, skipped: [] };
}

// The state file. An unknown version or a broken file starts empty without
// being overwritten until the user changes something (see the singleton).
function parseState(text) {
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!data || data.version !== 1)
        return null;
    var state = emptyState();
    var seen = {};
    (Array.isArray(data.custom) ? data.custom : []).slice(0, 32).forEach(function (raw) {
        var id = raw && typeof raw.id === "string" && /^custom-[0-9a-z]{1,16}$/.test(raw.id) ? raw.id : "";
        var context = id && !seen[id] ? clean(raw, id) : null;
        if (context) {
            seen[id] = true;
            state.custom.push(context);
        }
    });
    state.active = typeof data.active === "string" ? data.active : "";
    state.applied = cleanSettings(data.applied);
    // The restore snapshot holds what was there before; it is validated the
    // same way, so a hand-edited file cannot smuggle another key in.
    state.restore = cleanSettings(data.restore);
    state.skipped = Array.isArray(data.skipped) ? data.skipped.filter(function (k) { return !!KEYS[k]; }) : [];
    return state;
}

function newId(custom) {
    var n = 1;
    var taken = {};
    custom.forEach(function (c) { taken[c.id] = true; });
    while (taken["custom-" + n.toString(36)])
        n++;
    return "custom-" + n.toString(36);
}

// What activating `settings` changes, given `current` values and the set of
// coordinator domains that are enabled. Keys already at the wanted value are
// left out of the restore snapshot so deactivating never touches them.
function plan(settings, current, ownedDomains) {
    var apply = {};
    var restore = {};
    var skipped = [];
    ORDER.forEach(function (key) {
        if (!(key in settings))
            return;
        var spec = KEYS[key];
        if (spec.domain && ownedDomains.indexOf(spec.domain) >= 0) {
            skipped.push(key);
            return;
        }
        if (current[key] === settings[key])
            return;
        apply[key] = settings[key];
        if (current[key] !== undefined)
            restore[key] = current[key];
    });
    return { apply: apply, restore: restore, skipped: skipped };
}

// What deactivating puts back: only the keys that still hold the value the
// context set. A setting the user changed while the context was active is
// the user's and stays as it is.
function undo(applied, restore, current) {
    var out = {};
    ORDER.forEach(function (key) {
        if (key in restore && key in applied && current[key] === applied[key])
            out[key] = restore[key];
    });
    return out;
}

function describe(key) {
    var labels = {
        themeId: "Tema", reducedMotion: "Reducir movimiento", transparencyEnabled: "Transparencia",
        visualiserEnabled: "Visualizador", toastNowPlaying: "Aviso de lo que suena",
        suppressNotificationsInFullscreen: "Ocultar avisos en pantalla completa",
        "bottomHub.windowPreviews": "Vistas previas de ventanas", "bottomHub.windowThumbnails": "Miniaturas de ventanas",
        "dashboard.showMedia": "Multimedia en el dashboard", "dashboard.showWeather": "Clima en el dashboard",
        "dashboard.showPerformance": "Métricas en el dashboard", dashboardResourceUpdateInterval: "Muestreo del dashboard",
        dnd: "No molestar", gameMode: "Modo juego", powerProfile: "Perfil de energía", orbitalHold: "Pausar fondos animados"
    };
    return labels[key] || key;
}

function exportText(context) {
    return JSON.stringify({ kind: "cortetsu-context", version: 1, name: context.name, icon: context.icon,
                            summary: context.summary, settings: cleanSettings(context.settings) }, null, 2) + "\n";
}

function importText(text, custom) {
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!data || data.kind !== "cortetsu-context" || data.version !== 1)
        return null;
    return clean(data, newId(custom));
}
