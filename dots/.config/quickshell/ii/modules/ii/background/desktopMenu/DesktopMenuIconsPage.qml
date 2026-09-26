import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.editMode
import qs.modules.ii.background.shortcuts

/**
 * The desktop menu's "Desktop icons" page: the order, the layout and the
 * visibility of this screen's icons, all live - a sort plays on the desktop
 * behind the open menu, so the menu stays up to show it.
 *
 * Choosing the sort already in use flips its direction (the arrow on the
 * row says which). Every change here is one step of the icons' undo, which
 * the header's action button takes back.
 */
ColumnLayout {
    id: root

    signal backRequested()
    signal dismissRequested()

    required property string screenName

    spacing: 8

    // The page change, 0 -> 1, driven by the card (see DesktopMenuColorsPage).
    property real reveal: 1
    function slice(index: int): real {
        const t = (root.reveal - index * 0.14) / 0.72;
        return Math.max(0, Math.min(1, t));
    }

    readonly property var options: Config.options.background.desktopIcons
    readonly property var sources: DesktopShortcuts.otherScreens(root.screenName)

    readonly property var sorts: [
        { "key": "name", "symbol": "sort_by_alpha", "title": Translation.tr("Name") },
        { "key": "type", "symbol": "category", "title": Translation.tr("Type") },
        { "key": "added", "symbol": "schedule", "title": Translation.tr("Date added") },
        { "key": "used", "symbol": "trending_up", "title": Translation.tr("Most used") }
    ]

    component MenuRow: EditPanelRow {
        Layout.fillWidth: true
        hostRadius: Appearance.rounding.windowRounding
        hostPadding: 8
        trailingKind: "none"
    }
    component SectionLabel: StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.topMargin: 6
        Layout.bottomMargin: 1
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    // ── Header ───────────────────────────────────────────────────────────────
    EditMenuPageHeader {
        title: Translation.tr("Desktop icons")
        actionSymbol: DesktopShortcuts.canUndo ? "undo" : ""
        actionTooltip: Translation.tr("Undo (Ctrl+Z)")
        onActionRequested: DesktopShortcuts.undo()
        opacity: root.slice(0)
        transform: Translate { x: (1 - root.slice(0)) * 16 }
        onBackRequested: root.backRequested()
    }

    // ── Body ─────────────────────────────────────────────────────────────────
    // Scrolls past a height that keeps the card on a laptop screen.
    StyledFlickable {
        id: flick
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(body.implicitHeight, 470)
        contentHeight: body.implicitHeight
        clip: true
        opacity: root.slice(1)
        transform: Translate { x: (1 - root.slice(1)) * 16 }

        ColumnLayout {
            id: body
            width: flick.width
            spacing: 3

            SectionLabel {
                Layout.topMargin: 0
                text: Translation.tr("Sort by")
            }
            Repeater {
                model: root.sorts
                delegate: MenuRow {
                    required property var modelData
                    required property int index
                    readonly property bool current: root.options.sortBy === modelData.key
                    first: index === 0
                    last: false
                    symbol: modelData.symbol
                    title: modelData.title
                    selected: current && root.options.keepSorted
                    trailingKind: current ? "value" : "none"
                    valueText: current ? (root.options.sortDescending ? "↓" : "↑") : ""
                    onActivated: DesktopShortcuts.sortBy(root.screenName, modelData.key)
                }
            }
            MenuRow {
                first: false
                last: true
                symbol: "autorenew"
                title: Translation.tr("Keep sorted")
                subtitle: Translation.tr("Re-sort when icons come and go")
                trailingKind: "switch"
                switchChecked: root.options.keepSorted
                onActivated: DesktopShortcuts.setKeepSorted(!root.options.keepSorted)
            }

            SectionLabel {
                text: Translation.tr("Layout")
            }
            MenuRow {
                first: true
                last: false
                symbol: "grid_on"
                title: Translation.tr("Align to grid")
                onActivated: DesktopShortcuts.alignToGrid(root.screenName)
            }
            MenuRow {
                first: false
                last: false
                symbol: "auto_awesome_mosaic"
                title: Translation.tr("Auto-arrange")
                subtitle: Translation.tr("Drops snap to the nearest free cell")
                trailingKind: "switch"
                switchChecked: root.options.autoArrange
                onActivated: DesktopShortcuts.setAutoArrange(!root.options.autoArrange)
            }
            MenuRow {
                first: false
                last: true
                symbol: "stacks"
                title: Translation.tr("Stacks")
                subtitle: Translation.tr("Group apps, folders and files by kind")
                trailingKind: "switch"
                switchChecked: root.options.stacks
                onActivated: DesktopShortcuts.setStacks(!root.options.stacks)
            }

            SectionLabel {
                text: Translation.tr("Display")
            }
            MenuRow {
                first: true
                last: false
                symbol: "photo_size_select_large"
                title: Translation.tr("Icon size")
                trailingKind: "stepper"
                valueText: `${DesktopShortcuts.iconScale}×`
                stepDownEnabled: DesktopShortcuts.iconScale > DesktopShortcuts.iconSteps[0]
                stepUpEnabled: DesktopShortcuts.iconScale < DesktopShortcuts.iconSteps[DesktopShortcuts.iconSteps.length - 1]
                onStepUp: DesktopShortcuts.stepIconScale(1)
                onStepDown: DesktopShortcuts.stepIconScale(-1)
            }
            MenuRow {
                readonly property bool locked: Config.options.background.desktopIconsLocked ?? false
                first: false
                last: false
                symbol: locked ? "lock" : "lock_open"
                title: Translation.tr("Lock icons")
                trailingKind: "switch"
                switchChecked: locked
                onActivated: Config.options.background.desktopIconsLocked = !locked
            }
            MenuRow {
                first: false
                last: false
                symbol: DesktopShortcuts.hidden ? "visibility_off" : "visibility"
                title: Translation.tr("Show icons")
                trailingKind: "switch"
                switchChecked: !DesktopShortcuts.hidden
                onActivated: DesktopShortcuts.setHidden(!DesktopShortcuts.hidden)
            }
            MenuRow {
                first: false
                last: true
                symbol: "tune"
                title: Translation.tr("Icon appearance")
                subtitle: Translation.tr("Spacing, labels, backgrounds, badges")
                trailingKind: "chevron"
                onActivated: {
                    root.dismissRequested();
                    GlobalStates.openEditCatalogue("widgets", root.screenName, "desktopIcons");
                }
            }

            // Icons stored for another output - a monitor unplugged, or one
            // beside this - can be brought onto this screen's free cells.
            SectionLabel {
                visible: root.sources.length > 0
                text: Translation.tr("Other screens")
            }
            Repeater {
                model: root.sources
                delegate: MenuRow {
                    required property var modelData
                    required property int index
                    readonly property int count: DesktopShortcuts.itemsFor(modelData).length
                    first: index === 0
                    last: index === root.sources.length - 1
                    symbol: DesktopShortcuts.isConnected(modelData) ? "monitor" : "desktop_access_disabled"
                    title: Translation.tr("Bring icons from %1").arg(modelData)
                    subtitle: DesktopShortcuts.isConnected(modelData)
                        ? Translation.tr("%1 icons").arg(String(count))
                        : Translation.tr("%1 icons · disconnected").arg(String(count))
                    trailingKind: "add"
                    onActivated: DesktopShortcuts.moveToScreen(modelData, root.screenName, null)
                }
            }
        }
    }
}
