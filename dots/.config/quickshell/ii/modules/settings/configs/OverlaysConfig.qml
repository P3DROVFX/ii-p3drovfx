import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: overlaysConfigRoot

    property alias contentY: page.contentY
    property url activeSubPage: ""

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.width > 0 ? (subPageOverlay.x / subPageOverlay.width) : 1
        visible: opacity > 0

        ContentSection {
            title: Translation.tr("Game Overlays")
            icon: "sports_esports"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                RippleButton {
                    id: gameOverlayRipple
                    Layout.fillWidth: true
                    implicitHeight: gameOverlayRow.implicitHeight + 32
                    buttonRadius: Appearance.rounding.full
                    
                    colBackground: Appearance.colors.colTertiaryContainer
                    colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                    colRipple: Appearance.colors.colTertiaryContainerActive

                    contentItem: RowLayout {
                        id: gameOverlayRow
                        spacing: 12
                        anchors.fill: parent
                        anchors.margins: 16
                        
                        MaterialShapeWrappedMaterialSymbol {
                            text: "settings"
                            shape: MaterialShape.Shape.Circle
                            iconSize: 18
                            padding: 6
                            fill: 1
                            color: Appearance.colors.colTertiary
                            colSymbol: Appearance.colors.colOnTertiary
                        }
                        
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Game Overlay Options")
                            font.pixelSize: Appearance.font.pixelSize.medium
                            color: Appearance.colors.colOnTertiaryContainer
                        }
                        
                        MaterialSymbol {
                            text: "arrow_forward"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnTertiaryContainer
                        }
                    }

                    onClicked: {
                        overlaysConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/GameOverlayConfig.qml");
                    }
                }
            }
        }

        ContentSection {
            title: Translation.tr("Media Overlay")
            icon: "play_circle"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ConfigSwitch {
                    buttonIcon: "linear_scale"
                    text: Translation.tr("Show slider")
                    checked: Config.options.overlay.media.showSlider
                    onCheckedChanged: {
                        Config.options.overlay.media.showSlider = checked;
                    }
                }
                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Background opacity %")
                    value: Config.options.overlay.media.backgroundOpacityPercentage
                    from: 0
                    to: 100
                    stepSize: 5
                    onValueChanged: {
                        Config.options.overlay.media.backgroundOpacityPercentage = value;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "gradient"
                    text: Translation.tr("Use lyrics gradient masking")
                    checked: Config.options.overlay.media.useGradientMask
                    onCheckedChanged: {
                        Config.options.overlay.media.useGradientMask = checked;
                    }
                }
                ConfigSpinBox {
                    icon: "format_size"
                    text: Translation.tr("Lyrics font size")
                    value: Config.options.overlay.media.lyricSize
                    from: 10
                    to: 100
                    stepSize: 1
                    onValueChanged: {
                        Config.options.overlay.media.lyricSize = value;
                    }
                }
            }
        }
    }

    Item {
        id: subPageOverlay
        width: parent.width
        height: parent.height
        y: 0
        z: 10

        property bool isOpen: overlaysConfigRoot.activeSubPage.toString() !== ""
        property bool overlayActive: isOpen

        onXChanged: {
            if (!isOpen && x >= subPageOverlay.width - 1)
                overlayActive = false;
        }
        onIsOpenChanged: {
            if (isOpen) overlayActive = true;
        }

        x: isOpen ? 0 : subPageOverlay.width

        Behavior on x {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        enabled: isOpen

        Loader {
            id: subPageLoader
            anchors.fill: parent
            source: overlaysConfigRoot.activeSubPage
            active: subPageOverlay.overlayActive

            onLoaded: {
                item.goBack.connect(function() {
                    overlaysConfigRoot.activeSubPage = "";
                });
            }
        }
    }
}
