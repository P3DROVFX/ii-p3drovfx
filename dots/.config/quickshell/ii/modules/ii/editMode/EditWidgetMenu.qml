import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets
import qs.modules.ii.contextMenu

/**
 * The per-widget menu of Edit Mode: what it is, whether it is pinned, how big
 * it is, what the lock screen does with it, and the way to take it off.
 *
 * Every row carries its own filled body and its own circled icon rather than
 * being a line of text with a hover tint - the same shape the catalogue's rows
 * and the shell's other menus use, so a menu about a widget reads as the same
 * kind of object as the panel that placed it.
 *
 * The lock behaviour is FOUR states, and a row that cycled through them said
 * only where it currently was: you had to click three times to find out what
 * the choices were, and there was no way to reach one of them at all (a
 * lock-only widget could not be brought back to the desktop). It opens a
 * chooser beside the card instead - the same side-panel gesture the shell's
 * appearance menu uses - so the four are named, described and one click away.
 *
 * It acts on the widget item the canvas resolves from the instance id, so
 * every write goes down the widget's own persisted paths (both scale paths,
 * the per-monitor fork, the history pair) and nothing here duplicates them.
 * The card is inert once the widget is gone: rows disable rather than the menu
 * vanishing under the pointer.
 */
Item {
    id: root

    property var canvas: null
    property string instanceId: ""
    signal dismissRequested()

    readonly property var widget: (canvas && canvas.widgetById) ? canvas.widgetById(instanceId) : null
    readonly property var instance: widget ? widget.widgetInstance : null
    readonly property var metadata: instance ? WidgetsRegistry.getWidgetMetadata(instance.widgetId) : null
    readonly property bool isSelected: widget !== null && canvas !== null && canvas.selectedWidgets && canvas.selectedWidgets.indexOf(widget) !== -1
    readonly property var targetWidgets: (isSelected && canvas.selectedWidgets.length > 1) ? canvas.selectedWidgets : (widget ? [widget] : [])
    readonly property int targetCount: targetWidgets.length
    readonly property bool multiSelect: targetCount > 1
    readonly property bool pinned: root.multiSelect
        ? (root.targetWidgets.length > 0 && root.targetWidgets.every(w => w && w.pinned))
        : (widget ? widget.pinned : false)
    readonly property string lockBehavior: {
        if (!root.multiSelect)
            return widget ? (widget.lockBehavior || "hide") : "hide";
        if (root.targetWidgets.length === 0)
            return "hide";
        const first = root.targetWidgets[0]?.lockBehavior || "hide";
        return root.targetWidgets.every(w => (w?.lockBehavior || "hide") === first) ? first : (widget ? (widget.lockBehavior || "hide") : first);
    }
    readonly property bool lockOnly: root.lockBehavior === "lockOnly"

    readonly property var lockChoices: [
        {
            "value": "hide",
            "symbol": "visibility_off",
            "title": Translation.tr("Hidden"),
            "description": Translation.tr("Not drawn while the screen is locked")
        },
        {
            "value": "keep",
            "symbol": "visibility",
            "title": Translation.tr("Shown in place"),
            "description": Translation.tr("Stays exactly where it is on the desktop")
        },
        {
            "value": "custom",
            "symbol": "open_with",
            "title": Translation.tr("Own position"),
            "description": Translation.tr("Placed apart from the desktop; drag it on the Lockscreen tab")
        },
        {
            "value": "center",
            "symbol": "center_focus_strong",
            "title": Translation.tr("Centred"),
            "description": Translation.tr("Moves to the middle, stacked with the others")
        },
        {
            "value": "lockOnly",
            "symbol": "lock",
            "title": Translation.tr("Lock screen only"),
            "description": Translation.tr("Leaves the desktop entirely")
        }
    ]
    readonly property var currentLockChoice: root.lockChoices.find(choice => choice.value === root.lockBehavior)
        ?? root.lockChoices[0]

    // Whether the widget names a Settings page of its own. Most do; the
    // handful that do not simply have no options row.
    readonly property bool hasConfigPage: String(root.metadata?.configPage ?? "") !== ""

    readonly property real scaleFactor: widget ? widget.committedScaleFactor : 1
    readonly property real scaleStep: EditModeLogic.nearestSizeStep(root.scaleFactor)
    readonly property bool allSameScale: root.multiSelect
        ? root.targetWidgets.every(w => Math.abs((w.committedScaleFactor ?? 1) - root.scaleFactor) < 0.001)
        : true
    readonly property bool canGrow: root.multiSelect
        ? root.targetWidgets.some(w => w && EditModeLogic.steppedScale(w.committedScaleFactor ?? 1, 1) !== null)
        : (root.widget !== null && EditModeLogic.steppedScale(root.scaleFactor, 1) !== null)
    readonly property bool canShrink: root.multiSelect
        ? root.targetWidgets.some(w => w && EditModeLogic.steppedScale(w.committedScaleFactor ?? 1, -1) !== null)
        : (root.widget !== null && EditModeLogic.steppedScale(root.scaleFactor, -1) !== null)
    readonly property bool dense: ContextMenus.compact
    readonly property int padding: root.dense ? ContextMenus.compactPadding : 8

    // ── The entries ──────────────────────────────────────────────────────────
    // Every row the menu can carry, arranged by the user under "editWidget"
    // (ContextMenus). The two side cards stay side cards in either submenu
    // style: they were designed beside the menu, not inside it.
    readonly property var liveEntries: [
        {
            "id": "pin",
            "symbol": root.pinned ? "keep_off" : "keep",
            "title": root.pinned ? Translation.tr("Unpin position") : Translation.tr("Pin position"),
            "toggle": true,
            "checked": root.pinned,
            "enabled": root.multiSelect ? root.targetWidgets.length > 0 : root.instance !== null
        },
        {
            "id": "size",
            "symbol": "aspect_ratio",
            "title": Translation.tr("Size"),
            "stepper": true,
            "valueText": root.allSameScale ? (Math.round(root.scaleStep * 100) + "%") : "—",
            "canStepDown": root.canShrink,
            "canStepUp": root.canGrow,
            "enabled": root.multiSelect ? root.targetWidgets.length > 0 : root.widget !== null
        },
        // Beside the size, the way back to the plain one - a widget resized
        // by the grip has no other route to exactly 100%.
        {
            "id": "resetSize",
            "shown": root.multiSelect
                ? root.targetWidgets.some(w => w && Math.abs((w.committedScaleFactor ?? 1) - 1) > 0.001)
                : (root.widget !== null && Math.abs(root.scaleFactor - 1) > 0.001),
            "symbol": "fit_screen",
            "title": Translation.tr("Reset size")
        },
        // Everything the widget itself can be told to do. Not a copy of its
        // Settings page - the page itself, loaded beside the menu - so the
        // options here are whatever Settings has, without a second list of
        // them to keep in step.
        {
            "id": "options",
            "shown": root.hasConfigPage && !root.multiSelect,
            "symbol": "tune",
            "title": Translation.tr("Widget options"),
            "submenu": true,
            "enabled": root.instance !== null
        },
        // One more of this one, a step down and to the right. A widget can
        // be placed more than once, and the catalogue's row gives a fresh
        // copy at a default spot; this gives one that keeps its settings.
        {
            "id": "duplicate",
            "symbol": "content_copy",
            "title": Translation.tr("Duplicate"),
            "enabled": root.multiSelect ? root.targetWidgets.length > 0 : root.instance !== null
        },
        {
            "id": "lock",
            "symbol": root.currentLockChoice.symbol,
            "title": Translation.tr("On lock screen"),
            "subtitle": root.currentLockChoice.title,
            "submenu": true,
            "enabled": root.multiSelect ? root.targetWidgets.length > 0 : root.instance !== null
        },
        // On the Lockscreen tab a desktop widget is hidden from the lock, not
        // removed from the desktop; a lock-only one is removed outright.
        {
            "id": "remove",
            "symbol": "delete",
            "title": GlobalStates.editLockLayout && !root.lockOnly
                ? Translation.tr("Hide on lock screen") : Translation.tr("Remove from desktop"),
            "destructive": true,
            "enabled": root.multiSelect ? root.targetWidgets.length > 0 : (root.instance !== null
                && !(GlobalStates.editLockLayout && root.lockBehavior === "hide"))
        }
    ].filter(entry => entry.shown !== false)
    readonly property var arranged: ContextMenus.arrange("editWidget", root.liveEntries)

    // Where the lock row sits, so its chooser opens level with it.
    property real lockRowY: 0

    function activate(entry: var, from: Item): void {
        if (entry.custom) {
            const instanceId = root.instanceId;
            root.dismissRequested();
            ContextMenus.runCustom(entry, instanceId);
            return;
        }
        switch (entry.id) {
        case "pin": {
            const nextPinned = !root.pinned;
            GlobalStates.editHistoryBeginBatch();
            for (const w of root.targetWidgets) {
                if (w && w.widgetInstance && w.widgetInstance.id)
                    Config.updateWidgetPinned(w.widgetInstance.id, nextPinned);
            }
            GlobalStates.editHistoryEndBatch();
            break;
        }
        case "size":
            break;
        case "resetSize":
            GlobalStates.editHistoryBeginBatch();
            for (const w of root.targetWidgets) {
                if (w && w.commitResizeScale)
                    w.commitResizeScale(1);
            }
            GlobalStates.editHistoryEndBatch();
            break;
        case "options":
            root.lockChooserOpen = false;
            root.configOpen = !root.configOpen;
            break;
        case "duplicate": {
            root.dismissRequested();
            if (root.multiSelect && root.canvas && root.canvas.duplicateSelection) {
                root.canvas.duplicateSelection();
            } else if (root.instance) {
                const monitor = root.instance.monitorName ?? "";
                Config.duplicateWidgetInstance(root.instanceId, monitor);
            }
            break;
        }
        case "lock":
            if (from)
                root.lockRowY = from.mapToItem(root, 0, 0).y;
            root.configOpen = false;
            root.lockChooserOpen = !root.lockChooserOpen;
            break;
        case "remove": {
            root.dismissRequested();
            if (root.multiSelect) {
                if (GlobalStates.editLockLayout) {
                    GlobalStates.editHistoryBeginBatch();
                    for (const w of root.targetWidgets) {
                        if (!w || !w.widgetInstance) continue;
                        if (w.lockBehavior === "lockOnly")
                            Config.removeWidgetInstance(w.widgetInstance.id);
                        else
                            Config.updateWidgetLockBehavior(w.widgetInstance.id, "hide");
                    }
                    GlobalStates.editHistoryEndBatch();
                } else if (root.canvas && root.canvas.removeSelection) {
                    root.canvas.removeSelection();
                }
            } else {
                const instanceId = root.instanceId;
                if (GlobalStates.editLockLayout && !root.lockOnly)
                    Config.updateWidgetLockBehavior(instanceId, "hide");
                else
                    Config.removeWidgetInstance(instanceId);
            }
            break;
        }
        }
    }

    implicitWidth: !root.dense ? 268
        : Math.max(ContextMenus.compactMinWidth, Math.min(ContextMenus.compactMaxWidth,
            Math.ceil(Math.max(list.implicitWidth, iconBar.implicitWidth) + root.padding * 2)))
    implicitHeight: column.implicitHeight + root.padding * 2
    width: implicitWidth
    height: implicitHeight

    // From the corner the pointer is at: the card belongs to a point.
    ContextMenuMotion {
        id: motion
        Component.onCompleted: motion.playEnter(true)
    }
    opacity: motion.reveal
    // The user's menu size; the parent is in screen units, this card in its own.
    readonly property real zoom: ContextMenus.scale
    scale: motion.scale * root.zoom
    transformOrigin: Item.TopLeft

    // Whether a side panel is showing, and which side of the card it opens on:
    // the card is placed at a pointer that can be anywhere, so a panel flips
    // rather than running off the screen. The two are exclusive - one card
    // beside the menu at a time, or the second would land on the first.
    property bool lockChooserOpen: false
    property bool configOpen: false
    readonly property real chooserWidth: 274
    readonly property real chooserGap: 8
    readonly property real configWidth: Math.min(440, Math.max(300,
        (root.parent ? root.parent.width : 900) / root.zoom - root.width - root.chooserGap * 4))
    readonly property real configMaxHeight: Math.max(240,
        (root.parent ? root.parent.height : 720) / root.zoom - 32)

    function opensOnLeft(panelWidth) {
        return root.parent !== null
            && (root.x + (root.width + root.chooserGap + panelWidth) * root.zoom) > root.parent.width;
    }
    readonly property bool chooserOnLeft: root.opensOnLeft(root.chooserWidth)
    readonly property bool configOnLeft: root.opensOnLeft(root.configWidth)

    // Six of the widgets' Settings pages carry a text field, and under
    // layer-shell no item in a surface at keyboardFocus None can hold active
    // focus at all: the caret would never appear and the keys would go
    // wherever the keyboard already was. So the open panel asks the chrome to
    // hold the keyboard the same way the catalogue's search field does - as
    // intent, published upward, never read back off activeFocus.
    readonly property bool wantsKeyboard: root.configOpen && root.instance !== null && root.hasConfigPage

    onInstanceIdChanged: {
        root.lockChooserOpen = false;
        root.configOpen = false;
    }

    function stepSize(direction) {
        if (root.targetWidgets.length === 0)
            return;
        GlobalStates.editHistoryBeginBatch();
        for (const w of root.targetWidgets) {
            if (!w || !w.commitResizeScale)
                continue;
            const current = w.committedScaleFactor ?? 1;
            const next = EditModeLogic.steppedScale(current, direction);
            if (next !== null)
                w.commitResizeScale(next);
        }
        GlobalStates.editHistoryEndBatch();
    }

    StyledRectangularShadow {
        target: card
    }

    // A click on the card's own padding is a click ON the menu, never a
    // click away from it: swallowed here, under the rows.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: Appearance.m3colors.m3surfaceContainer
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.dense ? 4 : 3

        // The title. No body of its own - it names the card rather than
        // offering anything - so it is the one thing here that is not a pill.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.dense ? 6 : 8
            Layout.rightMargin: 8
            Layout.topMargin: 2
            Layout.bottomMargin: root.dense ? 2 : 4
            spacing: 8

            MaterialSymbol {
                text: root.multiSelect ? "select_all" : (root.metadata ? (root.metadata.icon || "widgets") : "widgets")
                iconSize: root.dense ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                text: root.multiSelect ? Translation.tr("%1 widgets selected").arg(root.targetCount) : (root.metadata ? root.metadata.name : Translation.tr("Widget"))
                font.pixelSize: root.dense ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideRight
            }
        }

        ContextMenuIconBar {
            id: iconBar
            Layout.fillWidth: true
            entries: root.arranged.bar
            hostPadding: root.padding
            onActivated: (entry, button) => root.activate(entry, button)
        }

        ContextMenuList {
            id: list
            Layout.fillWidth: true
            rows: root.arranged.rows
            dense: root.dense
            separators: root.dense
            hostPadding: root.padding
            openId: root.lockChooserOpen ? "lock" : root.configOpen ? "options" : ""
            onActivated: (entry, row) => root.activate(entry, row)
            onStepped: (entry, delta) => {
                if (entry.id === "size")
                    root.stepSize(delta);
            }
        }
    }

    // ── The lock-behaviour chooser ───────────────────────────────────────────
    // A card of its own beside the menu rather than a submenu inside it: the
    // four states each need a sentence to be choosable, and four sentences do
    // not fit a row that is already carrying its own answer.
    Loader {
        id: chooserLoader
        active: root.lockChooserOpen && (root.multiSelect ? root.targetWidgets.length > 0 : root.instance !== null)
        // Top-aligned with the row it belongs to, so the eye goes straight
        // from the chevron to the list.
        y: Math.min(root.lockRowY, root.height - (chooserLoader.item ? chooserLoader.item.height : 0))
        x: root.chooserOnLeft
            ? -root.chooserGap - root.chooserWidth
            : root.width + root.chooserGap
        z: 5

        sourceComponent: Item {
            id: chooser
            implicitWidth: root.chooserWidth
            implicitHeight: chooserColumn.implicitHeight + root.padding * 2
            width: implicitWidth
            height: implicitHeight

            transformOrigin: root.chooserOnLeft ? Item.TopRight : Item.TopLeft
            scale: 0.9
            opacity: 0
            Component.onCompleted: {
                chooser.scale = 1;
                chooser.opacity = 1;
            }
            Behavior on scale {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(chooser)
            }
            Behavior on opacity {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(chooser)
            }

            StyledRectangularShadow {
                target: chooserCard
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            Rectangle {
                id: chooserCard
                anchors.fill: parent
                radius: Appearance.rounding.windowRounding
                color: Appearance.m3colors.m3surfaceContainer
            }

            ColumnLayout {
                id: chooserColumn
                anchors.fill: parent
                anchors.margins: root.padding
                spacing: 3

                Repeater {
                    model: root.lockChoices

                    delegate: EditPanelRow {
                        required property var modelData
                        required property int index
                        dense: root.dense
                        hostRadius: Appearance.rounding.windowRounding
                        hostPadding: root.padding
                        Layout.fillWidth: true
                        first: index === 0
                        last: index === root.lockChoices.length - 1
                        symbol: modelData.symbol
                        title: modelData.title
                        subtitle: modelData.description
                        subtitleWrap: true
                        selected: modelData.value === root.lockBehavior
                        trailingKind: selected ? "check" : "none"
                        onActivated: {
                            root.lockChooserOpen = false;
                            GlobalStates.editHistoryBeginBatch();
                            for (const w of root.targetWidgets) {
                                if (w && w.widgetInstance && w.widgetInstance.id) {
                                    Config.updateWidgetLockBehavior(w.widgetInstance.id, modelData.value);
                                }
                            }
                            GlobalStates.editHistoryEndBatch();
                        }
                    }
                }
            }
        }
    }

    // ── The widget's own settings ────────────────────────────────────────────
    // The same side-panel gesture as the chooser above, carrying the widget's
    // real Settings page instead of a hand-written copy of it.
    Loader {
        id: configLoader
        active: root.configOpen && root.instance !== null && root.hasConfigPage
        // Beside the menu and inside the screen: a page of forms is taller
        // than the menu that opened it, so the card slides up as far as it
        // must rather than hanging off the bottom.
        y: {
            const h = configLoader.item ? configLoader.item.height : 0;
            const parentHeight = root.parent ? root.parent.height : root.height;
            return Math.max((16 - root.y) / root.zoom, Math.min(0, (parentHeight - 16 - root.y) / root.zoom - h));
        }
        x: root.configOnLeft
            ? -root.chooserGap - root.configWidth
            : root.width + root.chooserGap
        z: 5

        sourceComponent: EditWidgetConfigPanel {
            id: configPanel
            widgetId: root.instance ? root.instance.widgetId : ""
            maxWidth: root.configWidth
            maxHeight: root.configMaxHeight
            onDismissRequested: root.configOpen = false

            transformOrigin: root.configOnLeft ? Item.TopRight : Item.TopLeft
            scale: 0.9
            opacity: 0
            Component.onCompleted: {
                configPanel.scale = 1;
                configPanel.opacity = 1;
            }
            Behavior on scale {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(configPanel)
            }
            Behavior on opacity {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(configPanel)
            }
        }
    }
}
