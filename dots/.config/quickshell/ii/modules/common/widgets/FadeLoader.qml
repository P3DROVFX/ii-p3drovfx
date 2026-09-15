import QtQuick

import qs.modules.common

Loader {
    id: root
    property bool shown: true
    property alias fade: opacityBehavior.enabled
    property alias animation: opacityBehavior.animation
    // When keepAlive is false, the loader destroys its content when shown goes
    // false instead of keeping it resident at opacity 0. Use this for heavy
    // content that is only needed in specific modes (e.g. edit mode drawers)
    // to avoid holding objects in memory while they are never visible.
    property bool keepAlive: true
    opacity: shown ? 1 : 0
    visible: opacity > 0
    active: keepAlive ? true : shown

    Behavior on opacity {
        id: opacityBehavior
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
}
