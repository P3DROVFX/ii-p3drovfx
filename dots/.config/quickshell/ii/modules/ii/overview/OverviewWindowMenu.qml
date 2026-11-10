pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.contextMenu

/**
 * The window menu that drops from an app chip.
 *
 * Groups with a gap between them instead of a divider: what to do with the
 * window, then how to end it. `progress` (0 → 1) unrolls it from the edge
 * that faces the chip, so it opens downwards or, with `upwards`, from below.
 *
 * The entries are arranged by the user under "overviewWindow"
 * (ContextMenus): the groups come from the arrangement's separators, their
 * own commands run with the window's address as $II_CONTEXT_TARGET, and the
 * compact style shortens the rows, fits the width to them and puts the
 * entries placed in the icon bar on a card of their own on top.
 */
Item {
    id: root

    property bool floating: false
    property bool fullscreen: false
    property bool pinned: false
    property bool canScreenshot: true
    property bool upwards: false
    property real progress: 0
    property bool animationsEnabled: true
    property string customTarget: ""

    signal actionTriggered(string id)

    readonly property bool dense: ContextMenus.compact
    readonly property real padding: root.dense ? ContextMenus.compactPadding : OverviewStyle.menuPadding
    readonly property real rowGap: root.dense ? 1 : OverviewStyle.menuGroupGap
    readonly property real sectionGap: root.dense ? 6 : OverviewStyle.menuSectionGap

    readonly property var liveEntries: [
        { id: "screenshot", symbol: "screenshot_region", title: Translation.tr("Screenshot"), toggled: false, shown: root.canScreenshot, danger: false },
        { id: "float", symbol: root.floating ? "grid_view" : "picture_in_picture", title: root.floating ? Translation.tr("Tile") : Translation.tr("Float"), toggled: false, shown: true, danger: false },
        { id: "fullscreen", symbol: root.fullscreen ? "fullscreen_exit" : "fullscreen", title: Translation.tr("Fullscreen"), toggled: root.fullscreen, shown: true, danger: false },
        { id: "pin", symbol: "keep", title: root.pinned ? Translation.tr("Unpin") : Translation.tr("Pin"), toggled: root.pinned, shown: root.floating, danger: false },
        { id: "close", symbol: "close", title: Translation.tr("Close"), toggled: false, shown: true, danger: true },
        { id: "kill", symbol: "skull", title: Translation.tr("Force quit"), toggled: false, shown: true, danger: true }
    ].filter(item => item.shown)
    readonly property var arranged: ContextMenus.arrange("overviewWindow", root.liveEntries)
    readonly property var groups: ContextMenus.groupsOf(root.arranged.rows)
    readonly property var barEntries: root.arranged.bar.map(e => Object.assign({ "destructive": e.danger === true }, e))

    function trigger(entry: var): void {
        if (entry.custom)
            ContextMenus.runCustom(entry, root.customTarget);
        // The host closes the menu on any id it is handed.
        root.actionTriggered(entry.id);
    }

    // Compact: as wide as the rows need (OverviewMenuItem's own arithmetic),
    // within ContextMenus' bounds.
    FontMetrics {
        id: labelMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.smallie + 1
    }
    readonly property real naturalWidth: {
        let widest = ContextMenus.barNaturalWidth(root.barEntries.length);
        for (const e of root.arranged.rows) {
            if (e.separator)
                continue;
            widest = Math.max(widest, 10 + 18 + 10 + labelMetrics.advanceWidth(e.title ?? "") + 10 + (e.toggled ? 22 : 0));
        }
        return widest + root.padding * 2;
    }
    readonly property real baseWidth: root.dense
        ? Math.max(ContextMenus.compactMinWidth, Math.min(ContextMenus.compactMaxWidth, Math.ceil(root.naturalWidth)))
        : OverviewStyle.menuWidth
    // The user's menu size: laid out at its own size, scaled from the corner,
    // and reported to the chip at the size it takes on screen.
    readonly property real zoom: ContextMenus.scale
    implicitWidth: root.baseWidth * root.zoom
    implicitHeight: content.implicitHeight * root.zoom
    opacity: Math.min(1, root.progress * 2)

    Item {
        id: scaler
        width: root.baseWidth
        height: content.implicitHeight
        scale: root.zoom
        transformOrigin: Item.TopLeft

    // Unrolls from the chip's side; the content keeps its size and is revealed.
    Item {
        id: slot
        width: parent.width
        height: content.implicitHeight * root.progress
        y: root.upwards ? parent.height - height : 0
        clip: true

        Column {
            id: content
            width: parent.width
            y: root.upwards ? 0 : slot.height - implicitHeight
            spacing: root.sectionGap
            transform: Translate {
                y: (1 - root.progress) * (root.upwards ? OverviewStyle.menuSlide : -OverviewStyle.menuSlide)
            }

            // The icon bar, on a card of its own like a group.
            Item {
                width: content.width
                height: barRow.implicitHeight + root.padding * 2
                visible: root.barEntries.length > 0

                StyledRectangularShadow {
                    target: barShape
                }
                Rectangle {
                    id: barShape
                    anchors.fill: parent
                    radius: OverviewStyle.menuRadiusOuter
                    color: OverviewStyle.colMenuContainer
                }
                ContextMenuIconBar {
                    id: barRow
                    x: root.padding
                    y: root.padding
                    width: parent.width - root.padding * 2
                    entries: root.barEntries
                    hostRadius: OverviewStyle.menuRadiusOuter
                    hostPadding: root.padding
                    onActivated: (entry, button) => root.trigger(entry)
                }
            }

            Repeater {
                model: root.groups
                delegate: Item {
                    id: group
                    required property var modelData
                    width: content.width
                    height: rows.implicitHeight + root.padding * 2

                    StyledRectangularShadow {
                        target: groupShape
                    }
                    Rectangle {
                        id: groupShape
                        anchors.fill: parent
                        radius: OverviewStyle.menuRadiusOuter
                        color: OverviewStyle.colMenuContainer
                    }

                    Column {
                        id: rows
                        x: root.padding
                        y: root.padding
                        width: parent.width - root.padding * 2
                        spacing: root.rowGap

                        Repeater {
                            model: group.modelData
                            delegate: OverviewMenuItem {
                                required property var modelData
                                required property int index
                                width: rows.width
                                dense: root.dense
                                symbol: modelData.symbol
                                label: modelData.title
                                toggled: modelData.toggled === true
                                danger: modelData.danger === true
                                first: index === 0
                                last: index === group.modelData.length - 1
                                animationsEnabledHere: root.animationsEnabled
                                onClicked: root.trigger(modelData)
                            }
                        }
                    }
                }
            }
        }
    }
    }
}
