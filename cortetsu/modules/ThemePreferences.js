.pragma library
.import "../theme/ThemeProfiles.js" as Profiles

var limits = Profiles.limits;

function sanitise(values) {
    const result = {};
    for (const key of Object.keys(limits)) {
        const value = values?.[key];
        if (Number.isFinite(value))
            result[key] = Math.max(limits[key][0], Math.min(limits[key][1], value));
    }
    for (const key of Profiles.fonts) {
        const value = values?.[key];
        if (typeof value === "string" && value.trim().length > 0 && value.length <= 128 && !/[\x00-\x1f\x7f-\x9f]/.test(value))
            result[key] = value.trim();
    }
    return result;
}
