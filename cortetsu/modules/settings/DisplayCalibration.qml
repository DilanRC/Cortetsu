import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../components"
import ".."
import "../../services"
import "../CortetsuDesign.js" as CortetsuDesign

ColumnLayout {
    id: root

    spacing: CortetsuDesign.spacingStandard
    property string error: ""
    property bool requestedEnabled: false
    readonly property bool busy: service.running || temperatureProcess.running || gammaProcess.running

    Component.onCompleted: {
        if (CortetsuConfig.loaded && CortetsuConfig.colorCalibrationEnabled)
            root.apply();
    }

    Connections {
        target: CortetsuConfig
        function onLoadedChanged(): void {
            if (CortetsuConfig.loaded && CortetsuConfig.colorCalibrationEnabled)
                root.apply();
        }
    }

    function apply(): void {
        if (busy) {
            retry.restart();
            return;
        }
        error = "";
        requestedEnabled = CortetsuConfig.colorCalibrationEnabled;
        service.command = ["systemctl", "--user", requestedEnabled ? "start" : "stop", "hyprsunset.service"];
        service.running = true;
        CortetsuConfig.save();
    }

    Process {
        id: service
        command: []
        stderr: StdioCollector { id: serviceError }
        onExited: code => {
            if (code !== 0) {
                root.error = serviceError.text.trim() || qsTr("No se pudo cambiar el filtro de color");
                CortetsuConfig.colorCalibrationEnabled = !root.requestedEnabled;
                CortetsuConfig.save();
                return;
            }
            if (CortetsuConfig.colorCalibrationEnabled)
                temperatureProcess.running = true;
        }
    }
    Process {
        id: temperatureProcess
        command: ["hyprctl", "hyprsunset", "temperature", String(CortetsuConfig.colorTemperature)]
        stderr: StdioCollector { id: temperatureError }
        onExited: code => {
            if (code !== 0) {
                root.error = temperatureError.text.trim() || qsTr("No se pudo aplicar la temperatura");
                return;
            }
            gammaProcess.running = true;
        }
    }
    Process {
        id: gammaProcess
        command: ["hyprctl", "hyprsunset", "gamma", String(CortetsuConfig.colorGamma)]
        stderr: StdioCollector { id: gammaError }
        onExited: code => {
            if (code !== 0)
                root.error = gammaError.text.trim() || qsTr("No se pudo aplicar la gamma");
        }
    }
    Timer { id: retry; interval: 180; onTriggered: root.apply() }

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Color y calibración")
        detail: qsTr("Temperatura, gamma y saturación aplicadas por Hyprland y NVIDIA")
    }

    CortetsuSurface {
        Layout.fillWidth: true
        implicitHeight: 68
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlined: true
        RowLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            CortetsuIcon { text: "nightlight"; color: CortetsuDesign.colorPrimary }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                CortetsuText { text: qsTr("Filtro de color"); font.weight: Font.DemiBold }
                CortetsuText { text: CortetsuConfig.colorCalibrationEnabled ? qsTr("hyprsunset activo") : qsTr("Colores nativos"); color: CortetsuDesign.colorOnSurfaceVariant }
            }
            CortetsuToggle {
                checked: CortetsuConfig.colorCalibrationEnabled
                disabled: root.busy
                onToggled: enabled => { CortetsuConfig.colorCalibrationEnabled = enabled; root.apply(); }
            }
        }
    }

    CortetsuSurface {
        Layout.fillWidth: true
        implicitHeight: 154
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlined: true
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingStandard
            RowLayout {
                Layout.fillWidth: true
                CortetsuIcon { text: "thermostat"; color: CortetsuDesign.colorPrimary }
                CortetsuText { Layout.fillWidth: true; text: qsTr("Temperatura de color"); font.weight: Font.DemiBold }
                CortetsuText { text: qsTr("%1 K").arg(CortetsuConfig.colorTemperature); color: CortetsuDesign.colorOnSurfaceVariant }
            }
            CortetsuSlider {
                Layout.fillWidth: true
                from: 2500; to: 6500; step: 100
                value: CortetsuConfig.colorTemperature
                disabled: !CortetsuConfig.colorCalibrationEnabled || root.busy
                onMoved: value => { CortetsuConfig.colorTemperature = Math.round(value / 100) * 100; root.apply(); }
            }
            RowLayout {
                Layout.fillWidth: true
                CortetsuText { text: qsTr("Cálido"); color: CortetsuDesign.colorOnSurfaceVariant }
                CortetsuText { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: qsTr("Neutro"); color: CortetsuDesign.colorOnSurfaceVariant }
            }
        }
    }

    CortetsuSurface {
        Layout.fillWidth: true
        implicitHeight: 112
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlined: true
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingCompact
            RowLayout {
                Layout.fillWidth: true
                CortetsuIcon { text: "contrast"; color: CortetsuDesign.colorPrimary }
                CortetsuText { Layout.fillWidth: true; text: qsTr("Gamma"); font.weight: Font.DemiBold }
                CortetsuText { text: qsTr("%1%").arg(CortetsuConfig.colorGamma); color: CortetsuDesign.colorOnSurfaceVariant }
            }
            CortetsuSlider {
                Layout.fillWidth: true
                from: 50; to: 150; step: 1
                value: CortetsuConfig.colorGamma
                disabled: !CortetsuConfig.colorCalibrationEnabled || root.busy
                onMoved: value => { CortetsuConfig.colorGamma = Math.round(value); root.apply(); }
            }
        }
    }

    CortetsuSurface {
        Layout.fillWidth: true
        visible: Nvibrant.available || Nvibrant.error.length > 0
        implicitHeight: visible ? 112 : 0
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlined: true
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingCompact
            RowLayout {
                Layout.fillWidth: true
                CortetsuIcon { text: "palette"; color: CortetsuDesign.colorPrimary }
                CortetsuText { Layout.fillWidth: true; text: qsTr("Vibrance NVIDIA"); font.weight: Font.DemiBold }
                CortetsuText { text: Nvibrant.error.length > 0 ? qsTr("No disponible") : qsTr("%1 / 1024").arg(Nvibrant.value); color: Nvibrant.error.length > 0 ? CortetsuDesign.colorWarning : CortetsuDesign.colorOnSurfaceVariant }
            }
            CortetsuSlider { Layout.fillWidth: true; value: Nvibrant.value / 1024; disabled: !Nvibrant.available || Nvibrant.busy; onMoved: value => Nvibrant.setValue(value * 1024) }
        }
    }

    CortetsuStateMessage {
        Layout.fillWidth: true
        visible: root.error.length > 0
        kind: "error"
        title: qsTr("No se pudo aplicar la calibración")
        detail: root.error
    }
}
