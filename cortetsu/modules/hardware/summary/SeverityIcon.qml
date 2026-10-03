import QtQuick
import "../../../components"
import "../../../theme"

// The mark of a flagged reading. Shape and colour both change with the
// severity, so the flag does not rest on colour alone.
CortetsuIcon {
    id: root

    property string severity: ""

    visible: root.severity !== ""
    text: root.severity === "critical" ? "error" : "warning"
    color: root.severity === "critical" ? CortetsuDesign.colorVermillion : CortetsuDesign.colorWarning
}
