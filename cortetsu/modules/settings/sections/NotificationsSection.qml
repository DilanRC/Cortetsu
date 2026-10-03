pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

ColumnLayout {
    id: root

    required property var page

    spacing: CortetsuDesign.spacingStandard

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Comportamiento de notificaciones")
        detail: qsTr("Estado de No molestar y preferencias de presentación")
    }

    DomainHero {
        icon: CortetsuNotifications.dnd ? "notifications_off" : "notifications_active"
        title: CortetsuNotifications.dnd ? qsTr("No molestar activo") : qsTr("Notificaciones permitidas")
        detail: qsTr("Avisos en vivo e historial de la sesión")
        value: qsTr("%1 guardadas").arg(CortetsuNotifications.count)
        meta: CortetsuConfig.suppressNotificationsInFullscreen
            ? qsTr("Silenciadas en pantalla completa")
            : qsTr("Interrupciones disponibles")
        warningState: CortetsuNotifications.dnd
    }

    PreferenceToggle {
        title: qsTr("No molestar")
        detail: CortetsuNotifications.dnd ? qsTr("Las interrupciones están silenciadas") : qsTr("Las notificaciones pueden interrumpir")
        icon: CortetsuNotifications.dnd ? "notifications_off" : "notifications_active"
        checked: CortetsuNotifications.dnd
        onChanged: checked => CortetsuNotifications.dnd = checked
    }

    PreferenceToggle {
        title: qsTr("Abrir expandido")
        detail: qsTr("Expandir los grupos al abrir el centro")
        icon: "unfold_more"
        checked: CortetsuConfig.notificationOpenExpanded
        onChanged: checked => {
            CortetsuConfig.notificationOpenExpanded = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Ocultar en pantalla completa")
        detail: qsTr("Ocultar las notificaciones durante el trabajo a pantalla completa")
        icon: "fullscreen"
        checked: CortetsuConfig.suppressNotificationsInFullscreen
        onChanged: checked => {
            CortetsuConfig.suppressNotificationsInFullscreen = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Avisar al cambiar el estado de No molestar")
        detail: qsTr("Mostrar un aviso cuando DND se active o desactive")
        icon: "notifications_active"
        checked: CortetsuConfig.toastDndChanged
        onChanged: checked => {
            CortetsuConfig.toastDndChanged = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Avisar al cambiar el modo de juego")
        detail: qsTr("Mostrar un aviso al entrar o salir del modo de juego")
        icon: "sports_esports"
        checked: CortetsuConfig.toastGameModeChanged
        onChanged: checked => {
            CortetsuConfig.toastGameModeChanged = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Avisar sobre reproducción multimedia")
        detail: qsTr("Mostrar avisos cuando cambie la pista o el reproductor")
        icon: "music_note"
        checked: CortetsuConfig.toastNowPlaying
        onChanged: checked => {
            CortetsuConfig.toastNowPlaying = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Caducidad automática")
        detail: qsTr("Retirar las notificaciones después del tiempo configurado")
        icon: "timer"
        checked: CortetsuConfig.notificationExpire
        onChanged: checked => {
            CortetsuConfig.notificationExpire = checked;
            root.page.savePreference();
        }
    }

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Presentación y duración")
        detail: qsTr("Ajustar el ritmo sin perder el control del historial")
    }

    CortetsuSurface {
        Layout.fillWidth: true
        implicitHeight: 94
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlined: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingCompact

            RowLayout {
                Layout.fillWidth: true
                CortetsuText { Layout.fillWidth: true; text: qsTr("Duración normal"); textSize: CortetsuTypography.bodyPx; font.weight: Font.DemiBold }
                CortetsuText { text: qsTr("%1 s").arg(Math.round(CortetsuConfig.notificationDefaultExpireTimeout / 1000)); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
            }
            CortetsuSlider {
                Layout.fillWidth: true
                from: 2
                to: 15
                step: 1
                value: CortetsuConfig.notificationDefaultExpireTimeout / 1000
                disabled: !CortetsuConfig.notificationExpire
                onMoved: nextValue => { CortetsuConfig.notificationDefaultExpireTimeout = Math.round(nextValue) * 1000; root.page.savePreference(); }
            }
        }
    }

    CortetsuSurface {
        Layout.fillWidth: true
        implicitHeight: 94
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlined: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingCompact

            RowLayout {
                Layout.fillWidth: true
                CortetsuText { Layout.fillWidth: true; text: qsTr("Previsualización de grupos"); textSize: CortetsuTypography.bodyPx; font.weight: Font.DemiBold }
                CortetsuText { text: qsTr("%1 avisos").arg(CortetsuConfig.notificationGroupPreviewNum); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
            }
            CortetsuSlider {
                Layout.fillWidth: true
                from: 1
                to: 6
                step: 1
                value: CortetsuConfig.notificationGroupPreviewNum
                onMoved: nextValue => { CortetsuConfig.notificationGroupPreviewNum = Math.round(nextValue); root.page.savePreference(); }
            }
        }
    }

    ActionCard {
        title: qsTr("Limpiar historial")
        detail: qsTr("Eliminar las notificaciones guardadas, sin cambiar No molestar")
        icon: "delete_sweep"
        onActivated: CortetsuNotifications.clear()
    }
}
