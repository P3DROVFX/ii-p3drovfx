pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.quickToggles
import qs.modules.common.widgets
import qs.modules.common.notifications
import "QuickToggleCatalog.js" as QuickToggleCatalog

/**
 * A notification center quick toggle widget for the Dynamic Island dashboard.
 *
 * Embeds the shared NotificationList component inside a resizable Quick Toggle card.
 * Constrained to a minimum width of 4 columns (4xY) with freeform height (Y >= 1).
 */
Item {
    id: root

    required property int buttonIndex
    required property var buttonData
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize

    readonly property var catalogSize: QuickToggleCatalog.normalizeSize(root.buttonData?.type ?? "notificationListWidget", root.buttonData?.sizeW, root.buttonData?.sizeH, root.gridColumns)

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

    property string tooltipText: Translation.tr("Notifications")
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
        color: Appearance.colors.colLayer1
        scale: root.isDragging ? 1.05 : 1.0
        opacity: root.isDragging ? 0.95 : 1.0
        clip: true

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

        // Active NotificationList content
        Loader {
            id: contentLoader
            anchors.fill: parent
            anchors.margins: 5
            active: !root.isUnused
            sourceComponent: Item {
                anchors.fill: parent
                NotificationList {
                    id: notificationList
                    anchors.fill: parent
                    collapsed: false
                    entranceTrigger: root.entranceTrigger
                    enabled: !root.editMode && !root.isUnused
                }
            }
        }

        // Tray placeholder representation when in drawer
        Item {
            anchors.fill: parent
            anchors.margins: 6
            visible: root.isUnused

            RowLayout {
                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                    implicitWidth: 36
                    implicitHeight: 36
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer3

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "notifications"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer3
                    }
                }

                StyledText {
                    text: Translation.tr("Notifications")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
    }

    EditableQuickToggleItem {
        id: editableItem
        target: root
        visualItem: visualButton
    }
}
