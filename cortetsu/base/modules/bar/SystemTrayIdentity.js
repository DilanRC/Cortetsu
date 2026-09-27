.pragma library

const instanceIds = new WeakMap();
let nextInstanceId = 0;

function instanceKey(item) {
    let key = instanceIds.get(item);
    if (key === undefined) {
        key = `tray-instance-${++nextInstanceId}`;
        instanceIds.set(item, key);
    }
    return key;
}

function entries(items) {
    return items.map(item => ({ key: instanceKey(item), item }));
}

function popupName(key) {
    return `traymenu${key}`;
}
