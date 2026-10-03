.pragma library

// Search and movement over the Settings categories. Pure functions: the
// controller owns the list, the Nexus draws the result.

// "energia" finds "Energía": accents and case are not part of the query.
function normalise(text) {
    return String(text || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
}

// For each category, whether it matches and which of its settings did.
// A category matches by its own name or group; otherwise by a setting, and
// then the row can say which one.
function match(category, query) {
    const needle = normalise(query);
    if (!needle)
        return { matches: true, setting: "" };
    if (normalise(`${category.title} ${category.group}`).includes(needle))
        return { matches: true, setting: "" };
    const settings = category.settings || [];
    for (let i = 0; i < settings.length; ++i) {
        if (normalise(settings[i]).includes(needle))
            return { matches: true, setting: settings[i] };
    }
    if (normalise(category.keywords).includes(needle))
        return { matches: true, setting: "" };
    return { matches: false, setting: "" };
}

function matchingIds(categories, query) {
    return categories.filter(category => match(category, query).matches).map(category => category.id);
}

// The id `delta` places away from `current` among `ids`, without wrapping:
// holding an arrow stops at the end instead of jumping to the other one.
function neighbour(ids, current, delta) {
    if (!ids.length)
        return "";
    const index = ids.indexOf(current);
    if (index < 0)
        return delta > 0 ? ids[0] : ids[ids.length - 1];
    return ids[Math.max(0, Math.min(ids.length - 1, index + delta))];
}
