pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One focus schedule: its window of the day in condensed digits, the days it runs, the
 * apps it holds back, and whether it is on right now. A running schedule takes the
 * secondary colour pair; an idle one sits on the pane.
 */
Rectangle {
    id: root

    required property var schedule
    property bool editing: false
    property real layoutWidth: root.width

    signal editRequested()
    signal deleteRequested()
    signal toggleRequested(bool on)

    readonly property bool enabledRule: root.schedule?.enabled !== false
    readonly property bool running: ScreenTimeLimits.scheduleActive(root.schedule)
    readonly property bool lifted: root.running && ScreenTimeLimits.isIgnored("s:" + (root.schedule?.id ?? ""))
    readonly property int minutesAway: ScreenTimeLimits.scheduleMinutesAway(root.schedule)
    readonly property var keys: root.schedule?.keys ?? []

    readonly property color colContainer: root.running ? ClockStyle.colTertiaryContainer : ClockStyle.colIdleCard
    readonly property color colContainerHover: root.running ? ClockStyle.colTertiaryContainerHover : ClockStyle.colIdleCardHover
    readonly property color colContent: root.running ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnSurface
    readonly property real digitSize: Math.round(Math.max(30, Math.min(52, (root.layoutWidth - ClockStyle.cardPadding * 2) / 6.2)))
    readonly property bool engaged: cardHover.hovered || editButton.activeFocus || deleteButton.activeFocus

    function awayText(): string {
        if (!root.enabledRule || root.minutesAway < 0)
            return Translation.tr("Off");
        const span = ScreenTimeLimits.formatMinutes(root.minutesAway);
        if (root.lifted)
            return Translation.tr("Lifted for now");
        return root.running ? Translation.tr("On now · ends in %1").arg(span) : Translation.tr("Starts in %1").arg(span);
    }

    radius: ClockStyle.radiusCard
    color: root.editing ? ClockStyle.colSecondaryContainer : root.engaged ? root.colContainerHover : root.colContainer
    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: cardHover
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.editRequested()
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: ClockStyle.cardPadding
            topMargin: ClockStyle.gapLarge
            rightMargin: ClockStyle.gapLarge
        }
        spacing: ClockStyle.gapSmall

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            spacing: ClockStyle.gapSmall

            MaterialShapeWrappedMaterialSymbol {
                text: root.schedule?.allApps ? "do_not_disturb_on" : "bedtime"
                iconSize: 18
                padding: 8
                shape: MaterialShape.Shape.Cookie6Sided
                color: root.running ? ClockStyle.colTertiary : ClockStyle.colSecondaryContainer
                colSymbol: root.running ? ClockStyle.colOnTertiary : ClockStyle.colOnSecondaryContainer
                fill: 1
                rotation: root.running ? 30 : 0
                Behavior on rotation {
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: String(root.schedule?.name ?? "").length > 0 ? root.schedule.name : Translation.tr("Focus time")
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textNormal + 1
                font.weight: Font.DemiBold
                color: root.colContent
            }

            MaterialSymbol {
                visible: root.schedule?.strict === true
                text: "lock"
                iconSize: ClockStyle.iconSmall
                fill: 1
                color: root.colContent
            }

            Item {
                id: actionSlot
                property real revealProgress: root.engaged ? 1 : 0

                Layout.preferredWidth: (actionRow.implicitWidth + 4) * actionSlot.revealProgress
                Layout.preferredHeight: actionRow.implicitHeight
                clip: true

                Behavior on revealProgress {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: actionRow
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    opacity: actionSlot.revealProgress
                    enabled: root.engaged

                    ClockCardAction {
                        id: editButton
                        symbol: "edit"
                        tip: Translation.tr("Edit schedule")
                        colContent: root.colContent
                        onClicked: root.editRequested()
                    }
                    ClockCardAction {
                        id: deleteButton
                        symbol: "delete"
                        tip: Translation.tr("Delete")
                        danger: true
                        onClicked: root.deleteRequested()
                    }
                }
            }
        }

        // The window of the day, start over end in the clock's digits.
        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            StyledText {
                text: root.schedule?.start ?? "--:--"
                font.family: ClockStyle.fontMain
                font.variableAxes: root.enabledRule ? ClockStyle.axesDigitsBold : ClockStyle.axesDigits
                font.pixelSize: root.digitSize
                color: root.colContent
            }

            MaterialSymbol {
                text: "arrow_forward"
                iconSize: Math.round(root.digitSize * 0.42)
                color: root.colContent
                opacity: 0.7
            }

            StyledText {
                text: root.schedule?.end ?? "--:--"
                font.family: ClockStyle.fontMain
                font.variableAxes: root.enabledRule ? ClockStyle.axesDigitsBold : ClockStyle.axesDigits
                font.pixelSize: root.digitSize
                color: root.colContent
            }

            Item {
                Layout.fillWidth: true
            }
        }

        // The days it runs, in the locale's week order. Read-only, so drawn here
        // rather than with the clock's chips, which fade when not interactive.
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: 7

                Rectangle {
                    id: dayDot
                    required property int index
                    readonly property int day: (((Config.options?.time?.firstDayOfWeek ?? 6) + 1) % 7 + dayDot.index) % 7
                    readonly property bool on: (root.schedule?.days ?? [])[dayDot.day] !== false
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: 13
                    color: dayDot.on ? root.colContent : ColorUtils.applyAlpha(root.colContent, 0.1)

                    StyledText {
                        anchors.centerIn: parent
                        text: Qt.locale().dayName(dayDot.day, Locale.NarrowFormat)
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.Bold
                        color: dayDot.on ? root.colContainer : ColorUtils.applyAlpha(root.colContent, 0.6)
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            // Which apps: every one, or up to four icons and a count.
            Rectangle {
                visible: root.schedule?.allApps === true
                implicitWidth: allRow.implicitWidth + 20
                implicitHeight: 30
                radius: 15
                color: ColorUtils.applyAlpha(root.colContent, 0.1)

                RowLayout {
                    id: allRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: "apps"
                        iconSize: ClockStyle.iconSmall
                        color: root.colContent
                    }
                    StyledText {
                        text: Translation.tr("All apps")
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.DemiBold
                        color: root.colContent
                    }
                }
            }

            Repeater {
                model: root.schedule?.allApps ? 0 : Math.min(4, root.keys.length)

                LimitsAppIcon {
                    required property int index
                    size: 24
                    appKey: root.keys[index] ?? ""
                    colFallback: root.colContent
                }
            }

            StyledText {
                visible: !root.schedule?.allApps && root.keys.length > 4
                text: "+" + String(root.keys.length - 4)
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.Bold
                color: root.colContent
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: root.awayText()
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.DemiBold
                color: root.colContent
                opacity: 0.85
            }

            StyledSwitch {
                sizeScale: 0.9
                checked: root.enabledRule
                checkable: false
                activeColor: root.running ? root.colContent : ClockStyle.colPrimary
                activeThumbColor: root.running ? root.colContainer : ClockStyle.colOnPrimary
                onClicked: root.toggleRequested(!root.enabledRule)
            }
        }
    }
}
