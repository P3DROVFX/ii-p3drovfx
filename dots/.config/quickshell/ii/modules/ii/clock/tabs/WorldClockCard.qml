import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** One city: its name, how far it is from here, and its time — day or night at a glance. */
Rectangle {
    id: root

    required property int clockIndex
    property date now: new Date()
    property bool showSeconds: false
    property int count: 1

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property color colCard: ClockStyle.colSurfaceHigh
    readonly property color colCardHover: ClockStyle.colSurfaceHover
    readonly property color colDayBadge: ClockStyle.colTertiaryContainer
    readonly property color colOnDayBadge: ClockStyle.colOnTertiaryContainer
    readonly property color colNightBadge: ClockStyle.colSecondaryContainer
    readonly property color colOnNightBadge: ClockStyle.colOnSecondaryContainer
    readonly property real badgeSize: ClockStyle.worldCardHeight * 0.52
    readonly property real timeSize: Math.min(ClockStyle.worldCardHeight * 0.52, root.width * 0.14)

    readonly property var entry: WorldClockService.clocks[root.clockIndex] ?? ({})
    readonly property string tz: String(root.entry.tz ?? "")
    readonly property bool night: WorldClockService.isNight(root.tz, root.now)
    readonly property string offsetText: WorldClockService.relativeOffsetLabel(root.tz, root.now)

    signal renameRequested()

    implicitHeight: ClockStyle.worldCardHeight
    radius: ClockStyle.radiusLarge
    color: cardHover.hovered ? root.colCardHover : root.colCard

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: cardHover
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: ClockStyle.gapLarge
            rightMargin: ClockStyle.cardPadding
        }
        spacing: ClockStyle.gapLarge

        Item {
            implicitWidth: root.badgeSize
            implicitHeight: root.badgeSize

            MaterialShape {
                anchors.fill: parent
                shapeString: root.night ? "Cookie4Sided" : "Sunny"
                color: root.night ? root.colNightBadge : root.colDayBadge
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.night ? "dark_mode" : "light_mode"
                iconSize: root.badgeSize * 0.46
                fill: 1
                color: root.night ? root.colOnNightBadge : root.colOnDayBadge
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: WorldClockService.displayName(root.entry)
                elide: Text.ElideRight
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: ClockStyle.textLarge + 1
                color: ClockStyle.colOnSurface
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    const parts = [WorldClockService.dayRelationLabel(root.tz, root.now)];
                    parts.push(root.offsetText.length > 0 ? root.offsetText : Translation.tr("Same time"));
                    const abbreviation = WorldClockService.abbreviation(root.tz);
                    if (abbreviation.length > 0 && !/^[+-]/.test(abbreviation))
                        parts.push(abbreviation);
                    return parts.join(" · ");
                }
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }

        RowLayout {
            spacing: 0
            visible: !cardHover.hovered || root.width > ClockStyle.worldCardMinWidth * 1.4

            StyledText {
                text: WorldClockService.formatHourMinute(root.tz, root.now)
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigitsBold
                font.pixelSize: root.timeSize
                color: ClockStyle.colOnSurface
            }

            StyledText {
                visible: root.showSeconds
                Layout.alignment: Qt.AlignBottom
                Layout.bottomMargin: root.timeSize * 0.12
                text: ":" + WorldClockService.formatDate(root.tz, root.now, "ss")
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigits
                font.pixelSize: root.timeSize * 0.42
                color: ClockStyle.colSubtext
            }

            StyledText {
                visible: text.length > 0
                Layout.alignment: Qt.AlignBottom
                Layout.leftMargin: ClockStyle.gapTiny
                Layout.bottomMargin: root.timeSize * 0.12
                text: WorldClockService.meridiem(root.tz, root.now)
                font.pixelSize: root.timeSize * 0.32
                color: ClockStyle.colSubtext
            }
        }

        RowLayout {
            spacing: 0
            visible: opacity > 0
            opacity: cardHover.hovered ? 1 : 0
            Layout.preferredWidth: cardHover.hovered ? implicitWidth : 0

            Behavior on opacity {
                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
            }

            ClockIconButton {
                symbol: "arrow_upward"
                size: ClockStyle.iconButton - 4
                enabled: root.clockIndex > 0
                tooltip: Translation.tr("Move up")
                onClicked: WorldClockService.moveClock(root.clockIndex, root.clockIndex - 1)
            }
            ClockIconButton {
                symbol: "arrow_downward"
                size: ClockStyle.iconButton - 4
                enabled: root.clockIndex < root.count - 1
                tooltip: Translation.tr("Move down")
                onClicked: WorldClockService.moveClock(root.clockIndex, root.clockIndex + 1)
            }
            ClockIconButton {
                symbol: "edit"
                size: ClockStyle.iconButton - 4
                tooltip: Translation.tr("Rename")
                onClicked: root.renameRequested()
            }
            ClockIconButton {
                symbol: "delete"
                size: ClockStyle.iconButton - 4
                colIcon: ClockStyle.colError
                tooltip: Translation.tr("Remove")
                onClicked: WorldClockService.removeClock(root.clockIndex)
            }
        }
    }
}
