pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Bedtime: when you mean to stop using the computer, the reminders around it, and how
 * the last two weeks actually went. Tonight on the left; the nights on the right, each
 * a bar hanging from the target line — up when you stopped early, down when late.
 */
Item {
    id: root

    property date now: new Date()
    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null

    readonly property var opts: Config.options.clockApp.bedtime
    readonly property bool enabledBedtime: root.opts?.enable ?? false
    readonly property bool sideBySide: root.layoutWidth >= ClockStyle.mediumMax - 80
    readonly property real tonightWidth: Math.round(Math.max(320, Math.min(root.layoutWidth * 0.36, 440)))
    readonly property int nightCount: 14

    // Re-read when the day or the records move on; AppStats fills estimates in as it loads.
    readonly property var nights: {
        root.now;
        BedtimeService.nights;
        AppStats.history;
        root.opts?.time;
        return BedtimeService.history(root.nightCount);
    }
    readonly property var recorded: root.nights.filter(n => n.applies && n.lastActive > 0)
    readonly property int streak: BedtimeService.streak(root.nights)
    readonly property int onTimeCount: root.recorded.filter(n => n.onTime).length
    readonly property int averageLate: root.recorded.length > 0
        ? Math.round(root.recorded.reduce((sum, n) => sum + n.lateMinutes, 0) / root.recorded.length) : 0

    readonly property string pageSubtitle: !root.enabledBedtime ? Translation.tr("Off")
        : BedtimeService.phase === "bedtime" ? Translation.tr("%1 past bedtime").arg(BedtimeService.formatLate(BedtimeService.minutesLate))
        : BedtimeService.phase === "windDown" ? Translation.tr("Winding down")
        : Translation.tr("Tonight at %1").arg(root.opts?.time ?? "23:30")
    readonly property bool actionAvailable: false

    function lateLabel(minutes: int): string {
        if (Math.abs(minutes) < 1)
            return Translation.tr("on time");
        const text = BedtimeService.formatLate(Math.abs(minutes));
        return minutes > 0 ? Translation.tr("%1 late").arg(text) : Translation.tr("%1 early").arg(text);
    }

    function pickTime(): void {
        const parts = String(root.opts.time ?? "23:30").split(":").map(Number);
        root.panels?.pickers?.pickTime(parts[0] || 0, parts[1] || 0, Translation.tr("Bedtime"),
            (hour, minute) => root.opts.time = ClockFormat.pad(hour) + ":" + ClockFormat.pad(minute));
    }

    function toggleDay(day: int): void {
        const days = Array.from(root.opts.days ?? [true, true, true, true, true, true, true]);
        days[day] = !days[day];
        root.opts.days = days;
    }

    Component.onCompleted: BedtimeService.loadUsage(root.nightCount)

    component Stat: Rectangle {
        id: stat
        property string symbol: ""
        property string value: ""
        property string caption: ""
        property color colAccent: ClockStyle.colPrimaryContainer
        property color colOnAccent: ClockStyle.colOnPrimaryContainer

        Layout.fillWidth: true
        implicitHeight: 76
        radius: Appearance.rounding.normal
        color: ClockStyle.colField

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            MaterialShapeWrappedMaterialSymbol {
                text: stat.symbol
                iconSize: 18
                padding: 9
                fill: 1
                shape: MaterialShape.Shape.Cookie9Sided
                color: stat.colAccent
                colSymbol: stat.colOnAccent
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: stat.value
                    elide: Text.ElideRight
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: ClockStyle.textTitle + 4
                    color: ClockStyle.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: stat.caption
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }
            }
        }
    }

    // ── Tonight ─────────────────────────────────────────────────────────
    component Tonight: Rectangle {
        id: tonight
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colPane
        implicitHeight: tonightColumn.implicitHeight + 28

        ColumnLayout {
            id: tonightColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 14
            }
            spacing: 10

            // The target, as big as the alarms' digits: the one number this tab is about.
            Rectangle {
                id: targetTile
                Layout.fillWidth: true
                implicitHeight: 150
                radius: ClockStyle.radiusCard
                color: !root.enabledBedtime ? ClockStyle.colField
                    : targetPointer.containsMouse ? ClockStyle.colPrimaryContainerHover : ClockStyle.colPrimaryContainer

                readonly property color colContent: root.enabledBedtime ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant

                Behavior on color {
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }

                MouseArea {
                    id: targetPointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickTime()
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: ClockStyle.cardPadding
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        MaterialShapeWrappedMaterialSymbol {
                            text: "bedtime"
                            iconSize: 18
                            padding: 9
                            fill: 1
                            shape: MaterialShape.Shape.Cookie7Sided
                            color: root.enabledBedtime ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer
                            colSymbol: root.enabledBedtime ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
                            rotation: targetPointer.containsMouse ? 20 : 0
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Bedtime")
                            font.pixelSize: ClockStyle.textNormal + 1
                            font.weight: Font.DemiBold
                            color: targetTile.colContent
                        }

                        StyledSwitch {
                            sizeScale: 1.15
                            checked: root.enabledBedtime
                            checkable: false
                            activeColor: ClockStyle.colPrimary
                            activeThumbColor: ClockStyle.colOnPrimary
                            onClicked: root.opts.enable = !root.opts.enable
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    RowLayout {
                        spacing: ClockStyle.gapSmall

                        StyledText {
                            text: {
                                const parts = ClockFormat.alarmParts(root.opts?.time ?? "23:30");
                                return parts.hours + ":" + parts.minutes;
                            }
                            font.family: ClockStyle.fontMain
                            font.variableAxes: root.enabledBedtime ? ClockStyle.axesDigitsBold : ClockStyle.axesDigits
                            font.pixelSize: 64
                            color: targetTile.colContent
                            animateChange: !ClockStyle.reducedMotion
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 10
                            Layout.fillWidth: true
                            text: root.pageSubtitle
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textNormal
                            color: targetTile.colContent
                            opacity: 0.8
                        }
                    }
                }
            }

            StyledText {
                Layout.topMargin: 4
                text: Translation.tr("Wind-down reminder")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: ClockStyle.colOnSurfaceVariant
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [0, 15, 30, 45, 60]

                    ClockFormChip {
                        required property int modelData
                        label: modelData === 0 ? Translation.tr("Off") : Translation.tr("%1 min before").arg(modelData)
                        selected: (root.opts?.windDownMinutes ?? 30) === modelData
                        onTriggered: root.opts.windDownMinutes = modelData
                    }
                }
            }

            StyledText {
                Layout.topMargin: 4
                text: Translation.tr("Remind me while I'm still up")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: ClockStyle.colOnSurfaceVariant
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [0, 10, 15, 30]

                    ClockFormChip {
                        required property int modelData
                        label: modelData === 0 ? Translation.tr("Never") : Translation.tr("Every %1 min").arg(modelData)
                        selected: (root.opts?.remindEveryMinutes ?? 15) === modelData
                        onTriggered: root.opts.remindEveryMinutes = modelData
                    }
                }
            }

            StyledText {
                Layout.topMargin: 4
                text: Translation.tr("Nights")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: ClockStyle.colOnSurfaceVariant
            }

            ClockDayChips {
                Layout.fillWidth: true
                chipSize: 38
                days: root.opts?.days ?? [true, true, true, true, true, true, true]
                onToggled: day => root.toggleDay(day)
            }

            ClockFormPicker {
                Layout.topMargin: 4
                symbol: "tune"
                shapeKind: MaterialShape.Shape.Cookie6Sided
                caption: Translation.tr("Modes & routines")
                value: Translation.tr("Use the Bedtime trigger to dim, mute or lock")
                onTriggered: GlobalStates.modesOpen = true
            }
        }
    }

    // ── Nights ──────────────────────────────────────────────────────────
    component Nights: Rectangle {
        id: nightsPane
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colPane

        // Three hours either side of the target fills the chart; later still clips.
        readonly property real spanMinutes: 180

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Last %1 nights").arg(root.nightCount)
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: ClockStyle.colOnSurface
                }

                StyledText {
                    visible: root.nights.some(n => n.estimated)
                    text: Translation.tr("Faded bars are estimated from Usage")
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }
            }

            // Stats
            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                Stat {
                    symbol: "local_fire_department"
                    value: String(root.streak)
                    caption: Translation.tr("nights on time in a row")
                }
                Stat {
                    symbol: "check_circle"
                    value: `${root.onTimeCount}/${root.recorded.length}`
                    caption: Translation.tr("nights on time")
                    colAccent: ClockStyle.colSecondaryContainer
                    colOnAccent: ClockStyle.colOnSecondaryContainer
                }
                Stat {
                    symbol: root.averageLate > BedtimeService.onTimeGraceMinutes ? "schedule" : "bedtime"
                    value: root.recorded.length > 0 ? (root.averageLate > 0 ? "+" : "") + root.averageLate + "m" : "—"
                    caption: Translation.tr("average vs. target")
                    colAccent: root.averageLate > BedtimeService.onTimeGraceMinutes ? ClockStyle.colErrorContainer : ClockStyle.colTertiaryContainer
                    colOnAccent: root.averageLate > BedtimeService.onTimeGraceMinutes ? ClockStyle.colOnErrorContainer : ClockStyle.colOnTertiaryContainer
                }
            }

            // Chart
            Item {
                id: chart
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 160

                readonly property real labelHeight: 40
                readonly property real plotHeight: chart.height - chart.labelHeight
                readonly property real zeroY: chart.plotHeight * 0.4
                readonly property real column: chart.width / Math.max(1, root.nights.length)
                property bool anyHovered: false

                function yFor(minutes) {
                    const clamped = Math.max(-nightsPane.spanMinutes * 0.66, Math.min(nightsPane.spanMinutes, minutes));
                    return chart.zeroY + clamped / nightsPane.spanMinutes * (chart.plotHeight - chart.zeroY - 8);
                }

                // Target line
                Rectangle {
                    x: 0
                    y: chart.zeroY - 1
                    width: chart.width
                    height: 2
                    radius: 1
                    color: ClockStyle.colPrimary
                    opacity: 0.6
                }

                StyledText {
                    x: 4
                    y: chart.zeroY - height - 4
                    text: Translation.tr("Target")
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colPrimary
                }

                Repeater {
                    model: root.nights

                    Item {
                        id: nightColumn
                        required property var modelData
                        required property int index
                        readonly property bool known: nightColumn.modelData.lastActive > 0 && nightColumn.modelData.applies
                        readonly property real barY: chart.yFor(nightColumn.modelData.lateMinutes)

                        x: nightColumn.index * chart.column
                        width: chart.column
                        height: chart.height

                        HoverHandler {
                            id: nightHover
                            onHoveredChanged: chart.anyHovered = hovered
                        }

                        Rectangle {
                            visible: nightColumn.known
                            readonly property real barTop: Math.min(chart.zeroY, nightColumn.barY)
                            readonly property real barBottom: Math.max(chart.zeroY, nightColumn.barY)
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(28, chart.column * 0.56)
                            y: barTop
                            height: Math.max(8, barBottom - barTop)
                            radius: Math.min(width / 2, Appearance.rounding.normal)
                            opacity: (nightColumn.modelData.estimated ? 0.45 : 1) * (nightHover.hovered || !chart.anyHovered ? 1 : 0.6)
                            color: nightColumn.modelData.onTime ? ClockStyle.colPrimary
                                : nightColumn.modelData.lateMinutes > 60 ? ClockStyle.colError : ClockStyle.colTertiary

                            Behavior on height {
                                animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                            }
                            Behavior on y {
                                animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                            }

                            StaggeredEntrance {
                                index: nightColumn.index
                                step: 24
                                active: !ClockStyle.reducedMotion
                            }
                        }

                        Rectangle {
                            visible: !nightColumn.known
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: chart.zeroY - 4
                            width: 8
                            height: 8
                            radius: 4
                            color: ClockStyle.colOutline
                            opacity: 0.6
                        }

                        ColumnLayout {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            spacing: 0

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Qt.locale().dayName(BedtimeService.parseKey(nightColumn.modelData.night).getDay(), Locale.NarrowFormat)
                                font.pixelSize: ClockStyle.textSmall
                                font.weight: Font.DemiBold
                                color: nightColumn.modelData.applies ? ClockStyle.colOnSurface : ClockStyle.colSubtext
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: nightColumn.known ? Qt.formatTime(new Date(nightColumn.modelData.lastActive), "HH:mm") : "—"
                                font.pixelSize: ClockStyle.textSmall - 1
                                color: ClockStyle.colSubtext
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: nightHover.hovered && nightColumn.known
                            text: Qt.locale().toString(BedtimeService.parseKey(nightColumn.modelData.night), "dddd, d MMM") + " · "
                                + Translation.tr("stopped at %1").arg(Qt.formatTime(new Date(nightColumn.modelData.lastActive), "HH:mm"))
                                + " · " + root.lateLabel(nightColumn.modelData.lateMinutes)
                                + (nightColumn.modelData.estimated ? " · " + Translation.tr("estimated") : "")
                        }
                    }
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.sideBySide
        sourceComponent: RowLayout {
            spacing: ClockStyle.paneGap

            StyledFlickable {
                id: tonightFlick
                Layout.preferredWidth: root.tonightWidth
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: tonightPane.implicitHeight
                clip: true

                Tonight {
                    id: tonightPane
                    width: tonightFlick.width
                }
            }

            Nights {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: !root.sideBySide
        sourceComponent: StyledFlickable {
            id: stackFlick
            contentWidth: width
            contentHeight: stack.implicitHeight + ClockStyle.gapHuge
            clip: true

            ColumnLayout {
                id: stack
                width: stackFlick.width
                spacing: ClockStyle.paneGap

                Tonight {
                    Layout.fillWidth: true
                }

                Nights {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 380
                }
            }
        }
    }
}
