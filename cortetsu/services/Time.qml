pragma Singleton

import QtQuick
import Quickshell
import "../modules"

Singleton {
    property alias enabled: clock.enabled
    readonly property date date: clock.date
    readonly property int hours: clock.hours
    readonly property int minutes: clock.minutes
    readonly property string hourStr: hourFor(clock.date, CortetsuConfig.useTwelveHourClock)
    readonly property string minuteStr: format("mm")
    readonly property string secondStr: format("ss")
    readonly property string amPmStr: CortetsuConfig.useTwelveHourClock ? format("AP") : ""
    readonly property string timeStr: format(CortetsuRegional.liveClockPattern)
    function format(fmt: string): string { return Qt.formatDateTime(clock.date, fmt); }
    function hourFor(value: date, twelveHour: bool): string {
        const formatted = Qt.formatDateTime(value, twelveHour ? "h AP" : "HH");
        return twelveHour ? formatted.split(" ")[0] : formatted;
    }
    SystemClock {
        id: clock
        precision: CortetsuConfig.useSecondPrecision ? SystemClock.Seconds : SystemClock.Minutes
    }
}
