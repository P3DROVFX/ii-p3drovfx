pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    property var states: []
    property int currentIndex: 0

    signal stateRequested(int index)

    readonly property int stateCount: Math.max(2, root.states ? root.states.length : 2)

    readonly property real margin: 4
    readonly property real knobSize: root.height - (margin * 2)

    function positionForIndex(idx: int): real {
        if (root.stateCount <= 1) return root.margin;
        const availableWidth = root.width - root.knobSize - (root.margin * 2);
        const clampedIdx = Math.max(0, Math.min(root.stateCount - 1, idx));
        return root.margin + (availableWidth * (clampedIdx / (root.stateCount - 1)));
    }

    function nearestIndexForX(xVal: real): int {
        if (root.stateCount <= 1) return 0;
        const availableWidth = root.width - root.knobSize - (root.margin * 2);
        if (availableWidth <= 0) return 0;
        const progress = Math.max(0, Math.min(1, (xVal - root.margin) / availableWidth));
        return Math.round(progress * (root.stateCount - 1));
    }

    // Local override state to prevent snapback during async service updates
    property int localOverrideIndex: -1
    readonly property int activeVisualIndex: localOverrideIndex !== -1 ? localOverrideIndex : Math.max(0, Math.min(root.stateCount - 1, root.currentIndex))

    onCurrentIndexChanged: {
        localOverrideIndex = -1;
    }

    Timer {
        id: overrideResetTimer
        interval: 800
        repeat: false
        onTriggered: localOverrideIndex = -1
    }

    // Interactive dragging state
    property bool isDraggingKnob: false
    property real knobDragX: root.positionForIndex(root.activeVisualIndex)

    readonly property int hoverIndex: isDraggingKnob ? root.nearestIndexForX(knobDragX) : root.activeVisualIndex
    readonly property real targetX: root.positionForIndex(root.activeVisualIndex)

    function findParentFlickable(item): var {
        let p = item ? item.parent : null;
        while (p) {
            if (p.flicking !== undefined || p.interactive !== undefined) {
                return p;
            }
            p = p.parent;
        }
        return null;
    }

    property var parentFlickable: null
    Component.onCompleted: {
        root.parentFlickable = root.findParentFlickable(root);
    }

    function getStateIcon(idx: int): string {
        if (!root.states || idx < 0 || idx >= root.states.length)
            return "tune";
        const entry = root.states[idx];
        if (typeof entry === "string") return entry;
        return entry.icon || "tune";
    }

    // Capsule pill background
    Rectangle {
        id: bgPill
        anchors.fill: parent
        radius: height / 2
        color: Appearance.colors.colLayer2

        // Dots for each position
        Repeater {
            model: root.stateCount
            delegate: Rectangle {
                id: dot
                required property int index

                readonly property real dotX: root.positionForIndex(index) + (root.knobSize / 2)
                width: 6
                height: 6
                radius: 3
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
                anchors.verticalCenter: parent.verticalCenter
                x: dotX - 3
                opacity: root.hoverIndex === index ? 0.0 : 1.0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }
    }

    // Draggable Knob
    Rectangle {
        id: knob
        width: root.knobSize
        height: root.knobSize
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: Appearance.colors.colPrimary
        scale: root.isDraggingKnob ? 1.08 : 1.0

        x: root.isDraggingKnob ? root.knobDragX : root.targetX

        Behavior on x {
            enabled: !root.isDraggingKnob
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutBack
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.getStateIcon(root.hoverIndex)
            iconSize: 20
            color: Appearance.colors.colOnPrimary
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        property real startMouseX: 0
        property real startKnobX: 0

        onPressed: mouse => {
            startMouseX = mouse.x;
            startKnobX = knob.x;
            root.isDraggingKnob = true;
            root.knobDragX = Math.max(root.margin, Math.min(root.width - root.knobSize - root.margin, startKnobX));
            if (root.parentFlickable) {
                root.parentFlickable.interactive = false;
            }
        }

        onPositionChanged: mouse => {
            if (root.isDraggingKnob) {
                const delta = mouse.x - startMouseX;
                const newX = startKnobX + delta;
                root.knobDragX = Math.max(root.margin, Math.min(root.width - root.knobSize - root.margin, newX));
            }
        }

        onReleased: mouse => {
            if (root.isDraggingKnob) {
                root.isDraggingKnob = false;
                if (root.parentFlickable) {
                    root.parentFlickable.interactive = true;
                }
                const chosenIdx = root.nearestIndexForX(root.knobDragX);
                root.localOverrideIndex = chosenIdx;
                overrideResetTimer.restart();
                root.stateRequested(chosenIdx);
            }
        }

        onCanceled: {
            root.isDraggingKnob = false;
            if (root.parentFlickable) {
                root.parentFlickable.interactive = true;
            }
        }
    }
}
