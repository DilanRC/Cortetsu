.pragma library

// Qt's WeakMap can retain a dead QML wrapper key and crash during the next lookup.
const instanceIds = [];
let nextInstanceId = 0;

function instanceKey(item) {
    const existing = instanceIds.find(entry => entry.item === item);
    if (existing)
        return existing.key;
    const key = `tray-instance-${++nextInstanceId}`;
    instanceIds.push({ item, key });
    return key;
}

function entries(items) {
    for (let index = instanceIds.length - 1; index >= 0; index--) {
        if (!items.some(item => item === instanceIds[index].item))
            instanceIds.splice(index, 1);
    }
    return items.map(item => ({ key: instanceKey(item), item }));
}

function popupName(key) {
    return `traymenu${key}`;
}
