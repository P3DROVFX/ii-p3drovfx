import QtQuick
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * The card behind the Weight, Width and Stack type clocks, which can be turned
 * off. Without it the type sits straight on the wallpaper, optionally with a
 * soft shadow under it to keep it legible on busy pictures. Children go in
 * `content`, a box of the design size.
 */
Item {
    id: root

    property bool showBackground: true
    property bool textShadow: true
    default property alias content: contentLayer.data

    StyledRectangularShadow {
        target: card
        visible: root.showBackground && (Config.options.background.widgets.enableShadows ?? true)
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: root.showBackground ? WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor) : "transparent"

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    Item {
        id: contentLayer
        anchors.fill: parent
        layer.enabled: !root.showBackground && root.textShadow
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Appearance.colors.colShadow
            shadowBlur: 1.0
            shadowOpacity: 0.8
            shadowVerticalOffset: 2
            shadowHorizontalOffset: 0
        }
    }
}
