import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.dock
import qs.services
import Quickshell
import qs
import "./widgets"

DockContextMenuBase {
    id: root

    property var appToplevel: null
    property var desktopEntry: null

    readonly property int windowCount: root.appToplevel?.toplevels?.length ?? 0
    readonly property bool pinned: !!root.appToplevel && TaskbarApps.isPinned(root.appToplevel.appId)

    headerText: root.desktopEntry?.name ?? (root.appToplevel ? root.appToplevel.appId : "")
    headerSubtitle: root.windowCount > 1 ? Translation.tr("%1 windows").arg(root.windowCount)
        : root.windowCount === 1 ? Translation.tr("1 window")
        : Translation.tr("Not running")
    headerIcon: Component {
        DockIcon {
            appId: root.appToplevel?.appId ?? ""
            desktopEntry: root.desktopEntry
            isRunning: true
        }
    }

    // Only built while the menu is open: a closed menu holds no rows.
    menuGroups: root.menuOpen ? [
        (root.desktopEntry?.actions ?? []).map((action, index) => ({
            id: "desktopAction:" + index,
            text: action.name ?? "",
            icon: "arrow_outward",
            iconSource: action.icon ? Quickshell.iconPath(action.icon, true) : ""
        })),
        [
            { id: "launch", icon: "launch", text: Translation.tr("Launch") },
            {
                id: "livePreview",
                icon: "live_tv",
                visible: !!root.appToplevel?.appId,
                text: (Config.options?.dock?.enableLivePreviewWidget ?? false)
                    ? Translation.tr("Set as Live Preview")
                    : Translation.tr("Enable Live Preview")
            },
            {
                id: "pin",
                icon: "keep",
                text: Translation.tr("Pin to dock"),
                toggle: true,
                checked: root.pinned
            },
            // The way into Edit Mode from the dock itself: the mode opens with
            // the panel on the dock's own page, where its looks and apps live.
            { id: "edit", icon: "edit", text: Translation.tr("Edit dock"), visible: !GlobalStates.editMode }
        ],
        [
            {
                id: "close",
                icon: "close",
                destructive: true,
                visible: root.windowCount > 0,
                text: root.windowCount > 1 ? Translation.tr("Close all windows") : Translation.tr("Close window")
            }
        ]
    ] : []

    onActionTriggered: actionId => {
        if (actionId.startsWith("desktopAction:")) {
            const action = (root.desktopEntry?.actions ?? [])[parseInt(actionId.substring(14))];
            action?.execute();
        } else if (actionId === "launch") {
            root.desktopEntry?.execute();
        } else if (actionId === "livePreview") {
            Config.options.dock.enableLivePreviewWidget = true;
            DockLivePreviewService.selectApp(root.appToplevel.appId);
        } else if (actionId === "pin") {
            // Unpinning a closed app removes the very icon this menu hangs
            // from, so the menu leaves with the change instead of after it.
            if (root.appToplevel)
                TaskbarApps.togglePin(root.appToplevel.appId);
        } else if (actionId === "edit") {
            root.close();
            const screenName = (typeof dockRoot !== "undefined" && dockRoot.screen) ? dockRoot.screen.name : "";
            GlobalStates.openEditCatalogue("dock", screenName, "appearance");
            return;
        } else if (actionId === "close") {
            if (root.appToplevel)
                for (const t of root.appToplevel.toplevels) t.close();
        }
        root.close();
    }
}
