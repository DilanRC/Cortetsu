#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
component="$root/cortetsu/modules/StatusPill.qml"
hub="$root/cortetsu/modules/BottomHub.qml"
segment="$root/cortetsu/modules/CortetsuStatusSegment.qml"

require() {
    rg -Fq "$1" "$2" || {
        printf 'missing %s in %s\n' "$1" "$2" >&2
        exit 1
    }
}

for state in recordingActive dndActive idleInhibited; do
    require "property bool $state: false" "$component"
done

require "width: hasStatus ? pill.implicitWidth : 0" "$component"
require "visible: hasStatus || width > 0" "$component"
require 'tooltip: qsTr("Grabación de pantalla activa")' "$component"
require 'tooltip: qsTr("Reposo suspendido")' "$component"
require "text: item.tooltip" "$component"
require "recordingActive: CortetsuRecorder.running" "$hub"
require "dndActive: CortetsuNotifications.dnd" "$hub"
require "idleInhibited: CortetsuIdleInhibitor.enabled" "$hub"
require "StatusPill {" "$segment"
require "idleInhibited: root.idleInhibited" "$segment"
require "recordingActive: root.recordingActive" "$segment"
require "dndActive: root.dndActive" "$segment"
require "CortetsuStatusSegment {" "$root/cortetsu/modules/CortetsuBottomHubView.qml"

if rg -n 'Timer|Process|execDetached' "$component"; then
    echo 'StatusPill must not create a polling/process backend' >&2
    exit 1
fi

recording=$(rg -n 'label: qsTr\("REC"\)' "$component" | cut -d: -f1)
dnd=$(rg -n 'label: qsTr\("DND"\)' "$component" | cut -d: -f1)
idle=$(rg -n 'label: qsTr\("Activo"\)' "$component" | cut -d: -f1)

[[ "$recording" -lt "$dnd" && "$dnd" -lt "$idle" ]] || {
    echo 'Status order must be REC, DND, Activo' >&2
    exit 1
}

echo 'PASS: StatusPill state bindings, zero-width idle state, order, and no polling'
