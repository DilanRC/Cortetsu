import QtQuick
import Quickshell
import "services"
import "modules"

ShellRoot {
    id: root

    readonly property string firstLocation: "12.5,-70.25"
    readonly property string secondLocation: "12.6,-70.3"
    property real deadline: Date.now() + 10000

    function response(tempC): string {
        return JSON.stringify({
            current: {
                weather_code: 0,
                temperature_2m: tempC,
                apparent_temperature: tempC,
                relative_humidity_2m: 50,
                is_day: 1,
                wind_speed_10m: 3
            },
            daily: {
                time: ["2026-11-05"],
                temperature_2m_max: [tempC + 1],
                temperature_2m_min: [tempC - 1],
                weather_code: [0],
                sunrise: ["2026-11-05T06:00"],
                sunset: ["2026-11-05T18:00"]
            }
        });
    }

    function fail(reason: string): void {
        timer.stop();
        console.error("WEATHER_REFRESH_FAIL " + reason);
    }

    Timer {
        id: timer
        interval: 20
        repeat: true
        running: true

        onTriggered: {
            if (!CortetsuConfig.loaded || Weather.loc !== root.firstLocation) {
                if (Date.now() >= root.deadline)
                    root.fail(`setup timed out: loaded=${CortetsuConfig.loaded} loc=${Weather.loc}`);
                return;
            }

            Requests.clear();
            Weather.reload();
            const afterFirstUpdate = Requests.forecastRequests.length;
            Weather.reload();
            const forecasts = Requests.forecastRequests;
            if (afterFirstUpdate !== 1 || forecasts.length !== 2) {
                root.fail(`same-location updates expected counts 1 then 2; got ${afterFirstUpdate} then ${forecasts.length}`);
                return;
            }

            forecasts[1].onSuccess(root.response(20), {});
            forecasts[0].onSuccess(root.response(10), {});
            if (Weather.cc?.tempC !== 20) {
                root.fail(`stale response replaced latest forecast: ${Weather.cc?.tempC}`);
                return;
            }

            CortetsuConfig.weatherLocation = root.secondLocation;
            if (Weather.loc !== root.secondLocation || Requests.forecastRequests.length !== 3) {
                root.fail(`location change should make one forecast request; loc=${Weather.loc}, count=${Requests.forecastRequests.length}`);
                return;
            }

            Requests.forecastRequests[2].onError("offline", {});
            Weather.reload();
            if (Requests.forecastRequests.length !== 4) {
                root.fail(`reload after request error should make one forecast request; count=${Requests.forecastRequests.length}`);
                return;
            }

            CortetsuConfig.weatherLocation = "Next City";
            let geocoders = Requests.requests.filter(request => request.url.startsWith("https://geocoding-api.open-meteo.com/v1/search?"));
            if (geocoders.length !== 1) {
                root.fail(`city lookup should make one geocoding request; count=${geocoders.length}`);
                return;
            }
            geocoders[0].onSuccess(JSON.stringify({ results: [{ latitude: 12.6, longitude: -70.3, name: "Next City" }] }), {});
            if (Requests.forecastRequests.length !== 5) {
                root.fail(`geocoding the current location should refresh once; count=${Requests.forecastRequests.length}`);
                return;
            }

            Weather.reload();
            geocoders = Requests.requests.filter(request => request.url.startsWith("https://geocoding-api.open-meteo.com/v1/search?"));
            const staleGeocode = geocoders[1];
            CortetsuConfig.weatherLocation = root.secondLocation;
            staleGeocode.onSuccess(JSON.stringify({ results: [{ latitude: 12.7, longitude: -70.4, name: "Stale City" }] }), {});
            if (Weather.loc !== root.secondLocation || Requests.forecastRequests.length !== 6) {
                root.fail(`stale geocoding response changed the current location or duplicated a request; loc=${Weather.loc}, count=${Requests.forecastRequests.length}`);
                return;
            }

            CortetsuConfig.weatherLocation = "";
            let ipLookups = Requests.requests.filter(request => request.url.startsWith("http://ip-api.com/json?"));
            const staleIpLookup = ipLookups[ipLookups.length - 1];
            CortetsuConfig.weatherLocation = root.secondLocation;
            staleIpLookup.onSuccess(JSON.stringify({ status: "success", city: "Stale IP City", lat: 12.7, lon: -70.4 }), {});
            if (Weather.loc !== root.secondLocation || Requests.forecastRequests.length !== 7) {
                root.fail(`stale IP lookup changed the current location or duplicated a request; loc=${Weather.loc}, count=${Requests.forecastRequests.length}`);
                return;
            }

            CortetsuConfig.weatherLocation = "";
            ipLookups = Requests.requests.filter(request => request.url.startsWith("http://ip-api.com/json?"));
            ipLookups[ipLookups.length - 1].onSuccess(JSON.stringify({ status: "success", city: "Next City", lat: 12.6, lon: -70.3 }), {});
            if (Requests.forecastRequests.length !== 8) {
                root.fail(`IP lookup resolving the current location should refresh once; count=${Requests.forecastRequests.length}`);
                return;
            }

            timer.stop();
            console.log("WEATHER_REFRESH_PASS same-location=2 geocode=1 ip-lookup=1 location-change=1 after-error=1 stale-responses=ignored");
            Qt.quit();
        }
    }
}
