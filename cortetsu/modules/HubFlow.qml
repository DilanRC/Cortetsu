import QtQuick

// The Hub's islands lay their controls in a row on a horizontal edge and in
// a column on a lateral one. Nothing is rotated: the same items are stacked.
Grid {
    property bool vertical: false

    // Released before the other is fixed: as two bindings, rows and columns
    // both read 1 for a moment and Grid warns that the items do not fit.
    function orient(): void {
        if (vertical) {
            rows = -1;
            columns = 1;
        } else {
            columns = -1;
            rows = 1;
        }
    }

    rows: 1
    columns: -1
    onVerticalChanged: orient()
    Component.onCompleted: orient()
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter
}
