.pragma library

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
