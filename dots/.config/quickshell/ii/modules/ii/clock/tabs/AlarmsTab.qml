pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Alarms: one dense grid of tiles. The next alarm leads it as a wide hero tile, every
 * alarm follows as a tile sized to the room there is — five across on a desktop window,
 * one on a narrow one — and the timetable's suggestions close the page. Editing opens the
 * side sheet, so the grid you are editing stays in sight.
 */
Item {
    id: root

    property date now: new Date()
    property bool compact: false
    property bool wide: false
    property ClockSidePanel panels: null

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real gridGap: ClockStyle.gap
    // Decided on the settled width (see ClockAppContent.pageLayoutWidth), stretched on the
    // live one: the column count and the tile height hold still while a sheet slides in.
    property real layoutWidth: root.width
    readonly property real contentWidth: root.width - ClockStyle.gapTiny * 2
    readonly property real contentLayoutWidth: root.layoutWidth - ClockStyle.gapTiny * 2
    readonly property int columns: Math.max(1, Math.floor((root.contentLayoutWidth + root.gridGap) / (ClockStyle.alarmCardMinWidth + root.gridGap)))
    readonly property real tileLayoutWidth: (root.contentLayoutWidth - root.gridGap * (root.columns - 1)) / root.columns
    readonly property real tileWidth: Math.floor((root.contentWidth - root.gridGap * (root.columns - 1)) / root.columns)
    readonly property real tileHeight: Math.round(Math.max(210, Math.min(280, root.tileLayoutWidth * 0.82)))
    readonly property int heroSpan: Math.min(2, root.columns)
    readonly property bool showTimetable: (Config.options.clockApp?.showTimetableEvents ?? true) && CalendarService.khalAvailable

    readonly property int alarmCount: AlarmService.alarms.length
    readonly property var next: AlarmService.nextAlarm(root.now)
    readonly property int editingIndex: root.panels?.isShowing(editorSheet) ? (root.panels.current?.alarmIndex ?? -2) : -2
    readonly property string pageSubtitle: root.next
        ? Translation.tr("Next alarm %1").arg(ClockFormat.relativeDay(root.next.at, root.now) + " · " + ClockFormat.dateTime(root.next.at))
        : Translation.tr("No alarms on")

    function openEditor(index: int): void {
        root.panels?.show(editorSheet, { alarmIndex: index });
    }

    function primaryAction(): void {
        root.openEditor(-1);
    }

    Component {
        id: editorSheet
        AlarmEditorSheet {}
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + ClockStyle.fabClearance
        clip: true
        visible: root.alarmCount > 0

        ColumnLayout {
            id: content
            x: ClockStyle.gapTiny
            y: ClockStyle.gapTiny
            width: root.contentWidth
            spacing: ClockStyle.gapHuge

            // Every tile carries its own width: left to stretch, a layout gave the columns
            // with tiles all the slack, so a lone alarm swelled to the full row.
            Flow {
                id: grid
                Layout.preferredWidth: Math.max(root.contentWidth, root.contentLayoutWidth)
                spacing: root.gridGap

                // Tiles keep their settled size and the flow animates where they land, so a
                // sheet opening or the rail folding re-deals the tiles instead of
                // stretching them frame by frame.
                move: Transition {
                    enabled: !ClockStyle.reducedMotion
                    NumberAnimation {
                        properties: "x,y"
                        duration: ClockStyle.motionDefault.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
                    }
                }

                // ── Next alarm ──────────────────────────────────────────
                Rectangle {
                    id: hero
                    width: Math.floor(root.tileLayoutWidth * root.heroSpan + root.gridGap * (root.heroSpan - 1))
                    height: root.tileHeight
                    Behavior on width {
                        enabled: !ClockStyle.reducedMotion
                        animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                    }
                    radius: ClockStyle.radiusCard
                    color: root.next ? ClockStyle.colPrimary : ClockStyle.colIdleCard

                    readonly property color colContent: root.next ? ClockStyle.colOnPrimary : ClockStyle.colOnIdleCard

                    Behavior on color {
                        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                    }

                    StaggeredEntrance {
                        index: 0
                        active: !ClockStyle.reducedMotion
                    }

                    // The tile's one ornament: a scalloped shape far larger than the tile,
                    // parked off its right edge so only an arc of it shows. It turns a
                    // quarter as the day moves on, not every frame. A plain clip would
                    // square off the tile's rounded corners, so the arc is cut by a mask of
                    // the tile itself (kept in the tree, so the window can die safely).
                    Item {
                        id: heroOrnament
                        anchors.fill: parent
                        visible: false

                        MaterialShape {
                            id: heroShape
                            width: Math.round(root.tileHeight * 1.9)
                            height: width
                            x: hero.width - width * 0.36
                            y: (hero.height - height) / 2
                            shapeString: "Cookie12Sided"
                            color: hero.colContent
                            rotation: (root.now.getHours() * 60 + root.now.getMinutes()) / 4
                        }
                    }

                    Rectangle {
                        id: heroMask
                        anchors.fill: parent
                        radius: hero.radius
                        visible: false
                        layer.enabled: true
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: heroOrnament
                        maskEnabled: true
                        maskSource: heroMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                        opacity: 0.1
                    }

                    ColumnLayout {
                        anchors {
                            fill: parent
                            margins: ClockStyle.cardPadding + 4
                        }
                        spacing: ClockStyle.gapSmall

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapSmall

                            MaterialShapeWrappedMaterialSymbol {
                                text: root.next ? "alarm" : "alarm_off"
                                iconSize: 20
                                padding: 10
                                shape: MaterialShape.Shape.Cookie7Sided
                                color: hero.colContent
                                colSymbol: root.next ? ClockStyle.colPrimary : ClockStyle.colIdleCard
                                fill: 1
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.next ? Translation.tr("Next alarm") : Translation.tr("All alarms are off")
                                font.pixelSize: ClockStyle.textNormal
                                font.weight: Font.DemiBold
                                color: hero.colContent
                                elide: Text.ElideRight
                            }

                            ClockButton {
                                visible: root.next !== null && (root.next.alarm.days ?? []).includes(true)
                                variant: "tonal"
                                symbol: "event_busy"
                                label: Translation.tr("Skip")
                                iconOnly: root.tileLayoutWidth * root.heroSpan < 420
                                onClicked: AlarmService.skipNext(root.next.index)
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.next ? AlarmService.untilText(root.next.alarm, root.now) : Translation.tr("Turn one on to wake up on time")
                            elide: Text.ElideRight
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            font.family: ClockStyle.fontTitle
                            font.variableAxes: ClockStyle.axesTitle
                            Layout.rightMargin: heroShape.width * 0.12
                            font.pixelSize: Math.round(Math.max(ClockStyle.textTitle, Math.min(root.tileHeight * 0.13, (root.tileLayoutWidth * root.heroSpan) * 0.055)))
                            color: hero.colContent
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.next !== null
                            text: root.next
                                ? (String(root.next.alarm.label ?? "") || Translation.tr("Alarm")) + " · "
                                    + ClockFormat.relativeDay(root.next.at, root.now) + " " + ClockFormat.dateTime(root.next.at)
                                : ""
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textNormal
                            color: hero.colContent
                            opacity: 0.85
                        }
                    }
                }

                // ── Alarms ──────────────────────────────────────────────
                Repeater {
                    model: root.alarmCount

                    AlarmCard {
                        id: card
                        required property int index
                        width: Math.floor(root.tileLayoutWidth)
                        height: root.tileHeight
                        Behavior on width {
                            enabled: !ClockStyle.reducedMotion
                            animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                        }
                        alarm: AlarmService.alarms[card.index] ?? ({})
                        alarmIndex: card.index
                        layoutWidth: root.tileLayoutWidth
                        now: root.now
                        editing: root.editingIndex === card.index
                        onEditRequested: root.openEditor(card.index)

                        StaggeredEntrance {
                            index: card.index + 1
                            step: ClockStyle.staggerStep
                            active: !ClockStyle.reducedMotion
                        }
                    }
                }
            }

            Loader {
                Layout.fillWidth: true
                active: root.showTimetable
                visible: active && (item?.visible ?? false)
                sourceComponent: TimetableEventsStrip {
                    now: root.now
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        visible: root.alarmCount === 0
        spacing: ClockStyle.gapHuge

        Item {
            Layout.fillHeight: true
        }

        ClockEmptyState {
            Layout.alignment: Qt.AlignHCenter
            symbol: "alarm_add"
            shape: "Cookie9Sided"
            title: Translation.tr("No alarms")
            subtitle: Translation.tr("Add one to wake up on time, or pick an event from your timetable.")
        }

        ClockButton {
            Layout.alignment: Qt.AlignHCenter
            variant: "filled"
            symbol: "alarm_add"
            label: Translation.tr("New alarm")
            onClicked: root.openEditor(-1)
        }

        Item {
            Layout.fillHeight: true
        }

        Loader {
            Layout.fillWidth: true
            Layout.margins: ClockStyle.gapTiny
            active: root.showTimetable && root.alarmCount === 0
            visible: active && (item?.visible ?? false)
            sourceComponent: TimetableEventsStrip {
                now: root.now
            }
        }
    }
}
