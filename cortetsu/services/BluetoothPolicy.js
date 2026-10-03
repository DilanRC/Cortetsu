function contains(values, value) { return value !== null && values.indexOf(value) !== -1; }
function completion(kind, target, expected, members) {
    if (kind === "forget") return !contains(members, target);
    if (!contains(members, target)) return "removed";
    if (kind === "disconnect") return !target.connected;
    if (kind === "pair") return target.paired;
    if (kind === "cancel-pair") return !target.pairing;
    if (kind === "power") return target.enabled === expected;
    if (kind === "trusted") return target.trusted === expected;
    if (kind === "blocked") return target.blocked === expected;
    return false;
}
