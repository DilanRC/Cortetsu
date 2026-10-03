#!/usr/bin/env bash
set -euo pipefail

SOURCE="${1:?usage: extract-cortetsu-evolving-assets.sh APPROVED_BOARD.png}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="$ROOT/cortetsu/assets/branding"
TMP="$(mktemp -d /tmp/cortetsu-evolving-assets.XXXXXX)"
cleanup() {
    find "$TMP" -type f -delete
    rmdir "$TMP"
}
trap cleanup EXIT

extract_phase() {
    local phase="$1" geometry="$2"
    magick "$SOURCE" -crop "$geometry" -trim +repage -alpha set -fuzz 6% -transparent white "$TMP/$phase.png"
}

write_svg() {
    local name="$1" title="$2" description="$3" png="$4"
    local width height data
    read -r width height <<< "$(identify -format '%w %h' "$png")"
    data="$(base64 --wrap=0 "$png")"
    printf '%s\n' \
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 '"$width $height"'" role="img" aria-labelledby="title desc">' \
        '  <title id="title">'"$title"'</title>' \
        '  <desc id="desc">'"$description"'</desc>' \
        '  <image href="data:image/png;base64,'"$data"'" x="0" y="0" width="'"$width"'" height="'"$height"'" preserveAspectRatio="none"/>' \
        '</svg>' > "$DEST/$name"
}

mkdir -p "$DEST"
extract_phase human '180x570+70+115'
extract_phase awakening '310x570+285+115'
extract_phase monster '330x570+610+115'
extract_phase ascended '300x570+955+115'
extract_phase cosmic '390x600+1245+80'

write_svg cortetsu-mark-human.svg 'Cortetsu Human mark' 'Approved monochrome Human phase of the Cortetsu Evolving Mark.' "$TMP/human.png"
write_svg cortetsu-mark-awakening.svg 'Cortetsu Awakening mark' 'Approved monochrome Awakening phase of the Cortetsu Evolving Mark.' "$TMP/awakening.png"
write_svg cortetsu-mark-monster.svg 'Cortetsu Monster mark' 'Approved monochrome Monster phase of the Cortetsu Evolving Mark.' "$TMP/monster.png"
write_svg cortetsu-mark-ascended.svg 'Cortetsu Ascended mark' 'Approved monochrome Ascended phase of the Cortetsu Evolving Mark.' "$TMP/ascended.png"
write_svg cortetsu-mark-cosmic.svg 'Cortetsu Cosmic mark' 'Approved monochrome Cosmic phase of the Cortetsu Evolving Mark.' "$TMP/cosmic.png"

cp "$DEST/cortetsu-mark-ascended.svg" "$DEST/cortetsu-mark.svg"
cp "$DEST/cortetsu-mark-ascended.svg" "$DEST/cortetsu-mark-dark.svg"
magick "$TMP/ascended.png" -fill '#F6F3EC' -colorize 100% "$TMP/ascended-white.png"
write_svg cortetsu-mark-light.svg 'Cortetsu Ascended light mark' 'Approved monochrome Ascended mark for dark surfaces.' "$TMP/ascended-white.png"
cp "$DEST/cortetsu-mark-ascended.svg" "$DEST/cortetsu-mark-monochrome-black.svg"
cp "$DEST/cortetsu-mark-light.svg" "$DEST/cortetsu-mark-monochrome-white.svg"

ascended_data="$(base64 --wrap=0 "$TMP/ascended.png")"
printf '%s\n' \
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-labelledby="title desc">' \
    '  <title id="title">Cortetsu app icon</title>' \
    '  <desc id="desc">The approved Ascended Cortetsu mark on a restrained application tile.</desc>' \
    '  <rect x="52" y="52" width="920" height="920" rx="190" fill="#F8F8F8"/>' \
    '  <image href="data:image/png;base64,'"$ascended_data"'" x="292" y="132" width="440" height="760" preserveAspectRatio="none"/>' \
    '</svg>' > "$DEST/cortetsu-app-icon.svg"

printf 'Extracted five approved Cortetsu phases into %s\n' "$DEST"
