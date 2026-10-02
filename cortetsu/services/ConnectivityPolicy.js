.pragma library

function splitFields(line) {
    const fields = [];
    let value = "", escaped = false;
    for (const character of line) {
        if (escaped) { value += character; escaped = false; }
        else if (character === "\\") escaped = true;
        else if (character === ":") { fields.push(value); value = ""; }
        else value += character;
    }
    if (escaped) value += "\\";
    fields.push(value);
    return fields;
}

function rows(text) {
    return text.split("\n").filter(line => line.length > 0).map(splitFields);
}

function validUuid(uuid) {
    return typeof uuid === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(uuid);
}

function profiles(text) {
    return rows(text).filter(f => ["802-11-wireless", "802-3-ethernet"].includes(f[2]) && validUuid(f[0])).map(f => ({
        uuid: f[0], name: f[1], type: f[2], ssid: "", autoconnect: f[3] === "yes", device: f[4] || "", interface: ""
    }));
}

function properties(text) {
    const result = {};
    for (const fields of rows(text)) {
        const key = fields.shift();
        const base = key.split("[")[0];
        if (!result[base]) result[base] = [];
        result[base].push(fields.join(":"));
    }
    return result;
}

function accessPoints(text) {
    return rows(text).filter(f => f.length >= 7).map(f => ({
        active: f[0] === "*", bssid: f[1], ssid: f[2], strength: Number(f[3]) || 0,
        frequency: Number((f[4] || "").replace(/[^0-9.]/g, "")) || 0, security: f[5], device: f[6]
    }));
}

function strengthPercent(raw) {
    let value = Number(raw);
    if (!isFinite(value)) return 0;
    if (value >= 0 && value <= 1) value *= 100;
    return Math.max(0, Math.min(100, Math.round(value)));
}

function operation(id, kind, target, state, now) {
    return { id: id, kind: kind, target: target, state: state, startedAt: now,
        lastError: "", lastErrorCode: "", retryable: false };
}

function fail(operation, code, message, retryable) {
    return Object.assign({}, operation, { state: code === "password-required" ? "auth-required" : "failed",
        lastError: message, lastErrorCode: code, retryable: retryable });
}

function confirmed(operation, snapshot) {
    if (operation.kind === "connect") return snapshot.connected && (!operation.target.uuid || snapshot.uuid === operation.target.uuid);
    if (["disconnect", "disconnect-wired"].includes(operation.kind)) return !snapshot.connected;
    if (operation.kind === "enable") return snapshot.enabled === operation.target.enabled;
    if (operation.kind === "forget") return !snapshot.profiles.some(p => p.uuid === operation.target.uuid);
    if (operation.kind === "ipv4") return snapshot.profiles.some(p => p.uuid === operation.target.uuid && sameIpv4(p.ipv4, operation.target.config));
    if (operation.kind === "autoconnect") return snapshot.profiles.some(p => p.uuid === operation.target.uuid && p.autoconnect === operation.target.enabled);
    return false;
}

function commandError(text, exitCode) {
    const value = text.toLowerCase();
    if (value.includes("not running") || exitCode === 8) return { code: "service-unavailable", message: "NetworkManager no está disponible", retryable: true };
    if (value.includes("secrets") || value.includes("password")) return { code: "authentication-failed", message: "No se pudo autenticar la conexión", retryable: true };
    if (value.includes("timeout") || exitCode === 3) return { code: "timeout", message: "La conexión tardó demasiado", retryable: true };
    if (value.includes("unknown connection") || exitCode === 10) return { code: "profile-invalid", message: "El perfil ya no está disponible", retryable: false };
    return { code: "operation-failed", message: "NetworkManager rechazó la operación", retryable: true };
}

function ipv4Address(value, requirePrefix) {
    const pieces = value.split("/");
    if (pieces.length > 2 || (requirePrefix && pieces.length !== 2)) return false;
    const octets = pieces[0].split(".");
    if (octets.length !== 4 || !octets.every(octet => /^\d{1,3}$/.test(octet) && Number(octet) <= 255)) return false;
    return pieces.length === 1 || (/^\d{1,2}$/.test(pieces[1]) && Number(pieces[1]) <= 32);
}

function ipList(value) {
    return String(value || "").split(/[\s,]+/).filter(Boolean);
}

function ipv4Config(method, address, gateway, dns) {
    if (!["auto", "manual", "disabled"].includes(method)) return null;
    const addresses = method === "manual" ? ipList(address) : [];
    const dnsList = method === "disabled" ? [] : ipList(dns);
    const route = method === "manual" ? String(gateway || "").trim() : "";
    if ((method === "manual" && addresses.length === 0) || !addresses.every(value => ipv4Address(value, true))) return null;
    if ((route && (route.includes("/") || !ipv4Address(route, false))) || !dnsList.every(value => !value.includes("/") && ipv4Address(value, false))) return null;
    return { method: method, addresses: addresses, gateway: route, dns: dnsList, ignoreAutoDns: dnsList.length > 0 };
}

function sameIpv4(left, right) {
    return !!left && !!right && left.method === right.method && left.gateway === right.gateway
        && left.ignoreAutoDns === right.ignoreAutoDns
        && JSON.stringify(left.addresses) === JSON.stringify(right.addresses)
        && JSON.stringify(left.dns) === JSON.stringify(right.dns);
}

function newUuid() {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, character => {
        const value = Math.floor(Math.random() * 16);
        return (character === "x" ? value : (value & 3) | 8).toString(16);
    });
}

function hiddenInput(ssid, security, password) {
    if (typeof ssid !== "string" || !ssid.length || ssid.includes("\0")) return false;
    try { if ((encodeURIComponent(ssid).match(/%[A-F0-9]{2}|./g) || []).length > 32) return false; }
    catch (error) { return false; }
    if (!["open", "wpa-psk", "sae"].includes(security)) return false;
    if (security === "open") return password.length === 0;
    return password.length > 0 && !/[\r\n\0]/.test(password);
}

function profileDevice(candidates, profile, requestedName) {
    if (requestedName) {
        if (profile.interface && profile.interface !== requestedName) return null;
        return candidates.find(device => device.name === requestedName) || null;
    }
    return profile.interface ? candidates.find(device => device.name === profile.interface) || null
        : candidates.find(device => device.connected) || candidates[0] || null;
}

function hiddenRetryTarget(operation, ssid, device, security) {
    const target = operation.target;
    return ["failed", "auth-required"].includes(operation.state) && target.createdProfile
        && target.ssid === ssid && target.device === device && target.security === security;
}

function hiddenRetryProfile(operation, profiles, ssid, device, security) {
    const target = operation.target;
    if (!hiddenRetryTarget(operation, ssid, device, security)) return null;
    return profiles.find(profile => profile.uuid === target.uuid && profile.type === "802-11-wireless"
        && profile.ssid === ssid && (!profile.interface || profile.interface === device)
        && profile.hidden && profile.security === security) || null;
}
