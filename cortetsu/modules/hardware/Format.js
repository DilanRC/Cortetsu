.pragma library

// A missing reading formats to "", never to a zero or a dash that reads as
// data. The view decides what an absent value looks like.

function known(value) {
    return value !== null && value !== undefined && value !== "" && Number.isFinite(Number(value));
}

function fixed(value, digits) {
    return known(value) ? Number(value).toFixed(digits === undefined ? 1 : digits) : "";
}

function withUnit(value, digits, unit) {
    const text = fixed(value, digits);
    return text ? `${text} ${unit}` : "";
}

function percent(value) { return withUnit(value, 0, "%"); }
function celsius(value) { return withUnit(value, 0, "°C"); }
function gib(value, digits) { return withUnit(value, digits === undefined ? 1 : digits, "GiB"); }
function watts(value) { return withUnit(value, 1, "W"); }

// Below one gibibyte a size reads better in whole mebibytes.
function size(gibibytes) {
    if (!known(gibibytes))
        return "";
    return Number(gibibytes) < 1 ? `${Math.round(Number(gibibytes) * 1024)} MiB` : gib(gibibytes);
}

function gigahertz(mhz) {
    return known(mhz) && Number(mhz) > 0 ? `${(Number(mhz) / 1000).toFixed(1)} GHz` : "";
}

// "9.0 / 14.9 GiB", or "" when either side is missing.
function ratioGib(used, total, digits) {
    const d = digits === undefined ? 1 : digits;
    return known(used) && known(total) ? `${fixed(used, d)} / ${fixed(total, d)} GiB` : "";
}

function fraction(value) {
    return known(value) ? Math.max(0, Math.min(1, Number(value) / 100)) : -1;
}

function duration(seconds) {
    if (!known(seconds))
        return "";
    const total = Math.max(0, Number(seconds));
    const days = Math.floor(total / 86400);
    const hours = Math.floor((total % 86400) / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    if (days > 0)
        return `${days} d ${hours} h`;
    if (hours > 0)
        return `${hours} h ${minutes} min`;
    return `${minutes} min`;
}

function clock(date, twelveHour) {
    return date ? Qt.formatTime(date, twelveHour ? "h:mm:ss AP" : "HH:mm:ss") : "";
}

// Joins the parts that exist, so an absent reading leaves no gap or separator.
function join(parts, separator) {
    return parts.filter(part => !!part).join(separator === undefined ? " · " : separator);
}
