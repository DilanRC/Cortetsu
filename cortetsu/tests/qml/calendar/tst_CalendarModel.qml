import QtQuick
import QtTest
import "../../../modules/calendar/CalendarModel.js" as Model

// Date logic of the Calendar surface. Every date is local; the cases hold in
// any time zone (DST days included) because they build dates from fields.
TestCase {
    name: "CalendarModel"

    function allDay(start, end, extra) {
        return Object.assign({ allDay: true, start, end, title: start }, extra || {});
    }

    function timed(start, end) {
        return { allDay: false, start: start.toISOString(), end: end.toISOString(), title: "timed" };
    }

    function test_month_grid_is_monday_first() {
        // October 2026 starts on a Thursday and has 31 days.
        const cells = Model.monthCells(2026, 9);
        compare(cells.length, 42);
        compare(cells.slice(0, 4), [0, 0, 0, 1]);
        compare(cells.filter(day => day > 0).length, 31);
        compare(cells[3 + 30], 31);
        compare(cells[3 + 31], 0);
        // February of a leap year, starting on a Monday (2027 is not leap; 2028 is, and starts on Tuesday).
        compare(Model.daysInMonth(2028, 1), 29);
        compare(Model.monthCells(2028, 1).indexOf(1), 1);
        // A month starting on Sunday fills the first row with blanks.
        compare(Model.monthCells(2026, 2).indexOf(1), 6);
    }

    function test_all_day_end_is_exclusive() {
        const event = allDay("2026-10-20", "2026-10-21");
        verify(Model.occursOn(event, new Date(2026, 9, 20)));
        verify(!Model.occursOn(event, new Date(2026, 9, 21)));
        verify(!Model.occursOn(event, new Date(2026, 9, 19)));
    }

    function test_timed_event_ending_at_midnight_stays_on_its_day() {
        const event = timed(new Date(2026, 9, 20, 22, 0), new Date(2026, 9, 21, 0, 0));
        verify(Model.occursOn(event, new Date(2026, 9, 20, 15)));
        verify(!Model.occursOn(event, new Date(2026, 9, 21)));
    }

    function test_multi_day_event_across_months() {
        const event = allDay("2026-10-30", "2026-11-03");
        const october = Model.eventsByDay([event], 2026, 9);
        compare(Object.keys(october).map(Number).sort((a, b) => a - b), [30, 31]);
        const november = Model.eventsByDay([event], 2026, 10);
        compare(Object.keys(november).map(Number).sort((a, b) => a - b), [1, 2]);
        compare(Object.keys(Model.eventsByDay([event], 2026, 11)).length, 0);
        // Same month of another year is not this month, in either direction.
        compare(Object.keys(Model.eventsByDay([event], 2027, 9)).length, 0);
        compare(Object.keys(Model.eventsByDay([allDay("2027-10-05", "2027-10-06")], 2026, 9)).length, 0);
        compare(Model.eventsByDay([allDay("2027-10-05", "2027-10-06")], 2027, 9)[5].length, 1);
    }

    function test_events_by_day_matches_per_day_filter() {
        const events = [
            allDay("2026-10-01", "2026-10-02"),
            allDay("2026-09-28", "2026-10-03"),
            timed(new Date(2026, 9, 15, 9), new Date(2026, 9, 15, 10)),
            timed(new Date(2026, 9, 31, 23), new Date(2026, 10, 1, 1)),
            allDay("2026-10-15", "2026-10-16")
        ];
        const byDay = Model.eventsByDay(events, 2026, 9);
        for (let day = 1; day <= 31; ++day) {
            const expected = Model.eventsOn(events, new Date(2026, 9, day));
            compare((byDay[day] || []).length, expected.length, `day ${day}`);
        }
        compare(byDay[15].length, 2);
    }

    function test_invalid_events_are_skipped() {
        const events = [null, {}, { start: "x", end: "y" }, { allDay: true, start: 5, end: 6 }, allDay("2026-10-20", "2026-10-21")];
        compare(Model.eventsOn(events, new Date(2026, 9, 20)).length, 1);
        compare(Object.keys(Model.eventsByDay(events, 2026, 9)), ["20"]);
        compare(Model.eventsOn(undefined, new Date()).length, 0);
    }

    function test_same_day_and_day_start() {
        verify(Model.sameDay(new Date(2026, 9, 20, 0, 0), new Date(2026, 9, 20, 23, 59)));
        verify(!Model.sameDay(new Date(2026, 9, 20), new Date(2026, 9, 21)));
        verify(!Model.sameDay(null, new Date()));
        const start = Model.dayStart(new Date(2026, 2, 29, 13, 45));
        compare([start.getHours(), start.getMinutes(), start.getDate()], [0, 0, 29]);
    }

    // Navigating 1200 months either way keeps a valid first-of-month date.
    function test_month_navigation_round_trip() {
        let date = new Date(2026, 9, 20);
        for (let step = 0; step < 1200; ++step)
            date = new Date(date.getFullYear(), date.getMonth() + 1, 1);
        compare([date.getFullYear(), date.getMonth(), date.getDate()], [2126, 9, 1]);
        for (let step = 0; step < 2400; ++step)
            date = new Date(date.getFullYear(), date.getMonth() - 1, 1);
        compare([date.getFullYear(), date.getMonth(), date.getDate()], [1926, 9, 1]);
    }
}
