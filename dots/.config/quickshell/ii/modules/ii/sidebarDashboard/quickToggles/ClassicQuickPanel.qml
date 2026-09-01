import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.modules.ii.sidebarDashboard.quickToggles.classicStyle
// Keyed list model shared with the Android panel: it inserts and removes only
// the rows that actually changed, so adding one toggle never rebuilds - and
// re-queries the state of - every other one.
import qs.modules.ii.sidebarDashboard.quickToggles.androidStyle
import "classicStyle/ClassicQuickToggleCatalog.js" as ClassicQuickToggleCatalog

AbstractQuickPanel {
    id: root
    Layout.fillWidth: true
    implicitWidth: contentColumn.implicitWidth
    implicitHeight: contentColumn.implicitHeight
    color: "transparent"

    property bool editMode: false

    property int buttonSize: 40
    property int buttonSpacing: 5
    property int groupPadding: 5

    readonly property var usedToggles: ClassicQuickToggleCatalog.normalize(Config.options.sidebar.quickToggles.classic?.toggles)
    readonly property var unusedToggles: ClassicQuickToggleCatalog.unusedTypes(root.usedToggles)

    function toModelValues(types) {
        return types.map(type => ({
            id: type,
            type: type,
            sizeW: 1,
            sizeH: 1
        }));
    }

    function setToggles(types) {
        Config.options.sidebar.quickToggles.classic.toggles = types;
    }

    function addToggle(type) {
        if (!ClassicQuickToggleCatalog.hasType(type) || root.usedToggles.indexOf(type) >= 0)
            return;
        root.setToggles(root.usedToggles.concat([type]));
    }

    function removeToggle(type) {
        if (root.usedToggles.indexOf(type) < 0)
            return;
        root.setToggles(root.usedToggles.filter(candidate => candidate !== type));
    }

    // Inline components cannot see the ids of the file around them, so the
    // panel is handed over explicitly.
    component ToggleGrid: Grid {
        id: grid
        required property var panel
        required property var toggleTypes
        property bool unused: false

        spacing: grid.panel.buttonSpacing
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        // GroupButton reads this off its parent to drive the press bounce.
        property int clickIndex: -1

        // While a toggle is being dragged the grid shows a draft order and
        // only writes it back once the toggle is dropped.
        property string draggedType: ""
        property var draftOrder: []
        readonly property var displayTypes: grid.draggedType.length > 0 ? grid.draftOrder : grid.toggleTypes

        move: Transition {
            NumberAnimation {
                properties: "x,y"
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        function slotAt(x, y, count) {
            const cell = grid.panel.buttonSize + grid.panel.buttonSpacing;
            const column = Math.max(0, Math.min(grid.columns - 1, Math.floor(x / cell)));
            const row = Math.max(0, Math.floor(y / cell));
            return Math.max(0, Math.min(count - 1, row * grid.columns + column));
        }

        function beginToggleDrag(type) {
            if (grid.unused || !grid.panel.editMode || grid.toggleTypes.indexOf(type) < 0)
                return false;
            grid.draftOrder = grid.toggleTypes.slice();
            grid.draggedType = type;
            return true;
        }

        function updateToggleDrag(type, centerX, centerY) {
            if (grid.draggedType !== type)
                return;
            const order = grid.draftOrder.slice();
            const from = order.indexOf(type);
            if (from < 0)
                return;
            const to = grid.slotAt(centerX, centerY, order.length);
            if (to === from)
                return;
            order.splice(from, 1);
            order.splice(to, 0, type);
            grid.draftOrder = order;
        }

        function endToggleDrag() {
            if (grid.draggedType.length === 0)
                return;
            // Persist before dropping the draft, so the grid never flashes the
            // old order between the two.
            grid.panel.setToggles(grid.draftOrder.slice());
            grid.draggedType = "";
            grid.draftOrder = [];
        }

        function cancelToggleDrag() {
            grid.draggedType = "";
            grid.draftOrder = [];
        }

        // Toggles wrap onto as many rows as the sidebar width allows, so adding
        // one never pushes the row past the sidebar edge.
        readonly property real availableWidth: grid.panel.width - grid.panel.groupPadding * 2
        columns: Math.max(1, Math.floor((availableWidth + grid.panel.buttonSpacing) / (grid.panel.buttonSize + grid.panel.buttonSpacing)))

        StableQuickToggleModel {
            id: toggleModel
            sourceValues: grid.panel.toModelValues(grid.displayTypes)
        }

        Repeater {
            model: toggleModel
            delegate: ClassicToggleDelegateChooser {
                editMode: grid.panel.editMode
                isUnused: grid.unused
                draggable: grid.panel.editMode && !grid.unused

                onEditRequested: type => {
                    if (grid.unused)
                        grid.panel.addToggle(type);
                    else
                        grid.panel.removeToggle(type);
                }

                onOpenWifiDialog: grid.panel.openWifiDialog()
                onOpenBluetoothDialog: grid.panel.openBluetoothDialog()
                onOpenVpnDialog: grid.panel.openVpnDialog()
                onOpenTailscaleDialog: grid.panel.openTailscaleDialog()
                onOpenIdleInhibitorDialog: grid.panel.openIdleInhibitorDialog()
                onOpenModesDialog: grid.panel.openModesDialog()
            }
        }
    }

    Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: root.buttonSpacing

        Rectangle {
            id: usedGroup
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: usedGrid.implicitWidth + root.groupPadding * 2
            implicitHeight: usedGrid.implicitHeight + root.groupPadding * 2
            visible: root.usedToggles.length > 0
            color: Appearance.colors.colLayer1
            radius: (Config.options.appearance.sharpMode ? Appearance.rounding.small : root.buttonSize / 2) + root.groupPadding

            ToggleGrid {
                id: usedGrid
                anchors.centerIn: parent
                panel: root
                toggleTypes: root.usedToggles
            }
        }

        // Separator between shown and hidden toggles, edit mode only
        FadeLoader {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.buttonSize / 2
            anchors.rightMargin: root.buttonSize / 2
            shown: root.editMode && root.unusedToggles.length > 0
            fade: false
            active: shown || opacity > 0
            sourceComponent: Rectangle {
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }
        }

        // Hidden toggles, offered for adding back while editing
        FadeLoader {
            anchors.horizontalCenter: parent.horizontalCenter
            shown: root.editMode && root.unusedToggles.length > 0
            fade: false
            active: shown || opacity > 0
            sourceComponent: Rectangle {
                implicitWidth: unusedGrid.implicitWidth + root.groupPadding * 2
                implicitHeight: unusedGrid.implicitHeight + root.groupPadding * 2
                color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.5)
                radius: (Config.options.appearance.sharpMode ? Appearance.rounding.small : root.buttonSize / 2) + root.groupPadding

                ToggleGrid {
                    id: unusedGrid
                    anchors.centerIn: parent
                    panel: root
                    unused: true
                    toggleTypes: root.unusedToggles
                }
            }
        }
    }
}
