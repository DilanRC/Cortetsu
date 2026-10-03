.pragma library

var pages = {
    summary: 0,
    performance: 1,
    processes: 2,
    sensors: 3,
    io: 4,
    power: 5
};

function pageForKey(key, currentPage, key1, key9, key0) {
    if (key >= key1 && key <= key9)
        return key - key1;
    if (key === key0)
        return 9;
    return currentPage;
}

function handlesPageKey(key, key1, key9, key0) {
    return (key >= key1 && key <= key9) || key === key0;
}

function isEscape(key, keyEscape) {
    return key === keyEscape;
}
