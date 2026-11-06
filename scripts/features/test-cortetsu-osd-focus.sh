#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
registry="$root/cortetsu/modules/SurfaceRegistry.js"
window="$root/cortetsu/modules/drawers/ContentWindow.qml"
wrapper="$root/cortetsu/modules/osd/Wrapper.qml"
mini="$root/cortetsu/modules/osd/MiniSlider.qml"
grep -Fq '{ name: "osd", kind: "transient", exclusive: false, ownsKeyboard: true' "$registry"
grep -Fq 'enabled: focusGrab.active || panels.popouts.hasCurrent || root.screenState?.osd' "$window"
grep -Fq 'if (screenState?.osd || panels.popouts.isDetached' "$window"
grep -Fq 'return WlrKeyboardFocus.Exclusive;' "$window"
grep -Fq 'root.screenState.osd = false;' "$window"
grep -Fq 'root.showMini("volume")' "$wrapper"
grep -Fq 'root.showMini("brightness")' "$wrapper"
grep -Fq 'if (!screenState || screenState.osd' "$wrapper"
! grep -Eq 'Keys\.|forceActiveFocus|activeFocusOnTab|MouseArea' "$mini"
printf '%s\n' 'PASS: the explicit OSD takes keyboard focus and Escape closes it'
