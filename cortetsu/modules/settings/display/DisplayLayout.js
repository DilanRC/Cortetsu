.pragma library

// Pure arrangement helpers for Settings → Pantalla. Modes are Hyprland's
// "WIDTHxHEIGHT@RATEHz" strings exactly as cortetsu-display-probe lists them;
// nothing here invents a mode that the output did not report.

function parseMode(mode) {
    const match = String(mode ?? "").match(/^(\d+)x(\d+)(?:@([0-9.]+))?/);
    if (!match) return { width: 0, height: 0, refresh: 0 };
    return { width: Number(match[1]), height: Number(match[2]), refresh: Number(match[3] ?? 0) };
}

// The listed mode nearest to the output's live size and refresh rate.
function currentMode(monitor) {
    const modes = monitor?.available_modes ?? [];
    const width = Number(monitor?.width ?? 0);
    const height = Number(monitor?.height ?? 0);
    const refresh = Number(monitor?.refresh_hz ?? 0);
    let nearest = "";
    let delta = Infinity;
    for (const mode of modes) {
        const parsed = parseMode(mode);
        if (parsed.width !== width || parsed.height !== height) continue;
        const gap = Math.abs(parsed.refresh - refresh);
        if (gap < delta) { delta = gap; nearest = String(mode); }
    }
    return nearest || (modes.length ? String(modes[0]) : "preferred");
}

function fromMonitors(monitors) {
    return (monitors ?? []).map(monitor => ({
        name: monitor?.name ?? "",
        enabled: !(monitor?.disabled ?? false),
        mode: currentMode(monitor),
        x: Number(monitor?.x ?? 0),
        y: Number(monitor?.y ?? 0),
        scale: Number(monitor?.scale ?? 1),
        transform: Number(monitor?.transform ?? 0)
    }));
}

// Unique sizes, largest first: "1920x1080".
function resolutions(modes) {
    const seen = [];
    for (const mode of modes ?? []) {
        const parsed = parseMode(mode);
        if (!parsed.width) continue;
        const size = `${parsed.width}x${parsed.height}`;
        if (!seen.includes(size)) seen.push(size);
    }
    return seen.sort((left, right) => {
        const a = parseMode(left), b = parseMode(right);
        return b.width * b.height - a.width * a.height || b.width - a.width;
    });
}

// Refresh rates the output lists for one size, highest first.
function rates(modes, size) {
    return (modes ?? []).filter(mode => String(mode).startsWith(size + "@"))
        .map(mode => parseMode(mode).refresh)
        .sort((left, right) => right - left);
}

function modeFor(modes, size, refresh) {
    const candidates = (modes ?? []).filter(mode => String(mode).startsWith(size + "@"));
    if (!candidates.length) return `${size}@${Number(refresh || 60).toFixed(2)}Hz`;
    return candidates.reduce((best, mode) =>
        Math.abs(parseMode(mode).refresh - refresh) < Math.abs(parseMode(best).refresh - refresh) ? mode : best);
}

// Rotated outputs (transform 1, 3, 5, 7) swap width and height.
function logicalSize(output) {
    const mode = parseMode(output?.mode);
    const scale = Math.max(0.25, Number(output?.scale ?? 1));
    const rotated = Number(output?.transform ?? 0) % 2 === 1;
    const width = Math.round((rotated ? mode.height : mode.width) / scale);
    const height = Math.round((rotated ? mode.width : mode.height) / scale);
    return { width: width || 1920, height: height || 1080 };
}

function bounds(outputs) {
    const shown = (outputs ?? []).filter(output => output?.enabled ?? true);
    if (!shown.length) return { minX: 0, minY: 0, width: 1920, height: 1080 };
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const output of shown) {
        const size = logicalSize(output);
        minX = Math.min(minX, Number(output.x ?? 0));
        minY = Math.min(minY, Number(output.y ?? 0));
        maxX = Math.max(maxX, Number(output.x ?? 0) + size.width);
        maxY = Math.max(maxY, Number(output.y ?? 0) + size.height);
    }
    return { minX, minY, width: Math.max(1, maxX - minX), height: Math.max(1, maxY - minY) };
}

// A dragged output sticks to the nearest edge of another one within the
// threshold (logical pixels), so outputs touch instead of leaving a gap.
function snap(outputs, index, x, y, threshold) {
    const limit = threshold ?? 96;
    const moving = logicalSize(outputs[index]);
    let bestX = { gap: limit + 1, value: Math.round(x) };
    let bestY = { gap: limit + 1, value: Math.round(y) };
    outputs.forEach((other, position) => {
        if (position === index || !(other?.enabled ?? true)) return;
        const size = logicalSize(other);
        const ox = Number(other.x ?? 0), oy = Number(other.y ?? 0);
        for (const value of [ox + size.width, ox - moving.width, ox, ox + size.width - moving.width]) {
            const gap = Math.abs(value - x);
            if (gap < bestX.gap) bestX = { gap, value };
        }
        for (const value of [oy + size.height, oy - moving.height, oy, oy + size.height - moving.height]) {
            const gap = Math.abs(value - y);
            if (gap < bestY.gap) bestY = { gap, value };
        }
    });
    return { x: bestX.value, y: bestY.value };
}

// After one output changes size (mode, scale, rotation), the outputs that
// touched its right or bottom edge are moved so they still touch it.
function reflow(before, after, index) {
    const old = logicalSize(before[index]);
    const now = logicalSize(after[index]);
    const dx = now.width - old.width;
    const dy = now.height - old.height;
    if (!dx && !dy) return after;
    const anchor = before[index];
    const right = Number(anchor.x) + old.width;
    const bottom = Number(anchor.y) + old.height;
    return after.map((output, position) => {
        if (position === index || !(output?.enabled ?? true)) return output;
        const moved = Object.assign({}, output);
        if (dx && Number(before[position].x) >= right) moved.x = Number(output.x) + dx;
        if (dy && Number(before[position].y) >= bottom) moved.y = Number(output.y) + dy;
        return moved;
    });
}

function internal(output) {
    return String(output?.name ?? "").startsWith("eDP-");
}

// kind: "laptop" | "external" | "extend" (external left, panel right).
function preset(outputs, kind) {
    const next = (outputs ?? []).map(item => Object.assign({}, item));
    const panel = next.findIndex(internal);
    const outside = next.findIndex(item => !internal(item));
    if (kind === "laptop") {
        if (panel < 0) return { ok: false, reason: "No hay pantalla interna" };
        next.forEach((item, i) => { item.enabled = i === panel; });
        next[panel].x = 0; next[panel].y = 0;
        return { ok: true, outputs: next, selected: panel, reason: "Solo la pantalla del portátil" };
    }
    if (outside < 0) return { ok: false, reason: "Conecta primero una pantalla externa" };
    if (kind === "external") {
        next.forEach((item, i) => { item.enabled = i === outside; });
        next[outside].x = 0; next[outside].y = 0;
        return { ok: true, outputs: next, selected: outside, reason: "Solo la pantalla externa" };
    }
    if (panel < 0) return { ok: false, reason: "No hay pantalla interna" };
    next.forEach((item, i) => { item.enabled = i === panel || i === outside; });
    next[outside].x = 0; next[outside].y = 0;
    next[panel].x = logicalSize(next[outside]).width; next[panel].y = 0;
    return { ok: true, outputs: next, selected: outside, reason: "Externa a la izquierda, portátil a la derecha" };
}
