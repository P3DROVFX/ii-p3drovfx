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

    property string _activeStyle: ""
    property int _activeRepeats: 1

    readonly property var _styleComponents: ({
        "bounce": bounceAnimComponent,
        "hop": hopAnimComponent,
        "pulse": pulseAnimComponent,
        "wiggle": wiggleAnimComponent,
        "ripple": rippleAnimComponent
    })

    anchors.fill: parent
    z: -1

    function _resetValues() {
        lift = 0;
        pop = 1;
        tilt = 0;
        ringProgress = 0;
    }

    function _onAnimFinished() {
        root._activeStyle = "";
        root._resetValues();
    }

    function stop() {
        if (animLoader.item)
            animLoader.item.stop();
        root._activeStyle = "";
        root._resetValues();
    }

    function play(style, repeats) {
        stop();
        if (!root._styleComponents[style])
            return;
        root._activeRepeats = Math.max(1, repeats ?? 1);
        root._activeStyle = style;
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
        if (animLoader.item && animLoader.item.running)
            animLoader.item.loops = 1;
    }

    Loader {
        id: animLoader
        active: root._activeStyle !== ""
        sourceComponent: root._styleComponents[root._activeStyle] ?? null
        onLoaded: {
            if (item && root._activeStyle !== "") {
                item.loops = root._activeRepeats;
                item.restart();
            }
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
    Component {
        id: bounceAnimComponent
        SequentialAnimation {
            onFinished: root._onAnimFinished()
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
    }

    // One soft hop with a small rebound on landing.
    Component {
        id: hopAnimComponent
        SequentialAnimation {
            onFinished: root._onAnimFinished()
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
    }

    // Swell, then spring back past rest.
    Component {
        id: pulseAnimComponent
        SequentialAnimation {
            onFinished: root._onAnimFinished()
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
    }

    // A decaying shake.
    Component {
        id: wiggleAnimComponent
        SequentialAnimation {
            onFinished: root._onAnimFinished()
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
    }

    Component {
        id: rippleAnimComponent
        SequentialAnimation {
            onFinished: root._onAnimFinished()
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
}
