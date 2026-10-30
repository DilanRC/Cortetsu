// cortetsu-lyrics: hands Spotify's own lyrics to the Cortetsu dashboard.
//
// On every song change it asks Spotify for the track's lyrics (the same
// request the client's lyrics view makes) and POSTs them to the shell's
// loopback bridge (`cortetsu-lyrics serve`). The last payload is re-sent now
// and then, so a shell that restarts mid-song catches up.
(function cortetsuLyrics() {
    if (!globalThis.Spicetify?.Player?.data || !Spicetify.CosmosAsync) {
        setTimeout(cortetsuLyrics, 500);
        return;
    }

    const BRIDGE = "http://127.0.0.1:47853/lyrics";
    const RESEND_MS = 15000;
    let last = null;
    let generation = 0;

    async function post(payload) {
        try {
            await fetch(BRIDGE, {
                method: "POST",
                headers: { "content-type": "application/json" },
                body: JSON.stringify(payload),
            });
        } catch (_) {
            // The shell is not running; the next resend will try again.
        }
    }

    function trackId() {
        const uri = Spicetify.Player.data?.item?.uri ?? "";
        const m = uri.match(/^spotify:track:([A-Za-z0-9]+)$/);
        return m ? m[1] : "";
    }

    async function fetchLyrics(id) {
        try {
            const res = await Spicetify.CosmosAsync.get(
                `https://spclient.wg.spotify.com/color-lyrics/v2/track/${id}?format=json&vocalRemoval=false&market=from_token`,
                null,
                { "app-platform": "WebPlayer" },
            );
            const lyrics = res?.lyrics;
            const lines = (lyrics?.lines ?? []).map(l => ({
                t: Number(l.startTimeMs) || 0,
                text: String(l.words ?? ""),
            }));
            return { trackId: id, synced: lyrics?.syncType === "LINE_SYNCED", lines };
        } catch (_) {
            // No lyrics for this track (Spotify answers 404).
            return { trackId: id, synced: false, lines: [] };
        }
    }

    async function update() {
        const id = trackId();
        if (!id) return;
        const mine = ++generation;
        const payload = await fetchLyrics(id);
        if (mine !== generation) return; // a newer song won
        last = payload;
        post(payload);
    }

    Spicetify.Player.addEventListener("songchange", update);
    setInterval(() => { if (last) post(last); }, RESEND_MS);
    update();
})();
