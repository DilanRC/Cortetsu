.pragma library

// Opacity of the two translucent layers text sits on in Settings, by
// material style (1 is paper, which needs a denser panel to stay readable).
// The contrast gate reads these, so it always tests what is drawn.
function panelAlpha(materialStyle) {
    return materialStyle === 1 ? 0.92 : 0.6;
}

function groupAlpha(materialStyle) {
    return materialStyle === 1 ? 0.6 : 0.72;
}
