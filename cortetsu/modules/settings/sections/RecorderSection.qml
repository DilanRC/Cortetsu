pragma ComponentBehavior: Bound

import QtQuick.Layouts
import "../.."
import "../controls"

SettingsGroup {
    id: root

    property string pathError: ""

    title: qsTr("Grabador de pantalla")
    detail: qsTr("La carpeta se usa al terminar una grabación")

    SettingTextRow {
        objectName: "screenRecordSavePath"
        title: qsTr("Carpeta de destino")
        detail: qsTr("Vacío guarda en Vídeos/Recordings; admite rutas absolutas o ~/…")
        value: CortetsuConfig.screenRecordSavePath
        placeholderText: qsTr("~/Vídeos/Grabaciones")
        status: root.pathError ? "error" : ""
        statusText: root.pathError
        onCommitted: value => {
            const path = value.trim();
            if (path && !path.startsWith("/") && !/^~(\/|$)/.test(path)) {
                root.pathError = qsTr("Usa una ruta absoluta o empieza con ~/");
                return;
            }
            root.pathError = "";
            CortetsuConfig.screenRecordSavePath = path;
        }
    }
}
