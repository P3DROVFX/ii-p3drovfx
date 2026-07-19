import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: overlaysConfigRoot

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: page

        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
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
                    onClicked: {
                        overlaysConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/GameOverlayConfig.qml");
                    }

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

    ConfigSubPageHost {
        id: subPageOverlay

        anchors.fill: parent
        z: 10
    }

}
