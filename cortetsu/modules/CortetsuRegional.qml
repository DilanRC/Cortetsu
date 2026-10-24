pragma Singleton

import QtQml
import "CortetsuRegional.js" as RegionalLogic

// First-party regional/weather preferences and formatting surface.
// First-party replacement for the legacy shared-config lookup used for
// the 12h/24h clock, F/C unit and weather location prefs. Preferences are
// NOT duplicated here --
// CortetsuConfig (~/.config/cortetsu/preferences.json) stays the single
// source of truth; this singleton only re-exposes them under a
// regional-specific name and centralizes the pure formatting/URL/parsing
// logic that Weather.qml, DesktopClock.qml and Forecast.qml need, so that
// logic lives in one first-party, unit-testable place instead of being
// duplicated inline across three patched upstream files.
QtObject {
    id: root

    readonly property bool useTwelveHourClock: CortetsuConfig.useTwelveHourClock
    readonly property bool useFahrenheit: CortetsuConfig.useFahrenheit
    readonly property string weatherLocation: CortetsuConfig.weatherLocation

    readonly property string clockPattern: RegionalLogic.clockPattern(useTwelveHourClock)
    readonly property string hourPattern: RegionalLogic.hourPattern(useTwelveHourClock)

    // `pattern` is a key of RegionalLogic.datePatterns. Uses the session
    // locale, so day and month names follow LANG/LC_TIME.
    function formatDate(date: var, pattern: string, heading: bool): string {
        const text = Qt.locale().toString(date, RegionalLogic.datePatterns[pattern]);
        return heading ? RegionalLogic.capitalize(text) : text;
    }

    function formatTemperature(celsius: var): string {
        return RegionalLogic.formatTemperature(celsius, root.useFahrenheit);
    }

    function parseLocationQuery(raw: string): var {
        return RegionalLogic.parseLocationQuery(raw);
    }

    function buildForecastUrl(lat: var, lon: var): string {
        return RegionalLogic.buildForecastUrl(lat, lon);
    }

    function buildGeocodeUrl(cityName: string, lang: string): string {
        return RegionalLogic.buildGeocodeUrl(cityName, lang);
    }

    function buildReverseGeocodeUrl(lat: var, lon: var, lang: string): string {
        return RegionalLogic.buildReverseGeocodeUrl(lat, lon, lang);
    }

    function buildIpLookupUrl(): string {
        return RegionalLogic.buildIpLookupUrl();
    }

    function fixCityName(cityName: string): string {
        return RegionalLogic.fixCityName(cityName);
    }

    function weatherCondition(code: var): string {
        return RegionalLogic.weatherCondition(code);
    }

    function parseForecastResponse(json: var): var {
        return RegionalLogic.parseForecastResponse(json, new Date());
    }

    function parseGeocodeResponse(json: var): var {
        return RegionalLogic.parseGeocodeResponse(json);
    }

    function parseReverseGeocodeResponse(json: var): var {
        return RegionalLogic.parseReverseGeocodeResponse(json);
    }

    function parseIpLookupResponse(json: var): var {
        return RegionalLogic.parseIpLookupResponse(json);
    }

    function ipApiRateLimit(statusCode: int, headers: var): var {
        return RegionalLogic.ipApiRateLimit(statusCode, headers, Date.now());
    }
}
