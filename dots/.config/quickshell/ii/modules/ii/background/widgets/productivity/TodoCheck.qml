import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/*
 * A task's check. The shape is the state: a circle on the track while open,
 * a cookie on hover, a sunny burst in the accent with the check once done.
 */
Item {
    id: root

    property bool checked: false
    property bool interactive: true
    property real size: 30
    property color colTrack: WidgetColorScheme.pillBgColor
    property color colIdleContent: WidgetColorScheme.subtextColorOnBg
    property color colDone: WidgetColorScheme.accentColor
    property color colOnDone: WidgetColorScheme.onAccentColor
    signal toggled

    implicitWidth: root.size
    implicitHeight: root.size

    MaterialShape {
        anchors.fill: parent
        shape: root.checked ? MaterialShape.Shape.Sunny
            : (hover.hovered && root.interactive ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle)
        color: root.checked ? root.colDone
            : (hover.hovered && root.interactive ? ColorUtils.mix(root.colIdleContent, root.colTrack, 0.16) : root.colTrack)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: "check"
        iconSize: Math.round(root.size * 0.6)
        fill: 1
        color: root.checked ? root.colOnDone : root.colIdleContent
        opacity: root.checked ? 1 : (hover.hovered && root.interactive ? 0.7 : 0)
        scale: root.checked ? 1 : 0.6

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }
    }

    HoverHandler {
        id: hover
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.interactive
        onTapped: root.toggled()
    }
}
