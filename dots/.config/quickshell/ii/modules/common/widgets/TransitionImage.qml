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

    property var sourceSize: Qt.size(0, 0)
    property bool cache: false
    property bool antialiasing: true
    property bool asynchronous: true
    property bool smooth: true
    property bool mipmap: true

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
            front.opacity = 0;
            fadeAnim.target = front;
            fadeAnim.restart();
        } else {
            front.opacity = 1;
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
            root.imgAIsBack = !root.imgAIsBack;
        }
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
