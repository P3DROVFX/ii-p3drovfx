import QtQuick
import QtQuick.Layouts
import qs.modules.common

/**
 * Content that unfolds in place: its height and opacity follow `open`, and the content is
 * built only while it is open (or still closing), so a grid of canvases costs nothing
 * while the option that needs it is off.
 */
Item {
    id: root

    property bool open: false
    property alias sourceComponent: loader.sourceComponent
    readonly property alias item: loader.item

    Layout.preferredHeight: root.open && loader.item ? loader.item.implicitHeight : 0
    implicitHeight: Layout.preferredHeight
    clip: true
    opacity: root.open ? 1 : 0
    visible: opacity > 0

    Behavior on Layout.preferredHeight {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Loader {
        id: loader
        width: parent.width
        active: root.open || root.opacity > 0
    }
}
