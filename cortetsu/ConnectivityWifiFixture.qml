import QtQuick
import Quickshell
import "services"
import "services/ConnectivityPolicy.js" as Policy

// observe() reassigns `operation`, a dependency of operationConnected. Run
// inside that property's change handler it re-entered the binding, and Qt
// logged a binding loop. operationConnected flips here through the network
// reference itself, so only its change handler sees the change. The connect
// fails as "ap-unavailable" before any NetworkManager mutation.
ShellRoot {
    readonly property var wifi: ConnectivityWifi
    QtObject {
        id: before
        property bool connected: false
        property int state: 0
        property var device: null
        signal connectionFailed(int reason)
    }
    QtObject {
        id: after
        property bool connected: true
        property int state: 0
        property var device: null
        signal connectionFailed(int reason)
    }
    Timer {
        interval: 300; running: true
        onTriggered: {
            wifi.operationNetwork = before;
            wifi.operation = Policy.operation(1, "connect", {}, "connecting", Date.now());
            wifi.operationNetwork = after;
            Qt.callLater(() => {
                if (wifi.operation.state === "failed" && wifi.operation.lastErrorCode === "ap-unavailable")
                    console.log("WIFI_OBSERVED_PASS");
                else
                    console.error("WIFI_OBSERVED_FAIL " + JSON.stringify(wifi.operation));
                Qt.quit();
            });
        }
    }
}
