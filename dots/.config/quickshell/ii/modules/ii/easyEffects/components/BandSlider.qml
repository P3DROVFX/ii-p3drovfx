import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * One equalizer band's gain as a vertical bar: the part below the handle is the gain in
 * the accent, the part above it the room left, with a gap and a bar-shaped handle between
 * them, the way the app's horizontal sliders are drawn. Drag it (the drag is kept from any
 * Flickable around it), scroll it, or use the
 * arrow keys (ten steps with Shift); `moved(value)` reports each new gain and the bar
 * follows `value` again as soon as the hand lets go.
 */
Item {
    id: root

    property real value: 0
    property real from: -12
    property real to: 12
    property real step: 0.1
    property bool selected: false
    /// Shown in a small bubble above the handle while it is held.
    property string valueText: ""

    /// The part of this item (in its own coordinates) that is on screen, for a bar inside a
    /// clipping scroller: the value bubble stays inside it instead of being cut off.
    property real viewLeft: 0
    property real viewRight: width

    signal moved(real value)
    signal picked()

    readonly property real trackWidth: EasyEffectsStyle.bandSliderWidth
    readonly property real handleHeight: EasyEffectsStyle.gapTiny
    readonly property real handleGap: EasyEffectsStyle.gapSmall
    readonly property real held: area.pressed ? area.heldValue : root.value
    readonly property real position: Math.max(0, Math.min(1, (root.to - root.held) / (root.to - root.from)))
    readonly property real handleY: root.position * (root.height - root.handleHeight)

    implicitWidth: root.trackWidth + EasyEffectsStyle.gapSmall
    implicitHeight: EasyEffectsStyle.bandSliderHeight
    activeFocusOnTab: true

    function tidy(v: real): real {
        return Number((Math.round(v / root.step) * root.step).toFixed(2));
    }

    function nudge(steps: real): void {
        root.moved(root.tidy(Math.max(root.from, Math.min(root.to, root.value + steps * root.step))));
    }

    Keys.onPressed: event => {
        const up = event.key === Qt.Key_Up || event.key === Qt.Key_Right;
        if (!up && event.key !== Qt.Key_Down && event.key !== Qt.Key_Left)
            return;
        event.accepted = true;
        root.nudge((up ? 1 : -1) * (event.modifiers & Qt.ShiftModifier ? 50 : 5));
    }

    // Room left above the handle.
    Rectangle {
        x: (parent.width - root.trackWidth) / 2
        width: root.trackWidth
        height: Math.max(0, root.handleY - root.handleGap / 2 + root.handleHeight / 2)
        topLeftRadius: EasyEffectsStyle.pill(root.trackWidth)
        topRightRadius: topLeftRadius
        bottomLeftRadius: EasyEffectsStyle.radiusJoin
        bottomRightRadius: bottomLeftRadius
        color: EasyEffectsStyle.colSecondaryContainer
        visible: height > 0
    }

    // The gain.
    Rectangle {
        x: (parent.width - root.trackWidth) / 2
        y: root.handleY + root.handleHeight / 2 + root.handleGap / 2
        width: root.trackWidth
        height: Math.max(0, parent.height - y)
        topLeftRadius: EasyEffectsStyle.radiusJoin
        topRightRadius: topLeftRadius
        bottomLeftRadius: EasyEffectsStyle.pill(root.trackWidth)
        bottomRightRadius: bottomLeftRadius
        color: EasyEffectsStyle.colPrimary
        visible: height > 0
    }

    Rectangle {
        x: (parent.width - width) / 2
        y: root.handleY
        width: root.trackWidth + root.handleHeight * 2
        height: root.handleHeight
        radius: height / 2
        color: EasyEffectsStyle.colPrimary

        Rectangle {
            anchors.centerIn: parent
            width: parent.width + EasyEffectsStyle.gapTiny * 2
            height: parent.height + EasyEffectsStyle.gapTiny * 2
            radius: height / 2
            color: EasyEffectsStyle.tint(EasyEffectsStyle.colPrimary, EasyEffectsStyle.tintHover)
            opacity: root.activeFocus || area.containsMouse ? 1 : 0

            Behavior on opacity {
                animation: EasyEffectsStyle.motionFast.numberAnimation.createObject(this)
            }
        }
    }

    Rectangle {
        // Above the handle; below it when the handle is too near the top for the bubble.
        readonly property bool below: root.handleY < height + EasyEffectsStyle.gapSmall
        visible: area.pressed && root.valueText.length > 0
        x: Math.max(root.viewLeft, Math.min(root.viewRight - width, (parent.width - width) / 2))
        y: below ? root.handleY + root.handleHeight + EasyEffectsStyle.gapSmall : root.handleY - height - EasyEffectsStyle.gapSmall
        width: bubble.implicitWidth + EasyEffectsStyle.gapLarge
        height: EasyEffectsStyle.pillHeight - EasyEffectsStyle.gapTiny
        radius: height / 2
        color: EasyEffectsStyle.colPrimary
        z: 2

        StyledText {
            id: bubble
            anchors.centerIn: parent
            text: root.valueText
            font.pixelSize: EasyEffectsStyle.textCaption
            font.weight: Font.Bold
            color: EasyEffectsStyle.colOnPrimary
        }
    }

    MouseArea {
        id: area
        property real heldValue: root.value
        anchors.fill: parent
        hoverEnabled: true
        // A vertical drag belongs to the bar: without this the sheet's Flickable (and the
        // bars' own sideways one) steals the press and scrolls instead of moving the gain.
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        function valueAt(y: real): real {
            const p = Math.max(0, Math.min(1, (y - root.handleHeight / 2) / (root.height - root.handleHeight)));
            return root.tidy(root.to - p * (root.to - root.from));
        }

        function follow(y: real): void {
            const next = area.valueAt(y);
            if (next === area.heldValue)
                return;
            area.heldValue = next;
            root.moved(next);
        }

        onPressed: mouse => {
            root.forceActiveFocus();
            root.picked();
            area.heldValue = root.value;
            area.follow(mouse.y);
        }
        onPositionChanged: mouse => {
            if (area.pressed)
                area.follow(mouse.y);
        }
        onWheel: wheel => {
            // A sideways scroll belongs to the scroller around the bars.
            if (wheel.angleDelta.x !== 0 && wheel.angleDelta.y === 0) {
                wheel.accepted = false;
                return;
            }
            root.picked();
            root.nudge((wheel.angleDelta.y > 0 ? 1 : -1) * (wheel.modifiers & Qt.ShiftModifier ? 50 : 5));
        }
    }
}
