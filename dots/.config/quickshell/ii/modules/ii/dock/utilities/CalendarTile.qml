import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "CalendarAgenda.js" as CalendarAgenda

/**
 * Calendar. Square: the date is the icon — the weekday in wide capitals on
 * top, the day in tall condensed digits. When something starts within 15
 * minutes (or is on now) the tile turns primary. Wide: the same date block,
 * then the next appointment and how far it is, with its calendar colour as a
 * bar. The panel holds the whole day.
 */
UtilityTile {
    id: tile

    readonly property date now: DateTime.clock.date
    readonly property var events: CalendarService.visibleEvents ?? []
    readonly property var next: CalendarAgenda.upcoming(tile.events, tile.now, 1, 7)
    readonly property var nextItem: tile.next.length > 0 ? tile.next[0] : null
    readonly property int leftToday: CalendarAgenda.dayEvents(tile.events, tile.now)
        .filter(item => !item.allDay && item.end > tile.now).length
    readonly property string timeFormat: Config.options?.time?.format ?? "hh:mm"
    readonly property bool soon: tile.nextItem !== null
        && (CalendarAgenda.isHappening(tile.nextItem, tile.now) || tile.nextItem.start - tile.now < 15 * 60000)
    readonly property string weekday: Qt.formatDate(tile.now, "ddd").replace(".", "")

    surfaceColor: tile.soon ? ClockStyle.colPrimaryContainer : ClockStyle.colSurfaceHigh
    contentColor: tile.soon ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface

    function whenText(item) {
        const relative = CalendarAgenda.relative(item, tile.now, s => Translation.tr(s));
        const clock = Qt.formatDateTime(item.start, tile.timeFormat);
        if (relative === Translation.tr("Now"))
            return relative + " · " + Translation.tr("until %1").arg(Qt.formatDateTime(item.end, tile.timeFormat));
        return relative.length > 0 ? relative + " · " + clock : Qt.formatDateTime(item.start, "ddd ") + clock;
    }

    tooltipText: tile.nextItem
        ? tile.nextItem.event.content + " · " + tile.whenText(tile.nextItem)
        : Qt.formatDate(tile.now, "dddd, d MMMM")
    panelWidth: 360
    panelSubtitle: Qt.formatDate(tile.now, "dddd, d MMMM")

    // ── The date block, shared ──────────────────────────────────────────
    Item {
        id: dateBlock
        width: tile.wide ? tile.badgeSize + tile.pad : tile.width
        height: tile.height

        ColumnLayout {
            anchors.centerIn: parent
            spacing: -Math.round(tile.side * 0.06)
            TileCaption {
                Layout.alignment: Qt.AlignHCenter
                text: tile.weekday
                color: tile.soon ? tile.contentColor : ClockStyle.colPrimary
                font.pixelSize: Math.max(8, Math.round(tile.height * 0.19))
            }
            TileValue {
                Layout.alignment: Qt.AlignHCenter
                text: String(tile.now.getDate())
                color: tile.contentColor
                font.pixelSize: Math.round(tile.height * 0.5)
            }
        }
    }

    // ── Wide: the next appointment ──────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: dateBlock.width
        anchors.rightMargin: tile.pad * 2
        anchors.topMargin: tile.pad
        anchors.bottomMargin: tile.pad
        visible: tile.wide
        spacing: tile.pad

        Rectangle {
            Layout.fillHeight: true
            Layout.topMargin: Math.round(tile.pad * 0.5)
            Layout.bottomMargin: Math.round(tile.pad * 0.5)
            implicitWidth: Math.max(3, Math.round(tile.height * 0.07))
            radius: width / 2
            color: tile.nextItem ? (tile.nextItem.event.color ?? ClockStyle.colPrimary) : ColorUtils.applyAlpha(tile.contentColor, 0.2)
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            TileText {
                Layout.fillWidth: true
                text: tile.nextItem ? tile.nextItem.event.content
                    : CalendarService.khalAvailable ? Translation.tr("Free") : Translation.tr("No calendar")
                color: tile.contentColor
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Math.round(tile.height * 0.3)
                elide: Text.ElideRight
            }
            TileCaption {
                Layout.fillWidth: true
                text: tile.nextItem ? tile.whenText(tile.nextItem)
                    : CalendarService.khalAvailable ? Translation.tr("Nothing else this week") : Translation.tr("Connect one in Settings")
                color: tile.captionColor
                font.pixelSize: tile.captionSize
            }
        }
    }
}
