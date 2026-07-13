pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs
import qs.modules.common
import qs.modules.common.functions

Item {
    id: root

    // Required properties to orient and position the gradient
    required property bool vertical
    required property bool isBottom // For horizontal: true if bottom. For vertical: true if right (bottom/right are screen-edge variants).
    required property var targetScreen

    // ── Settings/Variables for Transparent Bar Glow & Blur ───────────────────
    // Declared at the beginning for ease of maintenance as requested.
    readonly property bool enableTransparentGlow: Config.options.bar.transparentGlow ?? true
    readonly property real glowDepth: vertical ? 220 : 120 // Depth of the gradient overlay
    readonly property real blurValue: 80                  // Blur amount (0 to 128)
    readonly property real dimOpacity: 0.15                // Extra dim opacity to darken slightly
    readonly property color dimColor: "#000000"           // Dimming color

    width: vertical ? glowDepth : (parent ? parent.width : 1920)
    height: vertical ? (parent ? parent.height : 1080) : glowDepth

    visible: enableTransparentGlow && Config.options.bar.barBackgroundStyle === 0

    // Wallpaper source logic (handling video wallpapers with thumbnail)
    readonly property string wallpaperPath: Config.options?.background?.wallpaperPath ?? ""
    readonly property bool wallpaperIsVideo: wallpaperPath !== "" && (wallpaperPath.endsWith(".mp4") || wallpaperPath.endsWith(".webm") || wallpaperPath.endsWith(".mkv") || wallpaperPath.endsWith(".avi") || wallpaperPath.endsWith(".mov"))
    readonly property string wallpaperSource: wallpaperPath !== "" ? Qt.resolvedUrl(wallpaperIsVideo ? Config.options?.background?.thumbnailPath ?? "" : wallpaperPath) : ""
    // ── 1. Mask Item ──────────────────────────────────────────────────────────
    Item {
        id: linearMask
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: root.vertical ? Gradient.Horizontal : Gradient.Vertical
                // Fade from screen edge (white / fully opaque) to inner screen (transparent)
                GradientStop {
                    position: 0.0
                    color: (!root.vertical && root.isBottom) || (root.vertical && root.isBottom) ? "transparent" : "white"
                }
                GradientStop {
                    position: 1.0
                    color: (!root.vertical && root.isBottom) || (root.vertical && root.isBottom) ? "white" : "transparent"
                }
            }
        }
    }

    // ── 2. Blurred Wallpaper Layer ─────────────────────────────────────────────
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: linearMask
        }

        Image {
            id: wallpaperImage
            source: root.wallpaperSource
            fillMode: Image.PreserveAspectCrop

            // Position and size to cover the entire screen for perfect alignment
            width: root.targetScreen ? root.targetScreen.width : 1920
            height: root.targetScreen ? root.targetScreen.height : 1080

            // Shift the wallpaper image so it aligns with the monitor bounds
            x: {
                if (!root.vertical)
                    return 0;
                return root.isBottom ? -(root.targetScreen ? root.targetScreen.width - parent.width : 0) : 0;
            }
            y: {
                if (root.vertical)
                    return 0;
                return root.isBottom ? -(root.targetScreen ? root.targetScreen.height - parent.height : 0) : 0;
            }

            layer.enabled: root.blurValue > 0
            layer.effect: MultiEffect {
                blurEnabled: root.blurValue > 0
                blurMax: 128
                blur: root.blurValue / 128
            }
        }
    }

    // ── 3. Dim Gradient Layer ──────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: root.vertical ? Gradient.Horizontal : Gradient.Vertical
            GradientStop {
                position: 0.0
                color: (!root.vertical && root.isBottom) || (root.vertical && root.isBottom) ? "transparent" : ColorUtils.applyAlpha(root.dimColor, root.dimOpacity)
            }
            GradientStop {
                position: 1.0
                color: (!root.vertical && root.isBottom) || (root.vertical && root.isBottom) ? ColorUtils.applyAlpha(root.dimColor, root.dimOpacity) : "transparent"
            }
        }
    }
}
