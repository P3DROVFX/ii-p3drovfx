import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.editMode
import "./widgets"

/**
 * Edit Mode's one popup on the dock, in three pages:
 *
 *   "item"    - a widget or button that was clicked: its size, its place in
 *               the widget stack, its options and the way off the dock;
 *   "options" - that item's real Settings page, drawn in the card (the same
 *               trade EditWidgetConfigPanel makes for desktop widgets: load the
 *               page Settings shows instead of restating it here);
 *   "add"     - the (+) tile's catalogue of what the dock can carry.
 *
 * One instance per dock, re-anchored to whatever was clicked.
 */
DockContextMenuBase {
    id: root

    property Item dockContent: null
    property DockEditController controller: null

    property string mode: "item"
    dockPos: root.dockContent?.dockPos ?? "bottom"
    property var target: null
    readonly property var info: root.target ? root.controller.describe(root.target) : ({})
    property string optionsPage: ""

    function openFor(anchor, item, mode) {
        // A popup already showing for something else is replaced at once:
        // the exit of one and the entry of the next would be two surfaces.
        if (root.active) {
            root.isClosing = false;
            root.active = false;
        }
        root.anchorItem = anchor;
        root.target = item;
        root.mode = mode;
        root.open();
    }

    function showOptions(page) {
        root.optionsPage = page;
        root.mode = "options";
    }

    onClosed: {
        root.target = null;
        root.optionsPage = "";
    }

    menuWidth: root.mode === "add" ? 404 : (root.mode === "options" ? 460 : 312)
    headerText: root.mode === "add" ? Translation.tr("Add to the dock") : (root.info.title ?? "")
    headerSubtitle: root.mode === "add" ? Translation.tr("Click to add, click again to take off")
        : root.mode === "options" ? Translation.tr("Options") : (root.info.subtitle ?? "")
    headerSymbol: root.mode === "add" ? "add_circle" : (root.info.symbol ?? "widgets")

    contentComponent: root.mode === "add" ? addSheet : (root.mode === "options" ? optionsSheet : null)
    menuGroups: root.menuOpen && root.mode === "item" ? root._itemGroups() : []

    function _itemGroups() {
        const item = root.target;
        const info = root.info;
        if (!item)
            return [];
        const groups = [];
        if (info.sizes) {
            groups.push([
                { "id": "square", "icon": "crop_square", "text": Translation.tr("Square"),
                  "subtitle": Translation.tr("One slot"), "selected": !info.wide },
                { "id": "wide", "icon": "crop_16_9", "text": Translation.tr("Wide"),
                  "subtitle": Translation.tr("More room for what it shows"), "selected": !!info.wide }
            ]);
        }
        if ((info.slots ?? 0) > 0) {
            groups.push([
                { "id": "slots", "icon": "width", "text": Translation.tr("Width"), "stepper": true,
                  "valueText": String(info.slots), "canStepDown": info.slots > 2, "canStepUp": info.slots < 6 }
            ]);
        }
        if (info.stackable && !root.controller.vertical) {
            groups.push([
                { "id": "stack", "icon": "stacks", "text": Translation.tr("In the widget stack"),
                  "subtitle": Translation.tr("Shares one slot, turned with the wheel"), "toggle": true,
                  "checked": root.controller.inStack(item.type) }
            ]);
        }
        if (item.type === "widgetStack") {
            groups.push(root.controller.nativeWidgets.filter(entry => entry.stackable).map(entry => ({
                "id": "member:" + entry.id, "icon": entry.symbol, "text": entry.title, "toggle": true,
                "checked": root.controller.inStack(entry.id)
            })));
        }
        const last = [];
        if ((info.options ?? "") !== "")
            last.push({ "id": "options", "icon": "tune", "text": Translation.tr("Options"), "chevron": true });
        last.push({ "id": "remove", "icon": "remove_circle",
            "text": item.type === "file" ? Translation.tr("Unpin from the dock")
                : item.type === "widgetStack" ? Translation.tr("Unstack") : Translation.tr("Remove from dock"),
            "subtitle": item.type === "widgetStack" ? Translation.tr("Its widgets go back to their own places") : "",
            "destructive": true });
        groups.push(last);
        return groups;
    }

    onActionTriggered: actionId => {
        const item = root.target;
        if (!item)
            return;
        if (actionId === "square" || actionId === "wide") {
            root.controller.setWide(item, actionId === "wide");
            root.target = Object.assign({}, item, { "wide": actionId === "wide" });
        } else if (actionId === "slots:up" || actionId === "slots:down") {
            root.controller.stepLivePreviewSlots(actionId === "slots:up" ? 1 : -1);
            root.target = Object.assign({}, item);
        } else if (actionId === "stack") {
            const stacked = !root.controller.inStack(item.type);
            root.controller.setStacked(item.type, stacked);
            // Stacked, the widget's own place is gone: so is what the menu
            // was anchored to.
            root.close();
        } else if (actionId.indexOf("member:") === 0) {
            const member = actionId.substring(7);
            root.controller.setStacked(member, !root.controller.inStack(member));
            root.target = Object.assign({}, item);
        } else if (actionId === "options") {
            root.showOptions(root.info.options);
        } else if (actionId === "remove") {
            root.close();
            root.controller.remove(item);
        }
    }

    // ── Options: the item's Settings page, in the card ─────────────────────
    Component {
        id: optionsSheet

        Item {
            id: options
            width: parent?.width ?? 0
            readonly property real maxHeight: 520
            readonly property real pageContentHeight: (pageLoader.item && pageLoader.item.flickable)
                ? pageLoader.item.flickable.contentHeight : 0
            implicitHeight: back.height + 8 + Math.max(96, Math.min(options.maxHeight, options.pageContentHeight))

            EditMenuPageHeader {
                id: back
                width: parent.width
                height: 40
                title: Translation.tr("Back")
                actionSymbol: "open_in_new"
                actionTooltip: Translation.tr("Open in Settings")
                onBackRequested: root.mode = "item"
                onActionRequested: {
                    root.close();
                    GlobalStates.openSettingsPage("dock", "widgets/DockUtilitiesConfig.qml");
                }
            }

            Item {
                anchors.top: back.bottom
                anchors.topMargin: 8
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    asynchronous: true
                    source: root.optionsPage !== "" ? Qt.resolvedUrl("../../settings/configs/" + root.optionsPage) : ""
                    onLoaded: {
                        if (item.hasOwnProperty("showBackButton"))
                            item.showBackButton = false;
                        if (item.hasOwnProperty("bottomContentPadding"))
                            item.bottomContentPadding = 4;
                    }
                }

                StyledIndeterminateProgressBar {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 24
                    visible: pageLoader.status !== Loader.Ready
                }

                ConfigSubPageHost {
                    id: subPageHost
                    anchors.fill: parent
                    z: 10
                }
            }

            // Settings rows that open a detail page look up the parent chain
            // for this.
            property alias activeSubPage: subPageHost.activeSubPage
        }
    }

    // ── Add: the catalogue ──────────────────────────────────────────────────
    Component {
        id: addSheet

        DockEditAddSheet {
            width: parent?.width ?? 0
            controller: root.controller
            onAppsRequested: {
                root.close();
                GlobalStates.openEditCatalogue("dock", root.dockContent?.currentScreen?.name ?? "", "apps:installed");
            }
        }
    }
}
