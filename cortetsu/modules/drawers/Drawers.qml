pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../services"
import ".."

Variants {
    model: CortetsuScreens.screens

    Scope {
        id: scope
        required property ShellScreen modelData

        Exclusions {
            screen: scope.modelData
        }

        ContentWindow {
            id: content
            screen: scope.modelData
        }
    }
}
