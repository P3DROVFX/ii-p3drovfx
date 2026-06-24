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
    property real hBarHiddenAmount: 0
    property real vBarHiddenAmount: 0
    property real screenWidth: 1920
    property real screenHeight: 1080
    property real dropWidth: 0
    property real dropHeight: 0

    property real animatedLeftSidebarWidth: 0
    property real animatedRightSidebarWidth: 0
    property bool leftSidebarActiveOnMonitor: false
    property bool rightSidebarActiveOnMonitor: false

    readonly property real leftSidebarPush: leftSidebarActiveOnMonitor ? animatedLeftSidebarWidth : 0
    readonly property real rightSidebarPush: rightSidebarActiveOnMonitor ? animatedRightSidebarWidth : 0

    readonly property real horizontalCenter: {
        const leftEdge = usingWrappedFrame ? frameThickness : (barVertical && !barBottom ? Math.max(0, verticalBarWidth - vBarHiddenAmount) : 0)
        const rightEdge = screenWidth - (usingWrappedFrame ? frameThickness : (barVertical && barBottom ? Math.max(0, verticalBarWidth - vBarHiddenAmount) : 0))
        if (rightEdge <= leftEdge)
            return screenWidth / 2
        return (leftEdge + rightEdge) / 2
    }

    readonly property real anchorX: horizontalCenter - dropWidth / 2

    readonly property real anchorY: {
        if (barVertical) {
            return usingWrappedFrame ? frameThickness : 0
        }
        if (barBottom) {
            return screenHeight - (usingWrappedFrame ? frameThickness : Math.max(0, barHeight - hBarHiddenAmount)) - dropHeight
        }
        return Math.max(0, barHeight - hBarHiddenAmount)
    }

    readonly property real scaleYOrigin: barBottom ? dropHeight : 0
}
