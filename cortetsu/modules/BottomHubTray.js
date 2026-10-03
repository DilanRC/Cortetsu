.pragma library

.import "../base/modules/bar/SystemTrayIdentity.js" as TrayIdentity

function instanceKey(item) {
    return TrayIdentity.instanceKey(item);
}

function itemForKey(items, key) {
    return items.find(item => instanceKey(item) === key) ?? null;
}

function visibleItems(items, hiddenIds, passiveStatus) {
    return items.filter(item => item.status !== passiveStatus && !hiddenIds.includes(item.id));
}

function visibleEntries(items, hiddenIds, passiveStatus) {
    return TrayIdentity.entries(items)
        .filter(({ item }) => item.status !== passiveStatus && !hiddenIds.includes(item.id));
}

function tooltipFor(item) {
    const title = [item.tooltipTitle, item.title, item.id]
        .map(value => String(value ?? "").trim())
        .find(value => value.length > 0) ?? "";
    const description = String(item.tooltipDescription ?? "").trim();
    return description && description !== title ? `${title}\n${description}` : title;
}

function primaryAction(item) {
    if (item.onlyMenu)
        return item.hasMenu ? "menu" : "none";
    return "activate";
}

function contextAction(item) {
    return item.hasMenu ? "menu" : "none";
}

function menuName(itemKey) {
    return TrayIdentity.popupName(itemKey);
}

function nextSelectable(count, fromIndex, direction, isSelectable) {
    for (let index = fromIndex + direction; index >= 0 && index < count; index += direction) {
        if (isSelectable(index))
            return index;
    }
    return -1;
}

function indexOfEntry(count, entryAt, target) {
    for (let index = 0; index < count; index++) {
        if (entryAt(index) === target)
            return index;
    }
    return -1;
}
