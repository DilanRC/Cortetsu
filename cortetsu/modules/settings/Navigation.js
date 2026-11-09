.pragma library

// Search and movement over the Settings categories. Pure functions: the
// controller owns the tree, the sidebar draws the result.

// "energia" finds "Energía": accents and case are not part of the query.
function normalise(text) {
    return String(text || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
}

// Whether a category matches: by its own name or keywords, or through one
// of its subpages.
function matchesCategory(category, needle) {
    if (normalise(`${category.title} ${category.keywords || ""}`).includes(needle))
        return true;
    return (category.pages || []).some(page => pageMatch(page, needle).matches);
}

// For one subpage, whether it matches and which of its settings did.
function pageMatch(page, needle) {
    if (normalise(page.title).includes(needle))
        return { matches: true, setting: "" };
    const settings = page.settings || [];
    for (let i = 0; i < settings.length; ++i) {
        if (normalise(settings[i]).includes(needle))
            return { matches: true, setting: settings[i] };
    }
    if (normalise(`${page.keywords || ""} ${page.detail || ""}`).includes(needle))
        return { matches: true, setting: "" };
    return { matches: false, setting: "" };
}

function matchingIds(categories, query) {
    const needle = normalise(query);
    if (!needle)
        return categories.map(category => category.id);
    return categories.filter(category => matchesCategory(category, needle)).map(category => category.id);
}

// What a search offers: each setting whose name matches, then each subpage
// that matches by name or keyword, then each category. A result knows the
// page that holds it and the path to show under its name.
function results(categories, query) {
    const needle = normalise(query);
    if (!needle)
        return [];
    const settings = [];
    const pages = [];
    const others = [];
    for (const category of categories) {
        for (const page of category.pages || []) {
            for (const setting of page.settings || []) {
                if (normalise(setting).includes(needle))
                    settings.push({ page: page.id, setting, title: setting, icon: page.icon, path: `${category.title} › ${page.title}` });
            }
            if (pageMatch(page, needle).matches && !(page.settings || []).some(s => normalise(s).includes(needle)))
                pages.push({ page: page.id, setting: "", title: page.title, icon: page.icon, path: category.title });
        }
        if (!(category.pages || []).length && normalise(`${category.title} ${category.keywords || ""}`).includes(needle))
            others.push({ page: category.id, setting: "", title: category.title, icon: category.icon, path: "" });
    }
    return settings.concat(pages, others).slice(0, 40);
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
