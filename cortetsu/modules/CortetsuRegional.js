.pragma library

// First-party regional/weather logic. It has no shared-config
// singleton or external namespace. Pure, deterministic functions only -- no network calls,
// no QML/Qt globals (Qt.formatDateTime, Requests, etc.) -- so this file can
// run unmodified under plain Node for tests, and unmodified inside
// Quickshell's QML JS engine (which is a superset of this dialect).
//
// Callers that need Qt.formatDateTime still own the actual formatting call;
// this module only decides *which pattern* to use and does the network-free
// heavy lifting: URL construction and JSON response parsing.

function clockPattern(useTwelveHour) {
    return useTwelveHour ? "h:mm A" : "h:mm";
}

function hourPattern(useTwelveHour) {
    return useTwelveHour ? "ha" : "hh:00";
}

function toFahrenheit(celsius) {
    return celsius * 9 / 5 + 32;
}

function formatTemperature(celsius, useFahrenheit) {
    if (celsius === undefined || celsius === null)
        return useFahrenheit ? "--°F" : "--°C";
    return useFahrenheit ? `${Math.round(toFahrenheit(celsius))}°F` : `${Math.round(celsius)}°C`;
}

// Splits a free-form weatherLocation preference into either explicit
// coordinates ("lat,lon") or a city name to geocode.
function parseLocationQuery(raw) {
    const value = (raw || "").trim();
    if (!value)
        return null;
    const commaIndex = value.indexOf(",");
    if (commaIndex !== -1 && !isNaN(parseFloat(value.slice(0, commaIndex))))
        return { type: "coords", value };
    return { type: "city", value };
}

function buildForecastUrl(lat, lon) {
    const params = [
        "latitude=" + lat,
        "longitude=" + lon,
        "hourly=weather_code,temperature_2m,precipitation_probability",
        "daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset",
        "current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m",
        "timezone=auto",
        "forecast_days=7"
    ];
    return "https://api.open-meteo.com/v1/forecast?" + params.join("&");
}

function buildGeocodeUrl(cityName, lang) {
    return `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(cityName)}&count=1&language=${lang || "en"}&format=json`;
}

function buildReverseGeocodeUrl(lat, lon, lang) {
    return `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=geocodejson&accept-language=${lang || "en"}`;
}

function buildIpLookupUrl() {
    return "http://ip-api.com/json?fields=status,message,city,lat,lon";
}

const CITY_DIACRITICS = {
    "Poznan": "Poznań", "Wroclaw": "Wrocław", "Krakow": "Kraków", "Gdansk": "Gdańsk",
    "Lodz": "Łódź", "Rzeszow": "Rzeszów", "Torun": "Toruń", "Bialystok": "Białystok",
    "Czestochowa": "Częstochowa", "Plock": "Płock", "Ruda Slaska": "Ruda Śląska",
    "Dabrowa Gornicza": "Dąbrowa Górnicza", "Elblag": "Elbląg",
    "Gorzow Wielkopolski": "Gorzów Wielkopolski", "Zielona Gora": "Zielona Góra",
    "Slupsk": "Słupsk", "Munchen": "München", "Koln": "Köln", "Dusseldorf": "Düsseldorf",
    "Nurnberg": "Nürnberg", "Sao Paulo": "São Paulo", "Montreal": "Montréal",
    "Quebec": "Québec", "Bogota": "Bogotá", "Medellin": "Medellín", "Cordoba": "Córdoba",
    "Istanbul": "İstanbul", "Izmir": "İzmir", "Malmo": "Malmö", "Goteborg": "Göteborg",
    "Zurich": "Zürich", "Geneve": "Genève"
};

function fixCityName(cityName) {
    if (!cityName)
        return "";
    return CITY_DIACRITICS[cityName] || cityName;
}

const WEATHER_CONDITIONS = {
    "0": "Clear", "1": "Clear", "2": "Partly cloudy", "3": "Overcast",
    "45": "Fog", "48": "Fog", "51": "Drizzle", "53": "Drizzle", "55": "Drizzle",
    "56": "Freezing drizzle", "57": "Freezing drizzle", "61": "Light rain",
    "63": "Rain", "65": "Heavy rain", "66": "Light rain", "67": "Heavy rain",
    "71": "Light snow", "73": "Snow", "75": "Heavy snow", "77": "Snow",
    "80": "Light rain", "81": "Rain", "82": "Heavy rain",
    "85": "Light snow showers", "86": "Heavy snow showers",
    "95": "Thunderstorm", "96": "Thunderstorm with hail", "99": "Thunderstorm with hail"
};

function weatherCondition(code) {
    return WEATHER_CONDITIONS[String(code)] || "Unknown";
}

// Parses an Open-Meteo /v1/forecast JSON body into the shape Weather.qml
// exposes (cc / forecast / hourlyForecast). `now` is injectable so tests are
// deterministic instead of depending on wall-clock time.
function parseForecastResponse(json, now) {
    if (!json || !json.current || !json.daily)
        return null;

    const current = {
        weatherCode: json.current.weather_code,
        weatherDesc: weatherCondition(json.current.weather_code),
        tempC: json.current.temperature_2m,
        feelsLikeC: json.current.apparent_temperature,
        humidity: json.current.relative_humidity_2m,
        windSpeed: json.current.wind_speed_10m,
        isDay: json.current.is_day,
        sunrise: json.daily.sunrise[0].replace("T", " "),
        sunset: json.daily.sunset[0].replace("T", " ")
    };

    const forecast = [];
    for (let i = 0; i < json.daily.time.length; i++) {
        forecast.push({
            date: json.daily.time[i].replace(/-/g, "/"),
            maxTempC: json.daily.temperature_2m_max[i],
            minTempC: json.daily.temperature_2m_min[i],
            weatherCode: json.daily.weather_code[i]
        });
    }

    const hourlyForecast = [];
    const reference = now !== undefined ? now : new Date();
    if (json.hourly) {
        for (let i = 0; i < json.hourly.time.length; i++) {
            const time = new Date(json.hourly.time[i].replace("T", " "));
            if (time < reference)
                continue;
            hourlyForecast.push({
                timestamp: json.hourly.time[i],
                hour: time.getHours(),
                tempC: Math.round(json.hourly.temperature_2m[i]),
                precipChance: json.hourly.precipitation_probability[i],
                weatherCode: json.hourly.weather_code[i]
            });
        }
    }

    return { current, forecast, hourlyForecast };
}

// Parses an Open-Meteo geocoding-api response into {lat, lon, name} or null.
function parseGeocodeResponse(json) {
    if (!json || !Array.isArray(json.results) || json.results.length === 0)
        return null;
    const result = json.results[0];
    return { lat: result.latitude, lon: result.longitude, name: fixCityName(result.name) };
}

// Parses a Nominatim reverse-geocode response into a city name or null.
function parseReverseGeocodeResponse(json) {
    const props = json?.features?.[0]?.properties?.geocoding;
    if (!props)
        return null;
    const cityName = props.type === "city" ? props.name : props.city;
    return cityName ? fixCityName(cityName) : null;
}

// Parses an ip-api.com lookup into {lat, lon, city} or null.
function parseIpLookupResponse(json) {
    if (!json || json.status !== "success")
        return null;
    const lat = Number(json.lat);
    const lon = Number(json.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lon))
        return null;
    return { lat, lon, city: fixCityName(json.city || "") };
}

// Pure calculation of the ip-api.com rate-limit backoff, extracted from the
// side-effecting version so it is independently testable. `headers` uses
// lower-cased keys, matching Quickshell's Requests metadata.
function ipApiRateLimit(statusCode, headers, now) {
    const reference = now !== undefined ? now : Date.now();
    const remainingHeader = headers?.["x-rl"];
    const exhausted = remainingHeader !== undefined && Number(remainingHeader) === 0;

    if (statusCode !== 429 && !exhausted)
        return { limited: false };

    const ttlHeader = headers?.["x-ttl"];
    const ttl = Number(ttlHeader);
    const delaySeconds = Number.isFinite(ttl) ? Math.max(1, Math.ceil(ttl) + 1) : 61;
    const delayMs = delaySeconds * 1000;

    return { limited: true, delayMs, blockedUntil: reference + delayMs };
}

// Date patterns with day or month names, in Spanish word order. Qt 6's
// Qt.formatDate and Qt.formatDateTime ignore the locale for a pattern string
// and print English names ("Fri 23"); format these with
// Qt.locale().toString(date, pattern), as CortetsuRegional.formatDate does.
var datePatterns = {
    weekdayDay: "ddd d",             // vie 23
    longDay: "dddd, d 'de' MMMM",    // viernes, 23 de octubre
    monthYear: "MMMM 'de' yyyy"      // octubre de 2026
};

// Spanish names are lower case; a heading starts with a capital.
function capitalize(text) {
    const value = String(text ?? "");
    return value.length > 0 ? value.charAt(0).toLocaleUpperCase() + value.slice(1) : "";
}
