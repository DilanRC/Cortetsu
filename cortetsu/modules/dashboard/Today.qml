pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var screenState
    property var payload: ({})
    property date dayAnchor: new Date()

    readonly property string cachePath: `${Quickshell.env("XDG_CACHE_HOME") || `${Quickshell.env("HOME")}/.cache`}/cortetsu/calendar-events.json`
    readonly property var todayEvents: (payload.events || [])
        .filter(event => eventOccursOnDay(event, dayAnchor))
        .slice()
        .sort((a, b) => eventDate(a).getTime() - eventDate(b).getTime())

    function eventDate(event): date {
        if (event.allDay) {
            const parts = String(event.start || "").split("-");
            return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        }
        return new Date(event.start);
    }

    function eventEndDate(event): date {
        if (event.allDay) {
            const parts = String(event.end || "").split("-");
            return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 0, 0, 0, -1);
        }
        return new Date(new Date(event.end).getTime() - 1);
    }

    function dayStart(value: date): date {
        return new Date(value.getFullYear(), value.getMonth(), value.getDate());
    }

    function eventOccursOnDay(event, value: date): bool {
        const target = dayStart(value).getTime();
        return target >= dayStart(eventDate(event)).getTime()
            && target <= dayStart(eventEndDate(event)).getTime();
    }

    function eventTime(event): string {
        if (event.allDay)
            return qsTr("All day");
        const start = eventDate(event);
        const end = new Date(event.end);
        if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()))
            return qsTr("Scheduled");
        return `${Qt.formatTime(start, "HH:mm")}–${Qt.formatTime(end, "HH:mm")}`;
    }

    function loadCalendar(): void {
        try {
            payload = JSON.parse(cache.text());
        } catch (_) {
            payload = {};
        }
    }

    function openCalendar(): void {
        if (!screenState)
            return;
        screenState.dashboard = false;
        screenState.cortetsuState?.setRetained("calendar", true);
    }

    Component.onCompleted: loadCalendar()

    FileView {
        id: cache
        path: root.cachePath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadCalendar()
        onFileChanged: root.loadCalendar()
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.screenState?.dashboard ?? false
        onTriggered: root.dayAnchor = new Date()
    }

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusLarge
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.78)
        outlined: true
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.56)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingCompact

        RowLayout {
            Layout.fillWidth: true

            CortetsuText {
                text: qsTr("TODAY")
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorPrimary
                font.weight: Font.DemiBold
            }

            Item { Layout.fillWidth: true }

            CortetsuButton {
                compact: true
                icon: "calendar_month"
                label: ""
                tooltipText: qsTr("Open Calendar")
                onClicked: root.openCalendar()
            }
        }

        CortetsuText {
            Layout.fillWidth: true
            text: Qt.formatDate(root.dayAnchor, "dddd, d MMMM")
            textSize: CortetsuTypography.titleMediumPx
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2

            Repeater {
                model: root.todayEvents.slice(0, 2)

                delegate: CortetsuListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: modelData.allDay ? "event" : "schedule"
                    title: modelData.summary || qsTr("Untitled event")
                    subtitle: root.eventTime(modelData)
                    selected: false
                    onClicked: root.openCalendar()
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.todayEvents.length === 0

                RowLayout {
                    anchors.centerIn: parent
                    spacing: CortetsuDesign.spacingCompact

                    CortetsuIcon {
                        text: "event_available"
                        iconSize: CortetsuTypography.iconMediumPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }

                    CortetsuText {
                        text: qsTr("No events today")
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                }
            }
        }

        CortetsuText {
            Layout.fillWidth: true
            visible: root.todayEvents.length > 2
            text: qsTr("+%1 more in Calendar").arg(root.todayEvents.length - 2)
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
            horizontalAlignment: Text.AlignRight
        }
    }
}
