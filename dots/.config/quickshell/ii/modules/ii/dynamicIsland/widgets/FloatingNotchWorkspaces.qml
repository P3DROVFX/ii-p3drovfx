import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent

    readonly property string workspaceStyle: Config.options.bar.styles.workspaces ?? "default"

    Loader {
        id: loader
        anchors.centerIn: parent

        width: loaderBaseWidth
        height: root.height > 0 ? root.height : 40

        readonly property real loaderBaseWidth: item ? item.implicitWidth : (Config.options.bar.workspaces.shown * 26)

        source: {
            if (root.workspaceStyle === "minimal")
                return "../../bar/widgets/workspaces/MinimalWorkspaces.qml";
            if (root.workspaceStyle === "expressive")
                return "../../bar/widgets/workspaces/ExpressiveWorkspaces.qml";
            if (root.workspaceStyle === "dock")
                return "../../bar/widgets/workspaces/DockWorkspaces.qml";
            return "../../bar/widgets/workspaces/Workspaces.qml";
        }
        onLoaded: {
            if (item) {
                if (item.hasOwnProperty("vertical")) {
                    item.vertical = false;
                }
            }
        }
    }

    implicitWidth: {
        let baseWidth = loader.item ? loader.item.implicitWidth : (Config.options.bar.workspaces.shown * 26);
        return Math.max(baseWidth + 40, loader.width + 32);
    }

    Component.onCompleted: {
        // Expose root to DynamicIslandPanel
        var p = root.parent;
        while (p && !p.hasOwnProperty("workspaceWidgetRef")) {
            p = p.parent;
        }
        if (p) {
            p.workspaceWidgetRef = root;
        }
    }
}
