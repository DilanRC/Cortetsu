.pragma library

function visibleItems(items, hiddenIds, passiveStatus) {
    return items.filter(item => item.status !== passiveStatus && !hiddenIds.includes(item.id));
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

function menuName(itemId) {
    return `traymenu${itemId}`;
}
