pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets

/**
 * Lightweight, virtualizable media tile for Home timeline and Albums grid.
 * Uses ClippingRectangle (no FBO layer.enabled / OpacityMask per item) and
 * bounded Image.sourceSize so memory stays low even across thousands of items.
 */
Item {
    id: root

    required property var itemData
    required property var store
    property bool isFavorite: false
    property bool selectionMode: false
    property bool selected: false
    property int videoMetaRev: 0
    signal clicked()
    signal toggleSelectRequested()

    readonly property bool isVideo: itemData && itemData.type === "video"
    readonly property string thumbUrl: {
        void root.videoMetaRev;
        return store ? store.thumbUrlFor(itemData) : "";
    }
    readonly property int videoDuration: {
        void root.videoMetaRev;
        return store ? store.durationFor(itemData) : 0;
    }

    Component.onCompleted: {
        if (root.isVideo && root.itemData && !root.thumbUrl && store)
            store.requestVideoThumb(root.itemData.path);
    }

    onItemDataChanged: {
        if (root.isVideo && root.itemData && !root.thumbUrl && store)
            store.requestVideoThumb(root.itemData.path);
    }

    ClippingRectangle {
        id: clipBox
        anchors.fill: parent
        radius: (tileMouse.containsMouse || root.selected) ? Appearance.rounding.large : Appearance.rounding.small
        color: Appearance.colors.colLayer2
        scale: root.selected ? 0.92 : (tileMouse.pressed ? 0.97 : 1.0)

        Behavior on radius {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Image {
            id: img
            anchors.fill: parent
            source: root.thumbUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            autoTransform: true
            sourceSize: Qt.size(160, 160)
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }

        // Placeholder icon while loading or if video thumbnail is pending
        MaterialSymbol {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready
            text: root.isVideo ? "movie" : "image"
            iconSize: 28
            color: Appearance.colors.colSubtext
            opacity: 0.45
        }

        // Video duration pill badge (bottom-left)
        Rectangle {
            visible: root.isVideo
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 8
            implicitWidth: badgeRow.implicitWidth + 14
            implicitHeight: 26
            radius: 13
            color: Appearance.colors.colSecondaryContainer

            RowLayout {
                id: badgeRow
                anchors.centerIn: parent
                spacing: 3

                MaterialSymbol {
                    text: "play_arrow"
                    fill: 1
                    iconSize: 16
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    text: root.videoDuration > 0 ? store.formatTime(root.videoDuration) : "VID"
                    font.pixelSize: 12
                    font.variableAxes: ({ "wght": 700, "wdth": 92, "ROND": 100 })
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }

        // Favorite MaterialShape badge (top-right)
        MaterialShape {
            visible: root.isFavorite
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            width: 28
            height: 28
            shape: MaterialShape.Shape.Cookie9Sided
            color: Appearance.m3colors.m3tertiaryContainer

            MaterialSymbol {
                anchors.centerIn: parent
                text: "favorite"
                fill: 1
                iconSize: 15
                color: Appearance.m3colors.m3onTertiaryContainer
            }
        }

        // Subtle hover / selection highlight scrim
        Rectangle {
            anchors.fill: parent
            color: root.selected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface
            opacity: root.selected ? 0.16 : (tileMouse.containsMouse ? 0.06 : 0)
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }

        // Crisp selection border ring
        Rectangle {
            visible: root.selected
            anchors.fill: parent
            radius: clipBox.radius
            color: "transparent"
            border.width: 3
            border.color: Appearance.colors.colPrimary
        }
    }

    MouseArea {
        id: tileMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        pressAndHoldInterval: 360
        onClicked: {
            if (root.selectionMode)
                root.toggleSelectRequested();
            else
                root.clicked();
        }
        onPressAndHold: root.toggleSelectRequested()
    }

    // Top-left hover / multi-selection checkbox (border-only rectangle when unselected, filled primary check when selected)
    Item {
        id: checkBtn
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 8
        width: 26
        height: 26
        z: 5
        visible: root.selectionMode || root.selected || tileMouse.containsMouse || checkMouse.containsMouse
        opacity: visible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Rectangle {
            anchors.fill: parent
            radius: 7
            color: root.selected
                ? Appearance.colors.colPrimary
                : (checkMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(0, 0, 0, 0.18))
            border.width: root.selected ? 0 : 2
            border.color: "#FFFFFF"
            Behavior on color { ColorAnimation { duration: 120 } }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.selected
                text: "check"
                iconSize: 17
                color: Appearance.colors.colOnPrimary
            }
        }

        MouseArea {
            id: checkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleSelectRequested()
        }
    }
}
