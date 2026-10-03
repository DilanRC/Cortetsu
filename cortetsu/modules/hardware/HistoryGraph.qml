pragma ComponentBehavior: Bound

import QtQuick
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// One or two series over the recent past, newest sample at the right edge.
// It repaints once per sample.
Panel {
    id: root

    property string title: ""
    property string icon: "monitoring"
    property string headline: ""
    property string subtitle: ""
    property string legendA: ""
    property string legendB: ""
    property string unit: ""
    property string actionLabel: ""
    property var seriesA: []
    property var seriesB: []
    property real maxValue: 0
    // Samples the full width stands for. A short history starts at the right
    // instead of being stretched across the whole graph.
    property int capacity: 80
    // False when the machine does not expose this reading: the graph gives way
    // to a line saying so instead of a flat zero.
    property bool available: true
    property string unavailableText: qsTr("Este equipo no expone esta lectura")
    property color colourA: CortetsuDesign.colorPrimary
    // The second series is neutral. Vermillion stays reserved for danger.
    property color colourB: CortetsuDesign.colorOnSurfaceMuted

    signal actionRequested()

    readonly property real effectiveMax: computeMax()
    readonly property real currentValue: seriesA?.length ? Number(seriesA[seriesA.length - 1] ?? 0) : 0
    readonly property real minValue: seriesMin(seriesA)
    readonly property real peakValue: seriesMax(seriesA)
    readonly property real averageValue: seriesAverage(seriesA)

    function computeMax(): real {
        if (root.maxValue > 0)
            return root.maxValue;
        return Math.max(1, Math.max(seriesMax(root.seriesA), seriesMax(root.seriesB)) * 1.18);
    }

    function seriesMin(values): real {
        if (!values || values.length === 0)
            return 0;
        let out = Number(values[0] ?? 0);
        for (const value of values)
            out = Math.min(out, Number(value ?? 0));
        return out;
    }

    function seriesMax(values): real {
        if (!values || values.length === 0)
            return 0;
        let out = 0;
        for (const value of values)
            out = Math.max(out, Number(value ?? 0));
        return out;
    }

    function seriesAverage(values): real {
        if (!values || values.length === 0)
            return 0;
        let total = 0;
        for (const value of values)
            total += Number(value ?? 0);
        return total / values.length;
    }

    function formatValue(value): string {
        const v = Number(value ?? 0);
        let digits = 1;
        if (Math.abs(v) >= 100 || root.unit === "%")
            digits = 0;
        else if (Math.abs(v) < 10)
            digits = 2;
        const suffix = root.unit.length ? ` ${root.unit}` : "";
        return `${v.toFixed(digits)}${suffix}`;
    }

    onSeriesAChanged: graph.requestPaint()
    onSeriesBChanged: graph.requestPaint()
    onMaxValueChanged: graph.requestPaint()
    onColourAChanged: graph.requestPaint()
    onColourBChanged: graph.requestPaint()

    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 44

        CortetsuIcon {
            id: glyph
            anchors.left: parent.left
            anchors.verticalCenter: titleText.verticalCenter
            text: root.icon
            color: CortetsuDesign.colorOnSurfaceMuted
            iconSize: CortetsuTypography.iconSmallPx
        }

        CortetsuText {
            id: titleText
            anchors.left: glyph.right
            anchors.leftMargin: CortetsuDesign.spacingCompact
            anchors.top: parent.top
            width: Math.min(implicitWidth, parent.width * 0.5)
            text: root.title
            color: CortetsuDesign.colorOnSurfaceMuted
            textSize: CortetsuTypography.labelLargePx
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        CortetsuText {
            anchors.left: titleText.right
            anchors.leftMargin: CortetsuDesign.spacingStandard
            anchors.right: parent.right
            anchors.baseline: titleText.baseline
            text: root.headline
            textSize: CortetsuTypography.titleMediumPx
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
        }

        CortetsuText {
            anchors.left: parent.left
            anchors.right: action.visible ? action.left : parent.right
            anchors.rightMargin: action.visible ? CortetsuDesign.spacingStandard : 0
            anchors.bottom: parent.bottom
            text: root.subtitle
            color: CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.labelSmallPx
            elide: Text.ElideRight
        }

        CortetsuButton {
            id: action
            anchors.right: parent.right
            anchors.top: parent.bottom
            anchors.topMargin: -18
            visible: root.actionLabel.length > 0
            disabled: !visible
            compact: true
            label: root.actionLabel
            icon: "swap_horiz"
            onClicked: root.actionRequested()
        }
    }

    CortetsuText {
        anchors.centerIn: chartArea
        visible: !root.available
        text: root.unavailableText
        color: CortetsuDesign.colorOnSurfaceVariant
        textSize: CortetsuTypography.bodySmallPx
    }

    Item {
        id: chartArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: footer.top
        anchors.topMargin: action.visible ? 22 : CortetsuDesign.spacingStandard
        anchors.bottomMargin: CortetsuDesign.spacingCompact

        Canvas {
            id: graph
            anchors.left: parent.left
            anchors.right: scaleLabels.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.rightMargin: CortetsuDesign.spacingCompact
            visible: root.available

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            function drawSeries(ctx, values, colour, max, fill): void {
                if (!values || values.length < 2)
                    return;

                const step = width / Math.max(1, root.capacity - 1);
                const first = Math.max(0, root.capacity - values.length);
                const start = Math.max(0, values.length - root.capacity);
                ctx.beginPath();
                for (let i = start; i < values.length; ++i) {
                    const value = Math.max(0, Math.min(max, Number(values[i] ?? 0)));
                    const x = (first + i - start) * step;
                    const y = height - 1 - (value / max) * (height - 2);
                    if (i === start)
                        ctx.moveTo(x, y);
                    else
                        ctx.lineTo(x, y);
                }
                ctx.lineWidth = 1.75;
                ctx.strokeStyle = colour;
                ctx.stroke();
                if (fill) {
                    ctx.lineTo(width, height);
                    ctx.lineTo(first * step, height);
                    ctx.closePath();
                    ctx.fillStyle = Qt.alpha(colour, 0.14);
                    ctx.fill();
                }
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                ctx.lineWidth = 1;
                ctx.strokeStyle = Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.3);
                for (let row = 0; row <= 2; ++row) {
                    const y = Math.round((height - 1) * row / 2) + 0.5;
                    ctx.beginPath();
                    ctx.moveTo(0, y);
                    ctx.lineTo(width, y);
                    ctx.stroke();
                }

                const max = Math.max(1, root.effectiveMax);
                drawSeries(ctx, root.seriesA, root.colourA, max, true);
                drawSeries(ctx, root.seriesB, root.colourB, max, false);
            }
        }

        Item {
            id: scaleLabels
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 58
            visible: root.available

            CortetsuText {
                anchors.right: parent.right
                anchors.top: parent.top
                text: root.formatValue(root.effectiveMax)
                color: CortetsuDesign.colorOnSurfaceVariant
                textSize: CortetsuTypography.labelSmallPx
            }

            CortetsuText {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.formatValue(root.effectiveMax / 2)
                color: CortetsuDesign.colorOnSurfaceVariant
                textSize: CortetsuTypography.labelSmallPx
            }

            CortetsuText {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: root.formatValue(0)
                color: CortetsuDesign.colorOnSurfaceVariant
                textSize: CortetsuTypography.labelSmallPx
            }
        }
    }

    Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 16
        visible: root.available

        Row {
            id: legends
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: CortetsuDesign.spacingStandard

            Legend { text: root.legendA; colour: root.colourA }
            Legend { text: root.legendB; colour: root.colourB }
        }

        CortetsuText {
            anchors.left: legends.right
            anchors.leftMargin: CortetsuDesign.spacingStandard
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("mín %1 · media %2 · máx %3")
                .arg(root.formatValue(root.minValue))
                .arg(root.formatValue(root.averageValue))
                .arg(root.formatValue(root.peakValue))
            color: CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.labelSmallPx
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
        }
    }

    component Legend: Row {
        id: legend

        property string text: ""
        property color colour: "transparent"

        visible: legend.text.length > 0
        spacing: 6

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 10
            height: 2
            color: legend.colour
        }

        CortetsuText {
            text: legend.text
            color: CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.labelSmallPx
        }
    }
}
