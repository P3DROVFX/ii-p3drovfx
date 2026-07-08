import QtQuick

QtObject {
    id: root

    property bool barVertical: false
    property bool barBottom: false
    property bool barOnLeft: false
    property bool barOnRight: false
    property bool usingWrappedFrame: false
    property int frameThickness: 0
    property int barHeight: 0
    property int verticalBarWidth: 0
    property real barMargin: 0
    property real hBarHiddenAmount: 0
    property real vBarHiddenAmount: 0
    property real screenWidth: 1920
    property real screenHeight: 1080
    property real dropWidth: 0
    property real dropHeight: 0

    property bool hasFullscreenWindow: false

    readonly property real horizontalCenter: {
        const leftEdge = usingWrappedFrame ? frameThickness : (barVertical && !barBottom ? Math.max(0, verticalBarWidth - vBarHiddenAmount) : 0);
        const rightEdge = screenWidth - (usingWrappedFrame ? frameThickness : (barVertical && barBottom ? Math.max(0, verticalBarWidth - vBarHiddenAmount) : 0));
        if (rightEdge <= leftEdge)
            return screenWidth / 2;
        return (leftEdge + rightEdge) / 2;
    }

    readonly property real anchorX: horizontalCenter - dropWidth / 2

    // barMargin is the visual inset of the bar background (e.g. hyprlandGapsOut for Float).
    // The barBackground has margins on all sides, so:
    //   Top bar:  visual bottom edge = barHeight - hBarHiddenAmount - barMargin
    //   Bottom bar: visual top edge = screenHeight - barHeight + barMargin - hBarHiddenAmount
    readonly property real anchorY: {
        if (hasFullscreenWindow) {
            return barBottom ? screenHeight - dropHeight : 0;
        }
        if (barVertical) {
            return (usingWrappedFrame ? frameThickness : 0);
        }
        if (barBottom) {
            return screenHeight - (usingWrappedFrame ? frameThickness : Math.max(0, barHeight - hBarHiddenAmount)) - dropHeight - root.margin;
        }
        return Math.max(0, barHeight - hBarHiddenAmount - barMargin);
    }
    property real margin: 0

    readonly property real scaleYOrigin: barBottom ? dropHeight : 0
}
