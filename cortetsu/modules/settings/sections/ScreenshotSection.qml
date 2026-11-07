pragma ComponentBehavior: Bound

import QtQuick.Layouts
import "../.."
import "../controls"

SettingsGroup {
    id: root

    property string pathError: ""

    title: qsTr("Capturas de pantalla")
    detail: qsTr("La carpeta se usa al guardar una captura de área")

    SettingTextRow {
        objectName: "screenSnipSavePath"
        title: qsTr("Carpeta de destino")
        detail: qsTr("Vacío guarda en Imágenes/Capturas; admite rutas absolutas o ~/…")
        value: CortetsuConfig.screenSnipSavePath
        placeholderText: qsTr("~/Imágenes/Capturas")
        status: root.pathError ? "error" : ""
        statusText: root.pathError
        onCommitted: value => {
            const path = value.trim();
            if (path && !path.startsWith("/") && !/^~(\/|$)/.test(path)) {
                root.pathError = qsTr("Usa una ruta absoluta o empieza con ~/");
                return;
            }
            root.pathError = "";
            CortetsuConfig.screenSnipSavePath = path;
        }
    }
}
