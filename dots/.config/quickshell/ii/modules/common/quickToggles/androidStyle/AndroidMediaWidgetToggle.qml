import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.quickToggles
import qs.modules.common.animations
import qs.modules.common.widgets
import "QuickToggleCatalog.js" as QuickToggleCatalog

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

    // Active pages and the drawer use one explicit packed coordinate system.
    // Bind only when geometry is present so fixed sliders can still be owned by
    // their Column positioner.
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

    property int entranceTrigger: -1
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations
    readonly property bool entrancePageActive: root.pageIndex === -1 || !root.panel
        || root.panel.currentPage === root.pageIndex

    DashboardEntranceProgress {
        id: entranceProgress
        animationSpec: Appearance.animation.elementMove
        animationsEnabled: root.entranceAnimationsEnabled
        trigger: root.entranceTrigger
        pageActive: root.entrancePageActive
        delayIndex: Math.min(Math.max(root.buttonIndex, 0), 15)
        staggerRatio: 0.08
    }

    property string tooltipText: {
        var player = MprisController.activePlayer;
        if (player && player.trackTitle) {
            var artist = player.trackArtist ? player.trackArtist : Translation.tr("Unknown Artist");
            return player.trackTitle + " - " + artist;
        }
        return Translation.tr("Media Player");
    }

    function scaled(value) { return QuickToggleMetrics.scaled(root.baseCellHeight, value); }
    readonly property real resizeDirectionX: editableItem.directionX
    readonly property real resizeDirectionY: editableItem.directionY

    // Effective sizes for live preview during resize
    readonly property int effectiveSizeW: root.catalogSize[0]
    readonly property int effectiveSizeH: root.catalogSize[1]

    property bool hovered: hoverHandler.hovered || (root.editMode && editableItem.containsMouse)

    HoverHandler {
        id: hoverHandler
    }

    property real baseWidth: root.baseCellWidth * root.effectiveSizeW + cellSpacing * (root.effectiveSizeW - 1)
    property real baseHeight: root.baseCellHeight * root.effectiveSizeH + cellSpacing * (root.effectiveSizeH - 1)

    implicitWidth: baseWidth
    implicitHeight: baseHeight

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainer
        visible: root.isDragging
        opacity: 0.5
    }

    Item {
        id: visualButton

        x: 0
        y: 0
        
        Behavior on width {
            enabled: !editableItem.resizing
            NumberAnimation {
                duration: Appearance.animation.elementResize.duration
                easing.type: Appearance.animation.elementResize.type
                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
            }
        }
        Behavior on height {
            enabled: !editableItem.resizing
            NumberAnimation {
                duration: Appearance.animation.elementResize.duration
                easing.type: Appearance.animation.elementResize.type
                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
            }
        }

        width: editableItem.resizing ? editableItem.previewWidth : root.width
        height: editableItem.resizing ? editableItem.previewHeight : root.height

        scale: (root.isDragging ? 1.05 : 1.0) * (0.85 + 0.15 * entranceProgress.progress)
        opacity: {
            if (entranceProgress.progress < 1) return entranceProgress.progress;
            if (root.isUnused)
                return 0.5;
            if (root.editMode && !root.isDragging)
                return 0.9;
            if (root.isDragging)
                return 0.95;
            return 1.0;
        }
        z: root.isDragging ? 99 : 1

        transform: Translate {
            x: root.isDragging ? root.dragOffsetX : 0
            y: (root.isDragging ? root.dragOffsetY : 0) + 20 * (1 - entranceProgress.progress)
        }

        Behavior on scale {
            enabled: !entranceProgress.running
            animation: Appearance.animation.clickBounce.numberAnimation.createObject(visualButton)
        }
        Behavior on opacity {
            enabled: !entranceProgress.running
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }

        property real radius: Config.options.appearance.sharpMode ? 0
            : Math.min(width / 2, height / 2, Appearance.rounding.large)
        QuickToggleMediaContent {
            anchors.fill: parent
            tile: root
        }
    }

    EditableQuickToggleItem {
        id: editableItem
        target: root
        visualItem: visualButton
    }
}
