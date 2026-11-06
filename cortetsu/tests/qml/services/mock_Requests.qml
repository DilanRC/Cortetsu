pragma Singleton

import QtQml

QtObject {
    id: root

    property var requests: []
    readonly property var forecastRequests: requests.filter(request => request.url.startsWith("https://api.open-meteo.com/v1/forecast?"))

    function get(url, onSuccess, onError, headers = {}): void {
        requests = requests.concat([{ url, onSuccess, onError, headers }]);
    }

    function clear(): void {
        requests = [];
    }
}
