pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common
import qs.modules.common.widgets

/**
 * Dot power button.
 *
 * A control you use once a day should not hold a permanent glyph's worth of
 * weight in the bar. At rest this is a dot; the symbol only appears when you go
 * for it, and stays while the session screen is up.
 *
 *   rest   a small dot in the bar's own ink
 *   hover  the dot opens out into the power symbol
 *   open   the symbol stays, in the accent
 *
 * The hit area never changes — only the drawing inside it does — so the button
 * is exactly as easy to click as the other two, and the bar cannot reflow when
 * the pointer crosses it.
 */
Item {
    id: root

    property bool vertical: false

    readonly property real side: (root.vertical
        ? Appearance.sizes.verticalBarWidth
        : Appearance.sizes.baseBarHeight) - 8

    implicitWidth: root.side
    implicitHeight: root.side

    readonly property bool open: GlobalStates.sessionOpen

    readonly property real dotSize: Math.max(4, Math.round(root.side * 0.22))
    readonly property real glyphSize: Math.round(root.side * 0.6)

    // One driver for the whole reveal. Two — a dot animation and a glyph
    // animation — would let the dot still be leaving while the glyph is already
    // there, and the button would read as two objects overlapping.
    readonly property real revealTarget: (root.open || mouseArea.containsMouse) ? 1.0 : 0.0
    property real reveal: root.revealTarget

    Behavior on reveal {
        enabled: !Appearance.reducedMotion
        NumberAnimation {
            duration: Math.round(240 * Appearance.animMultiplier)
            easing.type: Easing.OutCubic
        }
    }

    // A straight crossfade leaves a half-faded dot sitting inside a half-faded
    // glyph in the middle of the transition. Staggering the two halves of the
    // one driver hands the shape over instead: the dot is gone before the
    // symbol is really there.
    readonly property real dotOpacity: Math.max(0, Math.min(1, 1 - root.reveal * 1.7))
    readonly property real glyphOpacity: Math.max(0, Math.min(1, (root.reveal - 0.35) / 0.65))

    readonly property color colInk: root.open
        ? Appearance.colors.colPrimary
        : (mouseArea.containsMouse ? Appearance.colors.colOnLayer0 : Appearance.colors.colOnLayer1)

    // The dot grows towards the symbol it is about to become, so the two share
    // a size at the moment they trade places.
    Rectangle {
        id: dot
        anchors.centerIn: parent
        width: root.dotSize + (root.glyphSize - root.dotSize) * root.reveal
        height: dot.width
        radius: Appearance.rounding.full
        color: root.colInk
        opacity: root.dotOpacity * 0.75
        visible: opacity > 0.001

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(dot)
        }
    }

    MaterialSymbol {
        id: glyph
        anchors.centerIn: parent
        text: "power_settings_new"
        iconSize: root.glyphSize
        fill: root.open ? 1 : 0
        color: root.colInk
        opacity: root.glyphOpacity
        visible: opacity > 0.001

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(glyph)
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: GlobalStates.sessionOpen = !GlobalStates.sessionOpen
    }
}
