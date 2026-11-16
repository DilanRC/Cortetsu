.pragma library

// When the night light should be on. Times are "HH:mm" in local time; a
// range whose end is earlier than its start crosses midnight (20:00-07:00).
// An empty range (from === to) is never on.

function minutesOf(clock) {
    var parts = String(clock).split(":");
    return Number(parts[0]) * 60 + Number(parts[1]);
}

function inRange(minute, from, to) {
    var start = minutesOf(from), end = minutesOf(to);
    if (start === end)
        return false;
    return start < end ? minute >= start && minute < end : minute >= start || minute < end;
}

function activeAt(date, from, to) {
    return inRange(date.getHours() * 60 + date.getMinutes(), from, to);
}

// The next moment the schedule changes state after `date`: a manual choice
// holds until then, as a light switch does until the timer's next turn.
function nextBoundary(date, from, to) {
    var best = null;
    var marks = [minutesOf(from), minutesOf(to)];
    for (var day = 0; day <= 1; day++) {
        for (var i = 0; i < marks.length; i++) {
            var candidate = new Date(date.getFullYear(), date.getMonth(), date.getDate() + day,
                                     Math.floor(marks[i] / 60), marks[i] % 60, 0, 0);
            if (candidate > date && (best === null || candidate < best))
                best = candidate;
        }
    }
    return best;
}
