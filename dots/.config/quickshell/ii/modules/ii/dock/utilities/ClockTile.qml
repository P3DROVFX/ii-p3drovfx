import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Clock: the time, hh:mm, and nothing else — the number the tile is about in
 * tall, condensed digits (Google Sans Flex pulled narrow and heavy).
 * Square: hours over minutes, because stacking buys far larger digits than one
 * line in an icon-sized tile (the alarm tiles' rule). Wide: one line, the
 * colon in primary as the only accent. A click opens the Clock app.
 */
UtilityTile {
    id: tile

    readonly property date now: DateTime.clock.date
    readonly property bool twelveHour: ClockFormat.use12Hour
    readonly property string hours: {
        const h = tile.now.getHours();
        return tile.twelveHour ? String(((h + 11) % 12) + 1) : ClockFormat.pad(h);
    }
    readonly property string minutes: ClockFormat.pad(tile.now.getMinutes())
    readonly property string meridiem: tile.now.getHours() < 12 ? "AM" : "PM"
    // Narrower and heavier than the panels' digits: the tile is short, so the
    // glyphs gain their height by giving up width.
    readonly property var tallAxes: ({ "wght": 800, "wdth": 25, "ROND": 100 })

    surfaceColor: ClockStyle.colSurfaceHigh
    contentColor: ClockStyle.colOnSurface

    tooltipText: Qt.formatDate(tile.now, "dddd, d MMMM")
    panelSubtitle: ""

    function activate() {
        GlobalStates.openClockApp();
        return true;
    }

    // ── Square: hours over minutes ──────────────────────────────────────
    ColumnLayout {
        anchors.centerIn: parent
        visible: !tile.wide
        spacing: -Math.round(tile.side * 0.2)
        TileValue {
            Layout.alignment: Qt.AlignHCenter
            text: tile.hours
            color: tile.contentColor
            font.variableAxes: tile.tallAxes
            font.pixelSize: Math.round(tile.side * 0.48)
        }
        TileValue {
            Layout.alignment: Qt.AlignHCenter
            text: tile.minutes
            color: ClockStyle.colPrimary
            font.variableAxes: tile.tallAxes
            font.pixelSize: Math.round(tile.side * 0.48)
        }
    }

    // ── Wide: one line, as tall as the card allows ──────────────────────
    readonly property int wideSize: Math.round(tile.height * 0.9)
    // The font's ':' sits on the lowercase height, visibly under the middle
    // of tall condensed figures, so the colon is two dots centred on them.
    Row {
        id: wideRow
        anchors.centerIn: parent
        visible: tile.wide
        spacing: Math.round(tile.wideSize * 0.06)

        TileValue {
            id: hoursText
            text: tile.hours
            color: tile.contentColor
            font.variableAxes: tile.tallAxes
            font.pixelSize: tile.wideSize
        }
        Item {
            id: colon
            readonly property real dot: Math.max(3, Math.round(tile.wideSize * 0.11))
            // Centre of the figures, in the row's coordinates.
            // Figures stand on the baseline and rise ~0.72 em with these axes
            // (measured on the rendered digits: FontMetrics describes the
            // font's default instance, not the narrow heavy one drawn).
            readonly property real middle: hoursText.y + hoursText.baselineOffset - tile.wideSize * 0.36
            width: colon.dot
            height: hoursText.height
            Repeater {
                model: 2
                delegate: Rectangle {
                    required property int index
                    width: colon.dot
                    height: colon.dot
                    radius: colon.dot / 2
                    color: ClockStyle.colPrimary
                    y: colon.middle - colon.dot / 2 + (index === 0 ? -1 : 1) * Math.round(tile.wideSize * 0.16)
                }
            }
        }
        TileValue {
            text: tile.minutes
            color: tile.contentColor
            font.variableAxes: tile.tallAxes
            font.pixelSize: tile.wideSize
        }
        TileCaption {
            id: meridiemText
            visible: tile.twelveHour
            // On the figures' baseline (set by position: anchors inside a
            // Row cut the digits before).
            y: hoursText.baselineOffset - meridiemText.baselineOffset
            text: tile.meridiem
            color: tile.captionColor
            font.pixelSize: tile.captionSize
        }
    }
}
