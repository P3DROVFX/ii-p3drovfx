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

    configEntryName: "photo_pill_2x1"

    implicitWidth: 492
    implicitHeight: 240

    readonly property color accentBgColor: WidgetColorScheme.accentColor
    readonly property color onAccentTextColor: WidgetColorScheme.onAccentColor

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
                radius: Appearance.rounding.windowRounding
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
                        radius: Appearance.rounding.windowRounding
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
                        radius: Appearance.rounding.windowRounding
                    }
                }
            }
        }
    }
}

