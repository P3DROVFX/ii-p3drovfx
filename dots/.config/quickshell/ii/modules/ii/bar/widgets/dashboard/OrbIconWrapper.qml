import QtQuick
import qs.modules.common

/**
 * One orb of the Orbs dashboard button: a circle around a single indicator.
 *
 * Two treatments, chosen by the user in the dashboard button's page:
 *
 *   filled    a solid disc, the indicator painted on it
 *   outline   a ring and nothing else, the bar showing through
 *
 * > [!NOTE]
 * > **Sanctioned border.** `border.width` is otherwise forbidden in this repo,
 * > and it is used here because the outline treatment *is* the request: a
 * > circle with no background has nothing left to draw it with. The exception
 * > stops at this file and the policies `outline` button; it opens no
 * > precedent for hierarchy-by-stroke anywhere else.
 */
Rectangle {
    id: root

    property bool vertical: false
    property bool outlined: false
    property color colOrb: "transparent"
    property real ringWidth: 2

    property real diameter: (vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.baseBarHeight) - 8

    implicitWidth: root.diameter
    implicitHeight: root.diameter
    radius: Appearance.rounding.full

    color: root.outlined ? "transparent" : root.colOrb
    border.width: root.outlined ? root.ringWidth : 0
    border.color: root.outlined ? root.colOrb : "transparent"

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(root)
    }
    Behavior on border.color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(root)
    }
    Behavior on border.width {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
}
