import qs.modules.common
import QtQuick

/**
 * Recreation of GTK revealer. Expects one single child.
 */
Item {
    id: root
    property bool reveal
    property bool vertical: false
    clip: true

    implicitWidth: (reveal || vertical) ? childrenRect.width : 0
    implicitHeight: (reveal || !vertical) ? childrenRect.height : 0
    visible: reveal || (implicitWidth > 0 && !vertical) || (implicitHeight > 0 && vertical)
    
    // Scale and opacity for smooth entry/exit
    property real revealValue: reveal ? 1.0 : 0.0
    Behavior on revealValue {
        NumberAnimation {
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Easing.OutQuint
        }
    }

    onChildrenChanged: {
        for (var i = 0; i < children.length; i++) {
            children[i].scale = Qt.binding(() => root.revealValue);
            children[i].opacity = Qt.binding(() => root.revealValue);
        }
    }

    Behavior on implicitWidth {
        enabled: !vertical
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on implicitHeight {
        enabled: vertical
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
}
