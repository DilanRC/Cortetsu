pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."
import "../controls"

SettingsGroup {
    id: root
    property string locationError: ""
    title: qsTr("Clima")
    detail: qsTr("Ubicación utilizada para solicitar el pronóstico")
    SettingTextRow {
        objectName: "weatherLocation"
        title: qsTr("Ciudad o coordenadas")
        detail: qsTr("Vacío para detectar la ubicación por IP")
        status: root.locationError ? "error" : ""
        statusText: root.locationError
        value: CortetsuConfig.weatherLocation
        placeholderText: qsTr("San José o 9.93,-84.08")
        onCommitted: next => {
            const value = next.trim();
            const parsed = CortetsuRegional.parseLocationQuery(value);
            if (parsed?.type === "coords") {
                const parts = value.split(",").map(part => Number(part.trim()));
                if (value.split(",").some(part => !part.trim()) || parts.length !== 2 || !parts.every(Number.isFinite) || Math.abs(parts[0]) > 90 || Math.abs(parts[1]) > 180) {
                    root.locationError = qsTr("Latitud entre −90 y 90; longitud entre −180 y 180");
                    return;
                }
            }
            root.locationError = "";
            CortetsuConfig.weatherLocation = value;
            CortetsuConfig.save();
        }
    }

    SettingsGroup {
        title: qsTr("Actualización del pronóstico")
        detail: qsTr("Frecuencia de consulta del servicio meteorológico")
        SettingSliderRow {
            objectName: "weatherRefreshInterval"
            title: qsTr("Actualizar cada")
            from: 5
            to: 240
            step: 5
            value: CortetsuConfig.weatherRefreshInterval / 60000
            valueText: value >= 60
                ? qsTr("%1 h %2 min").arg(Math.floor(value / 60)).arg(value % 60)
                : qsTr("%1 min").arg(value)
            onMoved: next => {
                CortetsuConfig.weatherRefreshInterval = Math.round(next * 60000);
                CortetsuConfig.save();
            }
        }
    }
}
