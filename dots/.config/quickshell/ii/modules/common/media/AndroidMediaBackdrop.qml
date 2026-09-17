import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs.modules.common

// Existing AndroidMediaPopup artwork, vignette and shading palette. The tile
// supplies clipping and opacity while resizing; this keeps the settled look.
Item {
    id: root
    property string artSource: ""
    property bool playing: false
    readonly property bool artReady: artBlurredUnderlay.status === Image.Ready
        && artExpanded.status === Image.Ready
    readonly property real artVignetteBlur: playing ? 50 : 90
        Item {
            anchors.fill: parent

            Image {
                id: artBlurredUnderlay
                anchors.fill: parent
                source: root.artSource
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                visible: root.artSource !== ""
                layer.enabled: root.artVignetteBlur > 0
                layer.effect: MultiEffect {
                    blurEnabled: root.artVignetteBlur > 0
                    blurMax: 128
                    blur: root.artVignetteBlur / 128
                }
            }

            Item {
                id: vignetteMask
                anchors.fill: parent

                RadialGradient {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 1) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
                    }
                    horizontalRadius: width * 0.65
                    verticalRadius: height * 0.65
                }
            }

            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: vignetteMask
                }

                Image {
                    id: artExpanded
                    anchors.fill: parent
                    source: root.artSource
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    opacity: 0.85
                    visible: root.artSource !== ""
                }
            }
        }

        // The wash only exists to keep controls legible over cover art. With no
        // artwork it painted a black veil over the tile's own surface, which is
        // exactly what the empty 4x2 quick-toggle widget showed as "black background".
        Item {
            anchors.fill: parent
            visible: root.artSource !== ""
            opacity: root.playing ? 0.55 : 0.75

            Behavior on opacity {
                NumberAnimation {
                    duration: 400
                    easing.type: Easing.OutCubic
                }
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.05) }
                    GradientStop { position: 0.8; color: Qt.rgba(0, 0, 0, 0.25) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.3)
                opacity: root.playing ? 0.0 : 0.5

                Behavior on opacity {
                    NumberAnimation {
                        duration: 500
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

}
