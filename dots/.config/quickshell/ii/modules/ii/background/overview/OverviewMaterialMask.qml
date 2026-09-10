import QtQuick
import qs.modules.common.widgets

// A layer effect for the overview's wallpaper and widget planes. Only the
// small silhouette is rasterized; its scale/rotation are sampled in the final
// shader instead of repainting a transformed fullscreen mask every frame.
ShaderEffect {
    id: root
    required property var controller
    property var source
    property bool textureReady: false
    readonly property real maskReady: textureReady && controller.progress > 0 ? 1 : 0
    readonly property var maskSource: shapeTexture
    readonly property vector2d screenExtent: Qt.vector2d(width, height)
    readonly property real maskExtent: Math.max(1, controller.maskTargetDiameter * controller.maskScale)
    readonly property real maskAngle: controller.maskRotation * Math.PI / 180
    readonly property vector2d rotationVector: Qt.vector2d(Math.cos(maskAngle), Math.sin(maskAngle))

    fragmentShader: Qt.resolvedUrl("../shaders/overviewMaterialMask.frag.qsb")

    MaterialShape {
        id: silhouette
        width: root.controller.maskTargetDiameter
        height: width
        shapeString: root.controller.currentMaterialShape
        // Alpha data for a mask, not a theme color.
        color: "white"
        // The next shape is chosen with the overview fully closed. A morph
        // here would add 350ms of JS/Canvas repaint underneath the zoom.
        animation: NumberAnimation { duration: 0 }
        onPainted: shapeTexture.scheduleUpdate()
    }

    ShaderEffectSource {
        id: shapeTexture
        sourceItem: silhouette
        hideSource: true
        visible: false
        smooth: true
        // Live tracks a new silhouette/theme/size, not the animation uniforms.
        // The source has no animated transform and remains clean during zoom.
        live: true
        // Canvas painting and texture capture finish after layer creation.
        // Keep the wallpaper intact until the first mask is actually captured.
        onScheduledUpdateCompleted: root.textureReady = true
    }
}
