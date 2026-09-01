import QtQuick
import qs.modules.common

MouseArea {
    id: root

    readonly property bool isWidgetCanvas: true
    property real snapLineX: -1
    property real snapLineY: -1
    property bool draggingActive: false
    property bool gridOverlayEnabled: false
    property int alignmentGridStep: 10
    onAlignmentGridStepChanged: dotGrid.requestPaint()

    Canvas {
        id: dotGrid
        anchors.fill: parent
        z: -1
        visible: root.draggingActive && root.gridOverlayEnabled && opacity > 0.001
        opacity: root.draggingActive && root.gridOverlayEnabled ? 0.55 : 0

        readonly property real dotSize: 1.5
        readonly property color dotColor: Appearance.colors.colPrimary

        // Uniform on purpose. A radial falloff around the dragged widget was
        // tried and reverted: it repainted this full-screen canvas on every
        // pointer frame with a per-dot alpha, which is ~20k Qt.rgba allocations
        // and fillStyle switches per frame — the grid could not keep up and
        // read as simply missing. Painted once per size/step change, it costs
        // nothing while you drag.
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = dotGrid.dotColor;

            const offset = dotGrid.dotSize / 2;
            const step = Math.max(1, root.alignmentGridStep);
            for (let y = 0; y <= height; y += step) {
                for (let x = 0; x <= width; x += step) {
                    ctx.fillRect(x - offset, y - offset, dotGrid.dotSize, dotGrid.dotSize);
                }
            }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onDotColorChanged: requestPaint()
        onVisibleChanged: {
            if (visible)
                requestPaint();
        }

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    // Snap guides. They used to be toggled by `visible`, which made them blink
    // in and out at full strength; they now fade, and carry a soft bloom so the
    // line reads as a guide rather than as a 1.5px scratch on the wallpaper.
    Item {
        id: snapLineV
        visible: opacity > 0.001
        opacity: root.snapLineX >= 0 ? 1 : 0
        x: root.snapLineX
        width: 1.5
        height: root.height
        z: 999
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(snapLineV)
        }
        Rectangle {
            anchors.centerIn: parent
            width: 9
            height: parent.height
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.28) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colPrimary
        }
    }
    Item {
        id: snapLineH
        visible: opacity > 0.001
        opacity: root.snapLineY >= 0 ? 1 : 0
        y: root.snapLineY
        width: root.width
        height: 1.5
        z: 999
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(snapLineH)
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: 9
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.28) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colPrimary
        }
    }
}
