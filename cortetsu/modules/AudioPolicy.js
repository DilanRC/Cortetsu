.pragma library

function request(current, requested, maximum, protectedIncrease, maxIncrease) {
    if (!Number.isFinite(requested))
        return current;
    const bounded = Math.max(0, Math.min(maximum, requested));
    return protectedIncrease && bounded > current
        ? Math.min(bounded, current + maxIncrease) : bounded;
}
