pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common
import qs.modules.common.functions

/**
 * The level bar of the laptop battery tile, horizontal or standing up.
 *
 * The corners follow the bar's own thickness rather than a fixed token, so a bar in a
 * 2x1 tile is a rounded strip and a bar in a 4x4 one is the thick rounded block of the
 * design - a tile half the size does not keep the same 24 px corner.
 */
Item {
    id: root

    /** 0..1 */
    required property real level
    /** Fills from the bottom instead of from the left. */
    property bool vertical: false
    property color fillColor: Appearance.colors.colPrimary
    property color trackColor: ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.10)
    /** The notch cut into the middle of the filled part. */
    property color gripColor: ColorUtils.applyAlpha(Appearance.colors.colLayer2, 0.55)

    readonly property real thickness: root.vertical ? root.width : root.height
    readonly property real barRadius: Config.options.appearance.sharpMode ? 0
        : Math.max(3, Math.min(root.thickness * 0.32, Appearance.rounding.large,
            root.width / 2, root.height / 2))
    readonly property real span: root.vertical ? root.height : root.width
    // Never shorter than its own rounding, or the fill collapses into a lens.
    readonly property real fillLength: root.level <= 0 ? 0
        : Math.max(root.barRadius * 2, root.span * Math.max(0, Math.min(1, root.level)))

    Rectangle {
        anchors.fill: parent
        radius: root.barRadius
        color: root.trackColor
    }

    Rectangle {
        id: fill

        x: 0
        y: root.vertical ? root.height - root.fillLength : 0
        width: root.vertical ? root.width : root.fillLength
        height: root.vertical ? root.fillLength : root.height
        radius: root.barRadius
        color: root.fillColor

        Behavior on width {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: root.vertical ? Math.round(fill.width * 0.30) : Math.max(2, Math.round(root.thickness * 0.05))
            height: root.vertical ? Math.max(2, Math.round(root.thickness * 0.05)) : Math.round(fill.height * 0.30)
            radius: Appearance.rounding.full
            color: root.gripColor
            visible: (root.vertical ? fill.height : fill.width) > 44 && root.thickness >= 18
        }
    }
}
