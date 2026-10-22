.pragma library

// The UI and its deterministic race tests use this same reducer. A merge
// response may acknowledge only the batch sent to the owner: it must never
// dismiss notifications that arrived while that request was in flight.
function exactRevision(value) {
    return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

function normaliseEntries(value) {
    if (!Array.isArray(value) || value.length > 2048)
        return null;
    const seen = new Set();
    const result = [];
    for (const item of value) {
        if (!item || typeof item !== "object" || Array.isArray(item))
            return null;
        if (typeof item.id !== "string" && !(typeof item.id === "number" && Number.isSafeInteger(item.id)))
            return null;
        const id = String(item.id);
        if (!id || id.length > 512 || seen.has(id))
            return null;
        seen.add(id);
        result.push(Object.assign({}, item, {id}));
    }
    return result;
}

function parseHistory(text) {
    if (typeof text !== "string" || text.length > 1024 * 1024)
        return null;
    try { return normaliseEntries(JSON.parse(text)); }
    catch (_) { return null; }
}

function prepareBatch(baseIds, entries, clearRevision) {
    const next = normaliseEntries(entries);
    if (next === null || !Array.isArray(baseIds) || baseIds.length > 2048
        || baseIds.some(id => typeof id !== "string"))
        return null;
    const request = {base_ids: Array.from(new Set(baseIds)), entries: next};
    if (clearRevision !== undefined) {
        if (!exactRevision(clearRevision)) return null;
        request.clear_revision = clearRevision;
    }
    return request;
}

function reconcile(batch, verified) {
    const next = normaliseEntries(verified);
    if (next === null || !batch || !Array.isArray(batch.base_ids) || !Array.isArray(batch.entries))
        return null;
    const savedIds = next.map(item => item.id);
    const kept = new Set(savedIds);
    const submitted = new Set(batch.base_ids.concat(batch.entries.map(item => String(item.id))));
    return {removed: Array.from(submitted).filter(id => !kept.has(id)), savedIds};
}

function externalEdit(previousIds, entries) {
    // [] alone is not a clear event. It can be our own previous save, read
    // again after a newer notification has arrived. Explicit clear commands
    // have a separate owner revision; ordinary file edits remove saved IDs.
    return reconcile({base_ids: previousIds, entries: []}, entries);
}

function parseDnd(text) {
    try {
        const state = JSON.parse(text);
        if (!state || typeof state !== "object" || Array.isArray(state) || typeof state.dnd !== "boolean"
            || (state.revision !== undefined && !exactRevision(state.revision)))
            return null;
        return state;
    } catch (_) { return null; }
}

function observeClear(previous, next) {
    if (!next || typeof next !== "object" || Array.isArray(next) || !exactRevision(next.revision)
        || (next.pending !== undefined && typeof next.pending !== "boolean")
        || (previous !== null && next.revision < previous.revision))
        return null;
    return {clear: previous !== null && next.revision > previous.revision,
        state: {revision: next.revision, pending: next.pending === true}};
}
