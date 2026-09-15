pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property bool requestDockShow: false
    property int tileSize: 50
    property int tileSpacing: 4
    property int iconSize: 36
    property bool minimizeFocused: false
    property var pendingOrder: null
    property var seenIds: ({})

    function isNew(appId) {
        if (root.seenIds[appId]) return false;
        root.seenIds[appId] = true;
        return true;
    }

    signal bumpRequested(real centerX, var entry)
    signal bumpCleared()
    signal menuRequested(real centerX, var entry)
    signal scrollRequested(int delta, var entry)

    readonly property var appList: TaskbarApps.apps
        .filter(entry => entry.appId !== "SEPARATOR")
        .slice()
        .sort((a, b) => StringUtils.compare(a.appId, b.appId))

    readonly property var displayIds: {
        const order = root.pendingOrder ?? Config.options.akebono.dockOrder;
        const rank = id => {
            const i = order.indexOf(id);
            return i === -1 ? order.length : i;
        };
        return root.appList.map(entry => entry.appId).sort((a, b) => (rank(a) - rank(b)) || StringUtils.compare(a, b));
    }

    Layout.alignment: Qt.AlignVCenter
    implicitWidth: appList.length * tileSize + Math.max(0, appList.length - 1) * tileSpacing
    implicitHeight: tileSize

    function slotIndexOf(appId: string): int {
        const i = root.displayIds.indexOf(appId);
        return i === -1 ? root.displayIds.length : i;
    }

    function moveTo(appId, leftX) {
        const step = root.tileSize + root.tileSpacing;
        const ids = root.displayIds.slice();
        let target = Math.max(0, Math.min(Math.round(leftX / step), ids.length - 1));
        const from = ids.indexOf(appId);
        if (from === -1 || from === target) return;
        ids.splice(from, 1);
        ids.splice(target, 0, appId);
        root.pendingOrder = ids;
    }

    function commit() {
        if (root.pendingOrder !== null) {
            Config.options.akebono.dockOrder = root.pendingOrder;
            root.pendingOrder = null;
        }
    }

    function slotIndexFor(leftX, appId) {
        const step = root.tileSize + root.tileSpacing;
        const ids = root.displayIds.slice().filter(id => id !== appId);
        return Math.max(0, Math.min(Math.round(leftX / step), ids.length));
    }

    function slotCenterFor(leftX, appId) {
        return root.slotIndexFor(leftX, appId) * (root.tileSize + root.tileSpacing) + root.tileSize / 2;
    }

    function pinAt(leftX, appId) {
        const step = root.tileSize + root.tileSpacing;
        const ids = root.displayIds.slice().filter(id => id !== appId);
        const target = root.slotIndexFor(leftX, appId);
        ids.splice(target, 0, appId);
        Config.options.akebono.dockOrder = ids;
        if (!TaskbarApps.isPinned(appId))
            TaskbarApps.togglePin(appId);
        return target * step + root.tileSize / 2;
    }

    Repeater {
        model: ScriptModel {
            objectProp: "appId"
            values: root.appList
        }
        delegate: DockAppButton {
            required property var modelData
            appEntry: modelData
            dockApps: root
            iconSize: root.iconSize
            width: root.tileSize
            height: root.tileSize
            slotX: root.slotIndexOf(modelData.appId) * (root.tileSize + root.tileSpacing)
        }
    }
}
