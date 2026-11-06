pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io
import "../modules"

Singleton {
    id: root

    property string city: ""
    property string loc: ""
    property var cc: null
    property list<var> forecast: []
    property list<var> hourlyForecast: []
    property int requestGeneration: 0
    property var cachedCities: ({})

    readonly property string icon: cc ? weatherIcon(cc.weatherCode) : "󰖐"
    readonly property string description: cc?.weatherDesc ?? qsTr("No weather")
    readonly property string temp: formatTemp(cc?.tempC)
    readonly property string feelsLike: formatTemp(cc?.feelsLikeC)
    readonly property int humidity: cc?.humidity ?? 0
    readonly property real windSpeed: cc?.windSpeed ?? 0
    readonly property string sunrise: cc ? Qt.formatDateTime(new Date(cc.sunrise), CortetsuRegional.clockPattern) : "--:--"
    readonly property string sunset: cc ? Qt.formatDateTime(new Date(cc.sunset), CortetsuRegional.clockPattern) : "--:--"

    function formatTemp(value): string { return CortetsuRegional.formatTemperature(value); }
    function weatherIcon(code): string {
        if ([0, 1].includes(Number(code))) return "󰖙";
        if ([2, 3].includes(Number(code))) return "󰖐";
        if ([45, 48].includes(Number(code))) return "󰖑";
        if ([51, 53, 55, 56, 57].includes(Number(code))) return "󰖗";
        if ([61, 63, 65, 66, 67, 80, 81, 82].includes(Number(code))) return "󰖖";
        if ([71, 73, 75, 77, 85, 86].includes(Number(code))) return "󰖘";
        if ([95, 96, 99].includes(Number(code))) return "󰖓";
        return "󰖐";
    }

    function reload(): void {
        const generation = ++requestGeneration;
        const parsed = CortetsuRegional.parseLocationQuery(CortetsuRegional.weatherLocation);
        if (!parsed) {
            Requests.get(CortetsuRegional.buildIpLookupUrl(), text => {
                if (generation !== requestGeneration || CortetsuRegional.weatherLocation) return;
                const located = CortetsuRegional.parseIpLookupResponse(JSON.parse(text));
                if (located) { city = located.city; updateLocation(`${located.lat},${located.lon}`, generation); }
            }, () => {});
        } else if (parsed.type === "coords") {
            updateLocation(parsed.value, generation);
            fetchCity(parsed.value, generation);
        } else {
            Requests.get(CortetsuRegional.buildGeocodeUrl(parsed.value, "en"), text => {
                if (generation !== requestGeneration) return;
                const result = CortetsuRegional.parseGeocodeResponse(JSON.parse(text));
                if (result) { city = result.name; updateLocation(`${result.lat},${result.lon}`, generation); }
            }, () => {});
        }
    }

    function updateLocation(coords, generation): void {
        if (generation !== requestGeneration) return;
        if (loc === coords) fetchForecast();
        else loc = coords;
    }

    function fetchCity(coords, generation): void {
        if (cachedCities[coords]) { city = cachedCities[coords]; return; }
        const [lat, lon] = coords.split(",").map(value => value.trim());
        Requests.get(CortetsuRegional.buildReverseGeocodeUrl(lat, lon, "en"), text => {
            if (generation !== requestGeneration) return;
            const name = CortetsuRegional.parseReverseGeocodeResponse(JSON.parse(text));
            if (name) { city = name; cachedCities = Object.assign({}, cachedCities, { [coords]: name }); cache.setText(JSON.stringify(cachedCities)); }
        }, () => {});
    }

    function fetchForecast(): void {
        if (!loc || loc.indexOf(",") < 0) return;
        const generation = requestGeneration;
        const [lat, lon] = loc.split(",").map(value => value.trim());
        Requests.get(CortetsuRegional.buildForecastUrl(lat, lon), text => {
            if (generation !== requestGeneration) return;
            const parsed = CortetsuRegional.parseForecastResponse(JSON.parse(text));
            if (!parsed) return;
            cc = parsed.current;
            forecast = parsed.forecast.map(day => Object.assign({}, day, { icon: weatherIcon(day.weatherCode) }));
            hourlyForecast = parsed.hourlyForecast.map(hour => Object.assign({}, hour, { icon: weatherIcon(hour.weatherCode) }));
        }, () => {});
    }

    onLocChanged: fetchForecast()
    Connections { target: CortetsuRegional; function onWeatherLocationChanged(): void { root.reload(); } }
    Timer { interval: 3600000; running: true; repeat: true; onTriggered: root.reload() }
    FileView {
        id: cache
        path: `${Quickshell.env("XDG_CACHE_HOME") || `${Quickshell.env("HOME")}/.cache`}/cortetsu/cities.json`
        printErrors: false
        onLoaded: { try { root.cachedCities = JSON.parse(text()); } catch (_) { root.cachedCities = {}; } root.reload(); }
        onLoadFailed: root.reload()
    }
}
