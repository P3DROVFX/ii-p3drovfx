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

    configEntryName: "photo_minimal_temp_2x1"

    implicitWidth: 492
    implicitHeight: 240

    readonly property var currentData: Weather.data

    StyledDropShadow {
        id: shadowEffect
        target: mainCard
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
        id: mainCard
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: WidgetColorScheme.cardBgColor

        Item {
            id: innerContent
            anchors.fill: parent
            anchors.margins: 4

            Rectangle {
                id: fallbackBg
                anchors.fill: parent
                radius: Appearance.rounding.windowRounding - 4
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
                        radius: Appearance.rounding.windowRounding - 4
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
                        radius: Appearance.rounding.windowRounding - 4
                    }
                }
            }

            // Bottom-right temp badge
            Item {
                id: tempBadgeContainer
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                height: 48
                width: tempRow.implicitWidth + 32
                visible: {
                    let entry = Config.options.background.widgets[root.configEntryName];
                    return entry && entry.showOverlay !== undefined ? entry.showOverlay : true;
                }

                // Semi-transparent color overlay
                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: ColorUtils.applyAlpha(WidgetColorScheme.cardBgColor, 0.75)
                }

                RowLayout {
                    id: tempRow
                    anchors.centerIn: parent
                    spacing: 4

                    StyledText {
                        text: (root.currentData && root.currentData.temp) ? root.currentData.temp : "--°C"
                        color: WidgetColorScheme.textColorOnBg
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Bold
                    }
                }
            }
        }
    }
}
