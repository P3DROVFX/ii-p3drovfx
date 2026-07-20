import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    required property string imageSource

    readonly property int status: imgAIsBack ? imgA.status : imgB.status

    property int animationDuration: 1000
    property var fillMode: Image.PreserveAspectCrop
    property bool animated: true
    property bool imgAIsBack: true
    property bool lockAnimationActive: false

    property var sourceSize: Qt.size(0, 0)
    property bool cache: false
    property bool antialiasing: true
    property bool asynchronous: true
    property bool smooth: true
    property bool mipmap: true

    // Shader transition support
    property string transitionShader: ""
    property var shadersPath: ""
    property string activeShader: ""
    property real transitionProgress: 1.0

    readonly property Item fromImage: imgAIsBack ? imgA : imgB
    readonly property Item toImage: imgAIsBack ? imgB : imgA

    onImageSourceChanged: fadeTo(imageSource)
    Component.onCompleted: imgA.source = imageSource

    function fadeTo(newSrc) {
        var back = imgAIsBack ? imgA : imgB;
        var front = imgAIsBack ? imgB : imgA;

        if (newSrc === back.source)
            return;

        // No previous wallpaper loaded — load directly onto the back image
        // instead of crossfading, which would swap an empty image on top.
        if (back.source === "" || back.status === Image.Null) {
            back.source = newSrc;
            return;
        }

        front.source = newSrc;
        front.z = 1;
        back.z = 0;

        if (root.animated) {
            if (root.transitionShader !== "") {
                if (root.transitionShader === "random") {
                    let list = ["circle", "circlePit", "circleSelect", "magic", "Peel", "transition", "pixelate", "stripes"];
                    root.activeShader = list[Math.floor(Math.random() * list.length)];
                } else {
                    root.activeShader = root.transitionShader;
                }
                // Standard crossfade animation is skipped; reset opacities to 1.0 so
                // ShaderEffectSource captures the complete images
                front.opacity = 1.0;
                back.opacity = 1.0;
                shaderProgressAnim.restart();
            } else {
                front.opacity = 0;
                fadeAnim.target = front;
                fadeAnim.restart();
            }
        } else {
            front.opacity = 1;
            var oldBack = imgAIsBack ? imgA : imgB;
            oldBack.source = "";
            root.imgAIsBack = !root.imgAIsBack;
        }
    }

    NumberAnimation {
        id: fadeAnim
        property: "opacity"
        from: 0
        to: 1
        duration: root.animationDuration
        easing.type: Easing.InOutQuad

        onFinished: {
            var oldBack = root.imgAIsBack ? imgA : imgB;
            oldBack.source = "";
            root.imgAIsBack = !root.imgAIsBack;
        }
    }

    NumberAnimation {
        id: shaderProgressAnim
        target: root
        property: "transitionProgress"
        from: 0.0
        to: 1.0
        duration: root.animationDuration
        easing.type: Easing.InOutCubic
        onFinished: {
            var front = root.imgAIsBack ? imgB : imgA;
            var back = root.imgAIsBack ? imgA : imgB;
            front.opacity = 1;
            back.opacity = 0;
            back.source = "";
            root.imgAIsBack = !root.imgAIsBack;
            root.activeShader = "";
        }
    }

    ShaderEffectSource {
        id: fromSource
        sourceItem: root.imgAIsBack ? imgA : imgB
        hideSource: shaderProgressAnim.running
        live: shaderProgressAnim.running
        visible: false
    }

    ShaderEffectSource {
        id: toSource
        sourceItem: root.imgAIsBack ? imgB : imgA
        hideSource: shaderProgressAnim.running
        live: shaderProgressAnim.running
        visible: false
    }

    ShaderEffect {
        id: transitionEffect
        anchors.fill: parent
        z: 2
        visible: root.animated && root.activeShader !== "" && shaderProgressAnim.running
        
        property var fromImage: fromSource
        property var toImage: toSource
        property real progress: root.transitionProgress
        property real aspectX: width / height
        property real aspectY: 1.0
        property vector2d aspectRatio: Qt.vector2d(aspectX, aspectY)
        property vector2d origin: Qt.vector2d(0.5, 0.5)
        
        fragmentShader: (root.activeShader !== "" && root.shadersPath !== "")
            ? root.shadersPath + "/" + root.activeShader + ".frag.qsb"
            : ""
    }

    Image {
        id: imgA
        anchors.fill: parent
        fillMode: root.fillMode
        sourceSize: root.sourceSize
        cache: root.cache
        antialiasing: root.antialiasing
        asynchronous: root.asynchronous
        smooth: root.smooth
        mipmap: root.mipmap
    }

    Image {
        id: imgB
        anchors.fill: parent
        opacity: 0
        fillMode: root.fillMode
        sourceSize: root.sourceSize
        cache: root.cache
        antialiasing: root.antialiasing
        asynchronous: root.asynchronous
        smooth: root.smooth
        mipmap: root.mipmap
    }
}
