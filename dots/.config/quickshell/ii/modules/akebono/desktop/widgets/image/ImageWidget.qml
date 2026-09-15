pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import qs.modules.akebono.desktop.widgets

DesktopWidgetBase {
    id: root
    shadowRadius: 28
    readonly property string imgSource: widgetData.source ?? ""

    onImgSourceChanged: {
        gifLoader.sourceComponent = null;
        gifLoader.sourceComponent = gifComponent;
    }

    Squircle {
        anchors.fill: parent
        radius: 28
        smoothing: AkebonoAppearance.squircleSmoothing
        color: Appearance.colors.colLayer1
    }

    Item {
        id: imgHost
        anchors.fill: parent
        visible: root.imgSource !== ""
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Squircle {
                width: imgHost.width
                height: imgHost.height
                radius: 28
                smoothing: AkebonoAppearance.squircleSmoothing
                color: "white"
            }
        }

        Loader {
            id: gifLoader
            anchors.fill: parent
            active: root.imgSource !== ""
            sourceComponent: gifComponent
        }
    }

    Component {
        id: gifComponent
        AnimatedImage {
            anchors.fill: parent
            source: root.imgSource
            fillMode: AnimatedImage.PreserveAspectCrop
            asynchronous: true
            cache: false
            playing: true
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        visible: !imgHost.visible
        spacing: 4
        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: "add_photo_alternate"
            iconSize: 38
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: "Drop an image"
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
