.pragma library

function triggerDepth(minimumThickness, borderThickness, panelHeight) {
    return Math.max(minimumThickness, borderThickness + panelHeight);
}

function containsTop(y, minimumThickness, borderThickness, panelHeight) {
    return y <= triggerDepth(minimumThickness, borderThickness, panelHeight);
}

function containsBottom(y, height, minimumThickness, borderThickness, panelHeight, rounding = 0) {
    return y >= height - triggerDepth(minimumThickness, borderThickness, panelHeight) - 1 - rounding;
}

function dragRegionInset(borderThickness, dragMaskPadding) {
    // Leave the cursor's first reachable pixel outside the drag passthrough.
    return borderThickness + dragMaskPadding + 1;
}

function dragRegionHeight(windowHeight, borderThickness, dragMaskPadding) {
    // Region's far edge is inclusive, so leave the last coordinate outside.
    return windowHeight - 2 * dragRegionInset(borderThickness, dragMaskPadding) - 1;
}
