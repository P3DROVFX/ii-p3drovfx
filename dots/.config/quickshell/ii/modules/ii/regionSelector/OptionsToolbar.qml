pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Options toolbar
Toolbar {
    id: root

    // Use a synchronizer on these
    property var action
    property var selectionMode
    // Signals
    signal dismiss()

    scale: root.visible ? 1.0 : 0.8
    opacity: root.visible ? 1.0 : 0.0

    Behavior on scale {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutBack
            easing.overshoot: 1.4
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    ToolbarTabBar {
        id: tabBar
        tabButtonList: [
            {"icon": "activity_zone", "name": Translation.tr("Rect")},
            {"icon": "gesture", "name": Translation.tr("Circle")}
        ]
        Component.onCompleted: {
            currentIndex = root.selectionMode === RegionSelection.SelectionMode.RectCorners ? 0 : 1;
        }
        onCurrentIndexChanged: {
            const targetMode = currentIndex === 0 ? RegionSelection.SelectionMode.RectCorners : RegionSelection.SelectionMode.Circle;
            if (root.selectionMode !== targetMode) {
                root.selectionMode = targetMode;
            }
        }
    }

    Connections {
        target: root
        ignoreUnknownSignals: true
        function onSelectionModeChanged() {
            const targetIndex = root.selectionMode === RegionSelection.SelectionMode.RectCorners ? 0 : 1;
            if (tabBar.currentIndex !== targetIndex) {
                tabBar.currentIndex = targetIndex;
            }
        }
    }
}
