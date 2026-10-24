#!/usr/bin/env node
"use strict";
// Executes the real CortetsuRegional.js logic (URL building, response
// parsing, temperature/time formatting) under plain Node, feeding it
// hand-built JSON fixtures that stand in for Open-Meteo / Nominatim /
// ip-api responses. No network call is ever made -- HTTP is mocked by
// simply never happening: we hand the parse functions a canned payload
// exactly like the one `Requests.get` would have delivered to QML.
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const MODULE_PATH = path.join(__dirname, "..", "modules", "CortetsuRegional.js");
const source = fs.readFileSync(MODULE_PATH, "utf8");

if (!source.startsWith(".pragma library"))
    throw new Error("CortetsuRegional.js must start with the QML '.pragma library' directive");

// Strip the QML-only pragma line; the rest is plain ES2020, runnable as-is
// both here and inside Quickshell's JS engine.
const body = source.replace(/^\.pragma library\r?\n/, "");
const context = {};
vm.createContext(context);
vm.runInContext(
    body +
        "\nglobalThis.__EXPORTS__ = { clockPattern, hourPattern, toFahrenheit, formatTemperature, " +
        "parseLocationQuery, buildForecastUrl, buildGeocodeUrl, buildReverseGeocodeUrl, buildIpLookupUrl, " +
        "fixCityName, weatherCondition, parseForecastResponse, parseGeocodeResponse, " +
        "parseReverseGeocodeResponse, parseIpLookupResponse, ipApiRateLimit, capitalize, datePatterns };",
    context,
    { filename: "CortetsuRegional.js" }
);
const regional = context.__EXPORTS__;

let failures = 0;
function check(label, actual, expected) {
    const ok = JSON.stringify(actual) === JSON.stringify(expected);
    if (!ok) {
        failures++;
        console.error(`FAIL ${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
    }
}

// -- clock / temperature formatting -----------------------------------
check("clockPattern(12h)", regional.clockPattern(true), "h:mm A");
check("clockPattern(24h)", regional.clockPattern(false), "h:mm");
check("hourPattern(12h)", regional.hourPattern(true), "ha");
check("hourPattern(24h)", regional.hourPattern(false), "hh:00");
check("toFahrenheit(0)", regional.toFahrenheit(0), 32);
check("toFahrenheit(100)", regional.toFahrenheit(100), 212);
check("formatTemperature(21.4, false)", regional.formatTemperature(21.4, false), "21°C");
check("formatTemperature(21.4, true)", regional.formatTemperature(21.4, true), "71°F");
check("formatTemperature(undefined, false)", regional.formatTemperature(undefined, false), "--°C");
check("formatTemperature(undefined, true)", regional.formatTemperature(undefined, true), "--°F");

// -- location parsing ---------------------------------------------------
check("parseLocationQuery('')", regional.parseLocationQuery(""), null);
check("parseLocationQuery('  ')", regional.parseLocationQuery("  "), null);
check("parseLocationQuery('9.93,-84.08')", regional.parseLocationQuery("9.93,-84.08"), { type: "coords", value: "9.93,-84.08" });
check("parseLocationQuery('San Jose, Costa Rica')", regional.parseLocationQuery("San Jose, Costa Rica"), { type: "city", value: "San Jose, Costa Rica" });
check("parseLocationQuery('San Jose')", regional.parseLocationQuery("San Jose"), { type: "city", value: "San Jose" });

// -- URL construction (deterministic, no network) ------------------------
check(
    "buildForecastUrl",
    regional.buildForecastUrl("9.93", "-84.08"),
    "https://api.open-meteo.com/v1/forecast?latitude=9.93&longitude=-84.08&hourly=weather_code,temperature_2m,precipitation_probability&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m&timezone=auto&forecast_days=7"
);
check(
    "buildGeocodeUrl",
    regional.buildGeocodeUrl("San José", "es"),
    "https://geocoding-api.open-meteo.com/v1/search?name=San%20Jos%C3%A9&count=1&language=es&format=json"
);
check(
    "buildReverseGeocodeUrl",
    regional.buildReverseGeocodeUrl("9.93", "-84.08", "es"),
    "https://nominatim.openstreetmap.org/reverse?lat=9.93&lon=-84.08&format=geocodejson&accept-language=es"
);
check("buildIpLookupUrl", regional.buildIpLookupUrl(), "http://ip-api.com/json?fields=status,message,city,lat,lon");

// -- city diacritics + condition text ------------------------------------
check("fixCityName(Bogota)", regional.fixCityName("Bogota"), "Bogotá");
check("fixCityName(unknown)", regional.fixCityName("Springfield"), "Springfield");
check("fixCityName(empty)", regional.fixCityName(""), "");
check("weatherCondition(63)", regional.weatherCondition(63), "Rain");
check("weatherCondition(999)", regional.weatherCondition(999), "Unknown");

// -- mocked Open-Meteo /v1/forecast response ------------------------------
const forecastFixture = {
    current: {
        weather_code: 3,
        temperature_2m: 22.4,
        apparent_temperature: 21.9,
        relative_humidity_2m: 71,
        wind_speed_10m: 8.2,
        is_day: 1
    },
    daily: {
        time: ["2026-09-05", "2026-09-06"],
        temperature_2m_max: [26.1, 25.4],
        temperature_2m_min: [18.2, 17.9],
        weather_code: [3, 61],
        sunrise: ["2026-09-05T05:32", "2026-09-06T05:32"],
        sunset: ["2026-09-05T17:48", "2026-09-06T17:47"]
    },
    hourly: {
        time: ["2026-09-05T08:00", "2026-09-05T09:00", "2026-09-05T10:00"],
        temperature_2m: [20.1, 21.3, 22.8],
        precipitation_probability: [10, 20, 5],
        weather_code: [3, 61, 3]
    }
};
const now = new Date("2026-09-05T08:30:00");
const parsed = regional.parseForecastResponse(forecastFixture, now);
check("parseForecastResponse.current.weatherDesc", parsed.current.weatherDesc, "Overcast");
check("parseForecastResponse.current.tempC", parsed.current.tempC, 22.4);
check("parseForecastResponse.current.sunrise", parsed.current.sunrise, "2026-09-05 05:32");
check("parseForecastResponse.current.sunset", parsed.current.sunset, "2026-09-05 17:48");
check("parseForecastResponse.forecast.length", parsed.forecast.length, 2);
check("parseForecastResponse.forecast[0].date", parsed.forecast[0].date, "2026/09/05");
check("parseForecastResponse.forecast[1].weatherCode", parsed.forecast[1].weatherCode, 61);
// The 08:00 hour is before `now` (08:30) so it must be dropped; only the two
// future hours remain.
check("parseForecastResponse.hourlyForecast.length", parsed.hourlyForecast.length, 2);
check("parseForecastResponse.hourlyForecast[0].timestamp", parsed.hourlyForecast[0].timestamp, "2026-09-05T09:00");
check("parseForecastResponse.hourlyForecast[0].tempC", parsed.hourlyForecast[0].tempC, 21);
check("parseForecastResponse(missing current)", regional.parseForecastResponse({ daily: {} }, now), null);
check("parseForecastResponse(missing daily)", regional.parseForecastResponse({ current: {} }, now), null);

// -- mocked Open-Meteo geocoding-api response -----------------------------
check(
    "parseGeocodeResponse(hit)",
    regional.parseGeocodeResponse({ results: [{ latitude: 9.93, longitude: -84.08, name: "Bogota" }] }),
    { lat: 9.93, lon: -84.08, name: "Bogotá" }
);
check("parseGeocodeResponse(miss)", regional.parseGeocodeResponse({ results: [] }), null);
check("parseGeocodeResponse(malformed)", regional.parseGeocodeResponse({}), null);

// -- mocked Nominatim reverse-geocode response ----------------------------
check(
    "parseReverseGeocodeResponse(city)",
    regional.parseReverseGeocodeResponse({ features: [{ properties: { geocoding: { type: "city", name: "Munchen" } } }] }),
    "München"
);
check(
    "parseReverseGeocodeResponse(town, falls back to .city)",
    regional.parseReverseGeocodeResponse({ features: [{ properties: { geocoding: { type: "town", city: "Zurich" } } }] }),
    "Zürich"
);
check("parseReverseGeocodeResponse(empty)", regional.parseReverseGeocodeResponse({ features: [] }), null);

// -- mocked ip-api.com response --------------------------------------------
check(
    "parseIpLookupResponse(success)",
    regional.parseIpLookupResponse({ status: "success", city: "Sao Paulo", lat: "-23.55", lon: "-46.63" }),
    { lat: -23.55, lon: -46.63, city: "São Paulo" }
);
check("parseIpLookupResponse(failure)", regional.parseIpLookupResponse({ status: "fail", message: "invalid query" }), null);
check("parseIpLookupResponse(nonfinite coords)", regional.parseIpLookupResponse({ status: "success", lat: "nope", lon: "0" }), null);

// -- ip-api.com rate-limit backoff (pure, mocked headers/clock) -----------
check("ipApiRateLimit(200, {})", regional.ipApiRateLimit(200, {}, 0), { limited: false });
check("ipApiRateLimit(429, {'x-ttl':'30'})", regional.ipApiRateLimit(429, { "x-ttl": "30" }, 1000), { limited: true, delayMs: 31000, blockedUntil: 32000 });
check("ipApiRateLimit(429, no ttl header)", regional.ipApiRateLimit(429, {}, 1000), { limited: true, delayMs: 61000, blockedUntil: 62000 });
check("ipApiRateLimit(200, exhausted x-rl)", regional.ipApiRateLimit(200, { "x-rl": "0" }, 1000), { limited: true, delayMs: 61000, blockedUntil: 62000 });
check("ipApiRateLimit(200, remaining x-rl)", regional.ipApiRateLimit(200, { "x-rl": "5" }, 1000), { limited: false });

// -- Spanish date headings ------------------------------------------------
check("capitalize(viernes, 23 de octubre)", regional.capitalize("viernes, 23 de octubre"), "Viernes, 23 de octubre");
check("capitalize(empty)", regional.capitalize(""), "");
check("capitalize(undefined)", regional.capitalize(undefined), "");
check("datePatterns.longDay keeps 'de'", regional.datePatterns.longDay, "dddd, d 'de' MMMM");

if (failures > 0) {
    console.error(`${failures} assertion(s) failed`);
    process.exit(1);
}

console.log("test-regional.node: OK (" +
    "clock/temp formatting, location parsing, URL construction, mocked Open-Meteo/Nominatim/ip-api parsing, rate-limit backoff)");
