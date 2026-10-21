.pragma library

// True when only items as large as `container` cover (x, y): scrims and
// outside-click areas, never a panel. Invisible items are skipped (childAt).
function backdropOnly(container, x, y) {
    let item = container;
    let point = Qt.point(x, y);
    for (let child = item.childAt(point.x, point.y); child; child = item.childAt(point.x, point.y)) {
        if (child.width < container.width || child.height < container.height)
            return false;
        point = item.mapToItem(child, point.x, point.y);
        item = child;
    }
    return true;
}
