import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "QuickToggleResize.js" as Resize
import "QuickToggleCatalog.js" as QuickToggleCatalog

// Shared editing surface for every Android quick-toggle delegate. The visual
// widget stays owned by its base component; all edit gestures, Behaviors, and
// affordances are loaded lazily only while editMode is active.
Item {
    id: root

    required property var target
    required property var visualItem

    readonly property bool editMode: target ? target.editMode : false
    readonly property bool isUnused: target ? target.isUnused : false

    // Lightweight facade properties read by tile bases when editMode is off.
    readonly property bool resizing: editLoader.item ? editLoader.item.resizing : false
    readonly property real resizeOriginX: editLoader.item ? editLoader.item.resizeOriginX : 0
    readonly property real resizeOriginY: editLoader.item ? editLoader.item.resizeOriginY : 0
    readonly property real previewWidth: editLoader.item ? editLoader.item.previewWidth : 0
    readonly property real previewHeight: editLoader.item ? editLoader.item.previewHeight : 0
    readonly property real directionX: editLoader.item ? editLoader.item.directionX : 0
    readonly property real directionY: editLoader.item ? editLoader.item.directionY : 1
    readonly property bool containsMouse: editLoader.item ? editLoader.item.containsMouse : false

    anchors.fill: root.visualItem
    visible: root.editMode
    z: target && target.isDragging ? 100 : 10

    Loader {
        id: editLoader
        anchors.fill: parent
        active: root.editMode
        sourceComponent: Item {
            id: editSurface

            readonly property var controller: root.target && root.target.panel ? root.target.panel.editController : null
            readonly property bool pageFocused: root.isUnused || !root.target?.panel
                || root.target.pageIndex === root.target.panel.currentPage
            readonly property bool isSlider: root.target && root.target.buttonData
                ? ["volumeSlider", "micSlider", "brightnessSlider", "gammaSlider"].includes(root.target.buttonData.type)
                : false
            readonly property bool canResize: root.target && root.target.pageIndex >= 0 && !root.isUnused
                && QuickToggleCatalog.isResizable(root.target.buttonData?.type ?? "", root.target.gridColumns)

            property real pressX: 0
            property real pressY: 0
            property real pressPointerPanelX: 0
            property real pressPointerPanelY: 0
            property real pressItemPanelX: 0
            property real pressItemPanelY: 0
            property int resizeStartW: 1
            property int resizeStartH: 1
            property real resizeStartReferenceX: 0
            property real resizeStartReferenceY: 0
            property bool resizePressed: false
            readonly property bool resizing: resizePressed && root.editMode && editSurface.controller
                && editSurface.controller.active && editSurface.controller.mode === "resize"
                && editSurface.controller.draggedId === root.target.buttonData.id
            property real resizeStartWidth: 0
            property real resizeStartHeight: 0
            property real previewWidth: 0
            property real previewHeight: 0
            property real resizeOriginX: 0
            property real resizeOriginY: 0
            property real directionX: 0
            property real directionY: 1
            readonly property var resizeBounds: Resize.bounds(root.target.buttonData.type, root.target.gridColumns)
            readonly property real minimumHeight: editSurface.isSlider ? root.target.compactHeight : root.target.baseCellHeight

            Behavior on directionX { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(editSurface) }
            Behavior on directionY { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(editSurface) }

            property alias containsMouse: editInteraction.containsMouse

            function beginResize() {
                if (!editSurface.controller || !editSurface.canResize)
                    return false;
                if (!editSurface.controller.beginResize(root.target.buttonData.id, root.target.pageIndex))
                    return false;
                editSurface.resizeOriginX = root.target.x;
                editSurface.resizeOriginY = root.target.y;
                editSurface.resizeStartWidth = root.visualItem.width + (editSurface.isSlider ? root.target.horizontalMargin * 2 : 0);
                editSurface.resizeStartHeight = root.visualItem.height;
                editSurface.previewWidth = editSurface.resizeStartWidth;
                editSurface.previewHeight = editSurface.resizeStartHeight;
                var size = root.target.catalogSize;
                editSurface.resizeStartW = size[0];
                editSurface.resizeStartH = size[1];
                editSurface.resizePressed = true;
                return true;
            }

            function resizePointerInStableReference(sourceItem, pointerX, pointerY) {
                var reference = root.target.panel || root.target.gridRef || root.target.parent;
                if (!reference)
                    return Qt.point(pointerX, pointerY);
                return reference.mapFromItem(sourceItem, pointerX, pointerY);
            }

            function previewResize(deltaX, deltaY) {
                if (!editSurface.resizing || !editSurface.controller)
                    return;

                var geometry = Resize.pixels(editSurface.resizeStartWidth, editSurface.resizeStartHeight,
                    deltaX, deltaY, root.target.baseCellWidth, root.target.baseCellHeight,
                    root.target.cellSpacing, editSurface.resizeBounds, editSurface.minimumHeight);
                var dx = geometry.width - editSurface.previewWidth;
                var dy = geometry.height - editSurface.previewHeight;
                var distance = Math.sqrt(dx * dx + dy * dy);
                if (distance > 0.25) {
                    editSurface.directionX = dx / distance;
                    editSurface.directionY = dy / distance;
                }
                editSurface.previewWidth = geometry.width;
                editSurface.previewHeight = geometry.height;
                editSurface.controller.resizePreviewBottom = editSurface.resizeOriginY + geometry.height;
                var spanW = Resize.spanFromPixelWidth(geometry.width, root.target.baseCellWidth,
                    root.target.baseCellHeight, root.target.cellSpacing);
                var spanH = Resize.spanFromPixelHeight(geometry.height, root.target.baseCellHeight,
                    root.target.cellSpacing);
                var size = Resize.candidate(root.target.buttonData.type,
                    spanW, spanH,
                    root.target.gridColumns, [editSurface.controller.candidateSizeW, editSurface.controller.candidateSizeH]);
                editSurface.controller.previewResize(size[0], size[1]);
            }

            function finishResize() {
                if (!editSurface.resizing)
                    return;
                if (editSurface.controller)
                    editSurface.controller.commitResize();
                editSurface.resizePressed = false;
            }

            function cancelResize() {
                if (!editSurface.resizing)
                    return;
                if (editSurface.controller)
                    editSurface.controller.cancelResize();
                editSurface.resizePressed = false;
            }

            Connections {
                target: editSurface.controller
                function onActiveChanged() {
                    if (!editSurface.controller.active)
                        editSurface.resizePressed = false;
                }
            }

            MouseArea {
                id: editInteraction
                anchors.fill: parent
                cursorShape: root.target && root.target.isDragging ? Qt.ClosedHandCursor
                            : (root.isUnused ? Qt.PointingHandCursor : Qt.OpenHandCursor)
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton

                onPressed: event => {
                    if (!root.isUnused && !editSurface.controller)
                        return;
                    editSurface.pressX = event.x;
                    editSurface.pressY = event.y;
                    if (root.target.panel) {
                        var pointer = root.target.panel.mapFromItem(editInteraction, event.x, event.y);
                        var origin = root.target.panel.mapFromItem(root.target, 0, 0);
                        editSurface.pressPointerPanelX = pointer.x;
                        editSurface.pressPointerPanelY = pointer.y;
                        editSurface.pressItemPanelX = origin.x;
                        editSurface.pressItemPanelY = origin.y;
                    }
                    root.target.dragOffsetX = 0;
                    root.target.dragOffsetY = 0;
                    root.target.isDragging = false;
                }

                onPositionChanged: event => {
                    if (!pressed || root.isUnused)
                        return;
                    var dx = event.x - editSurface.pressX;
                    var dy = event.y - editSurface.pressY;
                    var panelPos = null;
                    if (root.target.panel) {
                        panelPos = root.target.panel.mapFromItem(editInteraction, event.x, event.y);
                        dx = panelPos.x - editSurface.pressPointerPanelX;
                        dy = panelPos.y - editSurface.pressPointerPanelY;
                    }
                    if (!root.target.isDragging && (Math.abs(dx) > 4 || Math.abs(dy) > 4)) {
                        if (!editSurface.controller.beginReorder(root.target.buttonData.id, root.target.pageIndex))
                            return;
                        root.target.isDragging = true;
                    }

                    if (!root.target.isDragging)
                        return;

                    if (root.target.panel) {
                        var currentOrigin = root.target.panel.mapFromItem(root.target, 0, 0);
                        root.target.dragOffsetX = editSurface.pressItemPanelX + dx - currentOrigin.x;
                        root.target.dragOffsetY = editSurface.pressItemPanelY + dy - currentOrigin.y;
                    } else {
                        root.target.dragOffsetX = dx;
                        root.target.dragOffsetY = dy;
                    }
                    if (!root.isUnused && editSurface.controller
                            && editSurface.controller.targetPage === root.target.pageIndex) {
                        var gridPos;
                        if (root.target.gridRef && root.target.panel) {
                            gridPos = root.target.gridRef.mapFromItem(
                                root.target.panel,
                                editSurface.pressItemPanelX + dx + root.target.width / 2,
                                editSurface.pressItemPanelY + dy + root.target.height / 2
                            );
                        } else {
                            gridPos = root.target.parent.mapFromItem(editInteraction, event.x, event.y);
                        }
                        editSurface.controller.previewReorderAt(
                            root.target.pageIndex,
                            gridPos.x,
                            gridPos.y,
                            root.target.baseCellWidth,
                            root.target.baseCellHeight,
                            root.target.cellSpacing,
                            root.target.panel ? root.target.panel.compactRowHeight : 0,
                            root.target.panel ? root.target.panel.compactToggleTypes : null
                        );
                    }
                    if (root.target.panel && root.target.panel.handleDragScrollRequest) {
                        if (!panelPos)
                            panelPos = root.target.panel.mapFromItem(editInteraction, event.x, event.y);
                        root.target.panel.handleDragScrollRequest(panelPos.x, root.target);
                    }
                }

                onReleased: event => {
                    if (root.target.isDragging) {
                        if (editSurface.controller)
                            editSurface.controller.commitReorder();
                        if (root.target.panel && root.target.panel.cancelDragScroll)
                            root.target.panel.cancelDragScroll();
                        root.target.isDragging = false;
                        root.target.dragOffsetX = 0;
                        root.target.dragOffsetY = 0;
                        return;
                    }

                    if (editSurface.controller && editSurface.controller.active)
                        editSurface.controller.cancelReorder();
                    if (!editSurface.controller)
                        return;
                    if (root.isUnused)
                        editSurface.controller.addToggle(root.target.buttonData.type, root.target.pageIndex);
                    else
                        editSurface.controller.removeToggle(root.target.buttonData.id);
                }

                onCanceled: {
                    if (editSurface.controller && editSurface.controller.active)
                        editSurface.controller.cancel();
                    root.target.isDragging = false;
                    root.target.dragOffsetX = 0;
                    root.target.dragOffsetY = 0;
                    editSurface.cancelResize();
                }
            }

            readonly property real cornerRadius: root.visualItem
                ? (root.visualItem.buttonRadius ?? root.visualItem.radius ?? Appearance.rounding.large)
                : Appearance.rounding.large

            Rectangle {
                id: editBorder
                anchors.fill: parent
                radius: editSurface.cornerRadius
                color: "transparent"
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.75)
                visible: editSurface.pageFocused && !root.target.isDragging
                z: 0
            }

            QuickToggleResizeHandle {
                id: diagonalGrip
                objectName: "quickToggleResizeGrip"
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -thickness / 2
                anchors.bottomMargin: -thickness / 2
                visible: editSurface.pageFocused && editSurface.canResize && !root.target.isDragging
                hitSize: Math.max(38, editSurface.cornerRadius + thickness + 12)
                thickness: Math.max(3.5, Math.min(5, Math.round(root.target.baseCellHeight * 0.07)))
                cornerRadius: editSurface.cornerRadius
                pressed: resizeArea.pressed
                hovered: resizeArea.containsMouse

                MouseArea {
                    id: resizeArea
                    objectName: "quickToggleResizeArea"
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: Math.max(18, Math.min(22, (root.target ? root.target.width : 56) * 0.38))
                    height: width
                    cursorShape: Qt.SizeFDiagCursor
                    hoverEnabled: true
                    preventStealing: true
                    acceptedButtons: Qt.LeftButton
                    onPressed: event => {
                        var start = editSurface.resizePointerInStableReference(resizeArea, event.x, event.y);
                        if (!editSurface.beginResize()) {
                            event.accepted = false;
                            return;
                        }
                        editSurface.resizeStartReferenceX = start.x;
                        editSurface.resizeStartReferenceY = start.y;
                    }
                    onPositionChanged: event => {
                        if (!pressed || !editSurface.resizing)
                            return;
                        var current = editSurface.resizePointerInStableReference(resizeArea, event.x, event.y);
                        editSurface.previewResize(current.x - editSurface.resizeStartReferenceX,
                            current.y - editSurface.resizeStartReferenceY);
                    }
                    onReleased: editSurface.finishResize()
                    onCanceled: editSurface.cancelResize()
                }
            }

            Rectangle {
                id: addBadge
                width: 20
                height: 20
                radius: Appearance.rounding.full
                color: Appearance.m3colors.m3success
                anchors.top: parent.top
                anchors.topMargin: -6
                anchors.right: parent.right
                anchors.rightMargin: -6
                visible: root.isUnused
                z: 10

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "add"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.m3colors.m3onSuccess
                }
            }

            Component.onDestruction: {
                if (editSurface.controller && editSurface.controller.active
                        && editSurface.controller.draggedId === root.target.buttonData.id)
                    editSurface.controller.cancel();
            }
        }
    }

    // Only instantiate StyledToolTip when the tile is actually hovered and has text.
    Loader {
        active: Boolean(root.target) && root.target.tooltipText !== ""
            && (root.target.hovered || root.containsMouse)
        sourceComponent: StyledToolTip {
            parent: root.target
            extraVisibleCondition: true
            text: root.target ? root.target.tooltipText : ""
        }
    }
}
