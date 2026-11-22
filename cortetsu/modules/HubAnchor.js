.pragma library

// Where the Hub sits on a monitor and what follows from it: its edge, how its
// islands are packed, where an attached popout opens and how much room the
// other surfaces must leave. Pure geometry, so every anchor is testable
// without a compositor.
//
//   edge    the screen edge the Hub is attached to
//   pack    "spread": islands at the two ends and the middle of the edge
//           "start" / "end": islands together at that end (a corner)
//
// A lateral Hub stacks its islands; nothing in it is rotated.

var fallback = "bottom-center";

var anchors = {
    "top-left": { edge: "top", pack: "start" },
    "top-center": { edge: "top", pack: "spread" },
    "top-right": { edge: "top", pack: "end" },
    "middle-left": { edge: "left", pack: "spread" },
    "middle-right": { edge: "right", pack: "spread" },
    "bottom-left": { edge: "bottom", pack: "start" },
    "bottom-center": { edge: "bottom", pack: "spread" },
    "bottom-right": { edge: "bottom", pack: "end" }
};

var ids = Object.keys(anchors);

// What each anchor is called on screen (Settings, the edit mode).
var labels = {
    "top-left": "Arriba a la izquierda", "top-center": "Arriba, a lo ancho",
    "top-right": "Arriba a la derecha", "middle-left": "Lateral izquierdo",
    "middle-right": "Lateral derecho", "bottom-left": "Abajo a la izquierda",
    "bottom-center": "Abajo, a lo ancho", "bottom-right": "Abajo a la derecha"
};

function valid(id) {
    return typeof id === "string" && Object.prototype.hasOwnProperty.call(anchors, id);
}

function normalize(id) {
    return valid(id) ? id : fallback;
}

function describe(id) {
    const key = normalize(id);
    const anchor = anchors[key];
    return {
        id: key,
        edge: anchor.edge,
        pack: anchor.pack,
        vertical: anchor.edge === "left" || anchor.edge === "right"
    };
}

// The anchor of one monitor: its own entry, else the default for all. An
// entry that is not a known anchor is ignored, so a damaged preference can
// never leave a Hub off screen.
function forMonitor(defaultId, perMonitor, monitorName) {
    const own = perMonitor && typeof perMonitor === "object" ? perMonitor[monitorName] : undefined;
    return valid(own) ? own : normalize(defaultId);
}

// Per-monitor entries with everything unknown dropped.
function sanitizeMap(value) {
    const out = {};
    if (!value || typeof value !== "object" || Array.isArray(value))
        return out;
    for (const name of Object.keys(value)) {
        if (name.length > 0 && name.length <= 64 && valid(value[name]))
            out[name] = value[name];
    }
    return out;
}

function clamp(value, low, high) {
    return Math.max(low, Math.min(Math.max(low, high), value));
}

// Top-left corner of an attached popout inside `area` (the drawers' item,
// whose origin is the screen's). `along` is the centre of the control that
// opened it, measured along the Hub's edge in the same coordinates; a
// negative value means "no control": the popout goes to the far end.
// `thickness` is what the Hub takes from its edge, `gap` the air between
// them, `inset` the least distance to any other edge.
function popoutPosition(id, along, popoutWidth, popoutHeight, areaWidth, areaHeight, thickness, gap, inset) {
    const anchor = describe(id);
    const offset = thickness + gap;
    if (anchor.vertical) {
        const y = along >= 0
            ? clamp(along - popoutHeight / 2, inset, areaHeight - popoutHeight - inset)
            : clamp(areaHeight - popoutHeight - inset, inset, areaHeight - popoutHeight - inset);
        const x = anchor.edge === "left"
            ? clamp(offset, inset, areaWidth - popoutWidth - inset)
            : clamp(areaWidth - popoutWidth - offset, inset, areaWidth - popoutWidth - inset);
        return { x: x, y: y };
    }
    const x = along >= 0
        ? clamp(along - popoutWidth / 2, inset, areaWidth - popoutWidth - inset)
        : clamp(areaWidth - popoutWidth - inset, inset, areaWidth - popoutWidth - inset);
    const y = anchor.edge === "top"
        ? clamp(offset, inset, areaHeight - popoutHeight - inset)
        : clamp(areaHeight - popoutHeight - offset, inset, areaHeight - popoutHeight - inset);
    return { x: x, y: y };
}

// The direction a popout travels while it opens: away from the Hub, towards
// the middle of the screen. Unit vector, to be scaled by the caller.
function popoutTravel(id) {
    switch (describe(id).edge) {
    case "top": return { x: 0, y: -1 };
    case "left": return { x: -1, y: 0 };
    case "right": return { x: 1, y: 0 };
    default: return { x: 0, y: 1 };
    }
}

// The point of a popout at `x`, `y` (size `w` x `h`) that faces the control
// at `along` on the Hub's edge, in the popout's own coordinates: it opens
// out of that point and closes back into it. Without a control, the middle
// of the side that faces the Hub.
function popoutOrigin(id, along, x, y, w, h) {
    const anchor = describe(id);
    if (anchor.vertical)
        return { x: anchor.edge === "left" ? 0 : w, y: along >= 0 ? clamp(along - y, 0, h) : h / 2 };
    return { x: along >= 0 ? clamp(along - x, 0, w) : w / 2, y: anchor.edge === "top" ? 0 : h };
}

// The anchors as they lie on the screen; "" is its centre, where no Hub goes.
var grid = [
    ["top-left", "top-center", "top-right"],
    ["middle-left", "", "middle-right"],
    ["bottom-left", "bottom-center", "bottom-right"]
];

// The anchor next to `id` in the direction (`dx`, `dy`) as they lie on the
// screen, stepping over the centre, where no Hub goes. At an edge it stays.
function move(id, dx, dy) {
    const from = normalize(id);
    let row = grid.findIndex(line => line.includes(from));
    let column = grid[row].indexOf(from);
    for (let step = 0; step < 2; ++step) {
        row = clamp(row + dy, 0, 2);
        column = clamp(column + dx, 0, 2);
        if (grid[row][column] !== "")
            return grid[row][column];
    }
    return from;
}

// The rectangle the Hub's islands take at `id` on a `screenW` x `screenH`
// monitor, for the edit mode's previews. `packedLength` is what the islands
// measure end to end; at a corner the Hub is that long.
// ponytail: the corner preview reuses the current packed length whatever the
// orientation; stacked and in a row the islands differ by a few pixels per
// icon. Measure both orientations if a preview ever needs to be exact.
// `margin` is the space left at the ends of the edge, `edgeMargin` the gap
// between the Hub and its own edge (the margin when not given).
function footprint(id, screenW, screenH, thickness, packedLength, margin, edgeGap, edgeMargin) {
    const anchor = describe(id);
    const toEdge = edgeMargin === undefined ? margin : edgeMargin;
    if (anchor.vertical) {
        const x = anchor.edge === "left" ? toEdge : screenW - toEdge - thickness;
        return { x: x, y: margin, width: thickness, height: Math.max(0, screenH - margin * 2) };
    }
    const y = anchor.edge === "top" ? toEdge : screenH - toEdge - thickness;
    if (anchor.pack === "spread")
        return { x: margin, y: y, width: Math.max(0, screenW - margin * 2), height: thickness };
    const length = clamp(packedLength, thickness, screenW - (margin + edgeGap) * 2);
    const x = anchor.pack === "start" ? margin + edgeGap : screenW - margin - edgeGap - length;
    return { x: x, y: y, width: length, height: thickness };
}

// The anchor a Hub dropped at (`x`, `y`) snaps to: the screen cut in thirds,
// as the anchors lie on it. The centre goes to the nearest edge.
function nearest(x, y, screenW, screenH) {
    if (!(screenW > 0) || !(screenH > 0) || !isFinite(x) || !isFinite(y))
        return fallback;
    const column = clamp(Math.floor(x / (screenW / 3)), 0, 2);
    const row = clamp(Math.floor(y / (screenH / 3)), 0, 2);
    if (grid[row][column] !== "")
        return grid[row][column];
    // Distance to each edge, relative to the screen, so a wide screen does
    // not favour the top and bottom.
    const fx = x / screenW, fy = y / screenH;
    const toSide = Math.min(fx, 1 - fx), toEnd = Math.min(fy, 1 - fy);
    if (toSide < toEnd)
        return fx < 0.5 ? "middle-left" : "middle-right";
    return fy < 0.5 ? "top-center" : "bottom-center";
}

// What the Hub takes from each edge of its monitor, for the surfaces that
// must stay clear of it (OSD, utilities, launcher).
function reserved(id, thickness) {
    const edge = describe(id).edge;
    return {
        top: edge === "top" ? thickness : 0,
        bottom: edge === "bottom" ? thickness : 0,
        left: edge === "left" ? thickness : 0,
        right: edge === "right" ? thickness : 0
    };
}

// Where a packed Hub (a corner anchor) starts along its edge. `offset` moves
// it away from its own end, in pixels; it never leaves the usable length.
// Spread anchors ignore it: their three slots are defined by the edge.
function packedStart(pack, length, edgeGap, packedLength, offset) {
    const room = Math.max(0, length - edgeGap * 2 - packedLength);
    const shift = clamp(Number.isFinite(offset) ? offset : 0, 0, room);
    return pack === "end" ? length - edgeGap - packedLength - shift : edgeGap + shift;
}

// Per-monitor offsets with everything not a finite, non-negative number dropped.
function sanitizeOffsets(value) {
    const out = {};
    if (!value || typeof value !== "object" || Array.isArray(value))
        return out;
    for (const name of Object.keys(value)) {
        const px = value[name];
        if (name.length > 0 && name.length <= 64 && typeof px === "number" && Number.isFinite(px) && px >= 0)
            out[name] = Math.min(8192, Math.round(px));
    }
    return out;
}
