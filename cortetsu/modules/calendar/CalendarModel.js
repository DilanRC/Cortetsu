.pragma library

// Pure date logic of the Calendar surface. Dates are local Date objects; event
// timestamps come from the cortetsu-calendar cache: all-day events carry
// "YYYY-MM-DD" (end exclusive, as Google returns it) and timed events an ISO
// date-time with its offset. No function reads the clock: callers pass `today`.

function dayStart(value) {
    return new Date(value.getFullYear(), value.getMonth(), value.getDate());
}

function sameDay(a, b) {
    return !!a && !!b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth()
        && a.getDate() === b.getDate();
}

function parseDate(text) {
    const parts = String(text).split("-");
    return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
}

function eventStart(event) {
    return event.allDay ? parseDate(event.start) : new Date(event.start);
}

// Last instant that belongs to the event: ends are exclusive.
function eventLastInstant(event) {
    const end = event.allDay ? parseDate(event.end) : new Date(event.end);
    return new Date(end.getTime() - 1);
}

function isValidEvent(event) {
    return !!event && typeof event.start === "string" && typeof event.end === "string"
        && !isNaN(eventStart(event).getTime()) && !isNaN(eventLastInstant(event).getTime());
}

function occursOn(event, day) {
    const target = dayStart(day).getTime();
    return target >= dayStart(eventStart(event)).getTime()
        && target <= dayStart(eventLastInstant(event)).getTime();
}

function eventsOn(events, day) {
    // The cache is already ordered by start.
    return (events || []).filter(event => isValidEvent(event) && occursOn(event, day));
}

function daysInMonth(year, month) {
    return new Date(year, month + 1, 0).getDate();
}

// Monday-first offset of the 1st of the month in a 7-column grid.
function firstOffset(year, month) {
    return (new Date(year, month, 1).getDay() + 6) % 7;
}

// The 42 cells of the month grid: day of month, or 0 outside the month.
function monthCells(year, month) {
    const offset = firstOffset(year, month);
    const days = daysInMonth(year, month);
    const cells = [];
    for (let index = 0; index < 42; index++) {
        const day = index - offset + 1;
        cells.push(day > 0 && day <= days ? day : 0);
    }
    return cells;
}

// Day of month -> events that touch it, for one month, in one pass over the
// events (each cell used to filter the whole list twice).
function eventsByDay(events, year, month) {
    const first = new Date(year, month, 1).getTime();
    const byDay = {};
    for (const event of events || []) {
        if (!isValidEvent(event))
            continue;
        const from = Math.max(dayStart(eventStart(event)).getTime(), first);
        const lastDay = dayStart(eventLastInstant(event));
        for (let day = new Date(from); day <= lastDay && day.getMonth() === month && day.getFullYear() === year;
             day = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1)) {
            const key = day.getDate();
            (byDay[key] = byDay[key] || []).push(event);
        }
    }
    return byDay;
}

// Keyboard moves of the selected day. Built from fields, so a DST day is
// still one step.
function addDays(value, days) {
    return new Date(value.getFullYear(), value.getMonth(), value.getDate() + days);
}

// A month away, on the same day when that month has it, else its last day
// (31 January + 1 month = 28 or 29 February, not 3 March).
function addMonths(value, months) {
    const first = new Date(value.getFullYear(), value.getMonth() + months, 1);
    return new Date(first.getFullYear(), first.getMonth(),
        Math.min(value.getDate(), daysInMonth(first.getFullYear(), first.getMonth())));
}

// The day a key selects from `selected`, or null when the key is not a
// calendar move. Arrows move by day and week, PageUp/PageDown by month,
// Home returns to `today`.
function dayForKey(key, selected, today, keys) {
    switch (key) {
    case keys.left: return addDays(selected, -1);
    case keys.right: return addDays(selected, 1);
    case keys.up: return addDays(selected, -7);
    case keys.down: return addDays(selected, 7);
    case keys.pageUp: return addMonths(selected, -1);
    case keys.pageDown: return addMonths(selected, 1);
    case keys.home: return dayStart(today);
    default: return null;
    }
}
