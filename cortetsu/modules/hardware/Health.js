.pragma library

// Each pair is [warning, critical]. They sit above what this class of laptop
// reaches under ordinary load, because an alert that fires on a normal day
// teaches the user to ignore the strip.
var limits = {
    cpuTempC: [90, 97],
    gpuTempC: [85, 92],
    memoryPct: [90, 96],
    diskPct: [90, 96],
    batteryPct: [20, 10]
};

function known(value) {
    return value !== null && value !== undefined && value !== "" && Number.isFinite(Number(value));
}

function rising(value, pair) {
    if (!known(value))
        return "";
    const number = Number(value);
    return number >= pair[1] ? "critical" : number >= pair[0] ? "warning" : "";
}

function falling(value, pair) {
    if (!known(value))
        return "";
    const number = Number(value);
    return number <= pair[1] ? "critical" : number <= pair[0] ? "warning" : "";
}

function hasReading(snapshot) {
    return !!snapshot && typeof snapshot === "object" && !!snapshot.cpu;
}

// Returns { level, issues }. `level` is "unknown" without a reading, otherwise
// "ok", "attention" or "critical". Each issue names the metric, its value and
// the page that explains it; the view owns the wording.
function evaluate(snapshot) {
    if (!hasReading(snapshot))
        return { level: "unknown", issues: [] };

    const issues = [];
    const add = (id, kind, severity, value, target, label) => {
        if (severity)
            issues.push({ id: id, kind: kind, severity: severity, value: Number(value), target: target, label: label || "" });
    };

    add("cpu-temp", "cpu-temp", rising(snapshot.cpu.temp_c, limits.cpuTempC), snapshot.cpu.temp_c, "sensors");

    const gpus = snapshot.gpus || [];
    for (let index = 0; index < gpus.length; ++index) {
        const gpu = gpus[index] || {};
        add(`gpu-temp-${index}`, "gpu-temp", rising(gpu.temp_c, limits.gpuTempC), gpu.temp_c, "sensors", gpu.vendor);
    }

    const memory = snapshot.memory || {};
    add("memory", "memory", rising(memory.usage, limits.memoryPct), memory.usage, "processes");

    const disk = snapshot.disk || {};
    add("disk", "disk", rising(disk.usage, limits.diskPct), disk.usage, "io");

    const battery = snapshot.battery || {};
    if (battery.present && battery.status === "Discharging")
        add("battery", "battery", falling(battery.percent, limits.batteryPct), battery.percent, "power");

    issues.sort((a, b) => (a.severity === b.severity ? 0 : a.severity === "critical" ? -1 : 1));
    const level = issues.length === 0 ? "ok" : issues[0].severity === "critical" ? "critical" : "attention";
    return { level: level, issues: issues };
}
