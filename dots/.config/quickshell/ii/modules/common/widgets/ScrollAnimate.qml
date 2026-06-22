import QtQuick
import qs.modules.common

Item {
    id: root
    visible: false

    // Master toggle from configuration
    property bool animateEnabled: Config.options?.appearance?.scrollAnimations ?? true

    readonly property Item parentItem: parent
    property Flickable flickable: null

    Scale {
        id: scrollScaleTransform
        origin.x: parentItem ? parentItem.width / 2 : 0
        origin.y: parentItem ? parentItem.height / 2 : 0
        xScale: root.animatedScale
        yScale: root.animatedScale
    }

    Component.onCompleted: {
        findFlickable();
        if (!flickable) {
            retryTimer.start();
        }
        if (parentItem) {
            var trans = parentItem.transform;
            if (trans.indexOf(scrollScaleTransform) === -1) {
                trans.push(scrollScaleTransform);
                parentItem.transform = trans;
            }
        }
    }

    onParentChanged: {
        findFlickable();
        if (parentItem) {
            var trans = parentItem.transform;
            if (trans.indexOf(scrollScaleTransform) === -1) {
                trans.push(scrollScaleTransform);
                parentItem.transform = trans;
            }
        }
    }

    Timer {
        id: retryTimer
        interval: 50
        repeat: false
        onTriggered: findFlickable()
    }

    function findFlickable() {
        var nextParent = parentItem ? parentItem.parent : null;
        while (nextParent) {
            if (nextParent.flickableDirection !== undefined && nextParent.contentY !== undefined) {
                flickable = nextParent;
                return;
            }
            nextParent = nextParent.parent;
        }
        flickable = null;
    }

    // Calculate relative Y coordinate inside the Flickable viewport
    readonly property real relativeY: {
        if (!flickable || !parentItem) return 0;
        // Bind to flickable scroll position and height to trigger updates
        var scrollY = flickable.contentY;
        var viewH = flickable.height;
        try {
            return parentItem.mapToItem(flickable, 0, 0).y;
        } catch (e) {
            return 0;
        }
    }

    // Check visibility with a generous buffer (100px at bottom, 60px at top)
    // to trigger the animation before it enters the viewport
    readonly property bool isVisible: {
        if (!animateEnabled) return true;
        if (!flickable || !parentItem || flickable.height <= 0) return true;
        
        var isBelowTop = (relativeY + parentItem.height) >= -60;
        var isAboveBottom = relativeY <= (flickable.height + 100);
        
        return isBelowTop && isAboveBottom;
    }

    // Target values
    readonly property real targetOpacity: (animateEnabled && !isVisible) ? 0.0 : 1.0
    readonly property real targetScale: (animateEnabled && !isVisible) ? 0.92 : 1.0

    // Animated values that interpolate smoothly
    property real animatedOpacity: animateEnabled ? 0.0 : 1.0
    property real animatedScale: animateEnabled ? 0.92 : 1.0

    Binding {
        target: root
        property: "animatedOpacity"
        value: targetOpacity
    }

    Binding {
        target: root
        property: "animatedScale"
        value: targetScale
    }

    Behavior on animatedOpacity {
        enabled: root.animateEnabled
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    Behavior on animatedScale {
        enabled: root.animateEnabled
        NumberAnimation {
            duration: 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.34, 1.3, 0.2, 1.0] // Fast, clean expressive overshoot
        }
    }

    // Set properties on parent item
    Binding {
        target: parentItem
        property: "opacity"
        value: root.animatedOpacity
        when: root.animateEnabled && root.animatedOpacity < 0.999
    }
}

