import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "photo_weather_2x1"

    implicitWidth: 492
    implicitHeight: 240

    readonly property var currentData: Weather.data

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg
    readonly property color subtextColorOnBg: WidgetColorScheme.subtextColorOnBg

    StyledDropShadow {
        id: shadowEffect
        target: outerBorder
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    readonly property string cleanSource: {
        let entry = Config.options.background.widgets[root.configEntryName];
        let path = (entry && entry.imagePath && entry.imagePath !== "") ? entry.imagePath : Config.options.background.widgets.photo.imagePath;
        if (!path || path === "") return "";
        const qIdx = path.indexOf("?");
        if (qIdx !== -1) path = path.substring(0, qIdx);
        return path.startsWith("file://") ? path : ("file://" + path);
    }

    readonly property bool isAnimated: {
        const lower = root.cleanSource.toLowerCase();
        return lower.includes(".gif") || lower.includes(".webp");
    }

    readonly property bool shouldPlay: {
        return root.visible && root.opacity > 0 && root.isAnimated
            && !GlobalStates.screenLocked
            && !GlobalStates.activeWorkspaceHasWindows;
    }

    Rectangle {
        id: outerBorder
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: "transparent"
        border.color: WidgetColorScheme.cardBgColor
        border.width: 4

        Item {
            id: innerContent
            anchors.fill: parent
            anchors.margins: outerBorder.border.width / 2

            Rectangle {
                id: fallbackBg
                anchors.fill: parent
                radius: Math.max(0, outerBorder.radius - (outerBorder.border.width / 2))
                color: WidgetColorScheme.innerShapeColor
            }

            // Static Image loader (hardware-accelerated, zero QMovie overhead)
            Image {
                id: staticImg
                anchors.fill: parent
                source: !root.isAnimated ? root.cleanSource : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: !root.isAnimated && status === Image.Ready

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: staticImg.width
                        height: staticImg.height
                        radius: Math.max(0, outerBorder.radius - (outerBorder.border.width / 2))
                    }
                }
            }

            // Animated GIF loader (only active when isAnimated is true)
            AnimatedImage {
                id: photoImage
                anchors.fill: parent
                source: root.isAnimated ? root.cleanSource : ""
                fillMode: Image.PreserveAspectCrop
                playing: root.shouldPlay
                paused: !root.shouldPlay
                asynchronous: true
                cache: false
                visible: root.isAnimated && status === Image.Ready

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: photoImage.width
                        height: photoImage.height
                        radius: Math.max(0, outerBorder.radius - (outerBorder.border.width / 2))
                    }
                }
            }

            // Bottom glass/overlay pill container
            Item {
                id: overlayContainer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 14
                height: 76
                visible: {
                    let entry = Config.options.background.widgets[root.configEntryName];
                    return entry && entry.showOverlay !== undefined ? entry.showOverlay : true;
                }

                // Semi-transparent color overlay
                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.windowRounding
                    color: ColorUtils.applyAlpha(WidgetColorScheme.cardBgColor, 0.75)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        StyledText {
                            text: (root.currentData && root.currentData.wDesc) ? root.currentData.wDesc : Translation.tr("Clear Sky")
                            color: root.textColorOnBg
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        StyledText {
                            text: {
                                const humidity = (root.currentData && root.currentData.humidity !== undefined) ? String(root.currentData.humidity) : "";
                                const city = (root.currentData && root.currentData.city) ? root.currentData.city : "";
                                if (humidity && city) {
                                    return Translation.tr("Humidity %1% in %2").arg(humidity).arg(city);
                                } else if (city) {
                                    return city;
                                } else if (humidity) {
                                    return Translation.tr("Humidity %1%").arg(humidity);
                                }
                                return "";
                            }
                            color: root.subtextColorOnBg
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Normal
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    // Circle 1: Temperature display
                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: width / 2
                        color: WidgetColorScheme.innerShapeColor

                        StyledText {
                            anchors.centerIn: parent
                            text: (root.currentData && root.currentData.temp) ? root.currentData.temp.replace("°C", "°").replace("°F", "°") : "--°"
                            color: WidgetColorScheme.textColorOnBg
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                        }
                    }

                    // Circle 2: Weather icon circle
                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: width / 2
                        color: Appearance.colors.colPrimary

                        Image {
                            anchors.centerIn: parent
                            source: WeatherIcons.getWeatherIcon(root.currentData?.wCode ?? 113, false)
                            sourceSize: Qt.size(26, 26)
                        }
                    }
                }
            }
        }
    }
}
