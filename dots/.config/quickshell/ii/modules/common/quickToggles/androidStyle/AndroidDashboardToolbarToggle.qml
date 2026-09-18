pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.quickToggles
import qs.modules.common.widgets
import "QuickToggleCatalog.js" as QuickToggleCatalog

/**
 * The island dashboard's toolbar: edit, reload, settings, session - the sidebar
 * dashboard header's four buttons, as a tile of the grid.
 *
 * It is permanent (see QuickToggleCatalog): its edit button is the only way into the
 * grid's edit mode, so the grid would lock itself if the tile could be removed. In edit
 * mode it moves and resizes like any other tile, and only its edit button stays live -
 * the others step aside so a press on them starts a drag instead.
 */
Item {
    id: root

    required property int buttonIndex
    required property var buttonData
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize

    readonly property var catalogSize: QuickToggleCatalog.normalizeSize(root.buttonData.type, root.buttonData.sizeW, root.buttonData.sizeH, root.gridColumns)

    property bool editMode: false
    property bool isUnused: false
    property bool isDragging: false
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property int pageIndex: 0
    property int gridColumns: 4
    property var panel: null
    property var gridRef: null
    property int entranceTrigger: -1
    // Read by the edit overlay; the actions carry their own tooltips.
    property string tooltipText: ""
    readonly property bool hovered: false

    readonly property bool hasExplicitGeometry: root.buttonData
        && root.buttonData.layoutX !== undefined
        && root.buttonData.layoutY !== undefined
    Binding on x {
        when: root.hasExplicitGeometry
        value: editableItem.resizing ? editableItem.resizeOriginX : Number(root.buttonData.layoutX)
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding on y {
        when: root.hasExplicitGeometry
        value: editableItem.resizing ? editableItem.resizeOriginY : Number(root.buttonData.layoutY)
        restoreMode: Binding.RestoreBindingOrValue
    }
    z: root.isDragging || editableItem.resizing ? 100 : 0

    Behavior on x {
        enabled: root.hasExplicitGeometry && !root.isDragging && !editableItem.resizing
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on y {
        enabled: root.hasExplicitGeometry && !root.isDragging && !editableItem.resizing
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    readonly property real resizeDirectionX: editableItem.directionX
    readonly property real resizeDirectionY: editableItem.directionY
    readonly property int effectiveSizeW: root.catalogSize[0]
    readonly property int effectiveSizeH: root.catalogSize[1]

    implicitWidth: root.baseCellWidth * root.effectiveSizeW + root.cellSpacing * (root.effectiveSizeW - 1)
    implicitHeight: root.baseCellHeight * root.effectiveSizeH + root.cellSpacing * (root.effectiveSizeH - 1)

    Rectangle {
        id: visualButton
        width: editableItem.resizing ? editableItem.previewWidth : root.width
        height: editableItem.resizing ? editableItem.previewHeight : root.height
        radius: Config.options.appearance.sharpMode ? 0 : Math.min(width / 2, height / 2, Appearance.rounding.large)
        color: Appearance.colors.colLayer2
        scale: root.isDragging ? 1.05 : 1.0
        opacity: root.isDragging ? 0.95 : 1.0

        transform: Translate {
            x: root.isDragging ? root.dragOffsetX : 0
            y: root.isDragging ? root.dragOffsetY : 0
        }

        Behavior on width {
            enabled: !editableItem.resizing
            animation: Appearance.animation.elementResize.numberAnimation.createObject(visualButton)
        }
        Behavior on height {
            enabled: !editableItem.resizing
            animation: Appearance.animation.elementResize.numberAnimation.createObject(visualButton)
        }
        Behavior on scale {
            animation: Appearance.animation.clickBounce.numberAnimation.createObject(visualButton)
        }
    }

    EditableQuickToggleItem {
        id: editableItem
        target: root
        visualItem: visualButton
    }

    // Above the edit overlay, so the edit button can end edit mode; the rest are
    // disabled while editing and let presses through to the overlay.
    RowLayout {
        z: 20
        anchors.fill: visualButton
        anchors.margins: 4
        spacing: 2

        ToolbarAction {
            symbol: "edit"
            toggled: root.panel ? root.panel.editMode : false
            live: true
            tooltip: Translation.tr("Edit dashboard")
            onClicked: {
                if (root.panel)
                    root.panel.editModeToggleRequested();
            }
        }
        ToolbarAction {
            symbol: "restart_alt"
            tooltip: Translation.tr("Reload Hyprland & Quickshell")
            onClicked: {
                Quickshell.execDetached(["hyprctl", "reload"]);
                Quickshell.reload(true);
            }
        }
        ToolbarAction {
            symbol: "settings"
            tooltip: Translation.tr("Settings")
            onClicked: GlobalStates.toggleSettings()
        }
        ToolbarAction {
            symbol: "power_settings_new"
            tooltip: Translation.tr("Session")
            onClicked: GlobalStates.sessionOpen = true
        }
    }

    component ToolbarAction: RippleButton {
        id: action
        required property string symbol
        property string tooltip: ""
        property bool live: false

        Layout.fillWidth: true
        Layout.fillHeight: true
        enabled: action.live || !root.editMode
        opacity: action.enabled ? 1 : 0.45
        buttonRadius: Appearance.rounding.full
        colBackground: action.toggled ? Appearance.colors.colPrimary : "transparent"
        colBackgroundHover: action.toggled ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: action.symbol
            iconSize: Math.min(22, action.height * 0.5)
            fill: action.toggled ? 1 : 0
            color: action.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        }

        StyledToolTip {
            text: action.tooltip
        }
    }
}
