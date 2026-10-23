pragma Singleton

import QtQuick
import Quickshell
import "../modules"

Singleton {
    property alias enabled: clock.enabled
    readonly property date date: clock.date
    readonly property int hours: clock.hours
    readonly property int minutes: clock.minutes
    readonly property string timeStr: format(CortetsuConfig.useTwelveHourClock ? "hh:mm:A" : "hh:mm")
    readonly property list<string> timeComponents: timeStr.split(":")
    readonly property string hourStr: timeComponents[0] ?? ""
    readonly property string minuteStr: timeComponents[1] ?? ""
    readonly property string amPmStr: timeComponents[2] ?? ""
    function format(fmt: string): string { return Qt.formatDateTime(clock.date, fmt); }
    // Every consumer shows hh:mm or a date; ticking per second only re-ran their bindings.
    SystemClock { id: clock; precision: SystemClock.Minutes }
}
