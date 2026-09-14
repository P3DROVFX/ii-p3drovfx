import QtQuick
import QtTest
import "dock/widgets"
import "dock"
import qs.modules.common

TestCase {
    id: testCase
    name: "DockPopups"
    when: windowShown
    visible: true
    width: 900
    height: 700

    Component { id: popupComponent; DockContextMenuBase { showHeader: false; contentComponent: Item { implicitWidth: 240; implicitHeight: 150 } } }
    Component { id: appComponent; DockAppButton {} }
    Component { id: tileComponent; DockAppGroupButton {} }
    Component { id: menuComponent; DockContextMenu {} }
    Component { id: groupComponent; DockGroupPopup {} }
    QtObject {
        id: fakeDock
        property string dockPos: "bottom"
        property bool isVertical: false
        property real buttonSlotSize: 72
        property real buttonSlotHeight: 72
        property int groupAnimationDuration: 120
        property string groupTransitionKind: ""
        property int openMenus: 0
        property bool buttonHovered: false
        property bool suppressHover: false
        property var lastHoveredButton: null
        property int dragStarts: 0
        function onButtonEntered(item) {}
        function onButtonExited(item) {}
        function startItemDrag(index, item, x, y) { dragStarts++; }
        function moveItemDrag(item, x, y) {}
        function endItemDrag() {}
        function cancelDrag() {}
        function isGroupExiting(id) { return false; }
        function isGroupEntryTransition(id) { return false; }
        function registerContextMenuOpen() { openMenus++; }
        function registerContextMenuClose() { openMenus--; }
        property var removed: []
        property var group: null
        function removeAppFromGroup(groupId, appId) {
            removed = removed.concat([appId]);
            group.apps = group.apps.filter(app => app.appId !== appId);
            return true;
        }
    }

    QtObject {
        id: appWindow
        property bool activated: true
        property int activations: 0
        function activate() { activations++; }
    }
    NumberAnimation { id: magnifyAnimation; property: "dockMagnificationScale"; to: 1.8; duration: 240 }

    function init() {
        fakeDock.removed = [];
        fakeDock.group = null;
        fakeDock.dragStarts = 0;
        appWindow.activations = 0;
    }
    function settle(popup) { tryCompare(popup, "popupProgress", 1); }
    function group() {
        const popup = createTemporaryObject(groupComponent, testCase, {
            dockContent: fakeDock, groupId: "test",
            apps: [{appId:"a",toplevels:[]},{appId:"b",toplevels:[]},{appId:"c",toplevels:[]}]
        });
        verify(popup);
        fakeDock.group = popup;
        popup.open();
        settle(popup);
        return popup;
    }
    function findApp(item, id) {
        if (item.appData?.appId === id && typeof item.removeMember === "function")
            return item;
        for (let child of item.children ?? []) {
            const found = findApp(child, id);
            if (found)
                return found;
        }
        return null;
    }
    function test_closeAtFirstFrame() {
        const popup = createTemporaryObject(popupComponent, testCase);
        popup.open();
        popup.close();
        tryCompare(popup, "active", false);
        compare(popup.item, null);
        compare(popup.isClosing, false);
    }
    function test_reverseClosingPreservesLoader() {
        const popup = createTemporaryObject(popupComponent, testCase);
        popup.open();
        settle(popup);
        const item = popup.item;
        popup.close();
        wait(40);
        const p = popup.popupProgress;
        verify(p > 0 && p < 1);
        popup.open();
        compare(popup.item, item);
        compare(popup.popupProgress, p);
        settle(popup);
        popup.close();
        tryCompare(popup, "active", false);
        popup.open();
        verify(popup.item !== null);
        verify(popup.popupProgress < 1);
        settle(popup);
    }
    function test_direction_data() {
        return [{tag:"bottom",x:0,y:1},{tag:"top",x:0,y:-1},{tag:"left",x:-1,y:0},{tag:"right",x:1,y:0}];
    }
    function test_direction(data) {
        const popup = createTemporaryObject(popupComponent, testCase, {dockPos:data.tag});
        compare(popup.motionX, data.x);
        compare(popup.motionY, data.y);
    }
    function test_folderKeepsMembersAndOpenPopup() {
        const popup = group();
        const a = findApp(popup.item, "a");
        const b = findApp(popup.item, "b");
        const c = findApp(popup.item, "c");
        verify(a && b && c);
        popup.apps = [popup.apps[2], popup.apps[0], popup.apps[1]];
        compare(findApp(popup.item, "a"), a);
        compare(findApp(popup.item, "c"), c);
        b.removeMember();
        compare(fakeDock.removed.length, 0);
        verify(b.removing);
        tryCompare(fakeDock, "removed", ["b"]);
        verify(popup.active);
        compare(findApp(popup.item, "a"), a);
        compare(findApp(popup.item, "c"), c);
    }
    function test_folderDragCancelDoesNotRemoveOrLaunch() {
        const popup = group();
        const app = findApp(popup.item, "a");
        app.pressedAction({x:20,y:20});
        app.down = true;
        app.positionChangedAction({x:57.25,y:41.5});
        verify(app.dragActive);
        compare(app.dragX, 37.25);
        compare(app.dragY, 21.5);
        app.down = false;
        popup.pointerInsidePopup = true;
        app.releaseAction();
        compare(app.dragActive, false);
        verify(app.suppressClick);
        tryCompare(app, "dragX", 0);
        tryCompare(app, "dragY", 0);
        compare(fakeDock.removed.length, 0);
    }
    function test_folderReleaseOutsideCommitsOnce() {
        const popup = group();
        const app = findApp(popup.item, "a");
        app.pressedAction({x:20,y:20});
        app.down = true;
        app.positionChangedAction({x:180,y:100});
        app.down = false;
        popup.pointerInsidePopup = false;
        app.releaseAction();
        verify(app.removing);
        compare(fakeDock.removed.length, 0);
        tryCompare(fakeDock, "removed", ["a"]);
    }
    function test_closeWhileRemovingCompletesRequest() {
        const popup = group();
        const app = findApp(popup.item, "a");
        popup.close();
        wait(30);
        app.removeMember();
        tryCompare(popup, "active", false);
        compare(fakeDock.removed.length, 1);
        compare(fakeDock.removed[0], "a");
    }
    function findMember(item, id) {
        if (item.entryKey === id && item.entry !== undefined)
            return item;
        for (let child of item.children ?? []) {
            const found = findMember(child, id);
            if (found)
                return found;
        }
        return null;
    }
    function test_folderTileRetainsLeavingMember() {
        const tile = createTemporaryObject(tileComponent, testCase, {
            dockContent: fakeDock, groupId: "test",
            apps: [{appId:"a",toplevels:[]},{appId:"b",toplevels:[]},{appId:"c",toplevels:[]}]
        });
        verify(tile);
        wait(140);
        const a = findMember(tile, "a");
        const b = findMember(tile, "b");
        const c = findMember(tile, "c");
        verify(a && b && c);
        tile.apps = [tile.apps[0], tile.apps[2]];
        compare(findMember(tile, "b"), b);
        verify(b.leaving);
        compare(findMember(tile, "a"), a);
        wait(180);
        compare(findMember(tile, "b"), null);
        compare(findMember(tile, "c"), c);
        tryCompare(c, "x", tile.cellSize + tile.gridGap);
        tryCompare(c, "y", 0);
        const surface = tile.children.find(child => child.width === tile.buttonSize * 0.92);
        verify(surface);
        compare(surface.color, Appearance.colors.colLayer0);
    }
    function menuRows(item, result) {
        if (item.labelText !== undefined && item.popup !== undefined)
            result.push(item);
        for (let child of item.children ?? [])
            menuRows(child, result);
        return result;
    }
    function test_contextMenuRowsUseSharedClock() {
        const popup = createTemporaryObject(menuComponent, testCase);
        verify(popup);
        popup.open();
        wait(35);
        const rows = menuRows(popup.item, []);
        verify(rows.length > 1);
        for (const row of rows) {
            compare(row.popup, popup);
            verify(row.opacity < 1);
        }
        settle(popup);
        for (const row of rows)
            compare(row.opacity, 1);
    }
    function test_clickDuringMagnificationDoesNotStartDrag() {
        const app = createTemporaryObject(appComponent, testCase, {
            x: 180, y: 180, dockContent: fakeDock, delegateIndex: 0,
            dockMagnificationScale: 1,
            appToplevel: {appId: "browser", pinned: true, toplevels: [appWindow]}
        });
        verify(app);
        const cursor = app.mapToItem(testCase, app.width - 7, 10);
        mouseMove(testCase, cursor.x, cursor.y);
        mousePress(testCase, cursor.x, cursor.y);
        verify(app._pressed);
        const pressedScale = app.scale;
        magnifyAnimation.target = app;
        magnifyAnimation.start();
        for (let frame = 0; frame < 10; frame++) {
            wait(18);
            // Same physical pointer while the underlying hit area grows.
            mouseMove(testCase, cursor.x, cursor.y);
            compare(fakeDock.dragStarts, 0);
        }
        verify(app.scale > pressedScale);
        mouseRelease(testCase, cursor.x, cursor.y);
        compare(appWindow.activations, 1);
        compare(fakeDock.dragStarts, 0);
        tryCompare(app, "pressProgress", 0);
        tryCompare(app, "dockMagnificationScale", 1.8);
    }
}
