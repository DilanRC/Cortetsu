pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../../components"
import "../../services"
import "../../utils"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// Previous, play or pause, next.
RowLayout {
    id: transport
    required property var active
    spacing: CortetsuDesign.spacingCompact
    CortetsuButton { compact: true; icon: "skip_previous"; label: ""; tooltipText: qsTr("Pista anterior"); disabled: !transport.active?.canGoPrevious; onClicked: transport.active?.previous() }
    CortetsuButton { compact: true; active: true; icon: transport.active?.isPlaying ? "pause" : "play_arrow"; label: ""; tooltipText: transport.active?.isPlaying ? qsTr("Pausar") : qsTr("Reproducir"); onClicked: transport.active?.togglePlaying() }
    CortetsuButton { compact: true; icon: "skip_next"; label: ""; tooltipText: qsTr("Pista siguiente"); disabled: !transport.active?.canGoNext; onClicked: transport.active?.next() }
}
