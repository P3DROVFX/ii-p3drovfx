pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.panels.windowSwitcher
import qs.modules.settings.configs.colors
import "../../../../services/windowSwitcher/WindowSwitcherLogic.js" as Logic

/**
 * Alt+Tab over your wallpaper, as it is set, built at its real size and scaled to the card:
 * the island's cover flow (its covers drawn the way IslandWindowSwitcher draws them) or the
 * floating panel made of the panel's own SwitcherCard, SwitcherTitleLine and SwitcherHints,
 * holding your real windows with the second most recent selected, as Alt+Tab starts.
 * Chips on the corner say which windows it lists and when it peeks.
 */
Item {
    id: root

    readonly property var switcher: Config.options.windowSwitcher
    readonly property bool on: root.switcher.enable
    readonly property bool inIsland: !Config.options.bar.floatingNotch.disableWindowSwitcher
    readonly property bool thumbnails: root.switcher.showThumbnails
    readonly property bool hints: root.switcher.showKeyHints

    // Your windows (the Settings window aside), most recent first, as the service builds them.
    readonly property var entries: {
        const toplevels = WindowSwitcher.toplevelsByAddress();
        return (HyprlandData.windowList ?? [])
            .filter(c => c && !/quickshell/i.test(c.class ?? "") && (c.workspace?.id ?? 0) > 0 && c.mapped !== false)
            .sort((a, b) => (a.focusHistoryID ?? 99) - (b.focusHistoryID ?? 99))
            .slice(0, 6)
            .map(c => Logic.entryFor(c, toplevels, WindowSwitcher.appName));
    }
    readonly property int selected: Math.min(1, Math.max(0, root.entries.length - 1))

    // Pictures stream for a moment after the card shows, then keep their last frame.
    property bool capturing: false
    onVisibleChanged: if (visible) warm.restart()
    Component.onCompleted: warm.restart()
    Timer {
        id: warm
        interval: 1
        onTriggered: {
            root.capturing = true;
            cool.restart();
        }
    }
    Timer {
        id: cool
        interval: 1500
        onTriggered: root.capturing = false
    }

    ClippingRectangle {
        id: stage
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: Appearance.colors.colLayer1

        ColorsWallpaperImage {
            anchors.fill: parent
            targetMode: "desktop"
        }

        // ── Island: covers turned towards the selection, the title, the keys ─
        Item {
            id: island

            // The island's large face at its real size (IslandWindowSwitcher's defaults).
            readonly property real coverWidth: 300
            readonly property real coverHeight: 188
            readonly property real topPadding: 16
            readonly property real titleGap: 10
            readonly property real titleHeight: 22
            readonly property real hintsHeight: root.hints ? 20 : 0
            readonly property real realWidth: island.coverWidth * 3.1
            readonly property real realHeight: island.topPadding + island.coverHeight + island.titleGap
                + island.titleHeight + island.hintsHeight + 18
            readonly property real fit: Math.min(1, (stage.width - 48) / island.realWidth, (stage.height - 64) / island.realHeight)

            visible: root.inIsland
            width: island.realWidth
            height: island.realHeight
            x: Math.round((stage.width - island.realWidth) / 2)
            y: 10
            scale: island.fit
            transformOrigin: Item.Top

            Rectangle {
                anchors.fill: parent
                radius: Math.min(height / 2, 48)
                color: "#000000"
            }

            Repeater {
                model: root.entries

                delegate: Item {
                    id: cover

                    required property var modelData
                    required property int index
                    // Offset from the selection: c leans and shrinks, d places.
                    readonly property real d: cover.index - root.selected
                    readonly property real c: Math.max(-1, Math.min(1, cover.d))
                    readonly property real a: Math.abs(cover.d)
                    readonly property real sourceAspect: picture.hasContent && picture.sourceSize.width > 0
                        ? picture.sourceSize.width / picture.sourceSize.height
                        : cover.modelData.width / Math.max(1, cover.modelData.height)

                    visible: cover.a < 2.75
                    x: island.width / 2 - island.coverWidth / 2 + cover.c * island.coverWidth * 0.62
                        + (cover.d - cover.c) * island.coverWidth * 0.24
                    y: island.topPadding
                    z: -cover.a
                    width: island.coverWidth
                    height: island.coverHeight
                    scale: 1 - Math.abs(cover.c) * 0.16
                    transform: Rotation {
                        origin.x: island.coverWidth / 2
                        origin.y: island.coverHeight / 2
                        axis { x: 0; y: 1; z: 0 }
                        angle: -cover.c * 50
                    }

                    ClippingRectangle {
                        id: frame
                        anchors.centerIn: parent
                        width: root.thumbnails ? Math.round(Math.min(island.coverWidth, island.coverHeight * cover.sourceAspect)) : island.coverWidth
                        height: root.thumbnails ? Math.round(Math.min(island.coverHeight, island.coverWidth / cover.sourceAspect)) : island.coverHeight
                        radius: Appearance.rounding.normal
                        color: root.thumbnails ? Appearance.colors.colLayer1 : Appearance.colors.colLayer2

                        ScreencopyView {
                            id: picture
                            anchors.fill: parent
                            captureSource: root.thumbnails && root.visible && cover.modelData.toplevel ? cover.modelData.toplevel : null
                            live: root.capturing
                            constraintSize: Qt.size(island.coverWidth, island.coverHeight)
                        }
                        Image {
                            anchors.centerIn: parent
                            visible: !picture.hasContent
                            source: Quickshell.iconPath(AppSearch.guessIcon(cover.modelData.appClass), "image-missing")
                            width: Math.round(Math.min(96, parent.height * 0.45))
                            height: width
                            sourceSize: Qt.size(width, height)
                            asynchronous: true
                        }
                        // Neighbours sink back into the island.
                        Rectangle {
                            anchors.fill: parent
                            color: Appearance.m3colors.m3shadow
                            readonly property real t: Math.min(cover.a, 2) / 2
                            opacity: 0.44 * t * t * (3 - 2 * t)
                        }
                    }

                    // The selection ring.
                    Rectangle {
                        anchors.centerIn: frame
                        width: frame.width + 6
                        height: frame.height + 6
                        radius: frame.radius + 3
                        color: "transparent"
                        border.width: 2
                        border.color: Appearance.colors.colPrimary
                        opacity: Math.max(0, 1 - Math.abs(cover.c) * 1.5)
                    }
                }
            }

            SwitcherTitleLine {
                anchors.horizontalCenter: parent.horizontalCenter
                y: island.topPadding + island.coverHeight + island.titleGap
                height: island.titleHeight
                maxWidth: island.coverWidth * 1.8
                entry: root.entries[root.selected] ?? null
            }
            SwitcherHints {
                anchors.horizontalCenter: parent.horizontalCenter
                y: island.topPadding + island.coverHeight + island.titleGap + island.titleHeight
                width: island.width - 48
                height: island.hintsHeight
                visible: root.hints
            }
        }

        // ── Panel: the floating switcher's own cards ────────────────────────
        Rectangle {
            id: panel

            // WindowSwitcherPanel's measures on a 1920×1080 screen, one row.
            readonly property real padding: 14
            readonly property real cardPadding: 10
            readonly property real gap: 6
            readonly property real titleHeight: 22
            readonly property real boxHeight: root.thumbnails ? 170 : 64
            readonly property real boxWidth: root.thumbnails ? Math.round(panel.boxHeight * 1.6) : 112
            readonly property real cellWidth: panel.boxWidth + panel.cardPadding * 2
            readonly property real cellHeight: panel.boxHeight + panel.titleHeight + panel.cardPadding * 3
            readonly property int count: Math.max(1, root.entries.length)
            readonly property real footerHeight: 10 + 24 + (root.hints ? 20 : 0)
            readonly property real realWidth: Math.max(root.hints ? 380 : 260,
                panel.count * (panel.cellWidth + panel.gap) - panel.gap + panel.padding * 2)
            readonly property real realHeight: panel.cellHeight + panel.footerHeight + panel.padding * 2
            readonly property real fit: Math.min(1, (stage.width - 48) / panel.realWidth, (stage.height - 72) / panel.realHeight)

            visible: !root.inIsland
            width: panel.realWidth
            height: panel.realHeight
            x: Math.round((stage.width - panel.realWidth) / 2)
            y: Math.round((stage.height - 48 - panel.realHeight) / 2)
            scale: panel.fit
            radius: Appearance.rounding.windowRounding
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            Item {
                x: panel.padding
                y: panel.padding
                width: panel.width - panel.padding * 2
                height: panel.cellHeight

                Rectangle {
                    x: root.selected * (panel.cellWidth + panel.gap)
                    width: panel.cellWidth
                    height: panel.cellHeight
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSecondaryContainer
                }

                Repeater {
                    model: root.entries

                    delegate: SwitcherCard {
                        required property var modelData
                        required property int index
                        entry: modelData
                        selected: index === root.selected
                        thumbnails: root.thumbnails
                        boxWidth: panel.boxWidth
                        boxHeight: panel.boxHeight
                        padding: panel.cardPadding
                        capturing: root.capturing && root.thumbnails
                        x: index * (panel.cellWidth + panel.gap)
                        width: panel.cellWidth
                        height: panel.cellHeight
                    }
                }
            }

            Item {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    margins: panel.padding
                }
                height: panel.footerHeight

                SwitcherTitleLine {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 10
                    height: 24
                    maxWidth: parent.width
                    entry: root.entries[root.selected] ?? null
                }
                SwitcherHints {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 34
                    width: parent.width
                    height: 20
                    visible: root.hints
                }
            }
        }

        // ── What it lists, and the peek ─────────────────────────────────────
        Row {
            anchors {
                left: parent.left
                bottom: parent.bottom
                margins: 12
            }
            spacing: 8

            Repeater {
                model: [
                    { icon: "workspaces", text: root.switcher.includeOtherWorkspaces ? Translation.tr("All workspaces") : Translation.tr("This workspace") },
                    { icon: "monitor", text: root.switcher.currentMonitorOnly ? Translation.tr("This monitor") : Translation.tr("All monitors") },
                    { icon: "visibility", text: root.switcher.peekDelayMs > 0 ? Translation.tr("Peek after %1 ms").arg(root.switcher.peekDelayMs) : Translation.tr("No peek") }
                ]
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    implicitWidth: chipRow.implicitWidth + 24
                    implicitHeight: 32
                    radius: height / 2
                    color: Appearance.colors.colSurfaceContainerHigh

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.icon
                            iconSize: 16
                            color: Appearance.colors.colOnSurface
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.text
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }
            }
        }

        // ── Off ─────────────────────────────────────────────────────────────
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer1
            opacity: root.on ? 0 : 0.78
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Rectangle {
                anchors.centerIn: parent
                implicitWidth: offRow.implicitWidth + 32
                implicitHeight: 40
                radius: height / 2
                color: Appearance.colors.colSurfaceContainerHigh
                Row {
                    id: offRow
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "keyboard_off"
                        iconSize: 20
                        color: Appearance.colors.colOnSurface
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Alt+Tab is left to Hyprland")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }
                }
            }
        }
    }
}
