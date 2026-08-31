import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.editMode

/**
 * One screen's worth of Edit Mode's chrome: a full-screen layer surface that is
 * transparent everywhere except the toolbar on it.
 *
 * Why not on the background surface: the desktop stays where it is - the
 * wallpaper and the widget canvas are already there - but those surfaces are
 * on the Background and Bottom layers, under the bar and the dock, which stay
 * in place at full size. Chrome drawn there would sit under the bar. So the
 * chrome takes a surface of its own on Overlay, and the desktop does not move.
 *
 * Three things a surface this size has to get right:
 *
 * Input. A screen-sized surface that accepts input everywhere makes the
 * desktop underneath unclickable - and the desktop underneath is the thing
 * being edited. The mask is the toolbar and nothing else.
 *
 * Blur. rules.lua's catch-all blurs every `quickshell:*` surface with a low
 * alpha threshold, under which a screen of transparent pixels asks the
 * compositor to blur the whole screen. The namespace is minted AND listed there
 * at `ignore_alpha = 1`, so only the toolbar's opaque body is blurred.
 *
 * Keyboard. None, deliberately: Escape and the arrows are answered by the
 * WidgetCanvas on the widgets surface, and a chrome surface taking OnDemand
 * focus would sit in front of it and swallow the keys.
 */
PanelWindow {
    id: root

    // Whether something is summoned over the desktop this chrome frames - a
    // special workspace, today. Under it the chrome drops to the desktop's own
    // layer, so the compositor blurs and dims both halves of the mode together
    // instead of painting the toolbar over the window.
    property bool underneath: false

    color: "transparent"
    WlrLayershell.namespace: "quickshell:editMode"
    WlrLayershell.layer: root.underneath ? WlrLayer.Bottom : WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0

    // All four edges and no margins, so this window's coordinate space is the
    // screen's. On a layer surface position IS margins, so a toolbar animating
    // into place through them would reconfigure the surface every frame; the
    // chrome moves inside the surface instead.
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    readonly property string screenName: root.screen ? root.screen.name : ""
    // The same pure function, on the same inputs, that the two desktop
    // surfaces build their transform out of - re-derived rather than published
    // across the window boundary, because every input is available here.
    readonly property var viewport: EditModeInsets.viewportFor(root.screenName, root.width, root.height)
    readonly property real progress: GlobalStates.editProgress
    readonly property real editShift: EditModeLogic.drawerTravel(root.viewport) * GlobalStates.editDrawerProgress
    readonly property var cardGeometry: EditModeLogic.cardRect(root.viewport, root.progress, root.width, root.height, root.editShift)
    readonly property var drawerGeometry: EditModeLogic.drawerRect(root.viewport, root.progress, GlobalStates.editDrawerProgress, root.width, root.height)
    readonly property var areaGeometry: EditModeLogic.areaRect(root.viewport, root.progress, root.width, root.height)

    // Whether the one widget menu belongs to this screen.
    readonly property bool menuOpenHere: GlobalStates.editWidgetMenuOpen && GlobalStates.editWidgetMenuScreenName === root.screenName
    readonly property bool barMenuOpenHere: GlobalStates.editBarMenuOpen && GlobalStates.editBarMenuScreenName === root.screenName

    readonly property bool barHoverHere: GlobalStates.editBarHoverShown && GlobalStates.editBarHoverScreenName === root.screenName

    // A point in the bar window's coordinates, in this surface's. The bar sits
    // flush with one screen edge, so the far edges translate by the window's
    // own size.
    function fromBarWindow(x, y, windowWidth, windowHeight) {
        const side = EditModeInsets.barSide;
        if (side === "bottom")
            return Qt.point(x, y + root.height - windowHeight);
        if (side === "right")
            return Qt.point(x + root.width - windowWidth, y);
        return Qt.point(x, y);
    }

    function barMenuPoint() {
        const from = root.fromBarWindow(GlobalStates.editBarMenuX, GlobalStates.editBarMenuY,
            GlobalStates.editBarMenuWindowWidth, GlobalStates.editBarMenuWindowHeight);
        let x = from.x;
        let y = from.y;
        const side = EditModeInsets.barSide;
        // Off the bar's body, so the card never covers the widgets it is about.
        const clear = EditModeInsets.barThickness + 4;
        if (side === "top")
            y = Math.max(y, clear);
        else if (side === "bottom")
            y = Math.min(y, root.height - clear) - 80;
        else if (side === "left")
            x = Math.max(x, clear);
        else
            x = Math.min(x, root.width - clear) - 200;
        return Qt.point(x, y);
    }

    // The toolbar, plus - while a menu is open - the whole screen: a click
    // anywhere that is not the menu dismisses it before it reaches the desktop.
    // The closer's region is zero-sized when there is no menu, so the desktop
    // gets every other click.
    mask: Region {
        item: chrome.toolbarItem
        Region {
            item: menuCloser
        }
        // A closed drawer is a zero-width item and contributes nothing.
        Region {
            item: chrome.drawerItem
        }
    }

    // The drawer's reveal, handed to the surface that owns the desktop: a
    // widget dragged back into the drawer is removed, and the widget deciding
    // that is on another layer surface. Removed with the surface, so the map
    // always reads "the screens whose drawer exists".
    readonly property rect drawerReveal: chrome.drawer
    onDrawerRevealChanged: root.publishDrawerReveal(root.drawerReveal)
    Component.onCompleted: root.publishDrawerReveal(root.drawerReveal)
    Component.onDestruction: root.publishDrawerReveal(null)
    function publishDrawerReveal(reveal) {
        if (root.screenName === "")
            return;
        const published = Object.assign({}, GlobalStates.editDrawerReveals);
        if (reveal === null)
            delete published[root.screenName];
        else
            published[root.screenName] = { "x": reveal.x, "y": reveal.y, "width": reveal.width, "height": reveal.height };
        GlobalStates.editDrawerReveals = published;
    }

    // A desktop widget let go over the drawer leaves the desktop. Answered
    // here and not on the widget: every store the mode writes is written from
    // the chrome, and there is one chrome (decision D4), so one answer.
    Connections {
        target: GlobalStates
        function onEditWidgetDroppedOnDrawer(instanceId) {
            const entry = (Config.options.background.activeWidgets ?? []).find(e => e && e.id === instanceId);
            if (entry)
                Config.removeWidgetFromDesktop(entry.widgetId);
        }
    }

    // A drawer row dropped on the card: the screen point becomes a canvas
    // point through the inverse of the desktop's transform, snapped to the
    // canvas's grid and kept inside it. A release back over the drawer, or
    // outside the card, is the gesture being abandoned.
    function addWidgetAt(widgetId, dropX, dropY) {
        if (EditModeLogic.pointInDrawerReveal(chrome.drawer, dropX, dropY))
            return;
        const card = root.cardGeometry;
        if (dropX < card.x || dropX > card.x + card.width || dropY < card.y || dropY > card.y + card.height)
            return;
        const p = EditModeLogic.canvasPointFromScreen(root.viewport, root.progress, root.editShift, dropX, dropY);
        const placed = EditModeLogic.dropPosition({
            "gridSize": 10,
            "canvasX": p.x,
            "canvasY": p.y,
            "screenWidth": root.width,
            "screenHeight": root.height
        });
        Config.addWidgetToDesktop(widgetId, placed.x, placed.y, root.screenName, GlobalStates.editLockPreview ? "lockOnly" : "hide");
    }

    // On the Lockscreen tab a widget already on the desktop is shown or hidden
    // there (lock behaviour hide <-> keep); one that is not becomes a
    // lock-only instance, absent from the desktop.
    function toggleWidget(widgetId) {
        const entry = (Config.options.background.activeWidgets ?? []).find(e => e && e.widgetId === widgetId) ?? null;
        if (GlobalStates.editLockPreview) {
            if (entry === null) {
                Config.addWidgetToDesktop(widgetId, undefined, undefined, root.screenName, "lockOnly");
                return;
            }
            const behavior = entry.lockBehavior || "hide";
            if (behavior === "lockOnly")
                Config.removeWidgetFromDesktop(widgetId);
            else
                Config.updateWidgetLockBehavior(entry.id, behavior === "hide" ? "keep" : "hide");
            return;
        }
        if (entry !== null)
            Config.removeWidgetFromDesktop(widgetId);
        else
            Config.addWidgetToDesktop(widgetId, undefined, undefined, root.screenName);
    }

    // The bar's layout is not history-aware on its own; the pair is recorded
    // here around the one write.
    function addBarComponent(componentId, bucket) {
        const layouts = Config.options.bar.layouts;
        if (!layouts || !(bucket in layouts))
            return;
        const before = EditModeLogic.listCopy(layouts[bucket] ?? []);
        if (before.some(e => e && e.id === componentId))
            return;
        const after = before.concat([{ "id": componentId, "centered": false, "visible": true }]);
        layouts[bucket] = after;
        GlobalStates.editHistoryPush({
            "undo": () => { Config.options.bar.layouts[bucket] = before; },
            "redo": () => { Config.options.bar.layouts[bucket] = after; }
        });
    }

    function toggleDockPin(appId) {
        const before = EditModeLogic.listCopy(Config.options.dock.pinnedApps ?? []);
        TaskbarApps.togglePin(appId);
        const after = EditModeLogic.listCopy(Config.options.dock.pinnedApps ?? []);
        GlobalStates.editHistoryPush({
            "undo": () => { Config.options.dock.pinnedApps = before; },
            "redo": () => { Config.options.dock.pinnedApps = after; }
        });
    }

    Item {
        id: menuCloser
        width: (root.menuOpenHere || root.barMenuOpenHere) ? root.width : 0
        height: (root.menuOpenHere || root.barMenuOpenHere) ? root.height : 0
    }

    // The hovered widget's name, off the bar's body on whichever edge it sits.
    // Drawn here rather than in the bar because the toolbar covers the strip
    // just past the bar, and this has to sit on top of it.
    Loader {
        anchors.fill: parent
        active: root.barHoverHere
        z: 11
        // Wrapped in a filling Item: a Loader with a size resizes whatever it
        // loads to match, and a chip that has been stretched over the whole
        // screen is not obviously a chip.
        sourceComponent: Item {
            Rectangle {
                readonly property real clear: EditModeInsets.barThickness + 6
                readonly property string side: EditModeInsets.barSide
                readonly property point at: root.fromBarWindow(GlobalStates.editBarHoverX, GlobalStates.editBarHoverY,
                    GlobalStates.editBarHoverWindowWidth, GlobalStates.editBarHoverWindowHeight)

                width: hoverLabel.implicitWidth + 20
                height: 26
                radius: Appearance.rounding.full
                color: Appearance.colors.colSecondaryContainer

                x: {
                    const wanted = side === "left" ? clear
                        : side === "right" ? root.width - clear - width
                        : at.x - width / 2;
                    return Math.min(Math.max(wanted, 8), root.width - width - 8);
                }
                y: {
                    const wanted = side === "bottom" ? root.height - clear - height
                        : side === "top" ? clear
                        : at.y - height / 2;
                    return Math.min(Math.max(wanted, 8), root.height - height - 8);
                }

                StyledText {
                    id: hoverLabel
                    anchors.centerIn: parent
                    text: GlobalStates.editBarHoverName
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSecondaryContainer
                }

                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.barMenuOpenHere
        z: 10
        sourceComponent: Item {
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: GlobalStates.closeEditBarMenu()
            }
            EditBarMenu {
                id: barMenuCard
                readonly property point at: root.barMenuPoint()
                x: Math.min(Math.max(at.x, 8), root.width - width - 8)
                y: Math.min(Math.max(at.y, 8), root.height - height - 8)
                controller: GlobalStates.editBarMenuController
                bucket: GlobalStates.editBarMenuBucket
                index: GlobalStates.editBarMenuIndex
                centered: GlobalStates.editBarMenuCentered
                onDismissRequested: GlobalStates.closeEditBarMenu()
                transformOrigin: Item.TopLeft
                scale: 0.85
                opacity: 0
                Component.onCompleted: {
                    scale = 1;
                    opacity = 1;
                }
                Behavior on scale {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(barMenuCard)
                }
                Behavior on opacity {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(barMenuCard)
                }
            }
        }
    }

    Loader {
        id: menuLoader
        anchors.fill: parent
        active: root.menuOpenHere
        z: 10
        sourceComponent: Item {
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: GlobalStates.closeEditWidgetMenu()
            }
            EditWidgetMenu {
                id: menuCard
                x: Math.min(Math.max(GlobalStates.editWidgetMenuX, 8), root.width - width - 8)
                y: Math.min(Math.max(GlobalStates.editWidgetMenuY, 8), root.height - height - 8)
                canvas: GlobalStates.editWidgetMenuCanvas
                instanceId: GlobalStates.editWidgetMenuInstanceId
                onDismissRequested: GlobalStates.closeEditWidgetMenu()
                // From the corner the pointer is at: the card belongs to a point.
                transformOrigin: Item.TopLeft
                scale: 0.85
                opacity: 0
                Component.onCompleted: {
                    scale = 1.0;
                    opacity = 1.0;
                }
                Behavior on scale {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(menuCard)
                }
                Behavior on opacity {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(menuCard)
                }
            }
        }
    }

    EditModeChromeContent {
        id: chrome
        anchors.fill: parent
        card: Qt.rect(root.cardGeometry.x, root.cardGeometry.y, root.cardGeometry.width, root.cardGeometry.height)
        area: Qt.rect(root.areaGeometry.x, root.areaGeometry.y, root.areaGeometry.width, root.areaGeometry.height)
        bandFraction: EditModeLogic.chromeBandFraction(root.viewport)
        // The second stand-down gate, the loader that creates this window
        // being the first. Either alone hides the chrome; both are kept so a
        // lost gate is not a lost chrome.
        opacity: Math.max(0, Math.min(1, root.progress))

        drawer: Qt.rect(root.drawerGeometry.x, root.drawerGeometry.y, root.drawerGeometry.width, root.drawerGeometry.height)
        drawerScreenName: root.screenName

        onDoneRequested: GlobalStates.editMode = false
        onUndoRequested: GlobalStates.editUndo()
        onRedoRequested: GlobalStates.editRedo()
        onTabRequested: tab => {
            GlobalStates.editWidgetMenuOpen = false;
            GlobalStates.editTab = tab;
        }
        onDrawerLockLayoutResetRequested: Config.clearWidgetLockPositions(root.screenName)
        onDrawerToggleRequested: GlobalStates.editDrawerOpen = !GlobalStates.editDrawerOpen
        onDrawerAddRequested: (widgetId, dropX, dropY) => root.addWidgetAt(widgetId, dropX, dropY)
        onDrawerToggleWidgetRequested: widgetId => root.toggleWidget(widgetId)
        onDrawerBarAddRequested: (componentId, bucket) => root.addBarComponent(componentId, bucket)
        onDrawerDockToggleRequested: appId => root.toggleDockPin(appId)
        // A preference, not a layout edit: no history entry, same as the
        // Settings toggle that writes the same key.
        onSnapToggleRequested: Config.options.background.widgets.enableSnap = !Config.options.background.widgets.enableSnap
    }
}
