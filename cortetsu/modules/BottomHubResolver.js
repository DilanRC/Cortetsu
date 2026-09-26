.pragma library

function normalizeIdentity(value) {
    return String(value ?? "")
        .toLowerCase()
        .replace(/[.]desktop$/, "")
        .replace(/[.]appimage$/, "");
}

function identitiesForWindow(window) {
    return [window.initialClass, window.class]
        .map(value => String(value ?? "").trim())
        .filter(value => value.length > 0);
}

function desktopEntryForWindow(window, entries, byId, isPinned) {
    const identities = identitiesForWindow(window);

    for (const identity of identities) {
        const entry = byId(identity);
        if (entry)
            return entry;
    }

    for (const identity of identities) {
        const normalized = normalizeIdentity(identity);
        const matches = entries.filter(candidate =>
            [candidate.startupClass, candidate.id].some(value =>
                normalizeIdentity(value) === normalized
            )
        );
        if (matches.length === 1)
            return matches[0];
    }

    const steamAppId = identities
        .map(identity => identity.match(/^steam_app_([0-9]+)$/i)?.[1])
        .find(value => value);
    if (steamAppId) {
        const steamUrl = `steam://rungameid/${steamAppId}`;
        const steamIcon = `steam_icon_${steamAppId}`;
        const matches = entries.filter(candidate => {
            const icon = String(candidate.icon ?? "")
                .split("/")
                .pop()
                .replace(/[.][^.]+$/, "");
            const command = Array.from(candidate.command ?? []);
            return icon === steamIcon
                || command.some(argument => {
                    const value = String(argument);
                    return value === steamUrl || value.endsWith(`=${steamUrl}`);
                });
        });
        const pinnedEntry = matches.find(candidate => isPinned(candidate));
        if (pinnedEntry)
            return pinnedEntry;
        if (matches.length === 1)
            return matches[0];
    }

    for (const identity of identities) {
        const normalized = normalizeIdentity(identity);
        const executableMatches = entries.filter(candidate => {
            const executable = Array.from(candidate.command ?? [])[0] ?? "";
            return normalizeIdentity(String(executable).split("/").pop()) === normalized;
        });
        if (executableMatches.length === 1)
            return executableMatches[0];
    }

    return null;
}

function groupKeyForWindow(window, entry, anonymousIndex, address) {
    const entryId = String(entry?.id ?? "").trim();
    if (entryId)
        return entryId;

    const identity = String(window.initialClass ?? "").trim()
        || String(window.class ?? "").trim();
    if (identity)
        return identity.toLowerCase();

    return `window:${address || anonymousIndex}`;
}

function groupWindows(clients, resolveEntry) {
    const groups = new Map();
    let anonymousWindowIndex = 0;

    for (const client of clients) {
        const window = client.lastIpcObject ?? {};
        const cls = String(window.class ?? "").trim()
            || String(window.initialClass ?? "").trim();
        const address = String(window.address ?? "").trim();
        const entry = resolveEntry(client);
        const key = groupKeyForWindow(window, entry, anonymousWindowIndex, address);
        if (!String(entry?.id ?? "").trim()
                && !String(window.initialClass ?? "").trim()
                && !String(window.class ?? "").trim()
                && !address)
            anonymousWindowIndex++;

        if (!groups.has(key)) {
            groups.set(key, {
                key: key,
                entry: entry,
                className: cls,
                pinned: false,
                windows: []
            });
        }

        groups.get(key).windows.push(client);
    }

    return groups;
}
