.pragma library

// Pure protocol/UI boundary. The transport owns deadlines and process lifetime;
// these functions never change state, execute commands or grant writer authority.
var domains = ["notifications", "gamemode", "power", "display"];
var maxInteger = 9007199254740991;

function integer(value, minimum, maximum) {
    return typeof value === "number" && isFinite(value) && Math.floor(value) === value
        && value >= minimum && value <= maximum;
}

function object(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validSession(session, runtime) {
    return typeof session === "string" && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/.test(session)
        && typeof runtime === "string" && runtime.startsWith("/") && runtime.indexOf("\0") < 0;
}

function validDescriptor(info, session, runtime) {
    return validSession(session, runtime) && object(info) && info.protocol === "cortetsu.ipc"
        && info.session_id === session && integer(info.session_epoch, 1, maxInteger)
        && info.socket === `${runtime}/cortetsu/cortetsu-${session}.sock`;
}

function protocol(message) {
    return object(message) && message.protocol === "cortetsu.ipc"
        && message.version?.major === 1 && message.version?.minor === 0;
}

function validHello(message, descriptor) {
    return protocol(message) && message.type === "hello_ack" && object(descriptor)
        && message.session_id === descriptor.session_id && message.session_epoch === descriptor.session_epoch
        && Array.isArray(message.capabilities) && message.capabilities.includes("snapshot");
}

function matchingResponse(message, pending) {
    return pending.length > 0 && protocol(message) && message.type === "response" && message.id === pending;
}

function activation(snapshot, domain) {
    return snapshot?.activations?.[domain]
        || {enabled: false, owner_session: "", manual_override_until_unix_ms: 0};
}

function ownedByAnother(snapshot, domain, session) {
    const owner = activation(snapshot, domain).owner_session;
    return owner.length > 0 && owner !== session;
}

function decisions(value) {
    if (!Array.isArray(value) || value.length > 256)
        return null;
    const result = [];
    for (const record of value) {
        if (!object(record) || !["rule_id", "resource", "outcome", "reason"].every(
                key => typeof record[key] === "string" && record[key].length <= 512)
                || (record.operation !== undefined && (typeof record.operation !== "string" || record.operation.length > 512)))
            return null;
        result.push({rule_id: record.rule_id, resource: record.resource, operation: record.operation || "",
            outcome: record.outcome, reason: record.reason});
    }
    return result;
}

function normaliseSnapshot(value) {
    if (!object(value) || value.mode !== "coordinator" || typeof value.authoritative !== "boolean"
            || typeof value.stream_stale !== "boolean" || !object(value.activations))
        return null;
    const history = decisions(value.decisions);
    if (history === null)
        return null;
    const active = {};
    for (const domain of domains) {
        const record = activation(value, domain);
        if (!object(record) || typeof record.enabled !== "boolean" || typeof record.owner_session !== "string"
                || (record.owner_session !== "" && !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/.test(record.owner_session))
                || !integer(record.manual_override_until_unix_ms, 0, maxInteger)
                || (record.enabled && !record.owner_session))
            return null;
        active[domain] = {enabled: record.enabled, owner_session: record.owner_session,
            manual_override_until_unix_ms: record.manual_override_until_unix_ms};
    }
    return {mode: value.mode, authoritative: value.authoritative, stream_stale: value.stream_stale,
        activations: active, decisions: history};
}

function commandFor(operation, domain, argument) {
    if (!domains.includes(domain))
        return null;
    if (operation === "enable" || operation === "disable")
        return ["cortetsu-policy", operation, domain];
    if (operation === "override" && integer(argument, 0, 604800))
        return ["cortetsu-policy", operation, domain, String(argument)];
    if (operation === "revoke" && typeof argument === "string" && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/.test(argument))
        return ["cortetsu-policy", operation, domain, argument];
    return null;
}

function commandAccepted(action, reply) {
    if (!object(action) || !object(reply) || reply.domain !== action.domain)
        return false;
    if (action.operation === "override")
        return integer(reply.manual_override_until_unix_ms, 0, maxInteger)
            && (action.seconds === 0 ? reply.manual_override_until_unix_ms === 0 : reply.manual_override_until_unix_ms > 0);
    if (action.operation === "revoke")
        return reply.revoked_owner_session === action.expectedOwner && reply.owner_session === ""
            && reply.enabled === false && reply.session_id === action.session;
    return reply.session_id === action.session && reply.enabled === (action.operation === "enable");
}

function actionConfirmed(action, snapshot) {
    if (!object(action) || !object(snapshot) || !object(snapshot.activations))
        return false;
    const record = activation(snapshot, action.domain);
    if (action.operation === "enable")
        return record.enabled && record.owner_session === action.session;
    if (action.operation === "disable" || action.operation === "revoke")
        return !record.enabled && record.owner_session === "";
    return action.operation === "override" && integer(action.until, 0, maxInteger)
        && record.manual_override_until_unix_ms === action.until;
}

function readRequest(operation, id, descriptor, argument) {
    let body;
    if (operation === "snapshot.get") body = {domains: ["coordinator"]};
    else if (operation === "policy.list") body = {};
    else if (operation === "explain.get" && typeof argument === "string"
            && /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(argument))
        body = {trace_id: argument};
    else return null;
    return {type: "request", protocol: "cortetsu.ipc", version: {major: 1, minor: 0}, id: id,
        op: operation, session_id: descriptor.session_id, session_epoch: descriptor.session_epoch,
        deadline_ms: 5000, body: body};
}

function utf8Length(text) {
    let bytes = 0;
    for (let i = 0; i < text.length; ++i) {
        const code = text.charCodeAt(i);
        if (code < 128) bytes++;
        else if (code < 2048) bytes += 2;
        else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length
                && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
            bytes += 4;
            i++;
        } else bytes += 3;
    }
    return bytes;
}
