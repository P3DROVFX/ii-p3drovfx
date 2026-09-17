import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "QuickToggleResize.js" as Resize
import "QuickToggleCatalog.js" as QuickToggleCatalog

// Shared editing surface for every Android quick-toggle delegate. The visual
// widget stays owned by its base component; this item only handles gestures,
// draft mutations, and edit affordances.
Item {
    id: root

    required property var target
    required property var visualItem

    readonly property var controller: target && target.panel ? target.panel.editController : null
    readonly property bool editMode: target ? target.editMode : false
    readonly property bool isUnused: target ? target.isUnused : false
    readonly property bool pageFocused: root.isUnused || !target?.panel
        || target.pageIndex === target.panel.currentPage
    readonly property bool isSlider: target && target.buttonData ? ["volumeSlider", "micSlider", "brightnessSlider", "gammaSlider"].includes(target.buttonData.type) : false
    readonly property bool canResize: target && target.pageIndex >= 0 && !root.isUnused
        && QuickToggleCatalog.isResizable(target.buttonData?.type ?? "", target.gridColumns)

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
    readonly property bool resizing: resizePressed && root.editMode && root.controller
        && root.controller.active && root.controller.mode === "resize"
        && root.controller.draggedId === root.target.buttonData.id
    property real resizeStartWidth: 0
    property real resizeStartHeight: 0
    property real previewWidth: 0
    property real previewHeight: 0
    property real resizeOriginX: 0
    property real resizeOriginY: 0
    property real directionX: 0
    property real directionY: 1
    readonly property var resizeBounds: Resize.bounds(root.target.buttonData.type, root.target.gridColumns)
    readonly property real minimumHeight: root.isSlider ? root.target.compactHeight : root.target.baseCellHeight

    // Direction may reverse while details are half dissolved. Ease that vector
    // only, leaving the surface and pointer geometry completely synchronous.
    Behavior on directionX { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root) }
    Behavior on directionY { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root) }

    property alias containsMouse: editInteraction.containsMouse

    anchors.fill: root.visualItem
    visible: root.editMode
    z: target && target.isDragging ? 100 : 10

    function beginResize() {
        if (!root.controller || !root.canResize)
            return false;
        if (!root.controller.beginResize(root.target.buttonData.id, root.target.pageIndex))
            return false;
        root.resizeOriginX = root.target.x;
        root.resizeOriginY = root.target.y;
        root.resizeStartWidth = root.visualItem.width + (root.isSlider ? root.target.horizontalMargin * 2 : 0);
        root.resizeStartHeight = root.visualItem.height;
        root.previewWidth = root.resizeStartWidth;
        root.previewHeight = root.resizeStartHeight;
        var size = root.target.catalogSize;
        root.resizeStartW = size[0];
        root.resizeStartH = size[1];
        root.resizePressed = true;
        return true;
    }

    function resizePointerInStableReference(sourceItem, pointerX, pointerY) {
        var reference = root.target.panel || root.target.gridRef || root.target.parent;
        if (!reference)
            return Qt.point(pointerX, pointerY);
        return reference.mapFromItem(sourceItem, pointerX, pointerY);
    }

    function previewResize(deltaX, deltaY) {
        if (!root.resizing || !root.controller)
            return;

        var geometry = Resize.pixels(root.resizeStartWidth, root.resizeStartHeight,
            deltaX, deltaY, root.target.baseCellWidth, root.target.baseCellHeight,
            root.target.cellSpacing, root.resizeBounds, root.minimumHeight);
        var dx = geometry.width - root.previewWidth;
        var dy = geometry.height - root.previewHeight;
        var distance = Math.sqrt(dx * dx + dy * dy);
        if (distance > 0.25) {
            root.directionX = dx / distance;
            root.directionY = dy / distance;
        }
        root.previewWidth = geometry.width;
        root.previewHeight = geometry.height;
        root.controller.resizePreviewBottom = root.resizeOriginY + geometry.height;
        var spanW = Resize.spanFromPixelWidth(geometry.width, root.target.baseCellWidth,
            root.target.baseCellHeight, root.target.cellSpacing);
        var spanH = Resize.spanFromPixelHeight(geometry.height, root.target.baseCellHeight,
            root.target.cellSpacing);
        var size = Resize.candidate(root.target.buttonData.type,
            spanW, spanH,
            root.target.gridColumns, [root.controller.candidateSizeW, root.controller.candidateSizeH]);
        root.controller.previewResize(size[0], size[1]);
    }

    function finishResize() {
        if (!root.resizing)
            return;
        if (root.controller)
            root.controller.commitResize();
        root.resizePressed = false;
    }

    function cancelResize() {
        if (!root.resizing)
            return;
        if (root.controller)
            root.controller.cancelResize();
        root.resizePressed = false;
    }

    Connections {
        target: root.controller
        function onActiveChanged() {
            if (!root.controller.active)
                root.resizePressed = false;
        }
    }

    MouseArea {
        id: editInteraction
        anchors.fill: parent
        visible: root.editMode
        cursorShape: root.target && root.target.isDragging ? Qt.ClosedHandCursor
                    : (root.isUnused ? Qt.PointingHandCursor : Qt.OpenHandCursor)
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton

        onPressed: event => {
            if (!root.isUnused && !root.controller)
                return;
            root.pressX = event.x;
            root.pressY = event.y;
            if (root.target.panel) {
                var pointer = root.target.panel.mapFromItem(editInteraction, event.x, event.y);
                var origin = root.target.panel.mapFromItem(root.target, 0, 0);
                root.pressPointerPanelX = pointer.x;
                root.pressPointerPanelY = pointer.y;
                root.pressItemPanelX = origin.x;
                root.pressItemPanelY = origin.y;
            }
            root.target.dragOffsetX = 0;
            root.target.dragOffsetY = 0;
            root.target.isDragging = false;
        }

        onPositionChanged: event => {
            if (!pressed || root.isUnused)
                return;
            var dx = event.x - root.pressX;
            var dy = event.y - root.pressY;
            var panelPos = null;
            if (root.target.panel) {
                panelPos = root.target.panel.mapFromItem(editInteraction, event.x, event.y);
                dx = panelPos.x - root.pressPointerPanelX;
                dy = panelPos.y - root.pressPointerPanelY;
            }
            if (!root.target.isDragging && (Math.abs(dx) > 4 || Math.abs(dy) > 4)) {
                if (!root.controller.beginReorder(root.target.buttonData.id, root.target.pageIndex))
                    return;
                root.target.isDragging = true;
            }

            if (!root.target.isDragging)
                return;

            // Preview packing may move the delegate root. Compensate that move
            // so the visual remains under the grabbed pointer without
            // reparenting it out of the stable delegate.
            if (root.target.panel) {
                var currentOrigin = root.target.panel.mapFromItem(root.target, 0, 0);
                root.target.dragOffsetX = root.pressItemPanelX + dx - currentOrigin.x;
                root.target.dragOffsetY = root.pressItemPanelY + dy - currentOrigin.y;
            } else {
                root.target.dragOffsetX = dx;
                root.target.dragOffsetY = dy;
            }
            if (!root.isUnused && root.controller
                    && root.controller.targetPage === root.target.pageIndex) {
                var gridPos;
                if (root.target.gridRef && root.target.panel) {
                    gridPos = root.target.gridRef.mapFromItem(
                        root.target.panel,
                        root.pressItemPanelX + dx + root.target.width / 2,
                        root.pressItemPanelY + dy + root.target.height / 2
                    );
                } else {
                    gridPos = root.target.parent.mapFromItem(editInteraction, event.x, event.y);
                }
                root.controller.previewReorderAt(
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
                if (root.controller) {
                    root.controller.commitReorder();
                }
                if (root.target.panel && root.target.panel.cancelDragScroll)
                    root.target.panel.cancelDragScroll();
                root.target.isDragging = false;
                root.target.dragOffsetX = 0;
                root.target.dragOffsetY = 0;
                return;
            }

            if (root.controller && root.controller.active)
                root.controller.cancelReorder();
            if (!root.controller)
                return;
            if (root.isUnused)
                root.controller.addToggle(root.target.buttonData.type, root.target.pageIndex);
            else
                root.controller.removeToggle(root.target.buttonData.id);
        }

        onCanceled: {
            if (root.controller && root.controller.active)
                root.controller.cancel();
            root.target.isDragging = false;
            root.target.dragOffsetX = 0;
            root.target.dragOffsetY = 0;
            root.cancelResize();
        }
    }

    readonly property real cornerRadius: root.visualItem
        ? (root.visualItem.buttonRadius ?? root.visualItem.radius ?? Appearance.rounding.large)
        : Appearance.rounding.large

    Rectangle {
        id: editBorder
        anchors.fill: parent
        radius: root.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.75)
        visible: root.editMode && root.pageFocused && !root.target.isDragging
        z: 0
    }

    QuickToggleResizeHandle {
        id: diagonalGrip
        objectName: "quickToggleResizeGrip"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -thickness / 2
        anchors.bottomMargin: -thickness / 2
        visible: root.pageFocused && root.canResize && !root.target.isDragging
        hitSize: Math.max(38, root.cornerRadius + thickness + 12)
        thickness: Math.max(3.5, Math.min(5, Math.round(root.target.baseCellHeight * 0.07)))
        cornerRadius: root.cornerRadius
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
                // Capture the pointer before beginning a transaction can reflow
                // the grid; future events are mapped to this same panel space.
                var start = root.resizePointerInStableReference(resizeArea, event.x, event.y);
                if (!root.beginResize()) {
                    event.accepted = false;
                    return;
                }
                root.resizeStartReferenceX = start.x;
                root.resizeStartReferenceY = start.y;
            }
            onPositionChanged: event => {
                if (!pressed || !root.resizing)
                    return;
                var current = root.resizePointerInStableReference(resizeArea, event.x, event.y);
                root.previewResize(current.x - root.resizeStartReferenceX,
                    current.y - root.resizeStartReferenceY);
            }
            onReleased: root.finishResize()
            onCanceled: root.cancelResize()
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

    StyledToolTip {
        parent: root.target
        extraVisibleCondition: root.target.tooltipText !== ""
                && (root.target.hovered || root.containsMouse)
        text: root.target.tooltipText
    }

    Component.onDestruction: {
        if (root.controller && root.controller.active
                && root.controller.draggedId === root.target.buttonData.id)
            root.controller.cancel();
    }
}
