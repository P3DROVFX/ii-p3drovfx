import QtQuick
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.widgets

/*
 * A cover cut to a Material shape. Changing `shape` morphs the cut (MaterialShape
 * animates between polygons on its own). Masked with QtQuick.Effects, never
 * Qt5Compat: the Settings preview builds this in a window that is destroyed.
 * Without a cover the shape is filled and carries a note glyph instead.
 */
Item {
    id: root

    property string source: ""
    property var shape: MaterialShape.Shape.Cookie12Sided
    property color placeholderColor: "gray"
    property color placeholderIconColor: "white"

    readonly property bool hasArt: root.source !== "" && art.status === Image.Ready

    MaterialShape {
        id: placeholder
        anchors.fill: parent
        shape: root.shape
        color: root.placeholderColor
        opacity: root.hasArt ? 0 : 1
        visible: opacity > 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "music_note"
            fill: 1
            iconSize: Math.round(root.width * 0.34)
            color: root.placeholderIconColor
        }
    }

    Image {
        id: art
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(Math.ceil(root.width * 2), Math.ceil(root.height * 2))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false
    }

    MaterialShape {
        id: mask
        anchors.fill: parent
        shape: root.shape
        color: "black"
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: art
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
        opacity: root.hasArt ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }
}
