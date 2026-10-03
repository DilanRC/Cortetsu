pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../../services"
import "../../CortetsuDesign.js" as CortetsuDesign

ColumnLayout {
    id: root

    required property var page

    spacing: CortetsuDesign.spacingStandard

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Comportamiento de entrada")
        detail: qsTr("Preferencias de interacción del teclado")
    }

    DomainHero {
        icon: "keyboard"
        title: qsTr("Entrada configurada")
        detail: qsTr("Preferencias de teclado y avisos del shell")
        value: CortetsuConfig.vimKeybinds ? qsTr("Vim activo") : qsTr("Vim desactivado")
        meta: Hypr.keyboardKnown
            ? qsTr("Distribución %1").arg(Hypr.kbLayoutFull || Hypr.kbLayout)
            : qsTr("Distribución no disponible")
        warningState: !Hypr.keyboardKnown
    }

    PreferenceToggle {
        title: qsTr("Navegación estilo Vim")
        detail: qsTr("Permitir navegación estilo Vim donde sea compatible")
        icon: "keyboard"
        checked: CortetsuConfig.vimKeybinds
        onChanged: checked => {
            CortetsuConfig.vimKeybinds = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Aviso de Bloq Mayús")
        detail: qsTr("Mostrar un aviso al cambiar Bloq Mayús")
        icon: "keyboard_capslock"
        checked: CortetsuConfig.toastCapsLockChanged
        onChanged: checked => {
            CortetsuConfig.toastCapsLockChanged = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Aviso de Bloq Num")
        detail: qsTr("Mostrar un aviso al cambiar Bloq Num")
        icon: "dialpad"
        checked: CortetsuConfig.toastNumLockChanged
        onChanged: checked => {
            CortetsuConfig.toastNumLockChanged = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Aviso de distribución del teclado")
        detail: qsTr("Mostrar un aviso al cambiar el idioma del teclado")
        icon: "language"
        checked: CortetsuConfig.toastKbLayoutChanged
        onChanged: checked => {
            CortetsuConfig.toastKbLayoutChanged = checked;
            root.page.savePreference();
        }
    }
}
