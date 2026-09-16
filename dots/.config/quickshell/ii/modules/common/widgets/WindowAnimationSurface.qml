pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.services

// Layer-shell reference panels keep their focus/cache semantics, but use exactly
// the window preset's curves, durations, scale percentages and slide direction.
Item {
    id: root
    required property bool open
    required property bool mapped
    required property real panelWidth
    required property real panelHeight
    property bool initialized: false
    signal closed()

    readonly property var entries: HyprlandSettings.appLaunchEntries(Config.options.appearance.appLaunchAnimation)
    function spec(leaf) {
        return root.entries.find(entry => entry.kind === "animation" && entry.spec.leaf === leaf)?.spec;
    }
    function curve(name) {
        const points = root.entries.find(entry => entry.kind === "curve" && entry.name === name)?.spec.points;
        return points ? [points[0][0], points[0][1], points[1][0], points[1][1], 1, 1] : [0, 0, 1, 1, 1, 1];
    }
    function transition(entering) {
        motion.stop();
        const spatial = root.spec(entering ? "windowsIn" : "windowsOut");
        const fade = root.spec(entering ? "fadeIn" : "fadeOut");
        const style = spatial?.style ?? "";
        const slide = style.startsWith("slide");
        // These panels are centred, so all edges tie in auto mode; choose bottom.
        const direction = style.split(" ")[1] || "bottom";
        const offsetX = slide && (direction === "left" || direction === "right")
            ? (direction === "left" ? -1 : 1) * (root.width + root.panelWidth) / 2 : 0;
        const offsetY = slide && (direction === "top" || direction === "bottom")
            ? (direction === "top" ? -1 : 1) * (root.height + root.panelHeight) / 2 : 0;
        const initialScale = slide ? 1 : parseFloat(style.split(" ")[1] || "100") / 100;
        if (entering && root.opacity === 0) {
            root.scale = initialScale;
            offset.x = offsetX;
            offset.y = offsetY;
        }
        const duration = spatial?.enabled ? Math.round(spatial.speed * 100) : 0;
        const bezier = root.curve(spatial?.bezier);
        for (const animation of [scaleAnimation, xAnimation, yAnimation]) {
            animation.duration = duration;
            animation.easing.bezierCurve = bezier;
        }
        scaleAnimation.to = entering ? 1 : initialScale;
        xAnimation.to = entering ? 0 : offsetX;
        yAnimation.to = entering ? 0 : offsetY;
        fadeAnimation.to = entering ? 1 : 0;
        fadeAnimation.duration = fade?.enabled ? Math.round(fade.speed * 100) : 0;
        fadeAnimation.easing.bezierCurve = root.curve(fade?.bezier);
        motion.start();
    }
    function update() {
        if (!root.initialized) return;
        if (!root.mapped) {
            startTimer.stop();
            motion.stop();
            root.opacity = 0;
        } else if (root.open) {
            startTimer.restart();
        } else {
            startTimer.stop();
            root.transition(false);
        }
    }
    opacity: 0
    transformOrigin: Item.Center
    transform: Translate { id: offset }
    onOpenChanged: root.update()
    onMappedChanged: root.update()
    Component.onCompleted: {
        root.initialized = true;
        root.update();
    }

    Timer {
        id: startTimer
        interval: 0
        onTriggered: if (root.mapped && root.open) root.transition(true)
    }
    ParallelAnimation {
        id: motion
        onFinished: if (!root.open) root.closed()
        NumberAnimation { id: scaleAnimation; target: root; property: "scale"; easing.type: Easing.BezierSpline }
        NumberAnimation { id: xAnimation; target: offset; property: "x"; easing.type: Easing.BezierSpline }
        NumberAnimation { id: yAnimation; target: offset; property: "y"; easing.type: Easing.BezierSpline }
        NumberAnimation { id: fadeAnimation; target: root; property: "opacity"; easing.type: Easing.BezierSpline }
    }
}
