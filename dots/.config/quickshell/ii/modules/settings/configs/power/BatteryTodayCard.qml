import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Today's charge by hour, from the App usage sampler's battery section. The level at the
 * close of each hour as an area, the hours spent charging as tertiary ticks under it, the
 * live level as a dot. The whole card opens the battery history (`clicked`).
 */
Rectangle {
    id: root

    signal clicked()

    readonly property bool sampling: AppStats.enabled && AppStats.binaryPresent
    readonly property var hours: {
        AppStats.history;
        return root.sampling ? AppStats.batteryHours(AppStats.todayDate) : new Array(24).fill(null);
    }
    readonly property var rollup: {
        AppStats.history;
        return root.sampling ? AppStats.batteryRollup([AppStats.todayDate], {}) : null;
    }
    readonly property bool hasHistory: root.hours.some(h => h !== null)
    readonly property int nowHour: new Date().getHours()

    // charge spent and gained today, in percent of a full pack
    readonly property real spentPct: root.rollup && root.rollup.fullMwh > 0 ? root.rollup.outMwh / root.rollup.fullMwh * 100 : NaN
    readonly property real gainedPct: root.rollup && root.rollup.fullMwh > 0 ? root.rollup.inMwh / root.rollup.fullMwh * 100 : NaN
    readonly property real avgWatts: root.rollup && root.rollup.offAc > 0 ? root.rollup.outMwh * 3.6 / root.rollup.offAc : NaN
    readonly property real onBatterySecs: root.rollup ? root.rollup.offAc : 0

    Component.onCompleted: if (root.sampling) AppStats.ensureDates([AppStats.todayDate])

    implicitHeight: 300
    radius: Appearance.rounding.verylarge
    color: cardHover.hovered && root.hasHistory ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

    HoverHandler {
        id: cardHover
        cursorShape: root.hasHistory ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        enabled: root.hasHistory
        onTapped: root.clicked()
    }

    function fmtHours(secs) {
        const h = Math.floor(secs / 3600);
        const m = Math.round((secs % 3600) / 60);
        return h > 0 ? `${h} h ${String(m).padStart(2, "0")}` : `${m} min`;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12

        // header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Translation.tr("Today")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.hasHistory ? Translation.tr("Charge at the close of each hour")
                        : (root.sampling ? Translation.tr("The day fills in as the sampler records")
                                         : Translation.tr("Turn on App usage history to follow the day"))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            // the door to the history
            Rectangle {
                visible: root.hasHistory
                implicitHeight: 36
                implicitWidth: detailsRow.implicitWidth + 24
                radius: height / 2
                color: cardHover.hovered ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                readonly property color colContent: cardHover.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                RowLayout {
                    id: detailsRow
                    anchors.centerIn: parent
                    spacing: 4
                    StyledText {
                        text: Translation.tr("Apps & history")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: parent.parent.colContent
                    }
                    MaterialSymbol {
                        text: "arrow_forward"
                        iconSize: Appearance.font.pixelSize.normal
                        color: parent.parent.colContent
                    }
                }
            }
        }

        // chart
        Item {
            id: chart
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 110

            readonly property real padBottom: 22
            readonly property real plotH: height - padBottom
            readonly property real colW: width / 24

            function xOf(hour) { return (hour + 0.5) * chart.colW; }
            function yOf(level) { return chart.plotH * (1 - level / 100); }

            // level points: close of each recorded hour, the live level for the current one
            readonly property var points: {
                const pts = [];
                for (let h = 0; h < 24; h++) {
                    const b = root.hours[h];
                    if (h === root.nowHour && root.hasHistory)
                        pts.push(Qt.point(chart.xOf(h), chart.yOf(Battery.percent)));
                    else if (b)
                        pts.push(Qt.point(chart.xOf(h), chart.yOf(b.end)));
                }
                return pts;
            }
            readonly property var area: chart.points.length < 2 ? [] : chart.points.concat([
                Qt.point(chart.points[chart.points.length - 1].x, chart.plotH),
                Qt.point(chart.points[0].x, chart.plotH)
            ])

            // quiet hour columns, the current one marked
            Repeater {
                model: 24
                delegate: Rectangle {
                    required property int index
                    x: index * chart.colW + 1.5
                    width: chart.colW - 3
                    y: 0
                    height: chart.plotH
                    radius: Math.min(width / 2, Appearance.rounding.verysmall)
                    color: index === root.nowHour ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                    opacity: index === root.nowHour ? 0.9 : 0.55
                }
            }

            Shape {
                anchors.fill: parent
                visible: chart.points.length >= 2
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.22)
                    PathPolyline { path: chart.area }
                }
                ShapePath {
                    strokeColor: Appearance.colors.colPrimary
                    strokeWidth: 3
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline { path: chart.points }
                }
            }

            // hours that charged, as ticks along the floor
            Repeater {
                model: 24
                delegate: Rectangle {
                    required property int index
                    readonly property var bucket: root.hours[index]
                    visible: !!bucket && bucket.charging > 300
                    x: index * chart.colW + 3
                    width: chart.colW - 6
                    height: 6
                    y: chart.plotH - height - 4
                    radius: 3
                    color: Appearance.colors.colTertiary
                }
            }

            // live dot
            Rectangle {
                visible: root.hasHistory
                width: 14
                height: 14
                radius: 7
                x: chart.xOf(root.nowHour) - 7
                y: chart.yOf(Battery.percent) - 7
                color: Appearance.colors.colPrimary
                Rectangle {
                    anchors.centerIn: parent
                    width: 6
                    height: 6
                    radius: 3
                    color: Appearance.colors.colOnPrimary
                }
            }

            Repeater {
                model: [0, 6, 12, 18, 23]
                delegate: StyledText {
                    required property int modelData
                    x: Math.max(0, Math.min(chart.width - width, chart.xOf(modelData) - width / 2))
                    y: chart.plotH + 6
                    text: modelData === 23 ? "24" : String(modelData).padStart(2, "0")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }

            // empty state over the quiet columns
            StyledText {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -chart.padBottom / 2
                visible: !root.hasHistory
                width: Math.min(parent.width - 32, 320)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.sampling ? Translation.tr("Nothing recorded yet today") : Translation.tr("Settings → App Usage records the battery beside your apps")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        // figures
        RowLayout {
            Layout.fillWidth: true
            visible: root.hasHistory
            spacing: 8

            Figure {
                caption: Translation.tr("On battery")
                value: root.onBatterySecs > 0 ? root.fmtHours(root.onBatterySecs) : "—"
            }
            Figure {
                caption: Translation.tr("Spent")
                value: isNaN(root.spentPct) || root.spentPct < 0.5 ? "—" : `−${Math.round(root.spentPct)}%`
            }
            Figure {
                caption: Translation.tr("Charged")
                value: isNaN(root.gainedPct) || root.gainedPct < 0.5 ? "—" : `+${Math.round(root.gainedPct)}%`
            }
            Figure {
                caption: Translation.tr("Average draw")
                value: isNaN(root.avgWatts) ? "—" : `${root.avgWatts.toFixed(1)} W`
            }
        }
    }

    component Figure: ColumnLayout {
        id: fig
        property string caption
        property string value
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            text: fig.caption
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: Appearance.colors.colOnSurfaceVariant
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            text: fig.value
            font.family: Appearance.font.family.main
            font.variableAxes: ({ "wght": 720, "wdth": 70, "ROND": 100 })
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
            elide: Text.ElideRight
        }
    }
}
