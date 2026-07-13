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
            title: Translation.tr("Notifications")
            icon: "notifications"

            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Timeout duration (ms)")
                value: Config.options.notifications.timeout
                from: 1000
                to: 10000
                stepSize: 500
                onValueChanged: {
                    Config.options.notifications.timeout = value;
                }
            }

            ConfigSpinBox {
                icon: "zoom_in"
                text: Translation.tr("Notification size (%)")
                value: Config.options.notifications.zoomPercent
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.notifications.zoomPercent = value;
                }
            }

            ConfigSwitch {
                buttonIcon: "desktop_windows"
                text: Translation.tr("Force specific monitor")
                checked: Config.options.notifications.monitor.enable
                onCheckedChanged: {
                    Config.options.notifications.monitor.enable = checked;
                }
            }

            ConfigTextField {
                text: Translation.tr("Force monitor name")
                icon: "desktop_windows"
                visible: Config.options.notifications.monitor.enable
                placeholderText: Translation.tr("Monitor Name (e.g. eDP-1)")
                inputText: Config.options.notifications.monitor.name

                textField.onTextChanged: {
                    if (textField.activeFocus) {
                        Config.options.notifications.monitor.name = textField.text;
                    }
                }
            }

            ConfigSwitch {
                buttonIcon: "counter_2"
                text: Translation.tr("Show unread count")
                checked: Config.options.bar.indicators.notifications.showUnreadCount
                onCheckedChanged: {
                    Config.options.bar.indicators.notifications.showUnreadCount = checked;
                }
            }

            ContentSubsection {
                title: Translation.tr("Notification indicator style")
                icon: "notifications"

                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.notification
                    onSelected: newValue => { Config.options.bar.styles.notification = newValue; }
                    options: [
                        { displayName: Translation.tr("Default"),    icon: "style",     value: "default" },
                        { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Notification position")
                icon: "place"

                ConfigSelectionArray {
                    currentValue: Config.options.notifications.position
                    onSelected: newValue => { Config.options.notifications.position = newValue; }
                    options: [
                        { displayName: Translation.tr("Top Left"),     icon: "north_west", value: "top_left" },
                        { displayName: Translation.tr("Top Right"),    icon: "north_east", value: "top_right" },
                        { displayName: Translation.tr("Bottom Left"),  icon: "south_west", value: "bottom_left" },
                        { displayName: Translation.tr("Bottom Right"), icon: "south_east", value: "bottom_right" }
                    ]
                }
            }
        }

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
