pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.clock

/**
 * Default date widget — the classic fraction mark: day above the diagonal,
 * month below it.
 *
 * The original lived in `verticalBar/VerticalDateWidget.qml` and hardcoded the
 * vertical bar's width, so the horizontal bar rendered a 44px-wide slot around
 * a 24px glyph. This one measures itself per orientation and keeps the drawing
 * identical.
 */
Item {
    id: root

    property bool vertical: false

    readonly property string dayPart: DateTime.dayOfMonthPadded
    readonly property string monthPart: DateTime.monthNumberPadded

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : content.implicitWidth + 10
    implicitHeight: root.vertical ? content.implicitHeight : Appearance.sizes.baseBarHeight

    Item {
        // Boundaries for the date numbers. Kept slightly taller than wide so
        // the diagonal reads as a fraction bar and never as a square.
        id: content
        anchors.centerIn: parent
        implicitWidth: 24
        implicitHeight: 30

        Shape {
            id: diagonalLine
            property real padding: 4
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 1.2
                strokeColor: Appearance.colors.colSubtext
                fillColor: "transparent"
                startX: content.width - diagonalLine.padding
                startY: diagonalLine.padding

                PathLine {
                    x: diagonalLine.padding
                    y: content.height - diagonalLine.padding
                }
            }
        }

        StyledText {
            id: dayText
            anchors {
                top: parent.top
                left: parent.left
            }
            font.pixelSize: 13
            color: Appearance.colors.colOnLayer1
            text: root.dayPart
        }

        StyledText {
            id: monthText
            anchors {
                bottom: parent.bottom
                right: parent.right
            }
            font.pixelSize: 13
            color: Appearance.colors.colOnLayer1
            text: root.monthPart
        }
    }

    MouseArea {
        id: dateMouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow

        ClockWidgetPopup {
            compact: Config.options.bar.tooltips.compactPopups
            hoverTarget: dateMouseArea
        }
    }
}
