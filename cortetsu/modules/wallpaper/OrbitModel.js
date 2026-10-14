.pragma library

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
}

// "ALL" first, then every category in first-seen order with its entry count.
// `lastName` names the bucket for entries without a category; it goes last.
function categoryCounts(entries, categoryFor, lastName) {
    const values = [];
    const slots = {};
    for (let i = 0; i < entries.length; ++i) {
        const category = categoryFor(entries[i]);
        if (!category)
            continue;
        if (slots[category] === undefined) {
            slots[category] = values.length;
            values.push({ name: category, count: 0 });
        }
        values[slots[category]].count += 1;
    }
    const named = values.filter(value => value.name !== lastName);
    const last = values.filter(value => value.name === lastName);
    return [{ name: "ALL", count: entries.length }].concat(named, last);
}

function filtered(entries, category, categoryFor) {
    if (category === "ALL")
        return entries.slice();
    return entries.filter(entry => categoryFor(entry) === category);
}

function normalize(index, count) {
    if (count <= 0)
        return -1;
    return ((index % count) + count) % count;
}

function prefetch(entries, currentIndex, maximum) {
    const count = entries.length;
    if (count === 0)
        return [];
    const size = clamp(Math.floor(maximum), 1, Math.min(18, count));
    const start = normalize(currentIndex - Math.floor(size / 2), count);
    const result = [];
    for (let i = 0; i < size; ++i)
        result.push(entries[(start + i) % count]);
    return result;
}

function basename(path) {
    const slash = path.lastIndexOf("/");
    return slash >= 0 ? path.slice(slash + 1) : path;
}

function resolveCurrentIndex(entries, actualPath) {
    for (let i = 0; i < entries.length; ++i) {
        if (entries[i].path === actualPath)
            return i;
    }
    const name = basename(actualPath || "");
    if (!name)
        return -1;
    let match = -1;
    for (let i = 0; i < entries.length; ++i) {
        if (basename(entries[i].path) !== name)
            continue;
        if (match >= 0)
            return -1;
        match = i;
    }
    return match;
}

// A collection that fits in the arc is laid out as a strip with real ends;
// a larger one wraps, so the wheel never runs out.
function arcWraps(count, half) {
    return count > half * 2 + 1;
}

// Entries around the anchor with their signed slot. `half` counts the slots
// on each side, including the hidden one that fades in while the arc turns.
function arc(entries, anchorIndex, half) {
    const count = entries.length;
    if (count === 0 || anchorIndex < 0)
        return [];
    const result = [];
    if (!arcWraps(count, half)) {
        for (let i = 0; i < count; ++i)
            result.push({ entry: entries[i], index: i, offset: i - anchorIndex });
        return result;
    }
    for (let offset = -half; offset <= half; ++offset) {
        const index = normalize(anchorIndex + offset, count);
        result.push({ entry: entries[index], index: index, offset: offset });
    }
    return result;
}

function arcSteps(from, to, count, half) {
    return arcWraps(count, half) ? shortestSteps(from, to, count) : to - from;
}

// Polar angle of a slot on the wheel under the stage. The selected slot sits
// at the top (-PI/2); `phase` is the turn in slots while a move animates.
function arcAngle(offset, phase, half, span) {
    return -Math.PI / 2 + (offset - phase) * span / Math.max(1, half);
}

// 1 at the top of the wheel, 0 at the edge of the visible span and beyond.
function arcDepth(angle, span) {
    const turn = Math.abs(angle + Math.PI / 2);
    if (turn >= span)
        return 0;
    return clamp((Math.cos(turn) - Math.cos(span)) / (1 - Math.cos(span)), 0, 1);
}

function move(index, direction, count) {
    return normalize(index + direction, count);
}

function shortestSteps(from, to, count) {
    if (count <= 1)
        return 0;
    const forward = normalize(to - from, count);
    return forward > count / 2 ? forward - count : forward;
}

function wheelIntent(accumulator, angleDelta, pixelDelta) {
    const delta = pixelDelta !== 0 ? pixelDelta : angleDelta;
    const threshold = pixelDelta !== 0 ? 40 : 120;
    const total = accumulator && delta && Math.sign(accumulator) !== Math.sign(delta)
        ? delta : accumulator + delta;
    if (!delta || Math.abs(total) < threshold)
        return { accumulator: total, direction: 0 };
    return {
        accumulator: Math.sign(total) * (Math.abs(total) % threshold),
        direction: total > 0 ? -1 : 1
    };
}

function previewEligible(pendingPath, currentPath, managerOpen, animating, queuedDirection) {
    return managerOpen && !animating && !queuedDirection && !!pendingPath && pendingPath === currentPath;
}
