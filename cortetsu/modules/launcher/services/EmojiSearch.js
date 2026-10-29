.pragma library

// cortetsu-emoji data: one "glyph words…" entry per line.
function parse(text) {
    const out = [];
    for (const line of text.split("\n")) {
        const trimmed = line.trim();
        const space = trimmed.search(/\s/);
        if (space <= 0)
            continue;
        out.push({ glyph: trimmed.slice(0, space), words: trimmed.slice(space).trim(), haystack: trimmed.toLowerCase() });
    }
    return out;
}

// Every word of the query must appear in the entry, in any order. The glyph
// is part of the entry, so typing the emoji itself finds it.
function filter(list, query, limit) {
    const words = query.toLowerCase().split(/\s+/).filter(w => w.length > 0);
    const out = [];
    for (let i = 0; i < list.length && out.length < limit; i++)
        if (words.every(w => list[i].haystack.includes(w)))
            out.push(list[i]);
    return out;
}
