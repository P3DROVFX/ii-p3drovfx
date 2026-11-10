import QtQuick
import qs.modules.common

/**
 * The feedback a dock icon plays when its app is launched or sends a
 * notification. The host button puts `shift`, `grow` and `turn` in its
 * `transform` list, and this item draws the ripple ring itself, behind the icon.
 *
 * Styles: "none", "bounce", "hop", "pulse", "wiggle", "ripple".
 */
Item {
    id: root

    required property Item host
    property string dockPos: "bottom"
    readonly property bool isVertical: dockPos === "left" || dockPos === "right"
    property real iconSize: host?.buttonSize ?? 48

    // Distance away from the dock edge, whatever side the dock sits on.
    property real lift: 0
    property real pop: 1
    property real tilt: 0
    property real ringProgress: 0

    readonly property real edgeOffset: (dockPos === "top" || dockPos === "left") ? lift : -lift
    readonly property Translate shift: Translate {
        x: root.isVertical ? root.edgeOffset : 0
        y: root.isVertical ? 0 : root.edgeOffset
    }
    readonly property Scale grow: Scale {
        origin.x: root.host.width / 2
        origin.y: root.host.height / 2
        xScale: root.pop
        yScale: root.pop
    }
    readonly property Rotation turn: Rotation {
        origin.x: root.host.width / 2
        origin.y: root.host.height / 2
        angle: root.tilt
    }

    readonly property var _animations: ({
        "bounce": bounceAnim,
        "hop": hopAnim,
        "pulse": pulseAnim,
        "wiggle": wiggleAnim,
        "ripple": rippleAnim
    })

    anchors.fill: parent
    z: -1

    function stop() {
        for (const key in _animations)
            _animations[key].stop();
        lift = 0;
        pop = 1;
        tilt = 0;
        ringProgress = 0;
    }

    function play(style, repeats) {
        const anim = _animations[style];
        stop();
        if (!anim)
            return;
        anim.loops = Math.max(1, repeats ?? 1);
        anim.start();
    }

    function playLaunch(style) {
        play(style, style === "bounce" ? 3 : 1);
    }

    function playNotification(style) {
        const repeats = { "bounce": 3, "hop": 2, "pulse": 2, "ripple": 2 };
        play(style, repeats[style] ?? 1);
    }

    // The app is up: let the running cycle land instead of looping on.
    function settle() {
        for (const key in _animations) {
            if (_animations[key].running)
                _animations[key].loops = 1;
        }
    }

    Rectangle {
        anchors.centerIn: parent
        visible: root.ringProgress > 0
        width: root.iconSize * (0.8 + root.ringProgress * 0.6)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, 3 * (1 - root.ringProgress))
        border.color: Appearance.colors.colPrimary
        opacity: 1 - root.ringProgress
    }

    // macOS: three hops that land hard.
    SequentialAnimation {
        id: bounceAnim
        NumberAnimation {
            target: root
            property: "lift"
            from: 0
            to: 18
            duration: 126
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "lift"
            from: 18
            to: 0
            duration: 154
            easing.type: Easing.InQuad
        }
    }

    // One soft hop with a small rebound on landing.
    SequentialAnimation {
        id: hopAnim
        NumberAnimation {
            target: root
            property: "lift"
            from: 0
            to: 12
            duration: 170
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "lift"
            to: 0
            duration: 170
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root
            property: "lift"
            to: 3
            duration: 90
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "lift"
            to: 0
            duration: 110
            easing.type: Easing.InQuad
        }
    }

    // Swell, then spring back past rest.
    SequentialAnimation {
        id: pulseAnim
        NumberAnimation {
            target: root
            property: "pop"
            from: 1
            to: 1.18
            duration: 140
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "pop"
            to: 1
            duration: 320
            easing.type: Easing.OutBack
            easing.overshoot: 3
        }
    }

    // A decaying shake.
    SequentialAnimation {
        id: wiggleAnim
        NumberAnimation {
            target: root
            property: "tilt"
            to: -10
            duration: 60
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "tilt"
            to: 10
            duration: 60
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "tilt"
            to: -8
            duration: 60
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "tilt"
            to: 8
            duration: 60
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "tilt"
            to: -4
            duration: 60
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "tilt"
            to: 0
            duration: 60
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation {
        id: rippleAnim
        NumberAnimation {
            target: root
            property: "ringProgress"
            from: 0.001
            to: 1
            duration: 600
            easing.type: Easing.OutCubic
        }
        PropertyAction {
            target: root
            property: "ringProgress"
            value: 0
        }
    }
}
