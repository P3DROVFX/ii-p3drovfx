import QtQuick
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.widgets

/*
 * A gallery thumbnail cut to a Material shape; changing `shape` morphs the cut.
 * Masked with QtQuick.Effects (never Qt5Compat), as MediaShapedArt does. Until the
 * thumbnail is on disk the shape is filled and carries a glyph.
 */
Item {
    id: root

    property string source: ""
    property var shape: MaterialShape.Shape.Square
    property string placeholderIcon: "photo"
    property color placeholderColor: Appearance.colors.colSecondaryContainer
    property color placeholderIconColor: Appearance.colors.colOnSecondaryContainer

    readonly property bool hasArt: root.source !== "" && art.status === Image.Ready

    MaterialShape {
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
            text: root.placeholderIcon
            fill: 1
            iconSize: Math.round(root.width * 0.36)
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
