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
