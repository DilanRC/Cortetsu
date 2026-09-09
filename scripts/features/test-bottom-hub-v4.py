#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULES = ROOT / "cortetsu/modules"
HUB = (MODULES / "BottomHub.qml").read_text()
VIEW = (MODULES / "CortetsuBottomHubView.qml").read_text()
TRAY = (MODULES / "CortetsuTraySegment.qml").read_text()
MIGRATOR = (ROOT / "cortetsu/bin/migrate-bottom-hub-from-main.py").read_text()
CHECKER = (ROOT / "cortetsu/bin/check-bottom-hub-target.py").read_text()
HYPR = (ROOT / "config/hypr-user.lua").read_text()
MANIFEST = (ROOT / "cortetsu/contracts/patch-debt.tsv").read_text()
SHORTCUTS = (MODULES / "Shortcuts.qml").read_text()
PANELS = (MODULES / "drawers/Panels.qml").read_text()
POPOUT = (MODULES / "bar/popouts/ClipWrapper.qml").read_text()
WINDOW_CARD = (MODULES / "overview/WindowCard.qml").read_text()
BAR = (MODULES / "bar/BarWrapper.qml").read_text()


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"FAIL: falta {label}: {needle}")


def forbid(text: str, needle: str, label: str) -> None:
    if needle in text:
        raise SystemExit(f"FAIL: queda {label}: {needle}")


def main() -> None:
    require(HUB, "CortetsuBottomHubView {", "frontera first-party")
    require(VIEW, "id: appSegment", "isla central")
    require(VIEW, "id: traySegment", "isla tray")
    require(VIEW, "id: statusSegment", "isla sistema")
    if not (VIEW.index("id: appSegment") < VIEW.index("id: traySegment") < VIEW.index("id: statusSegment")):
        raise SystemExit("FAIL: orden visual esperado center -> tray -> system")
    require(VIEW, "anchors.right: statusSegment.left", "tray separado de sistema")
    require(HUB, "const sourceIndex = SystemTray.items.values.indexOf(item);", "indice SNI estable")
    require(HUB, "item.icon || Icons.getTrayIcon(item.id, item.icon)", "icono SNI prioritario")
    require(HUB, "toggleUtilitiesFor", "control legacy de sidebar/utilities")
    forbid(TRAY, "SystemTray", "backend SNI dentro de la vista")
    forbid(HUB, "`traymenu${trayItem.index}`", "índice filtrado incorrecto")

    require(MIGRATOR, "def qml_block(", "migración QML por bloque")
    require(MIGRATOR, 'qml_block(after, "Launcher.Wrapper", "launcher")', "launcher localizado por id")
    forbid(MIGRATOR, '"anchors.horizontalCenter: parent.horizontalCenter\\n        anchors.bottom: parent.bottom\\n",', "reemplazo global ambiguo")
    require(CHECKER, 'qml_block(text, "Launcher.Wrapper", "launcher")', "validación scoped del launcher")
    require(BAR, "readonly property bool disabled: true", "retiro de barra nativa")
    require(BAR, "implicitWidth: 0", "ancho de barra retirada")

    # First-party entry points are no longer aliases for the legacy Utilities panel.
    require(HYPR, '"SUPER + I",\n    hl.dsp.global("cortetsu:settings")', "SUPER+I a Settings")
    require(HYPR, '"SUPER + Slash",\n    hl.dsp.global("cortetsu:qsd")', "SUPER+/ a Quick Settings")
    forbid(HYPR, '"SUPER + I",\n    hl.dsp.global("cortetsu:utilities")', "SUPER+I legacy Utilities")
    require(HYPR, '"SUPER + H",\n    hl.dsp.global("cortetsu:hardware")', "SUPER+H a Hardware Center")

    require(HUB, "hubRoot.toggleLauncherFor(state.modelData);", "SUPER alterna el launcher")
    require(SHORTCUTS, 'name: "sidebar"', "atajo del centro lateral")
    require(SHORTCUTS, "OverlayPolicy.closeAll(state);", "exclusividad de superficies")
    require(SHORTCUTS, "const open = !(state.sidebar || state.utilities);", "sidebar abre su par de utilidades")
    require(SHORTCUTS, 'Quickshell.env("XDG_CONFIG_HOME") ||', "ruta XDG del launcher")
    forbid(SHORTCUTS, "/quickshell/caelestia/current", "ruta legacy del launcher")
    require(PANELS, "anchors.right: root.screenState.utilities ? utilities.left : parent.right", "centros adyacentes")
    require(POPOUT, "content.bottomAnchorCenter - content.nonAnimWidth / 2", "popup centrado en su icono")
    require(POPOUT, "ClipWrapper owns the screen-space placement", "una sola autoridad de geometría")
    require(POPOUT, "width: implicitWidth", "bounds visibles del popup")
    require(POPOUT, "height: implicitHeight", "bounds interactivos del popup")
    require(POPOUT, "        x: 0\n        transformOrigin: Item.Bottom", "contenido local al ancla")
    require(WINDOW_CARD, "import qs.utils", "Overview resuelve Icons sin ReferenceError")
    forbid(POPOUT, "caelestia", "dependencia Caelestia en el wrapper de popup")

    print("BottomHub v4 architecture tests: OK")


if __name__ == "__main__":
    main()
