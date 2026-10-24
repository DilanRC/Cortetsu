.pragma library

// The Sistema page: the identity of the machine as the firmware reports it
// (/sys/class/dmi/id, world-readable) next to what the probe already reads.

// SMBIOS 3.x chassis types a laptop or desktop reports; others stay unnamed.
var chassisNames = {
    "3": "Sobremesa",
    "8": "Portátil",
    "9": "Portátil",
    "10": "Portátil",
    "13": "Todo en uno",
    "14": "Portátil",
    "30": "Tableta",
    "31": "Convertible",
    "32": "Desmontable"
};

// Firmware placeholders that mean "not filled in".
var placeholders = ["", "default string", "to be filled by o.e.m.", "not specified", "none", "system product name"];

function clean(value) {
    const text = String(value ?? "").trim();
    return placeholders.indexOf(text.toLowerCase()) >= 0 ? "" : text;
}

function chassis(code) {
    return chassisNames[String(code ?? "").trim()] ?? "";
}

// DMI dates are MM/DD/YYYY (SMBIOS 3.x, 7.1). Shown day first, as the rest
// of the shell does in Spanish; anything else is shown as it came.
function biosDate(value) {
    const text = clean(value);
    const match = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(text);
    return match ? `${match[2]}/${match[1]}/${match[3]}` : text;
}

// Plain text for the clipboard: one "label: value" line per known fact.
function report(rows) {
    return (rows ?? [])
        .filter(row => row && clean(row.value))
        .map(row => `${row.label}: ${clean(row.value)}`)
        .join("\n");
}
