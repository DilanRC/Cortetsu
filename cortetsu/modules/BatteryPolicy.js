.pragma library

function crossedLowWarning(previousPercent, currentPercent, thresholdPercent) {
    return Number.isFinite(previousPercent)
        && Number.isFinite(currentPercent)
        && Number.isFinite(thresholdPercent)
        && thresholdPercent >= 0
        && currentPercent <= thresholdPercent
        && previousPercent > thresholdPercent;
}
