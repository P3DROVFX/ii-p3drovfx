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
 * Supports responsive 2x1/3x1/4x1 (horizontal row), 1x2/1x3/1x4 (vertical column),
 * and 2x2/4x4/grid layouts in the Session Screen style with colPrimaryContainer
 * backgrounds that smoothly animate to full-pill/circle radius on active/press/hover.
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

    function scaled(value) {
        return QuickToggleMetrics.scaled(root.baseCellHeight, value);
    }

    readonly property bool isVertical: root.effectiveSizeW === 1 && root.effectiveSizeH > 1
    readonly property bool isGrid: root.effectiveSizeW > 1 && root.effectiveSizeH > 1
    readonly property bool isHorizontal: !isVertical && !isGrid

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

    // ── 1. HORIZONTAL LAYOUT (e.g. 2x1, 3x1, 4x1) ────────────────────────────
    RowLayout {
        z: 20
        anchors.fill: visualButton
        anchors.margins: 4
        spacing: 2
        visible: root.isHorizontal

        ToolbarActionLinear {
            symbol: "edit"
            toggled: root.panel ? root.panel.editMode : false
            live: true
            tooltip: Translation.tr("Edit dashboard")
            onClicked: {
                if (root.panel)
                    root.panel.editModeToggleRequested();
            }
        }
        ToolbarActionLinear {
            symbol: "restart_alt"
            tooltip: Translation.tr("Reload Hyprland & Quickshell")
            onClicked: {
                Quickshell.execDetached(["hyprctl", "reload"]);
                Quickshell.reload(true);
            }
        }
        ToolbarActionLinear {
            symbol: "settings"
            tooltip: Translation.tr("Settings")
            onClicked: GlobalStates.toggleSettings()
        }
        ToolbarActionLinear {
            symbol: "power_settings_new"
            tooltip: Translation.tr("Session")
            onClicked: GlobalStates.sessionOpen = true
        }
    }

    // ── 2. VERTICAL LAYOUT (e.g. 1x2, 1x3, 1x4) ──────────────────────────────
    ColumnLayout {
        z: 20
        anchors.fill: visualButton
        anchors.margins: 4
        spacing: 2
        visible: root.isVertical

        ToolbarActionLinear {
            symbol: "edit"
            toggled: root.panel ? root.panel.editMode : false
            live: true
            tooltip: Translation.tr("Edit dashboard")
            onClicked: {
                if (root.panel)
                    root.panel.editModeToggleRequested();
            }
        }
        ToolbarActionLinear {
            symbol: "restart_alt"
            tooltip: Translation.tr("Reload Hyprland & Quickshell")
            onClicked: {
                Quickshell.execDetached(["hyprctl", "reload"]);
                Quickshell.reload(true);
            }
        }
        ToolbarActionLinear {
            symbol: "settings"
            tooltip: Translation.tr("Settings")
            onClicked: GlobalStates.toggleSettings()
        }
        ToolbarActionLinear {
            symbol: "power_settings_new"
            tooltip: Translation.tr("Session")
            onClicked: GlobalStates.sessionOpen = true
        }
    }

    // ── 3. GRID LAYOUT (e.g. 2x2, 4x4, 3x2, 4x2, etc.) ──────────────────────
    GridLayout {
        z: 20
        anchors.fill: visualButton
        anchors.margins: root.scaled(6)
        columnSpacing: root.scaled(6)
        rowSpacing: root.scaled(6)
        columns: 2
        rows: 2
        visible: root.isGrid

        ToolbarActionGrid {
            symbol: "edit"
            toggled: root.panel ? root.panel.editMode : false
            live: true
            tooltip: Translation.tr("Edit dashboard")
            onClicked: {
                if (root.panel)
                    root.panel.editModeToggleRequested();
            }
        }
        ToolbarActionGrid {
            symbol: "restart_alt"
            tooltip: Translation.tr("Reload Hyprland & Quickshell")
            onClicked: {
                Quickshell.execDetached(["hyprctl", "reload"]);
                Quickshell.reload(true);
            }
        }
        ToolbarActionGrid {
            symbol: "settings"
            tooltip: Translation.tr("Settings")
            onClicked: GlobalStates.toggleSettings()
        }
        ToolbarActionGrid {
            symbol: "power_settings_new"
            tooltip: Translation.tr("Session")
            onClicked: GlobalStates.sessionOpen = true
        }
    }

    // ── Classic Linear Action Button (for 1-line Row / Column) ───────────────
    component ToolbarActionLinear: RippleButton {
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
            iconSize: Math.min(22, Math.min(action.width, action.height) * 0.5)
            fill: action.toggled ? 1 : 0
            color: action.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        }

        StyledToolTip {
            text: action.tooltip
        }
    }

    // ── Session Screen Style Action Button (for 2x2 / 4x4 Grid layouts) ───────
    component ToolbarActionGrid: RippleButton {
        id: action
        required property string symbol
        property string tooltip: ""
        property bool live: false

        Layout.fillWidth: true
        Layout.fillHeight: true
        enabled: action.live || !root.editMode
        opacity: action.enabled ? 1 : 0.45

        readonly property bool activeState: action.toggled || action.hovered || action.isPressed || action.down

        buttonRadius: activeState
            ? Math.min(width, height) / 2
            : Appearance.rounding.large
        buttonRadiusPressed: Math.min(width, height) / 2
        buttonEffectiveRadius: action.down ? buttonRadiusPressed : buttonRadius

        Behavior on buttonRadius {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        colBackground: action.activeState ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
        colBackgroundHover: Appearance.colors.colPrimary
        colBackgroundActive: Appearance.colors.colPrimaryActive
        colRipple: Appearance.colors.colPrimaryActive

        scale: action.down ? 0.94 : (action.hovered ? 1.04 : 1.0)
        Behavior on scale {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: action.symbol
            iconSize: Math.min(Math.min(action.width, action.height) * 0.48, root.scaled(36))
            fill: action.toggled ? 1 : 0
            color: action.activeState ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
        }

        StyledToolTip {
            text: action.tooltip
        }
    }
}
