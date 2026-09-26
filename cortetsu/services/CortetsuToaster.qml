pragma Singleton

import QtQml
import Quickshell

// Small first-party event surface used by shell-owned features. It deliberately
// stores plain values so no upstream C++ type can leak across the boundary.
Singleton {
    id: root

    property var toasts: []
    property int nextId: 0
    function toast(title, message, icon, type = 0) {
        const item = { id: nextId++, title, message, icon, type };
        toasts = [item, ...toasts];
    }

    function dismiss(id) {
        toasts = toasts.filter(item => item.id !== id);
    }

}
