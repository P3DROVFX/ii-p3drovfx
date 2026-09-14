import QtQuick
import qs.modules.common

// One interruptible clock for surface, content, blur and Loader lifetime.
Item {
    id: root
    property real progress: 0
    property real destination: 0
    property int duration: Appearance.animation.elementMoveEnter.duration
    readonly property bool running: animation.running
    signal settled(real value)

    function animateTo(value) {
        animation.stop();
        destination = Math.max(0, Math.min(1, value));
        if (Math.abs(progress - destination) < 0.0001) {
            progress = destination;
            settled(destination);
            return;
        }
        animation.to = destination;
        animation.start();
    }

    function reset(value) {
        animation.stop();
        destination = value;
        progress = value;
    }

    function phase(index) {
        const delay = Math.min(7, Math.max(0, index)) * 0.035 + 0.08;
        return Math.max(0, Math.min(1, (progress - delay) / (1 - delay)));
    }

    NumberAnimation {
        id: animation
        onFinished: root.settled(root.progress)
        target: root
        property: "progress"
        duration: root.duration
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }
}
