pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common
import "QuickToggleCatalog.js" as QuickToggleCatalog

/**
 * Everything a custom widget tile needs that is not its design.
 *
 * The grid, the tray and the edit controller talk to every tile through the same
 * properties, and a widget tile has to place itself from the packer's geometry, follow
 * the resize preview, lift while dragged and carry the edit overlay. That is ~100 lines
 * every widget would otherwise copy. A tile built on this declares only its content:
 *
 *     AndroidWidgetTileBase {
 *         id: root
 *         MyContent { anchors.fill: parent }    // lives inside the tile's surface
 *     }
 *
 * Children are placed inside the surface (`surface`), so they follow the resize preview
 * and the drag, and sit under the edit overlay. Size the content from the tile
 * (`root.width`/`root.height` or anchors) and branch on `effectiveSizeW/H` for layouts
 * that change with the tile's size.
 */
Item {
    id: root

    // ── Set by the delegate chooser ──────────────────────────────────────────
    required property int buttonIndex
    required property var buttonData
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize

    property bool editMode: false
    /** Drawn in the tray rather than on the grid. */
    property bool isUnused: false
    /**
     * Whether this tile is genuinely on screen, and the gate for anything that
     * polls a service on its behalf.
     *
     * Placement is not presence: a grid can outlive its surface - the sidebar keeps
     * its dashboard warm (`keepRightSidebarLoaded`) - and `isUnused` only says the
     * tile is drawn in the tray. Reading `visible` returns the effective visibility,
     * which follows the ancestors: it drops with a closed surface and returns when it
     * opens, so a service works only while its data can actually be seen.
     */
    readonly property bool shownOnScreen: visible && !isUnused
    property bool isDragging: false
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property int pageIndex: 0
    property int gridColumns: 4
    property var panel: null
    property var gridRef: null
    property int entranceTrigger: -1

    // ── Read by the edit overlay ─────────────────────────────────────────────
    property string tooltipText: ""
    readonly property bool hovered: false

    // ── Look ─────────────────────────────────────────────────────────────────
    /** The tile's surface colour; transparent lets content draw its own. */
    property color surfaceColor: Appearance.colors.colLayer2
    /** The tile's corner radius, the grid's tile radius by default. */
    property real surfaceRadius: Config.options.appearance.sharpMode ? 0
        : Math.min(surface.width / 2, surface.height / 2, Appearance.rounding.large)
    /** Clip content to the surface's rounded shape (content drawn to its edges). */
    property bool clipContent: true

    /** The live surface, for content that needs its size while it is resized. */
    readonly property alias surface: visualButton
    default property alias content: contentHolder.data

    // ── Size ─────────────────────────────────────────────────────────────────
    readonly property var catalogSize: QuickToggleCatalog.normalizeSize(root.buttonData.type,
        root.buttonData.sizeW, root.buttonData.sizeH, root.gridColumns)
    readonly property int effectiveSizeW: root.catalogSize[0]
    readonly property int effectiveSizeH: root.catalogSize[1]
    readonly property real resizeDirectionX: editableItem.directionX
    readonly property real resizeDirectionY: editableItem.directionY

    implicitWidth: root.baseCellWidth * root.effectiveSizeW + root.cellSpacing * (root.effectiveSizeW - 1)
    implicitHeight: root.baseCellHeight * root.effectiveSizeH + root.cellSpacing * (root.effectiveSizeH - 1)

    // ── Placement: the packer owns it ────────────────────────────────────────
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

    // ── The surface ──────────────────────────────────────────────────────────
    Rectangle {
        id: visualButton
        width: editableItem.resizing ? editableItem.previewWidth : root.width
        height: editableItem.resizing ? editableItem.previewHeight : root.height
        radius: root.surfaceRadius
        color: root.surfaceColor
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

        Item {
            id: contentHolder
            anchors.fill: parent
            // Rectangular clip; a design that reaches its corners should keep inside
            // `surfaceRadius` or draw its own rounded shape.
            clip: root.clipContent
        }
    }

    // Drag, reorder, resize handle, add/remove badge.
    EditableQuickToggleItem {
        id: editableItem
        target: root
        visualItem: visualButton
    }
}
