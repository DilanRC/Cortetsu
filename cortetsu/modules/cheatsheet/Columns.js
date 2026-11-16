.pragma library

// Spreads groups over `count` columns, each group to the shortest column so
// far (a group costs its rows plus one for its heading). Order is kept
// inside a column, so reading down a column follows the original order.
function balance(groups, count) {
    var columns = [];
    var heights = [];
    for (var i = 0; i < Math.max(1, count); i++) {
        columns.push([]);
        heights.push(0);
    }
    for (var g = 0; g < groups.length; g++) {
        var shortest = 0;
        for (var c = 1; c < heights.length; c++)
            if (heights[c] < heights[shortest])
                shortest = c;
        columns[shortest].push(groups[g]);
        heights[shortest] += groups[g].bindings.length + 1;
    }
    return columns.filter(function (column) { return column.length > 0; });
}
