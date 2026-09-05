import QtQuick
import QtQuick.Layouts
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
    
    headerText: root.desktopEntry?.name ?? (root.appToplevel ? root.appToplevel.appId : "")
    headerIcon: Component {
        DockIcon {
            implicitWidth: 22
            implicitHeight: 22
            appId: root.appToplevel?.appId ?? ""
            isRunning: true
        }
    }

    contentComponent: ColumnLayout {
        spacing: 0
        
        // Desktop entry actions (e.g. "New Window", "New Private Window")
        Repeater {
            model: root.desktopEntry?.actions ?? []
            delegate: DockMenuButton {
                required property var modelData
                required property int index
                Layout.fillWidth: true

                readonly property var shapePool: [
                    "Flower", "Gem", "SoftBurst", "Clover4Leaf",
                    "Heart", "Puffy", "Diamond", "Pentagon",
                    "Cookie6Sided", "SoftBoom", "Bun", "PuffyDiamond"
                ]

                shapeString: shapePool[index % shapePool.length]
                labelText: modelData.name ?? ""
                onTriggered: { modelData.execute(); root.close() }
            }
        }

        Rectangle {
            visible: (root.desktopEntry?.actions?.length ?? 0) > 0
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            implicitHeight: 1
            color: Appearance.colors.colLayer0Border
        }

        DockMenuButton {
            Layout.fillWidth: true
            symbolName: "launch"
            labelText: qsTr("Launch")
            onTriggered: { root.desktopEntry?.execute(); root.close() }
        }

        DockMenuButton {
            visible: !!root.appToplevel?.appId
            Layout.fillWidth: true
            symbolName: "live_tv"
            labelText: (Config.options?.dock?.enableLivePreviewWidget ?? false)
                ? Translation.tr("Set as Live Preview")
                : Translation.tr("Enable Live Preview")
            onTriggered: {
                Config.options.dock.enableLivePreviewWidget = true;
                DockLivePreviewService.selectApp(root.appToplevel.appId);
                root.close();
            }
        }

        DockMenuButton {
            Layout.fillWidth: true
            symbolName: (root.appToplevel && TaskbarApps.isPinned(root.appToplevel.appId)) ? "keep_off" : "keep"
            labelText: (root.appToplevel && TaskbarApps.isPinned(root.appToplevel.appId)) ? qsTr("Unpin") : qsTr("Pin")
            onTriggered: {
                if (root.appToplevel) TaskbarApps.togglePin(root.appToplevel.appId)
                root.close()
            }
        }

        // The way into Edit Mode from the dock itself: the mode opens with the
        // panel on the dock's own page, where its looks and its apps live.
        DockMenuButton {
            visible: !GlobalStates.editMode
            Layout.fillWidth: true
            symbolName: "edit"
            labelText: Translation.tr("Edit dock")
            onTriggered: {
                root.close();
                const screenName = (typeof dockRoot !== "undefined" && dockRoot.screen) ? dockRoot.screen.name : "";
                GlobalStates.openEditCatalogue("dock", screenName, "appearance");
            }
        }

        DockMenuButton {
            visible: (root.appToplevel?.toplevels?.length ?? 0) > 0
            Layout.fillWidth: true
            symbolName: "close"
            labelText: (root.appToplevel?.toplevels?.length ?? 0) > 1
                       ? qsTr("Close all windows") : qsTr("Close window")
            isDestructive: true
            onTriggered: {
                if (root.appToplevel)
                    for (const t of root.appToplevel.toplevels) t.close()
                root.close()
            }
        }
    }
}
