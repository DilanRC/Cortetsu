#!/usr/bin/env python3
"""Evaluate the current first-party BottomHub composition and visual contract."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
modules = ROOT / "cortetsu/modules"

hub = (modules / "BottomHub.qml").read_text(encoding="utf-8")
view = (modules / "CortetsuBottomHubView.qml").read_text(encoding="utf-8")
rail = (modules / "CortetsuAppRail.qml").read_text(encoding="utf-8")
tray = (modules / "CortetsuTraySegment.qml").read_text(encoding="utf-8")
status = (modules / "CortetsuStatusSegment.qml").read_text(encoding="utf-8")
status_pill = (modules / "StatusPill.qml").read_text(encoding="utf-8")
mode = (modules / "CortetsuModeSegment.qml").read_text(encoding="utf-8")
workspace = (modules / "CortetsuWorkspaceDots.qml").read_text(encoding="utf-8")
tooltip = (ROOT / "cortetsu/components/CortetsuTooltip.qml").read_text(encoding="utf-8")
interactions = (modules / "drawers/Interactions.qml").read_text(encoding="utf-8")

criteria = {
    "superficie exterior transparente": 'color: "transparent"' in hub,
    "dock continuo": all(
        token in view
        for token in (
            "CortetsuSurface {",
            "id: dockBackdrop",
            "anchors.fill: parent",
            "baseColor: Qt.alpha(CortetsuDesign.colorSumi",
            "outlined: false",
        )
    ),
    "segmentos con CortetsuDesign": all("CortetsuDesign" in text for text in (rail, tray, status, mode)),
    "launcher first-party": "CortetsuModeSegment" in view and "launcherRequested" in view,
    "workspace state": "occupiedWorkspaceIds" in view and "activeWsId" in view,
    "centro adaptativo": "appRailMaxWidth" in view and "maxWidth: root.appRailMaxWidth" in view,
    "centro geometrico": "anchors.horizontalCenter: parent.horizontalCenter" in view,
    "hover con escala contenida": "CortetsuDesign.hoverScale" in rail,
    "animacion corta": "CortetsuDesign.motionFastMs" in rail,
    "tooltip compartido": all(
        "CortetsuTooltip" in text
        for text in (rail, tray, status_pill)
    ),
    "tooltip de aplicaciones": "modelData.title" in rail and "CortetsuTooltip" in rail,
    "tooltip de tray": "modelData.title" in tray and "CortetsuTooltip" in tray,
    "tooltip con superficie": all(
        token in tooltip
        for token in (
            "contentItem: CortetsuText",
            "CortetsuTypography.labelSmallPx",
            "baseColor: CortetsuDesign.colorTetsu",
        )
    ),
    "contador expandido": 'root.notificationCount > 9 ? qsTr("9+")' in status,
    "audio Cortetsu": "volumeIcon" in status and "volumeWheel" in status,
    "volume scroll preference is honored": "if (!CortetsuConfig.bar.scrollActions.volume)" in hub,
    "workspace scope preference is honored": "CortetsuConfig.bar.workspaces.perMonitorWorkspaces" in hub,
    "status cluster is configurable": all(
        token in hub
        for token in (
            "CortetsuConfig.bottomHub.statusCluster.audio",
            "CortetsuConfig.bottomHub.statusCluster.network",
            "CortetsuConfig.bottomHub.statusCluster.bluetooth",
            "CortetsuConfig.bottomHub.statusCluster.battery",
        )
    ),
    "dock segments are configurable": all(
        token in hub
        for token in (
            "CortetsuConfig.bottomHub.segments.mode",
            "CortetsuConfig.bottomHub.segments.apps",
            "CortetsuConfig.bottomHub.segments.tray",
            "CortetsuConfig.bottomHub.segments.status",
        )
    ) and all(
        token in view
        for token in (
            "required property bool modeVisible",
            "required property bool appsVisible",
            "required property bool trayVisible",
            "required property bool statusVisible",
        )
    ),
    "hover de controles del sistema": all(
        f'root.attachedControlEntered("{mode}"' in status
        for mode in ("audio", "network", "bluetooth", "battery")
    ),
    "wifi first-party": 'attachedControlRequested("network"' in status,
    "Bluetooth first-party": 'attachedControlRequested("bluetooth"' in status,
    "bateria first-party": "batteryIcon" in status and "batteryCritical" in status,
    "tray como isla": "CortetsuTraySegment" in view and "CortetsuSurface" in tray,
    "icono SNI conservado": "iconSource" in tray,
    "quick settings first-party": "toggleUtilitiesFor" in hub,
    "notificaciones first-party": "toggleSidebarFor" in hub,
    "anclaje de popups": "attachedControlRequested" in view and "bottomAnchorCenter" in hub,
    "handoff de popup desde BottomHub": "if (!popouts.bottomAttached" in interactions,
    "hitbox de hover estable": "property real visualScale" in (modules / "HubButton.qml").read_text(encoding="utf-8")
        and "scale: 1" in (modules / "HubButton.qml").read_text(encoding="utf-8"),
    "foco bajo demanda": "focusable: true" in hub and "WlrKeyboardFocus.OnDemand" in hub,
    "foco conserva navegacion de workspaces": all(
        token in workspace
        for token in (
            "function focusWorkspace(workspaceId): void",
            "function activateWorkspace(workspaceId): void",
            "restoreFocus.workspaceId = workspaceId",
            "restoreFocus.restart()",
            "onTriggered: root.focusWorkspace(workspaceId)",
        )
    ),
    "foco al presionar": all(
        token in text
        for text, token in (
            (view, "CortetsuAppRail"),
            (rail, "onPressed: appItem.forceActiveFocus()"),
            (tray, "onPressed: trayItem.forceActiveFocus()"),
            (status, "onPressed: parent.forceActiveFocus()"),
            (workspace, "onPressed: workspaceDot.forceActiveFocus()"),
        )
    ),
}

if "toggleOverviewFor" in hub or 'icon: "view_quilt"' in hub:
    raise SystemExit("FAIL: BottomHub conserva el control Overview retirado")
if 'icon: "speaker_group"' in hub:
    raise SystemExit("FAIL: BottomHub conserva el segundo control de audio duplicado")

missing = sorted(name for name, passed in criteria.items() if not passed)
score = (len(criteria) - len(missing)) / len(criteria)
print(f"BottomHub design eval: {len(criteria) - len(missing)}/{len(criteria)} ({score:.0%})")
if missing:
    raise SystemExit("FAIL: " + ", ".join(missing))
