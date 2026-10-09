pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import "WorkspaceShapes.js" as Shapes

/**
 * The active indicator in motion. The bar only shows what an indicator does when the
 * workspace changes, so this track lets the page make that happen: tap a slot and the
 * indicator travels the way the chosen mode says (a pill that stretches, a fixed shape,
 * a new random shape per hop, a triangle aimed where you went).
 */
Item {
    id: root

    readonly property int slotCount: 5
    readonly property real slotSize: 44
    readonly property real indicatorSize: 34
    readonly property real trackPadding: 8
    readonly property real pillInset: 4
    readonly property int arrowMorphMs: 420
    readonly property int arrowRestMs: 260
    readonly property real turn: 90

    /** "pill" | "shape" | "random" | "arrow" */
    property string mode: "pill"
    property string shapeName: "Pentagon"
    property string colorMode: "primary"
    property real indicatorOpacity: 1

    property int current: 1
    property int previous: 1
    property bool arrowShown: false
    property real arrowRotation: turn
    property string randomShape: "Circle"
    property real randomRotation: 0

    readonly property bool squareIndicator: root.mode === "random" || root.mode === "arrow"
    readonly property bool shapeIndicator: root.mode !== "pill"
    readonly property real trackWidth: root.slotCount * root.slotSize + root.trackPadding * 2

    implicitWidth: root.trackWidth
    implicitHeight: root.slotSize + root.trackPadding * 2

    function go(slot) {
        if (slot === root.current)
            return;
        root.previous = root.current;
        root.current = slot;
        if (root.mode === "random")
            root.rerollShape();
        else if (root.mode === "arrow")
            root.pointArrow();
    }

    function rerollShape() {
        let next = root.randomShape;
        while (next === root.randomShape)
            next = Shapes.all[Math.floor(Math.random() * Shapes.all.length)];
        root.randomShape = next;
        root.randomRotation += root.turn;
    }

    function pointArrow() {
        root.arrowRotation = root.current > root.previous ? root.turn : root.turn * 3;
        root.arrowShown = true;
        arrowHold.restart();
    }

    // Changing the mode plays one hop, so the new behaviour is visible without a tap.
    property bool armed: false
    Component.onCompleted: root.armed = true
    onModeChanged: {
        if (root.armed)
            Qt.callLater(() => root.go((root.current + 1) % root.slotCount));
    }

    Timer {
        id: arrowHold
        interval: Math.round((root.arrowMorphMs + root.arrowRestMs) * Appearance.animMultiplier)
        onTriggered: root.arrowShown = false
    }

    BarWidgetPalette {
        id: palette
        colorMode: root.colorMode
    }

    AnimatedTabIndexPair {
        id: pair
        index: root.current
        easingType: Easing.OutBack
        easingOvershoot: 1.7
        idx1Duration: 250
        idx2Duration: 350
    }

    Rectangle {
        id: track
        anchors.centerIn: parent
        width: root.trackWidth
        height: root.implicitHeight
        radius: Math.min(height / 2, Appearance.rounding.large)
        color: Appearance.colors.colLayer2

        Rectangle {
            id: pill
            visible: !root.shapeIndicator
            readonly property real lead: Math.min(pair.idx1, pair.idx2)
            readonly property real span: Math.abs(pair.idx1 - pair.idx2)
            x: root.trackPadding + pill.lead * root.slotSize + root.pillInset
            y: (track.height - height) / 2
            width: (pill.span + 1) * root.slotSize - root.pillInset * 2
            height: root.indicatorSize
            radius: Appearance.rounding.full
            color: palette.colBackground
            opacity: root.indicatorOpacity
        }

        MaterialShape {
            id: shape
            visible: root.shapeIndicator
            x: root.trackPadding + pair.idx1 * root.slotSize + (root.slotSize - width) / 2
            y: (track.height - height) / 2
            width: root.indicatorSize
            height: root.indicatorSize
            color: palette.colBackground
            opacity: root.indicatorOpacity
            shapeString: root.mode === "arrow" ? (root.arrowShown ? "Triangle" : "Circle")
                : root.mode === "random" ? root.randomShape : root.shapeName
            rotation: root.mode === "arrow" ? root.arrowRotation
                : root.mode === "random" ? root.randomRotation : 0
            Behavior on rotation {
                enabled: root.mode === "random" && !Appearance.reducedMotion
                RotationAnimation {
                    duration: Math.round(350 * Appearance.animMultiplier)
                    direction: RotationAnimation.Clockwise
                    easing.type: Easing.OutBack
                }
            }
        }

        Repeater {
            model: root.slotCount
            delegate: Item {
                id: slot

                required property int index
                readonly property bool active: root.current === slot.index

                x: root.trackPadding + slot.index * root.slotSize
                y: root.trackPadding
                width: root.slotSize
                height: root.slotSize

                StyledText {
                    anchors.centerIn: parent
                    text: String(slot.index + 1)
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: slot.active ? Font.Bold : Font.Normal
                    color: slot.active ? palette.colOnBackground : Appearance.colors.colOnLayer2
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.go(slot.index)
                }
            }
        }
    }
}
