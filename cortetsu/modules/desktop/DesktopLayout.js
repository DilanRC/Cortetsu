.pragma library

// Geometry of desktop widgets. Pure functions, no QML objects.
//
// A widget is stored by the centre of its box as a fraction of its monitor
// (cx, cy in 0..1), not in pixels: the same layout survives a new
// resolution, a scale change or the laptop panel at 1.25. The box is then
// clamped inside the usable area, which leaves a margin and the edge the
// Hub sits on, so a widget never ends up under the Hub or off screen.

var margin = 24;
var gridStep = 8;
var snapReach = 10;
var maxWidgets = 24;
var maxNoteLength = 4000;

var types = ["clock", "date", "weather", "battery", "system", "storage", "network", "media", "note"];
var sizes = ["s", "m", "l"];
var scales = { s: 0.8, m: 1, l: 1.3 };
var baseSizes = {
    clock: [360, 156], date: [272, 294], weather: [300, 186], battery: [232, 154],
    system: [300, 218], storage: [300, 162], network: [300, 162], media: [348, 162], note: [264, 230]
};

function validType(type) {
    return types.indexOf(type) >= 0;
}

function sizeOf(type, size) {
    var base = baseSizes[type] || [240, 140];
    var scale = scales[size] || 1;
    return { w: Math.round(base[0] * scale), h: Math.round(base[1] * scale) };
}

// The part of the monitor widgets may use: a margin on every side plus what
// the Hub reserves on its edge (HubAnchor.reserved).
function area(screenW, screenH, reserved) {
    var r = reserved || { top: 0, bottom: 0, left: 0, right: 0 };
    return {
        x0: margin + r.left, y0: margin + r.top,
        x1: Math.max(margin + r.left, screenW - margin - r.right),
        y1: Math.max(margin + r.top, screenH - margin - r.bottom)
    };
}

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
}

function clampBox(x, y, w, h, a) {
    return {
        x: Math.round(clamp(x, a.x0, Math.max(a.x0, a.x1 - w))),
        y: Math.round(clamp(y, a.y0, Math.max(a.y0, a.y1 - h))),
        w: w, h: h
    };
}

function rectFor(entry, screenW, screenH, reserved) {
    var s = sizeOf(entry.type, entry.size);
    var x = (isFinite(entry.cx) ? Number(entry.cx) : 0.5) * screenW - s.w / 2;
    var y = (isFinite(entry.cy) ? Number(entry.cy) : 0.5) * screenH - s.h / 2;
    return clampBox(x, y, s.w, s.h, area(screenW, screenH, reserved));
}

function centreFor(rect, screenW, screenH) {
    return {
        cx: clamp((rect.x + rect.w / 2) / Math.max(1, screenW), 0, 1),
        cy: clamp((rect.y + rect.h / 2) / Math.max(1, screenH), 0, 1)
    };
}

// Lines a moving box can rest on: the usable area's edges and middle, and
// the edges and middles of the other boxes. Returns the snapped position and
// the guides that caught it (for drawing). Without a guide in reach the box
// rests on an 8 px grid.
function snap(rect, others, screenW, screenH, reserved) {
    var a = area(screenW, screenH, reserved);
    var xs = [a.x0, a.x1, (a.x0 + a.x1) / 2];
    var ys = [a.y0, a.y1, (a.y0 + a.y1) / 2];
    for (var i = 0; i < others.length; i++) {
        var o = others[i];
        xs.push(o.x, o.x + o.w, o.x + o.w / 2);
        ys.push(o.y, o.y + o.h, o.y + o.h / 2);
    }
    var bx = axis(rect.x, rect.w, xs);
    var by = axis(rect.y, rect.h, ys);
    var box = clampBox(bx.start, by.start, rect.w, rect.h, a);
    var guides = [];
    if (bx.line !== null)
        guides.push({ vertical: true, at: bx.line });
    if (by.line !== null)
        guides.push({ vertical: false, at: by.line });
    return { x: box.x, y: box.y, guides: guides };
}

function axis(start, size, lines) {
    var best = { start: Math.round(start / gridStep) * gridStep, line: null };
    var reach = snapReach;
    var points = [start, start + size / 2, start + size];
    for (var i = 0; i < lines.length; i++) {
        for (var p = 0; p < points.length; p++) {
            var gap = Math.abs(lines[i] - points[p]);
            if (gap < reach) {
                reach = gap;
                best = { start: start + lines[i] - points[p], line: lines[i] };
            }
        }
    }
    return best;
}

// Where a new widget appears: near the centre, stepped so that several
// added in a row do not stack exactly.
function spawnCentre(countOnScreen) {
    var step = (countOnScreen % 6) * 0.03;
    return { cx: 0.5 + step, cy: 0.42 + step };
}

function newId() {
    return "w" + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
}

// A preference entry, or null if it cannot be shown. Unknown fields are
// dropped; a damaged file never breaks the desktop.
function sanitise(entry) {
    if (!entry || typeof entry !== "object" || !validType(entry.type))
        return null;
    var out = {
        id: typeof entry.id === "string" && entry.id.length > 0 ? entry.id.slice(0, 64) : newId(),
        type: entry.type,
        screen: typeof entry.screen === "string" ? entry.screen.slice(0, 64) : "",
        cx: isFinite(entry.cx) ? clamp(Number(entry.cx), 0, 1) : 0.5,
        cy: isFinite(entry.cy) ? clamp(Number(entry.cy), 0, 1) : 0.5,
        size: sizes.indexOf(entry.size) >= 0 ? entry.size : "m"
    };
    if (entry.type === "clock")
        out.showDate = entry.showDate !== false;
    if (entry.type === "note")
        out.text = typeof entry.text === "string" ? entry.text.slice(0, maxNoteLength) : "";
    return out;
}

function sanitiseList(list) {
    if (!Array.isArray(list))
        return [];
    var out = [];
    var seen = {};
    for (var i = 0; i < list.length && out.length < maxWidgets; i++) {
        var entry = sanitise(list[i]);
        if (entry && !seen[entry.id]) {
            seen[entry.id] = true;
            out.push(entry);
        }
    }
    return out;
}

// Cortetsu 2.x had one desktop clock with a nine-point position. On the
// first load without a widget list it becomes a clock widget in the same
// place, on every connected monitor's first screen ("" = first screen).
var legacyCentres = {
    "top-left": [0.16, 0.12], "top-center": [0.5, 0.12], "top-right": [0.84, 0.12],
    "middle-left": [0.16, 0.5], "middle-center": [0.5, 0.5], "middle-right": [0.84, 0.5],
    "bottom-left": [0.16, 0.86], "bottom-center": [0.5, 0.86], "bottom-right": [0.84, 0.86]
};

function legacyClock(position, showDate) {
    var c = legacyCentres[position] || legacyCentres["top-left"];
    return { id: newId(), type: "clock", screen: "", cx: c[0], cy: c[1], size: "m", showDate: showDate !== false };
}
