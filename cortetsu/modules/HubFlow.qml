import QtQuick

// The Hub's islands lay their controls in a row on a horizontal edge and in
// a column on a lateral one. Nothing is rotated: the same items are stacked.
Grid {
    property bool vertical: false

    rows: vertical ? -1 : 1
    columns: vertical ? 1 : -1
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter
}
