import QtQuick

Item {
    id: root

    signal pointerEntered
    signal pointerExited

    HoverHandler {
        id: pointer
        enabled: root.enabled

        onHoveredChanged: {
            if (hovered)
                root.pointerEntered();
            else
                root.pointerExited();
        }
    }
}
