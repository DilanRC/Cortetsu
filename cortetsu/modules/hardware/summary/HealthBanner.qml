pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography
import "../Format.js" as Format
import "../Health.js" as Health

// The verdict. It answers "is everything fine?" before any number is read,
// and lists what needs attention with the page that explains each item.
Item {
    id: root

    required property var health
    required property var snapshot
    required property string status
    required property var sampleTime
    required property var pageLabels

    signal pageRequested(string target)
    signal retryRequested()

    readonly property bool stale: root.status === "stale"
    readonly property var issues: root.health?.issues ?? []
    readonly property string tone: root.health?.level === "critical"
        ? "critical"
        : root.stale || root.health?.level === "attention" ? "warning" : "ok"
    readonly property color toneColor: root.tone === "critical"
        ? CortetsuDesign.colorVermillion
        : root.tone === "warning" ? CortetsuDesign.colorWarning : CortetsuDesign.colorSuccess
    readonly property string timeText: Format.clock(root.sampleTime, CortetsuConfig.useTwelveHourClock)

    readonly property string headline: root.stale
        ? qsTr("Lecturas detenidas")
        : root.tone === "critical"
            ? qsTr("Requiere atención ahora")
            : root.tone === "warning" ? qsTr("Conviene revisar") : qsTr("Todo en orden")
    readonly property string detail: root.stale
        ? qsTr("La sonda no responde. Los datos son de las %1.").arg(root.timeText)
        : root.tone === "ok"
            ? qsTr("Temperaturas, memoria, disco y batería dentro de lo normal · Lectura de las %1").arg(root.timeText)
            : qsTr("Lectura de las %1").arg(root.timeText)

    function issueTitle(issue): string {
        const value = Format.fixed(issue.value, 0);
        switch (issue.kind) {
        case "cpu-temp": return qsTr("CPU a %1 °C").arg(value);
        case "gpu-temp": return issue.label
            ? qsTr("GPU %1 a %2 °C").arg(issue.label).arg(value)
            : qsTr("GPU a %1 °C").arg(value);
        case "memory": return qsTr("Memoria al %1 %").arg(value);
        case "disk": return qsTr("Disco al %1 %").arg(value);
        case "battery": return qsTr("Batería al %1 %").arg(value);
        }
        return "";
    }

    function issueDetail(issue): string {
        const step = issue.severity === "critical" ? 1 : 0;
        switch (issue.kind) {
        case "cpu-temp": return qsTr("Por encima de %1 °C").arg(Health.limits.cpuTempC[step]);
        case "gpu-temp": return qsTr("Por encima de %1 °C").arg(Health.limits.gpuTempC[step]);
        case "memory": {
            const free = Format.gib(root.snapshot?.memory?.available_gb);
            return free ? qsTr("%1 disponibles").arg(free) : "";
        }
        case "disk": {
            const free = Format.gib(root.snapshot?.disk?.free_gb, 0);
            return free ? qsTr("%1 libres").arg(free) : "";
        }
        case "battery": return qsTr("Sin cargador conectado");
        }
        return "";
    }

    implicitHeight: column.implicitHeight

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusLarge
        baseColor: root.tone === "ok"
            ? Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
            : Qt.alpha(root.toneColor, 0.10)
        outlined: root.tone !== "ok"
        outlineColor: Qt.alpha(root.toneColor, 0.46)
    }

    Column {
        id: column
        width: parent.width

        Item {
            width: parent.width
            height: 68

            CortetsuIcon {
                id: verdictIcon
                anchors.left: parent.left
                anchors.leftMargin: CortetsuDesign.spacingComfortable
                anchors.verticalCenter: parent.verticalCenter
                text: root.stale ? "sync_problem" : root.tone === "critical" ? "error" : root.tone === "warning" ? "warning" : "check_circle"
                color: root.toneColor
                iconSize: CortetsuTypography.iconLargePx
                fill: 1
            }

            Column {
                anchors.left: verdictIcon.right
                anchors.leftMargin: CortetsuDesign.spacingStandard
                anchors.right: retry.visible ? retry.left : parent.right
                anchors.rightMargin: CortetsuDesign.spacingComfortable
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                CortetsuText {
                    objectName: "healthHeadline"
                    width: parent.width
                    text: root.headline
                    textSize: CortetsuTypography.titleLargePx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                CortetsuText {
                    width: parent.width
                    text: root.detail
                    color: CortetsuDesign.colorOnSurfaceMuted
                    textSize: CortetsuTypography.bodySmallPx
                    elide: Text.ElideRight
                }
            }

            CortetsuButton {
                id: retry
                objectName: "healthRetry"
                anchors.right: parent.right
                anchors.rightMargin: CortetsuDesign.spacingComfortable
                anchors.verticalCenter: parent.verticalCenter
                visible: root.stale
                disabled: !root.stale
                icon: "refresh"
                label: qsTr("Reintentar")
                onClicked: root.retryRequested()
            }
        }

        Flow {
            id: issueFlow
            width: parent.width
            // Past three issues the rows pair up, so the strip never takes
            // more than three lines from the meters below it.
            readonly property int columns: root.issues.length > 3 ? 2 : 1

            Repeater {
                id: issueRows
                objectName: "healthIssues"
                // Index-based on purpose: a new reading updates the rows in place
                // and delegates are created only when the number of issues changes.
                model: root.issues.length

                delegate: NavBlock {
                    id: row
                    required property int index
                    readonly property var issue: root.issues[row.index] ?? ({})

                    width: issueFlow.width / issueFlow.columns
                    height: 40
                    framed: false
                    compact: true
                    padding: CortetsuDesign.spacingComfortable
                    radiusValue: CortetsuDesign.radiusMedium
                    destination: root.pageLabels[row.issue.target] ?? ""
                    accessibleName: `${root.issueTitle(row.issue)}. ${root.issueDetail(row.issue)}`
                    onActivated: root.pageRequested(row.issue.target)

                    SeverityIcon {
                        id: issueIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 3
                        anchors.verticalCenter: parent.verticalCenter
                        severity: row.issue.severity ?? ""
                        iconSize: CortetsuTypography.iconMediumPx
                    }

                    CortetsuText {
                        id: issueTitleText
                        anchors.left: issueIcon.right
                        anchors.leftMargin: CortetsuDesign.spacingStandard + 3
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.issueTitle(row.issue)
                        textSize: CortetsuTypography.bodyLargePx
                        font.weight: Font.DemiBold
                    }

                    CortetsuText {
                        anchors.left: issueTitleText.right
                        anchors.leftMargin: CortetsuDesign.spacingStandard
                        anchors.right: parent.right
                        anchors.rightMargin: 120
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.issueDetail(row.issue)
                        color: CortetsuDesign.colorOnSurfaceMuted
                        textSize: CortetsuTypography.bodySmallPx
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: root.issues.length > 0 ? CortetsuDesign.spacingCompact : 0
        }
    }
}
