pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import "../../../ii/dock"
import "../../../ii/dock/DockMagnification.js" as DockMagnification

/**
 * The magnification, to try: the dock's own app buttons on a tray at the bottom of
 * the wallpaper, magnified under the pointer by the dock's own lens arithmetic
 * (DockMagnification.js: the field, the content scale, the room it pushes open)
 * with the saved intensity, reach, curve, motion and spacing. Nothing launches.
 */
Item {
    id: root

    readonly property var dock: Config.options.dock
    readonly property var live: GlobalStates.dockContents.length > 0 ? GlobalStates.dockContents[0] : null
    readonly property var apps: {
        const items = root.live ? (root.live.modelItems ?? []) : [];
        return items.filter(item => item?.type === "app").slice(0, 9);
    }

    DockPreviewContext {
        id: ctx
        live: root.live
        dockPos: "bottom"
    }

    readonly property real slot: ctx.buttonSlotSize
    readonly property real spacing: root.dock.iconSpacing ?? 0
    readonly property real scaleMax: root.dock.magnificationScale ?? 1.5
    readonly property real radiusPx: Math.max(Appearance.sizes.dockButtonSize, root.slot * (root.dock.magnificationInfluenceRadius ?? 2.35))
    readonly property string curve: root.dock.magnificationCurve ?? "cosine"
    readonly property bool dynamicSpacing: root.dock.magnificationDynamicSpacing ?? true
    readonly property var motion: {
        switch (root.dock.magnificationMotion ?? "balanced") {
        case "fast": return Appearance.animation.dockMagnificationScale.fast;
        case "smooth": return Appearance.animation.dockMagnificationScale.smooth;
        default: return Appearance.animation.dockMagnificationScale.balanced;
        }
    }

    readonly property real baseLength: root.apps.length * root.slot + Math.max(0, root.apps.length - 1) * root.spacing
    readonly property real fitScale: Math.max(0.4, Math.min(1, (root.width - 60) / Math.max(1, root.baseLength * root.scaleMax)))

    // The lens: a pointer that trails by the motion's lag, and a strength that
    // grows in while the pointer is over the tray and eases out after it leaves.
    property real pointerTarget: 0
    property real pointer: root.pointerTarget
    Behavior on pointer {
        enabled: root.motion.pointerLag > 0
        NumberAnimation {
            duration: root.motion.pointerLag * 3
            easing.type: Easing.OutCubic
        }
    }
    readonly property bool lensOn: trayHover.hovered
    property real strength: root.lensOn ? 1 : 0
    Behavior on strength {
        NumberAnimation {
            duration: root.lensOn ? root.motion.strengthDuration : root.motion.exitDuration
            easing.type: Easing.OutCubic
        }
    }

    function weightAt(index) {
        const center = index * (root.slot + root.spacing) + root.slot / 2;
        return DockMagnification.weightForDistance(Math.abs(root.pointer - center), root.radiusPx, root.curve, root.strength);
    }

    // ── Backdrop: the bottom of the desktop ──────────────────────────────
    ClippingRectangle {
        anchors.fill: parent
        // The screen's own corners: a larger radius cut the ends of attached docks.
        radius: Appearance.rounding.windowRounding
        color: Appearance.colors.colLayer2

        Item {
            width: parent.width
            height: Math.max(parent.height, parent.width * 9 / 16)
            y: parent.height - height
            ColorsWallpaperImage {
                anchors.fill: parent
                targetMode: "desktop"
                visible: root.visible
            }
        }
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0
            opacity: 0.16
        }

        // ── The tray, at the dock's pixel size (scaled down only to fit) ──
        Item {
            id: scene
            width: root.width / root.fitScale
            height: root.height / root.fitScale
            scale: root.fitScale
            transformOrigin: Item.TopLeft

            Rectangle {
                id: tray
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(Appearance.sizes.elevationMargin * 1.2)
                width: row.width
                height: ctx.buttonSlotHeight
                radius: (root.dock.dockRadius ?? -1) >= 0 ? root.dock.dockRadius : Appearance.rounding.windowRounding + 12
                color: Appearance.colors.colLayer0

                HoverHandler {
                    id: trayHover
                    // Measured against the unmagnified layout, as the dock does.
                    onPointChanged: {
                        const p = trayHover.point.position.x - (tray.width - root.baseLength) / 2;
                        root.pointerTarget = p;
                    }
                }

                Row {
                    id: row
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    spacing: root.spacing

                    Repeater {
                        model: root.apps
                        delegate: Item {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property real weight: root.weightAt(cell.index)
                            // DockButton reads this from its parent chain.
                            readonly property real _magnificationScale: DockMagnification.contentScale(cell.weight, root.scaleMax, 1)
                            width: root.slot + DockMagnification.layoutExtra(cell.weight, root.scaleMax, root.slot, 1, root.dynamicSpacing)
                            height: ctx.buttonSlotHeight

                            DockAppButton {
                                anchors.centerIn: parent
                                appToplevel: cell.modelData.appData
                                dockContent: ctx
                                delegateIndex: cell.index
                            }
                        }
                    }
                }

                // A picture: the buttons never get the click.
                DockInputShield {
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }
    }
}
