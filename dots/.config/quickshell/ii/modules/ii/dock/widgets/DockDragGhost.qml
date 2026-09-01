import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.dock
import qs.services
import qs.modules.common.functions

Item {
    id: root
    width: Appearance.sizes.dockButtonSize
    height: Appearance.sizes.dockButtonSize
    visible: false

    property string draggedAppId: ""
    property string fixedItemKey: ""
    property bool willUnpin: false
    property bool isFile: false
    property bool fileIsImage: false
    property string filePath: ""
    property string fileResolvedIcon: ""

    readonly property string renderType: {
        if (fixedItemKey !== "") return "fixed"
        if (isFile) return fileIsImage ? "image" : "file"
        return "app"
    }

    Loader {
        anchors.fill: parent
        sourceComponent: {
            switch (renderType) {
                case "fixed": return fixedComponent
                case "app": return appComponent
                case "image": return imageComponent
                case "file": return fileComponent
            }
        }
    }

    Component {
        id: appComponent
        Item {
            anchors.fill: parent
            DockIcon {
                anchors.centerIn: parent
                implicitWidth: Appearance.sizes.dockButtonSize
                implicitHeight: Appearance.sizes.dockButtonSize
                appId: root.draggedAppId
                isRunning: true
            }
        }
    }

    Component {
        id: fixedComponent
        Item {
            anchors.fill: parent
            Rectangle {
                anchors.centerIn: parent
                width: Appearance.sizes.dockButtonSize
                height: Appearance.sizes.dockButtonSize
                radius: Appearance.rounding.normal
                color: Appearance.colors.colPrimaryContainer
                opacity: 0.7

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: Appearance.sizes.dockButtonSize * 0.5
                    color: Appearance.colors.colOnPrimaryContainer
                    text: {
                        switch (root.fixedItemKey) {
                            case "pin": return "keep"
                            case "trash": return "delete"
                            case "overview": return "apps"
                            case "media": return "music_note"
                            case "weather": return "cloud"
                            case "sports": return "sports_soccer"
                            default: return "drag_indicator"
                        }
                    }
                }
            }
        }
    }

    Component {
        id: imageComponent
        Image {
            id: ghostThumbnail
            anchors.fill: parent
            source: root.fileIsImage ? ("file://" + root.filePath) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: ghostThumbnail.width
                    height: ghostThumbnail.height
                    radius: Appearance.rounding.small
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: ghostThumbnail.status !== Image.Ready
                text: "image"
                iconSize: Appearance.sizes.dockButtonSize / 2
                color: Appearance.colors.colOnLayer0
            }
        }
    }

    Component {
        id: fileComponent
        IconImage {
            anchors.fill: parent
            source: root.fileResolvedIcon
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.ClosedHandCursor
        acceptedButtons: Qt.NoButton
    }
}
