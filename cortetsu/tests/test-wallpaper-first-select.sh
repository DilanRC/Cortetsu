#!/usr/bin/env bash
# First wallpaper selection on a HOME that has never had one: path.txt does not
# exist, so the FileView watch is not armed. Runs the real CortetsuWallpapers
# singleton with a fake cortetsu-wallpaper-select and private XDG roots; no
# window is created and nothing of the session's state is read or written.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="${CORTETSU_WALLPAPER_FIXTURE:-$REPO/cortetsu/WallpaperFirstSelectFixture.qml}"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/walls" "$TMP/config/cortetsu" "$TMP/state" "$TMP/cache" "$TMP/data"
: > "$TMP/walls/first.png"; : > "$TMP/walls/second.png"; : > "$TMP/walls/broken.png"

# Answers late (after FileView's first load has failed) and writes path.txt the
# way the real helper does: a new file on the first run, a rename afterwards.
cat > "$TMP/bin/cortetsu-wallpaper-select" <<'SH'
#!/bin/sh
case "$1" in */broken.png) echo "fake select: broken.png" >&2; exit 1 ;; esac
sleep 0.3
dir="$XDG_STATE_HOME/cortetsu/wallpaper"
mkdir -p "$dir"
printf '%s\n' "$1" > "$dir/path.txt.tmp" && mv -f "$dir/path.txt.tmp" "$dir/path.txt"
SH
chmod +x "$TMP/bin/cortetsu-wallpaper-select"

# Reduced motion zeroes every motion token; the apply deadline must not be one.
for reduced in false true; do
    rm -rf -- "$TMP/state"; mkdir -p "$TMP/state"
    printf '{"schema":1,"smartScheme":false,"reducedMotion":%s,"wallpaperDirectory":"%s"}\n' \
        "$reduced" "$TMP/walls" > "$TMP/config/cortetsu/preferences.json"
    output="$(env PATH="$TMP/bin:$PATH" XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state" \
        XDG_CACHE_HOME="$TMP/cache" XDG_DATA_HOME="$TMP/data" CORTETSU_WALLPAPERS_DIR="$TMP/walls" \
        timeout 20s qs -p "$FIXTURE" --no-color 2>&1)" || true
    if [[ "$output" != *WALLPAPER_FIRST_SELECT_PASS* ]]; then
        printf '%s\n' "$output" | grep -E 'WALLPAPER_FIRST_SELECT|ERROR|WARN' >&2 || printf '%s\n' "$output" >&2
        echo "FAIL: first wallpaper selection (reducedMotion=$reduced)" >&2
        exit 1
    fi
done
echo "PASS: first wallpaper selection on a fresh HOME, a second one and a failing helper, with and without reduced motion"
