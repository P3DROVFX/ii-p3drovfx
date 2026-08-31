import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "QuickToggleLayout.js" as QuickToggleLayout

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
    readonly property bool isMedia: target && target.buttonData ? target.buttonData.type === "mediaWidget" : false
    readonly property bool isSlider: target && target.buttonData ? ["volumeSlider", "micSlider", "brightnessSlider", "gammaSlider"].includes(target.buttonData.type) : false
    readonly property bool canResize: target && target.pageIndex >= 0 && !root.isUnused
    readonly property bool canResizeHeight: root.canResize

    property real pressX: 0
    property real pressY: 0
    property real pressPointerPanelX: 0
    property real pressPointerPanelY: 0
    property real pressItemPanelX: 0
    property real pressItemPanelY: 0
    property real editDragX: 0
    property real editDragY: 0
    property bool editingRight: false
    property bool editingBottom: false
    property int resizeStartW: 1
    property int resizeStartH: 1
    property real resizeStartReferenceX: 0
    property real resizeStartReferenceY: 0
    property bool resizing: false

    property alias containsMouse: editInteraction.containsMouse

    anchors.fill: parent
    visible: root.editMode
    z: target && target.isDragging ? 100 : 10

    function beginResize() {
        if (!root.controller || !root.canResize)
            return false;
        if (!root.controller.beginResize(root.target.buttonData.id, root.target.pageIndex))
            return false;
        var size = root.target.catalogSize;
        root.resizeStartW = size[0];
        root.resizeStartH = size[1];
        root.resizing = true;
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

        var width = root.resizeStartW;
        var height = root.resizeStartH;
        if (root.isMedia) {
            var threshold = root.target.baseCellWidth / 2;
            width = deltaX > threshold ? 4 : (deltaX < -threshold ? 2 : root.resizeStartW);
            width = Math.max(2, Math.min(4, width));
            if (width === 4 && height === 1)
                height = 2;
        } else {
            width = QuickToggleLayout.resizeSpanFromDelta(
                root.resizeStartW,
                deltaX,
                root.target.baseCellWidth,
                root.target.cellSpacing,
                root.target.gridColumns
            );
            if (root.canResizeHeight)
                height = QuickToggleLayout.resizeSpanFromDelta(
                    root.resizeStartH,
                    deltaY,
                    root.target.baseCellHeight,
                    root.target.cellSpacing,
                    8
                );
        }

        root.controller.previewResize(width, height);
    }

    function finishResize() {
        if (!root.resizing)
            return;
        root.resizing = false;
        if (root.controller)
            root.controller.commitResize();
        root.editDragX = 0;
        root.editDragY = 0;
        root.editingRight = false;
        root.editingBottom = false;
    }

    function cancelResize() {
        if (!root.resizing)
            return;
        root.resizing = false;
        if (root.controller)
            root.controller.cancelResize();
        root.editDragX = 0;
        root.editDragY = 0;
        root.editingRight = false;
        root.editingBottom = false;
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
                    root.target.cellSpacing
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
            if (root.editingRight || root.editingBottom)
                return;
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

    Rectangle {
        id: editBorder
        anchors.fill: parent
        visible: root.editMode && !root.target.isDragging
        color: "transparent"
        border.width: 2
        radius: Appearance.rounding.large
        border.color: root.isUnused
                ? (root.target.hovered ? Appearance.colors.colPrimary : "transparent")
                : (root.target.hovered ? Appearance.colors.colPrimary
                                        : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7))
        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(editBorder)
        }
    }

    Rectangle {
        id: rightDragHandle
        width: 8
        height: 24
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimary
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: -width / 2
        visible: root.canResize

        MouseArea {
            id: rightResizeArea
            anchors.fill: parent
            anchors.margins: -12
            cursorShape: Qt.SizeHorCursor
            preventStealing: true

            onPressed: event => {
                if (!root.beginResize())
                    return;
                var start = root.resizePointerInStableReference(rightResizeArea, event.x, event.y);
                root.resizeStartReferenceX = start.x;
                root.resizeStartReferenceY = start.y;
                root.editingRight = true;
            }
            onPositionChanged: event => {
                if (!root.resizing)
                    return;
                var current = root.resizePointerInStableReference(rightResizeArea, event.x, event.y);
                var deltaX = current.x - root.resizeStartReferenceX;
                root.editDragX = deltaX;
                root.previewResize(deltaX, 0);
            }
            onReleased: root.finishResize()
        }
    }

    Rectangle {
        id: bottomDragHandle
        width: 24
        height: 8
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimary
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -height / 2
        visible: root.canResizeHeight && (!root.isMedia || root.target.catalogSize[0] <= 2)

        MouseArea {
            id: bottomResizeArea
            anchors.fill: parent
            anchors.margins: -12
            cursorShape: Qt.SizeVerCursor
            preventStealing: true

            onPressed: event => {
                if (!root.beginResize())
                    return;
                var start = root.resizePointerInStableReference(bottomResizeArea, event.x, event.y);
                root.resizeStartReferenceX = start.x;
                root.resizeStartReferenceY = start.y;
                root.editingBottom = true;
            }
            onPositionChanged: event => {
                if (!root.resizing)
                    return;
                var current = root.resizePointerInStableReference(bottomResizeArea, event.x, event.y);
                var deltaY = current.y - root.resizeStartReferenceY;
                root.editDragY = deltaY;
                root.previewResize(0, deltaY);
            }
            onReleased: root.finishResize()
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
