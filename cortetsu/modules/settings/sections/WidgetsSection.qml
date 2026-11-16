pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../services"
import "../../../theme"
import "../.."
import ".."
import "../controls"
import "../../CortetsuOverlayPolicy.js" as OverlayPolicy

// Ajustes → Personalización → Widgets. The editor on the desktop is where
// widgets are placed; this page says what each monitor has, opens the
// editor on a widget, removes one with a confirmation, and lists every
// widget type with the reason when this machine cannot feed it.
ColumnLayout {
    id: root

    required property var context

    readonly property var sizeNames: ({ s: qsTr("pequeño"), m: qsTr("mediano"), l: qsTr("grande") })

    // The editor opens on the monitor the widget lives on (or on this one
    // for a new session), so the keys move it where it is.
    function edit(id: string): void {
        DesktopWidgets.selected = id;
        const item = DesktopWidgets.entry(id);
        const screen = item ? Quickshell.screens.find(s => s.name === DesktopWidgets.ownerScreen(item)) : null;
        if (!screen) {
            root.context.openSurface("desktopWidgets");
            return;
        }
        root.context.screenState.settings = false;
        Qt.callLater(() => OverlayPolicy.open(CortetsuShellState.allStates(), CortetsuShellState.forScreen(screen), "desktopWidgets"));
    }

    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Escritorio")
        icon: "widgets"
        detail: qsTr("Los widgets viven sobre el fondo, detrás de las ventanas, y solo leen datos mientras el escritorio está a la vista")

        SettingActionRow {
            objectName: "openDesktopEditor"
            title: qsTr("Editar el escritorio")
            detail: qsTr("Añadir, mover con el ratón o las flechas, cambiar el tamaño y escribir notas")
            actionLabel: qsTr("Editar")
            actionIcon: "edit"
            onActivated: root.edit("")
        }
    }

    // One group per connected monitor, with what it shows.
    Repeater {
        model: Quickshell.screens

        delegate: SettingsGroup {
            id: monitor
            required property ShellScreen modelData
            readonly property var ids: DesktopWidgets.idsFor(modelData.name)

            title: qsTr("Monitor %1").arg(modelData.name)
            icon: "monitor"
            detail: ids.length === 0 ? qsTr("Sin widgets")
                : ids.length === 1 ? qsTr("1 widget") : qsTr("%1 widgets").arg(ids.length)
            collapsible: ids.length > 4

            Repeater {
                model: monitor.ids

                delegate: SettingActionRow {
                    required property string modelData
                    readonly property var item: DesktopWidgets.entry(modelData)
                    readonly property var kind: DesktopWidgets.info(item?.type ?? "")
                    leadingIcon: kind?.icon ?? "widgets"
                    title: kind?.title ?? ""
                    detail: {
                        const parts = [root.sizeNames[item?.size] ?? ""];
                        if (item?.type === "note")
                            parts.push(item.text ? item.text.split("\n")[0].slice(0, 48) : qsTr("vacía"));
                        if (item?.screen && item.screen !== monitor.modelData.name)
                            parts.push(qsTr("de %1, desconectado").arg(item.screen));
                        return parts.filter(Boolean).join(" · ");
                    }
                    actionLabel: qsTr("Quitar")
                    actionIcon: "delete"
                    danger: true
                    confirm: true
                    onActivated: DesktopWidgets.remove(modelData)
                    interactive: true
                    onClicked: root.edit(modelData)
                }
            }

            SettingValueRow {
                visible: monitor.ids.length === 0
                title: qsTr("Nada sobre el fondo")
                detail: qsTr("Abre el editor y elige un widget de la lista")
                value: ""
            }
        }
    }

    // The gallery: every type, available or not, and why not.
    SettingsGroup {
        title: qsTr("Tipos de widget")
        icon: "dashboard_customize"
        detail: qsTr("Cada uno lee un servicio real del shell; sin datos, lo dice en vez de mostrar ceros")
        collapsible: true

        Repeater {
            model: DesktopWidgets.catalogue

            delegate: SettingActionRow {
                required property var modelData
                leadingIcon: modelData.icon
                title: modelData.title
                detail: modelData.available ? modelData.detail
                    : modelData.type === "battery" ? qsTr("Este equipo no informa de una batería")
                    : qsTr("No disponible en este equipo")
                actionLabel: qsTr("Añadir")
                actionIcon: "add"
                actionDisabled: !modelData.available || DesktopWidgets.full
                onActivated: {
                    const screenName = root.context.screen?.name ?? Quickshell.screens[0]?.name ?? "";
                    const id = DesktopWidgets.add(modelData.type, screenName);
                    if (id)
                        root.edit(id);
                }
            }
        }
    }
}
