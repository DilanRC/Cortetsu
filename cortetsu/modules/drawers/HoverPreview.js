.pragma library

function contains(rect, x, y) {
    return !!rect && x >= rect.x && x < rect.x + rect.width
        && y >= rect.y && y < rect.y + rect.height;
}

function shouldKeepOpen(inPanel, inTrigger, inException = false) {
    return !!(inPanel || inTrigger || inException);
}
