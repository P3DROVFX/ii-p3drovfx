import QtQuick
import Quickshell
import qs
import qs.services
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

    // A phone's or another PC's entry is only a thumbnail here: its file starts coming over
    // when the pointer lingers (phone) or presses, and the drag begins once it is on this PC.
    readonly property bool hasPhone: area.paths.some(p => FileShelf.isRemote(p))
    // Only the phone's photos on hover: another PC's file may be large, so it waits for a press.
    readonly property bool hoverFetch: area.paths.some(p => FileShelf.isPhone(p))
    Timer {
        interval: 180
        running: area.hoverFetch && area.containsMouse
        onTriggered: area.paths.forEach(p => FileShelf.prepare(p))
    }

    onPressed: event => {
        area.pressPoint = Qt.point(event.x, event.y);
        area.dragging = false;
        if (area.hasPhone)
            area.paths.forEach(p => FileShelf.prepare(p));
    }
    onPositionChanged: event => {
        if (!area.pressed || area.dragging || area.paths.length === 0)
            return;
        if (Math.abs(event.x - area.pressPoint.x) + Math.abs(event.y - area.pressPoint.y) < 8)
            return;
        const files = FileShelf.resolve(area.paths);
        if (files === null)
            return;
        area.dragging = true;
        GlobalStates.fileDragActive = true;
        try {
            dragProxy.Drag.mimeData = { "text/uri-list": UtilityFiles.uriList(files) };
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
