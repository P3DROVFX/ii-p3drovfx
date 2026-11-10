pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.contextMenu
import qs.modules.settings.configs.colors

/**
 * The menu the page is editing, drawn by the shell's own menu pieces over the
 * wallpaper: the user's arrangement (ContextMenus.arrange), the chosen style,
 * the cascade card beside its row when submenus open as cards, and the open
 * motion, replayed on demand. Entries that only exist at runtime (an app's
 * actions) stand in as sample rows. Nothing on the stage acts.
 */
Item {
    id: root

    property string menuId: "desktop"
    readonly property var definition: ContextMenus.definition(root.menuId)

    readonly property real stageMinHeight: 300
    readonly property real stageMaxHeight: 420
    readonly property real scrimOpacity: 0.16
    readonly property real edgeMargin: 11
    readonly property real pillPadding: 18
    readonly property real tagGap: 12
    readonly property real compactBreak: 600
    readonly property real menuMargin: 24

    readonly property bool dense: ContextMenus.compact
    readonly property bool cascade: ContextMenus.cascade
    readonly property real padding: root.dense ? ContextMenus.compactPadding : ContextMenus.comfortablePadding
    readonly property bool compact: root.width < root.compactBreak
    readonly property real preferredHeight: Math.max(root.stageMinHeight, Math.min(root.stageMaxHeight, root.width * 0.42))

    // Every declared entry stands in for itself; a runtime block shows as
    // two sample rows so its place in the order reads.
    readonly property var liveEntries: (root.definition?.entries ?? []).filter(e => !e.separator && !e.header).map(e => e.block
        ? {
            "id": e.id,
            "items": [
                { "id": e.id + ":1", "symbol": e.symbol, "title": Translation.tr("%1 (from the app)").arg(Translation.tr(e.title)) },
                { "id": e.id + ":2", "symbol": e.symbol, "title": Translation.tr("…") }
            ]
        }
        : {
            "id": e.id,
            "symbol": e.symbol,
            "title": Translation.tr(e.title),
            "submenu": e.submenu === true,
            "destructive": e.id === "remove" || e.id === "close" || e.id === "kill" || e.id === "empty" || e.id === "__remove"
        })
    readonly property var arranged: ContextMenus.arrange(root.menuId, root.liveEntries)
    readonly property var firstSubmenu: root.arranged.rows.find(e => e.submenu) ?? null

    function replay(): void {
        motion.playEnter(true);
        sideMotion.playEnter(true);
    }
    onMenuIdChanged: root.replay()
    onDenseChanged: root.replay()
    onCascadeChanged: root.replay()
    Component.onCompleted: root.replay()

    ClippingRectangle {
        id: backdrop
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer2

        ColorsWallpaperImage {
            anchors.fill: parent
            targetMode: "desktop"
            visible: root.visible
        }
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0
            opacity: root.scrimOpacity
        }
    }

    // The menu, scaled down only when the stage is shorter than it. Outside
    // the clip: it never reaches the edge, and its shadow should not be cut.
    Item {
        id: menuLayer
        anchors.fill: parent

        Item {
            id: menuHolder
            // At the user's size (ContextMenus.scale), smaller only when the stage is shorter.
            readonly property real fit: Math.min(ContextMenus.scale, (root.height - root.menuMargin * 2) / Math.max(1, menu.height))
            x: Math.round((root.width - (menu.width + (side.visible ? side.width + ContextMenus.cascadeGap : 0)) * menuHolder.fit) / 2)
            y: root.menuMargin
            width: menu.width
            height: menu.height
            scale: menuHolder.fit
            transformOrigin: Item.TopLeft

            ContextMenuMotion {
                id: motion
            }

            Item {
                id: menu
                width: !root.dense ? 268
                    : Math.max(ContextMenus.compactMinWidth, Math.min(ContextMenus.compactMaxWidth,
                        Math.ceil(Math.max(list.implicitWidth, bar.implicitWidth) + root.padding * 2)))
                height: card.height
                opacity: motion.reveal
                scale: motion.scale
                transformOrigin: Item.TopLeft

                StyledRectangularShadow {
                    target: card
                }
                Rectangle {
                    id: card
                    width: parent.width
                    height: column.implicitHeight + root.padding * 2
                    radius: Appearance.rounding.windowRounding
                    color: Appearance.m3colors.m3surfaceContainer

                    ColumnLayout {
                        id: column
                        x: root.padding
                        y: root.padding
                        width: parent.width - root.padding * 2
                        spacing: root.dense ? 4 : 3

                        ContextMenuIconBar {
                            id: bar
                            Layout.fillWidth: true
                            entries: root.arranged.bar
                            hostPadding: root.padding
                        }
                        ContextMenuList {
                            id: list
                            Layout.fillWidth: true
                            rows: root.arranged.rows
                            dense: root.dense
                            separators: root.dense || root.definition?.groups === true
                            hostPadding: root.padding
                            openId: root.cascade && root.firstSubmenu ? root.firstSubmenu.id : ""
                        }
                    }
                }
            }

            // Cascade: a sample page beside the first row that has one.
            Item {
                id: side
                visible: root.cascade && root.firstSubmenu !== null
                readonly property Item anchorRow: {
                    // Read so the row is looked up again when the list changes.
                    const rows_ = root.arranged.rows.length + list.implicitHeight;
                    if (!root.firstSubmenu || rows_ < 0)
                        return null;
                    const rows = list.focusRows();
                    return rows.find(r => r.entry && r.entry.id === root.firstSubmenu.id) ?? null;
                }
                x: menu.width + ContextMenus.cascadeGap
                y: side.anchorRow ? side.anchorRow.mapToItem(menuHolder, 0, 0).y - root.padding : 0
                width: Math.round(menu.width * 0.86)
                height: sideCard.height
                opacity: Math.min(motion.reveal, sideMotion.reveal)
                scale: 0.95 + 0.05 * sideMotion.grow
                transformOrigin: Item.TopLeft

                ContextMenuMotion {
                    id: sideMotion
                }
                StyledRectangularShadow {
                    target: sideCard
                }
                Rectangle {
                    id: sideCard
                    width: parent.width
                    height: sideColumn.implicitHeight + root.padding * 2
                    radius: Appearance.rounding.windowRounding
                    color: Appearance.m3colors.m3surfaceContainer

                    ContextMenuList {
                        id: sideColumn
                        x: root.padding
                        y: root.padding
                        width: parent.width - root.padding * 2
                        dense: root.dense
                        hostPadding: root.padding
                        rows: [
                            { "id": "a", "symbol": "radio_button_checked", "title": Translation.tr("Option") },
                            { "id": "b", "symbol": "radio_button_unchecked", "title": Translation.tr("Option") },
                            { "id": "c", "symbol": "radio_button_unchecked", "title": Translation.tr("Option") }
                        ]
                    }
                }
            }
        }
    }

    // Name tag: the menu on show and where it opens.
    Rectangle {
        id: tag
        x: root.edgeMargin
        y: root.height - height - root.edgeMargin
        height: tagColumn.implicitHeight + 12
        width: Math.min(root.width - action.width - root.edgeMargin * 2 - root.tagGap,
                        tagColumn.implicitWidth + root.pillPadding * 2)
        radius: Math.min(height / 2, Appearance.rounding.large)
        color: Appearance.colors.colSurfaceContainerHigh

        ColumnLayout {
            id: tagColumn
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: root.pillPadding
                rightMargin: root.pillPadding
            }
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr(root.definition?.name ?? "")
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr(root.definition?.description ?? "")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
    }

    // Status: the shell's own menu, not a drawing of it.
    Rectangle {
        x: root.edgeMargin
        y: root.edgeMargin
        height: statusRow.implicitHeight + 12
        width: statusRow.implicitWidth + root.pillPadding * 1.5
        radius: height / 2
        color: Appearance.colors.colSurfaceContainerHigh

        RowLayout {
            id: statusRow
            anchors.centerIn: parent
            spacing: 6

            Rectangle {
                implicitWidth: 7
                implicitHeight: 7
                radius: 3.5
                color: Appearance.colors.colPrimary
            }
            StyledText {
                text: Translation.tr("Live")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
            }
        }
    }

    // Plays the open again, in the style on show.
    RippleButton {
        id: action
        anchors {
            right: parent.right
            rightMargin: root.edgeMargin
        }
        y: tag.y
        implicitHeight: tag.height
        implicitWidth: root.compact ? tag.height : actionRow.implicitWidth + root.pillPadding * 2
        buttonRadius: height / 2
        buttonRadiusPressed: Appearance.rounding.small
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive
        onClicked: root.replay()

        StyledToolTip {
            visible: root.compact && action.hovered
            text: Translation.tr("Replay")
        }

        contentItem: Item {
            RowLayout {
                id: actionRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    text: "replay"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                }
                StyledText {
                    visible: !root.compact
                    text: Translation.tr("Replay")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }
}
