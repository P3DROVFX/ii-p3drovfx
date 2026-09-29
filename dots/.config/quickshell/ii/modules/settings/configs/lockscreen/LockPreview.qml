import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.panels.lock
import qs.modules.ii.lock
import "LockLook.js" as LockLook

/**
 * The lock screen as the focused monitor will show it, shrunk. Bottom to top:
 * the lock wallpaper under the lock's own treatments; the desktop widgets the lock
 * keeps, each the real widget (built as a preview) where the lock puts it; and the
 * real `LockSurface` — the one Edit Mode's Lockscreen tab draws — fed the inert
 * `LockPreviewContext`. Everything is built at the monitor's size and scaled down.
 * The notifications are examples passed through the real notification list, so
 * position, privacy, size and count show as they would.
 *
 * On top, the free corners are offered to the notifications while the pointer is
 * over the preview.
 */
ClippingRectangle {
    id: root

    /// A preset being tried on (pointed at, not chosen), or null for the saved look.
    property var lookOverride: null

    readonly property var lock: Config.options.lock
    readonly property var monitor: {
        const name = Hyprland.focusedMonitor?.name ?? "";
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (screens[i].name === name)
                return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }
    readonly property real screenWidth: Math.max(1, root.monitor?.width ?? 1920)
    readonly property real screenHeight: Math.max(1, root.monitor?.height ?? 1080)
    /// Width over height of the monitor; the preview keeps it.
    readonly property real aspect: root.screenWidth / root.screenHeight
    readonly property real scaleFactor: root.width / root.screenWidth
    readonly property bool engaged: previewHover.hovered
    readonly property bool usesHyprlock: root.lock.useHyprlock

    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1

    HoverHandler {
        id: previewHover
    }

    LockEffectLayer {
        anchors.fill: parent
        screenScale: root.scaleFactor
        blurRadius: root.lookOverride ? root.lookOverride.blur : LockLook.valueOf(root.lock, "blur")
        desaturation: root.lookOverride ? root.lookOverride.desaturate : LockLook.valueOf(root.lock, "desaturate")
        colorWash: root.lookOverride ? root.lookOverride.colorWash : LockLook.valueOf(root.lock, "colorWash")
        vignette: root.lookOverride ? root.lookOverride.vignette : LockLook.valueOf(root.lock, "vignette")
    }

    readonly property var sampleNotifications: {
        const now = Date.now();
        const make = (index, appName, summary, body) => ({
            "notificationId": -1 - index,
            "appName": appName,
            "appIcon": "",
            "image": "",
            "summary": summary,
            "body": body,
            "time": now - index * 7 * 60000,
            "urgency": "normal",
            "isTransient": false
        });
        return [
            make(0, Translation.tr("Messages"), Translation.tr("Ana"), Translation.tr("Are we still on for tonight?")),
            make(1, Translation.tr("Calendar"), Translation.tr("Team sync in 15 minutes"), Translation.tr("Video call")),
            make(2, Translation.tr("Mail"), Translation.tr("Your order has shipped"), Translation.tr("Arrives on Thursday")),
            make(3, Translation.tr("Messages"), Translation.tr("Leo"), Translation.tr("Sent a photo")),
            make(4, Translation.tr("System"), Translation.tr("Updates available"), Translation.tr("12 packages can be upgraded"))
        ];
    }

    // Built at the monitor's size and scaled down as one piece, so the widgets and the
    // surface keep the lock's own geometry. The surface and some widgets carry Qt5Compat
    // effects, whose hidden sources must not outlive the Settings window (see
    // qt5compat-effects-pin-dead-windows): the Loader lets go as soon as the preview
    // leaves its window.
    Loader {
        id: screenLoader
        active: root.Window.window !== null && root.visible && root.width > 0 && !root.usesHyprlock
        asynchronous: true
        width: root.screenWidth
        height: root.screenHeight
        scale: root.scaleFactor
        transformOrigin: Item.TopLeft
        opacity: status === Loader.Ready ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        sourceComponent: Item {
            LockWidgetLayer {
                anchors.fill: parent
                monitorName: root.monitor?.name ?? ""
            }

            LockSurface {
                anchors.fill: parent
                interactive: false
                sampleNotifications: root.sampleNotifications
                context: LockPreviewContext {
                    id: previewContext
                }
                // A few typed characters, so the field shows the characters' look.
                Component.onCompleted: previewContext.currentText = "preview"
            }
        }
    }

    // ── Where the notifications go ──────────────────────────────────────
    Repeater {
        model: ["top_left", "top_right", "bottom_left", "bottom_right"]

        Item {
            id: corner
            required property string modelData
            readonly property var conf: root.lock.notifications
            readonly property real zoom: (corner.conf.zoomPercent ?? 100) / 100
            readonly property bool current: corner.conf.position === corner.modelData
            readonly property bool offered: corner.conf.enable && root.engaged && !root.usesHyprlock && !corner.current
            readonly property real margin: 20 * root.scaleFactor

            // One card's footprint on the real lock: 380 × ~60 at 100 %.
            width: 380 * corner.zoom * root.scaleFactor
            height: 60 * corner.zoom * root.scaleFactor
            x: corner.modelData.endsWith("right") ? root.width - width - corner.margin : corner.margin
            y: corner.modelData.startsWith("bottom") ? root.height - height - corner.margin : corner.margin
            opacity: corner.offered ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Rectangle {
                anchors.fill: parent
                radius: Math.min(height / 2, Appearance.rounding.normal)
                color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, cornerArea.containsMouse ? 0.45 : 0.18)
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
            DashedBorder {
                anchors.fill: parent
                radius: Math.min(height / 2, Appearance.rounding.normal)
                color: ColorUtils.applyAlpha(Appearance.colors.colOnPrimaryContainer, 0.8)
                borderWidth: 1
                dashLength: 4
                gapLength: 3
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: "notifications"
                iconSize: Math.max(14, Math.min(24, parent.height * 0.5))
                color: Appearance.colors.colOnPrimaryContainer
            }
            MouseArea {
                id: cornerArea
                anchors.fill: parent
                enabled: corner.offered
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: corner.conf.position = corner.modelData
            }
        }
    }

    // ── Hyprlock draws its own lock ─────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: root.usesHyprlock ? 0.6 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }
    Rectangle {
        anchors.centerIn: parent
        visible: root.usesHyprlock
        width: hyprlockRow.implicitWidth + 32
        height: 40
        radius: height / 2
        color: Appearance.colors.colTertiaryContainer

        Row {
            id: hyprlockRow
            anchors.centerIn: parent
            spacing: 8
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: "lock_open_right"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnTertiaryContainer
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Translation.tr("Hyprlock draws the lock screen")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnTertiaryContainer
            }
        }
    }
}
