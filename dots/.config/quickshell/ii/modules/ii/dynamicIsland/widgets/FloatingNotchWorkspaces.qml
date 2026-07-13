import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool isExpanded: false

    readonly property string workspaceStyle: Config.options.bar.styles.workspaces ?? "default"

    Loader {
        id: loader
        anchors.centerIn: parent

        // Instead of scale (causes aliasing), use explicit width/height
        // expanding widget fills more space when expanded
        width: root.isExpanded
            ? (loaderBaseWidth * 1.15)
            : loaderBaseWidth
        height: root.isExpanded ? 80 : (root.height > 0 ? root.height : 40)

        readonly property real loaderBaseWidth: root.implicitWidth - 20

        Behavior on width {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }

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
        return (baseWidth * (root.isExpanded ? 1.15 : 1.0)) + 20;
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
