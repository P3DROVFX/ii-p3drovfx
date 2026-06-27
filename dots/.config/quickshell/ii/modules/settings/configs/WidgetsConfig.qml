import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: widgetsConfigRoot

    property alias contentY: page.contentY
    property url activeSubPage: ""

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.width > 0 ? (subPageOverlay.x / subPageOverlay.width) : 1
        visible: opacity > 0

        ContentSection {
            title: Translation.tr("Widget Manager")
            icon: "widgets"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                // ── Clock Widget ───────────────────────────────────────────────
                ConfigSwitch {
                    topLeftRadius: Appearance.rounding.full
                    topRightRadius: Appearance.rounding.full
                    bottomLeftRadius: Appearance.rounding.full
                    bottomRightRadius: Appearance.rounding.full
                    buttonIcon: "schedule"
                    text: Translation.tr("Clock Widget")
                    checked: Config.options.background.widgets.clock.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.enable = checked;
                    }
                }

                RippleButton {
                    id: clockRipple
                    visible: Config.options.background.widgets.clock.enable
                    Layout.fillWidth: true
                    implicitHeight: clockRow.implicitHeight + 32
                    buttonRadius: Appearance.rounding.full
                    
                    colBackground: Appearance.colors.colTertiaryContainer
                    colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                    colRipple: Appearance.colors.colTertiaryContainerActive

                    contentItem: RowLayout {
                        id: clockRow
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
                            text: Translation.tr("Clock Options")
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
                        widgetsConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/DesktopClockWidgetConfig.qml");
                    }
                }

                Item { Layout.preferredHeight: 24 } // Long spacing

                // ── Weather Widget ─────────────────────────────────────────────
                ConfigSwitch {
                    topLeftRadius: Appearance.rounding.full
                    topRightRadius: Appearance.rounding.full
                    bottomLeftRadius: Appearance.rounding.full
                    bottomRightRadius: Appearance.rounding.full
                    buttonIcon: "cloud"
                    text: Translation.tr("Weather Widget")
                    checked: Config.options.background.widgets.weather.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.weather.enable = checked;
                    }
                }

                RippleButton {
                    id: weatherRipple
                    visible: Config.options.background.widgets.weather.enable
                    Layout.fillWidth: true
                    implicitHeight: weatherRow.implicitHeight + 32
                    buttonRadius: Appearance.rounding.full
                    
                    colBackground: Appearance.colors.colTertiaryContainer
                    colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                    colRipple: Appearance.colors.colTertiaryContainerActive

                    contentItem: RowLayout {
                        id: weatherRow
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
                            text: Translation.tr("Weather Options")
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
                        widgetsConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/DesktopWeatherWidgetConfig.qml");
                    }
                }

                Item { Layout.preferredHeight: 24 } // Long spacing

                // ── Media Widget ───────────────────────────────────────────────
                ConfigSwitch {
                    topLeftRadius: Appearance.rounding.full
                    topRightRadius: Appearance.rounding.full
                    bottomLeftRadius: Appearance.rounding.full
                    bottomRightRadius: Appearance.rounding.full
                    buttonIcon: "play_circle"
                    text: Translation.tr("Media Widget")
                    checked: Config.options.background.widgets.media.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.media.enable = checked;
                    }
                }

                RippleButton {
                    id: mediaRipple
                    visible: Config.options.background.widgets.media.enable
                    Layout.fillWidth: true
                    implicitHeight: mediaRow.implicitHeight + 32
                    buttonRadius: Appearance.rounding.full
                    
                    colBackground: Appearance.colors.colTertiaryContainer
                    colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                    colRipple: Appearance.colors.colTertiaryContainerActive

                    contentItem: RowLayout {
                        id: mediaRow
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
                            text: Translation.tr("Media Options")
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
                        widgetsConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/DesktopMediaWidgetConfig.qml");
                    }
                }

                Item { Layout.preferredHeight: 24 } // Long spacing

                // ── Date Widget ───────────────────────────────────────────────
                ConfigSwitch {
                    topLeftRadius: Appearance.rounding.full
                    topRightRadius: Appearance.rounding.full
                    bottomLeftRadius: Appearance.rounding.full
                    bottomRightRadius: Appearance.rounding.full
                    buttonIcon: "calendar_today"
                    text: Translation.tr("Date Widget")
                    checked: Config.options.background.widgets.date.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.date.enable = checked;
                    }
                }

                RippleButton {
                    id: dateRipple
                    visible: Config.options.background.widgets.date.enable
                    Layout.fillWidth: true
                    implicitHeight: dateRow.implicitHeight + 32
                    buttonRadius: Appearance.rounding.full
                    
                    colBackground: Appearance.colors.colTertiaryContainer
                    colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                    colRipple: Appearance.colors.colTertiaryContainerActive

                    contentItem: RowLayout {
                        id: dateRow
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
                            text: Translation.tr("Date Options")
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
                        widgetsConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/DateDesktopWIdgetConfig.qml");
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

        property bool isOpen: widgetsConfigRoot.activeSubPage.toString() !== ""
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
            source: widgetsConfigRoot.activeSubPage
            active: subPageOverlay.overlayActive

            onLoaded: {
                item.goBack.connect(function() {
                    widgetsConfigRoot.activeSubPage = "";
                });
            }
        }
    }
}
