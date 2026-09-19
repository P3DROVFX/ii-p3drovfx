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

    /**
     * The strip's own size, for the island to pad evenly around it. The bar widget
     * reports the whole bar's height, so the drawn height is its button size (plus the
     * occupied-indicator background around it) when the style exposes one.
     */
    readonly property real contentWidth: loader.loaderBaseWidth
    readonly property real contentHeight: loader.item && loader.item.iconBoxWrapperSize
        ? loader.item.iconBoxWrapperSize + 2 : 28

    implicitWidth: root.contentWidth + 16

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
