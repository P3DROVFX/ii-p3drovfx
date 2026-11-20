import QtQuick

/**
 * The slide-and-fade a text plays when its value changes: the old value slides
 * out by (-distanceX, -distanceY) while fading, the text is swapped, and the new
 * value slides in from (distanceX, distanceY). Used as the animation of a
 * `Behavior on text` (AnimatedStyledText, AnimatedMaterialSymbol); the empty
 * PropertyAction is where that Behavior writes the new text.
 *
 * It owns the Translate it moves and appends it to the host's transform list,
 * so a plain StyledText carries neither the animation nor the transform.
 */
SequentialAnimation {
    id: root

    required property Item host
    property real distanceX: 0
    property real distanceY: 6
    readonly property int stepDuration: 150

    readonly property Translate shift: Translate {}

    Component.onCompleted: {
        const list = [];
        for (let i = 0; i < root.host.transform.length; i++)
            list.push(root.host.transform[i]);
        list.push(root.shift);
        root.host.transform = list;
    }

    alwaysRunToEnd: true
    ParallelAnimation {
        NumberAnimation {
            target: root.shift
            property: "x"
            to: -root.distanceX
            duration: root.stepDuration
            easing.type: Easing.InSine
        }
        NumberAnimation {
            target: root.shift
            property: "y"
            to: -root.distanceY
            duration: root.stepDuration
            easing.type: Easing.InSine
        }
        NumberAnimation {
            target: root.host
            property: "opacity"
            to: 0
            duration: root.stepDuration
            easing.type: Easing.InSine
        }
    }
    PropertyAction {} // The text update lands here, between the slide out and the slide in
    PropertyAction {
        target: root.shift
        property: "x"
        value: root.distanceX
    }
    PropertyAction {
        target: root.shift
        property: "y"
        value: root.distanceY
    }
    ParallelAnimation {
        NumberAnimation {
            target: root.shift
            property: "x"
            to: 0
            duration: root.stepDuration
            easing.type: Easing.OutSine
        }
        NumberAnimation {
            target: root.shift
            property: "y"
            to: 0
            duration: root.stepDuration
            easing.type: Easing.OutSine
        }
        NumberAnimation {
            target: root.host
            property: "opacity"
            to: 1
            duration: root.stepDuration
            easing.type: Easing.OutSine
        }
    }
}
