import QtQuick
import Quickshell
import qs
import "UtilityFiles.js" as UtilityFiles

/**
 * Press and travel: a native drag carrying `paths` as a text/uri-list, the
 * way the dock exports a pinned file (DockContent.moveItemDrag) — the QDrag
 * runs to the drop synchronously, so the area is back to rest when it returns.
 * A press that stays is a click.
 */
MouseArea {
    id: area

    property var paths: []
    property string dragIcon: "text-x-generic"
    signal dragFinished()

    property point pressPoint: Qt.point(0, 0)
    property bool dragging: false

    acceptedButtons: Qt.LeftButton
    preventStealing: true
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true

    onPressed: event => {
        area.pressPoint = Qt.point(event.x, event.y);
        area.dragging = false;
    }
    onPositionChanged: event => {
        if (!area.pressed || area.dragging || area.paths.length === 0)
            return;
        if (Math.abs(event.x - area.pressPoint.x) + Math.abs(event.y - area.pressPoint.y) < 8)
            return;
        area.dragging = true;
        GlobalStates.fileDragActive = true;
        try {
            dragProxy.Drag.mimeData = { "text/uri-list": UtilityFiles.uriList(area.paths) };
            dragProxy.Drag.imageSource = Quickshell.iconPath(area.dragIcon, "text-x-generic");
            dragProxy.Drag.active = true;
            dragProxy.Drag.startDrag(Qt.CopyAction);
        } finally {
            dragProxy.Drag.active = false;
            dragProxy.Drag.mimeData = {};
            dragProxy.Drag.imageSource = "";
            GlobalStates.fileDragActive = false;
            area.dragging = false;
        }
        Qt.callLater(function() {
            area.dragFinished();
        });
    }
    onReleased: {
        area.dragging = false;
        GlobalStates.fileDragActive = false;
    }
    onCanceled: {
        area.dragging = false;
        GlobalStates.fileDragActive = false;
    }
    Component.onDestruction: {
        if (area.dragging)
            GlobalStates.fileDragActive = false;
    }

    Item {
        id: dragProxy
        visible: false
        Drag.dragType: Drag.None
        Drag.supportedActions: Qt.CopyAction
        Drag.proposedAction: Qt.CopyAction
        Drag.imageSourceSize: Qt.size(48, 48)
    }
}
