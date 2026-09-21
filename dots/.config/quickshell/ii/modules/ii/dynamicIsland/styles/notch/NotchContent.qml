pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.dynamicIsland.core
import qs.modules.ii.overview
import qs.modules.ii.wallpaperSelector
import qs.modules.ii.dynamicIsland.widgets
import qs.modules.ii.localSendPopup
import qs.modules.ii.colorPickerPopup
import qs.modules.ii.bluetoothConnectionPopup
import qs.services

/**
 * Draws whichever activity the notch is showing.
 *
 * Two things are deliberate here.
 *
 * The loader's `source` follows the *activity*, not the presentation: the legacy widgets
 * each render both states from an `isExpanded` property, and reloading them on expand
 * would restart their internal state - the album art state machine being the expensive
 * one. So expanding rebinds a property and never rebuilds anything.
 *
 * And the resting face is drawn here rather than loaded: a clock needs no file, and the
 * old panel's "home" widget was three lines of layout that cost a Loader.
 */
Item {
    id: content

    required property string activityId
    required property bool expanded
    required property var controller
    /** Side widgets of the resting face (media, AI), from the island. */
    property var sideIds: []
    /** The island's resting height; the resting face sizes itself from it. */
    property real restingHeight: 42
    /** The island body's colour, for faces that fade their own edges into it. */
    property color surfaceColor: Appearance.colors.colLayer0
    /** The width the resting face asks for: the clock and its side widgets. */
    readonly property real restingWidth: restingFace.targetWidth

    /**
     * What is on screen, which lags `activityId` by the length of the exit animation.
     *
     * The loader replaces its item the instant its source changes, so binding it
     * straight to `activityId` left nothing to animate out - the old content simply
     * blinked away. Holding it back for the exit gives the transition two halves: the
     * outgoing activity slides off and blurs, then the incoming one slides in.
     *
     * Plain state, never a binding. Declared as `displayedId: activityId` it changed on
     * its own the moment the activity did, so whether the transition ran at all depended
     * on whether the binding or the change handler was evaluated first - and the first
     * imperative assignment then broke the binding for good, freezing the content on
     * whatever happened to be showing.
     */
    property string displayedId: ""

    readonly property string sourcePath: IslandRegistry.legacyContentFor(content.displayedId)
    readonly property bool hasWidget: content.sourcePath !== ""

    /**
     * State the widgets reach for by walking up their parent chain.
     *
     * `FloatingNotchWifi` looks for `wifiSsid` and `FloatingNotchWorkspaces` publishes
     * itself into `workspaceWidgetRef`; the panel used to hold both. Declaring them here
     * keeps those walks working. They disappear when the activities get presentations
     * that take their data from the source directly, the way every new one does.
     */
    readonly property string wifiSsid: {
        const payload = content.controller.sources.wifi.payload;
        return (payload && payload.ssid) ? payload.ssid : "";
    }
    property var workspaceWidgetRef: null

    readonly property bool isSearch: content.displayedId === "search"
    readonly property bool isOsd: content.displayedId === "osd"
    readonly property bool isWallpaper: content.displayedId === "wallpaper"
    readonly property bool isSession: content.displayedId === "session"
    readonly property bool isColorPicker: content.displayedId === "colorPicker"
    /**
     * A device that just connected, drawn as the popup's tall card rather than the
     * island's old wide strip - the same card the floating popup shows.
     */
    readonly property bool isBluetoothCard: content.displayedId === "bluetooth"
        && GlobalStates.islandOwnsBluetoothCard
        && GlobalStates.floatingNotchBtDevice !== null
    /**
     * An incoming transfer, as opposed to files being sent.
     *
     * Receiving is a question - accept or reject - and the popup already asks it in a
     * tall, narrow card. The island's own LocalSend face is the wide drop target for
     * sending, which is a different job; this draws the popup's card instead.
     */
    readonly property bool isLocalSendRequest: content.displayedId === "localSend"
        && GlobalStates.islandOwnsLocalSendRequest
        && LocalSend.currentTransfer !== null
        // A drag still wants the drop target, even mid-transfer.
        && !content.controller.sources.localSend.dragHovering
    /** The dashboard is on, or on its way: it crossfades over the faces, see below. */
    readonly property bool isDashboard: content.activityId === "dashboard"

    property bool dashboardBuilt: false
    onIsDashboardChanged: {
        if (content.isDashboard)
            content.dashboardBuilt = true;
        // Kept alive while hidden, so leaving it has to leave it clean: out of edit
        // mode, back on the grid.
        else if (dashboardLoader.item)
            dashboardLoader.item.resetState();
    }
    Timer {
        interval: 4000
        running: !content.dashboardBuilt
        onTriggered: content.dashboardBuilt = true
    }

    /** Room the dashboard may take, from the island; it stops growing its grid there. */
    property real dashboardAvailableWidth: 1600
    property real dashboardAvailableHeight: 900
    /** The size the dashboard's grid asks for, unanimated; the island morphs to it. */
    readonly property real dashboardTargetWidth: dashboardLoader.item ? dashboardLoader.item.targetWidth : 0
    readonly property real dashboardTargetHeight: dashboardLoader.item ? dashboardLoader.item.targetHeight : 0
    /** Editing or an open page pins the dashboard open; see NotchIsland.dashboardPinned. */
    readonly property bool dashboardEditing: dashboardLoader.item ? dashboardLoader.item.holdOpen : false
    /** Only the grid editor, without an open page: the one hold a click away must not end. */
    readonly property bool dashboardGridEditing: dashboardLoader.item ? dashboardLoader.item.editMode : false
    /** A dashboard page may take text; the island hands it the keyboard. */
    readonly property bool dashboardWantsKeyboard: dashboardLoader.item ? dashboardLoader.item.wantsKeyboard : false

    /**
     * Open one of the dashboard's detail pages from outside the island.
     *
     * The dashboard is built lazily, so the request also builds it; an open page pins
     * the dashboard, which is what brings the island out with it.
     */
    /** Back from a detail page to the grid, so the page stops holding the island open. */
    function closeDashboardPage() {
        if (dashboardLoader.item)
            dashboardLoader.item.closePage();
    }

    function showDashboardPage(pageId) {
        content.dashboardBuilt = true;
        if (dashboardLoader.item) {
            dashboardLoader.item.showPage(pageId);
            return;
        }
        // Still incubating: ask again once it exists.
        pendingPage.pageId = pageId;
    }

    property QtObject pendingPage: QtObject {
        property string pageId: ""
    }

    Connections {
        target: dashboardLoader
        function onItemChanged() {
            if (!dashboardLoader.item || content.pendingPage.pageId === "")
                return;
            dashboardLoader.item.showPage(content.pendingPage.pageId);
            content.pendingPage.pageId = "";
        }
    }

    /**
     * The size search *wants*, read before anything eases it.
     *
     * The surface animates toward this and drives the widget's size in return, so the
     * two are never chasing each other; see SearchWidget.hostDrivesSize.
     */
    readonly property Item searchItem: searchLoader.item
    readonly property real searchTargetWidth: searchLoader.item ? searchLoader.item.contentTargetWidth : 0
    readonly property real searchTargetHeight: searchLoader.item ? searchLoader.item.contentTargetHeight : 0

    // ── The workspace overview, inside the island ────────────────────────────
    /**
     * The overview is part of the search face, not a panel hanging under it.
     *
     * It used to be drawn by the island's *window*, anchored below the island body -
     * managed by the island but visually a second surface with its own background and
     * shadow. Here it is inside the body: the island grows to hold the search field and
     * the grid together, and the grid draws straight onto the island's surface.
     */
    property bool overviewVisible: false
    property bool overviewBuilt: false
    /** 0..1, the island's own fade; the overview plays no entrance of its own. */
    property real overviewFade: 0
    property int overviewRows: 2
    property int overviewColumns: 3
    property real overviewScale: 0.15
    property var overviewPanelWindow: null
    property int overviewMonitorIndex: 0
    /** Gap between the search field and the grid below it. */
    readonly property real overviewGap: 8

    /** What the grid asks for; the island adds it to the search face's own size. */
    readonly property real overviewTargetWidth: overviewLoader.item ? overviewLoader.item.implicitWidth : 0
    readonly property real overviewTargetHeight: overviewLoader.item ? overviewLoader.item.implicitHeight : 0
    /** The room the grid takes out of the surface, gap included. */
    readonly property real overviewArea: (content.overviewVisible && content.overviewTargetHeight > 0)
        ? content.overviewTargetHeight + content.overviewGap : 0

    /**
     * The search field's own height, declared - never measured off the surface.
     *
     * Deriving it as `surface height - grid` looked equivalent and was not: the surface
     * height is animating, so the field grew from nothing to its full height while the
     * island opened and dragged the grid anchored under it down the screen. That travel
     * was a second animation on top of the island's own, which is what made the opening
     * feel like two separate motions.
     *
     * Pinned to what search asks for, the field and the grid are already in their final
     * places on the first frame; the island growing over them is the whole animation,
     * exactly as it is for search on its own.
     */
    readonly property real searchFaceHeight: content.searchTargetHeight > 0
        ? content.searchTargetHeight : 54

    /**
     * The size the wallpaper browser wants, declared rather than measured.
     *
     * Same contract as search: the island animates toward this and gives the browser its
     * live size in return, so neither is ever chasing the other.
     */
    readonly property real wallpaperTargetWidth: wallpaperLoader.item ? wallpaperLoader.item.contentTargetWidth : 0
    readonly property real wallpaperTargetHeight: wallpaperLoader.item ? wallpaperLoader.item.contentTargetHeight : 0

    /**
     * The size the OSD indicator wants.
     *
     * It declares its own `osdWidth`/`osdHeight` (380x72), and the registry's numbers
     * for the activity were neither - so the island sized itself to a pill and cut the
     * indicator off. Reading them from the indicator keeps the two from drifting apart
     * again.
     */
    readonly property real osdTargetWidth: (osdLoader.item && osdLoader.item.osdWidth > 0)
        ? osdLoader.item.osdWidth : 0
    readonly property real osdTargetHeight: (osdLoader.item && osdLoader.item.osdHeight > 0)
        ? osdLoader.item.osdHeight : 0

    /** Both popup cards measure themselves; the island animates to what they ask. */
    readonly property real bluetoothCardTargetWidth: bluetoothCardLoader.item ? bluetoothCardLoader.item.implicitWidth : 0
    readonly property real bluetoothCardTargetHeight: bluetoothCardLoader.item ? bluetoothCardLoader.item.implicitHeight : 0
    readonly property real colorPickerTargetWidth: colorPickerLoader.item ? colorPickerLoader.item.implicitWidth : 0
    readonly property real colorPickerTargetHeight: colorPickerLoader.item ? colorPickerLoader.item.implicitHeight : 0
    readonly property real localSendRequestTargetWidth: localSendRequestLoader.item ? localSendRequestLoader.item.implicitWidth : 0
    readonly property real localSendRequestTargetHeight: localSendRequestLoader.item ? localSendRequestLoader.item.implicitHeight : 0

    /** The size the session menu wants; declared, like search's. */
    readonly property real sessionTargetWidth: sessionLoader.item ? sessionLoader.item.contentTargetWidth : 0
    readonly property real sessionTargetHeight: sessionLoader.item ? sessionLoader.item.contentTargetHeight : 0

    function focusSearch() {
        if (searchLoader.item)
            searchLoader.item.focusSearchInput();
    }

    function cancelSearch() {
        if (searchLoader.item)
            searchLoader.item.cancelSearch();
    }

    /**
     * Changing what the island shows is a dissolve, not a cut and not a slide.
     *
     * Into and out of the dashboard it is a true crossfade: the faces and the dashboard
     * live in separate layers on one clock (`dashboardReveal`), so from the first frame
     * the face fades and blurs out while the dashboard fades and sharpens in, and for
     * the middle of the transition both are on screen. A fade that emptied one before
     * starting the other read as a blink, however short.
     *
     * Between two faces (one loader, so one at a time) the outgoing face dims and blurs,
     * the swap happens while it is dim, and the incoming one sharpens back in.
     *
     * Media is exempt from the blur. Its face *is* an album cover, and blurring a
     * photograph on every track change looks like a rendering fault rather than motion.
     */
    property real morphOpacity: 1.0
    property real morphBlur: 0.0
    /** How far a face dims before the swap; the rest of the change is the blur. */
    readonly property real morphFloor: 0.15

    /** 0 = the faces, 1 = the dashboard; one clock for both halves of the crossfade. */
    property real dashboardReveal: content.isDashboard ? 1 : 0
    Behavior on dashboardReveal {
        NumberAnimation {
            duration: Math.round(320 * Appearance.animMultiplier)
            easing.type: Easing.InOutQuad
        }
    }

    /**
     * Media keeps its cover sharp; see above. Search is exempt for the same reason: a
     * field the user is about to type into must not arrive out of focus, and the surface
     * behind it is travelling far enough that the blur added nothing but cost.
     */
    readonly property var sharpFaces: ["media", "search", "dashboard", "wallpaper", "session", "colorPicker"]
    readonly property bool blurAllowed: content.sharpFaces.indexOf(content.activityId) === -1
        && content.sharpFaces.indexOf(content.displayedId) === -1

    function beginMorph() {
        // The dashboard crossfades over whatever face is showing, which stays put
        // underneath it; nothing to swap.
        if (content.activityId === "dashboard" || content.activityId === content.displayedId)
            return;
        // Straight to it on the first paint, and whenever the dashboard covers the
        // faces: the change happens unseen and the crossfade back reveals it.
        if (content.displayedId === "" || content.dashboardReveal > 0.5) {
            morph.stop();
            content.morphOpacity = 1.0;
            content.morphBlur = 0.0;
            content.displayedId = content.activityId;
            return;
        }
        morph.restart();
    }

    onActivityIdChanged: content.beginMorph()
    Component.onCompleted: content.beginMorph()

    SequentialAnimation {
        id: morph
        running: false

        // Out: dim and blur.
        ParallelAnimation {
            NumberAnimation {
                target: content
                property: "morphOpacity"
                to: content.morphFloor
                duration: Math.round(120 * Appearance.animMultiplier)
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: content
                property: "morphBlur"
                to: content.blurAllowed ? 1.0 : 0.0
                duration: Math.round(120 * Appearance.animMultiplier)
                easing.type: Easing.InQuad
            }
        }

        // The swap happens while the face is dim. A script rather than a
        // PropertyAction, so the value is read when the action runs.
        ScriptAction {
            script: content.displayedId = content.activityId
        }

        // In: sharpen and brighten.
        ParallelAnimation {
            NumberAnimation {
                target: content
                property: "morphOpacity"
                to: 1.0
                duration: Math.round(220 * Appearance.animMultiplier)
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: content
                property: "morphBlur"
                to: 0.0
                duration: Math.round(240 * Appearance.animMultiplier)
                easing.type: Easing.OutCubic
            }
        }

        // An activity that arrived mid-transition is picked up here, so the island
        // always lands on the current one instead of the one it started toward.
        onFinished: content.beginMorph()
    }

    // ── The faces ────────────────────────────────────────────────────────────
    // Everything but the dashboard, in one layer: it dims and blurs as a whole, both
    // for a swap between faces and under the dashboard's crossfade.
    // It follows the island's live size throughout, crossfade included: held at its
    // pre-expansion size it stood still while the island grew, and snapped to the
    // island's size when the crossfade ended before the island had finished shrinking.
    Item {
        id: faces
        anchors.fill: parent
        readonly property real blur: Math.max(content.morphBlur, content.dashboardReveal)
        opacity: content.morphOpacity * (1 - content.dashboardReveal)
        visible: faces.opacity > 0.001

        // The layer only exists while the blur is on screen: an always-on layer would
        // cost a full offscreen pass for an island that is mostly still.
        layer.enabled: faces.blur > 0.001
        layer.smooth: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 24
            blur: faces.blur
        }

        Loader {
            id: widgetLoader

            anchors.centerIn: parent
            width: parent.width
            height: parent.height

            active: content.hasWidget && !content.isSearch && !content.isOsd && !content.isWallpaper
                && !content.isSession && !content.isColorPicker && !content.isLocalSendRequest
                && !content.isBluetoothCard
            source: content.sourcePath

            // Rebinding rather than reloading; see above.
            Binding {
                target: widgetLoader.item && widgetLoader.item.hasOwnProperty("isExpanded") ? widgetLoader.item : null
                property: "isExpanded"
                value: content.expanded
            }

            // Some widgets lay themselves out differently when they are one of several.
            // With a single slot there is always exactly one.
            Binding {
                target: widgetLoader.item && widgetLoader.item.hasOwnProperty("panelWidgetsCount") ? widgetLoader.item : null
                property: "panelWidgetsCount"
                value: 1
            }

            Binding {
                target: widgetLoader.item && widgetLoader.item.hasOwnProperty("isDragOverNotch") ? widgetLoader.item : null
                property: "isDragOverNotch"
                value: content.controller.sources.localSend.dragHovering
            }

            // LocalSend's drop state lives in its source; the widget is handed it.
            Binding {
                target: widgetLoader.item && widgetLoader.item.hasOwnProperty("serviceChoice") ? widgetLoader.item : null
                property: "serviceChoice"
                value: content.controller.sources.localSend.serviceChoice
            }
            Binding {
                target: widgetLoader.item && widgetLoader.item.hasOwnProperty("queueFiles") ? widgetLoader.item : null
                property: "queueFiles"
                value: content.controller.sources.localSend.queueFiles
            }
            Binding {
                target: widgetLoader.item && widgetLoader.item.hasOwnProperty("leftHover") ? widgetLoader.item : null
                property: "leftHover"
                value: content.controller.sources.localSend.dragHovering && !content.controller.sources.localSend.dragOnRight
            }
            Binding {
                target: widgetLoader.item && widgetLoader.item.hasOwnProperty("rightHover") ? widgetLoader.item : null
                property: "rightHover"
                value: content.controller.sources.localSend.dragHovering && content.controller.sources.localSend.dragOnRight
            }
            // ...and when the widget ends a choice itself (KDE Connect's send completing),
            // the source hears of it.
            Connections {
                target: widgetLoader.item && widgetLoader.item.hasOwnProperty("serviceChoice") ? widgetLoader.item : null
                ignoreUnknownSignals: true
                function onServiceChoiceChanged() {
                    if (widgetLoader.item.serviceChoice === 0)
                        content.controller.sources.localSend.serviceChoice = 0;
                }
            }

            opacity: 0
            scale: 0.96
            onLoaded: {
                widgetLoader.opacity = 1;
                widgetLoader.scale = 1;
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(widgetLoader)
            }
            Behavior on scale {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveSmall.duration
                    easing.type: Easing.OutBack
                    easing.overshoot: 0.5
                }
            }
        }

        // ── Search ───────────────────────────────────────────────────────────────
        // Kept loaded across a close so the query and the result list survive being
        // dismissed and reopened, which is what the launcher has always done.
        Loader {
            id: searchLoader
            // Fills the surface rather than sizing it: the island is already animating to
            // the size search asked for, and a loader that measured its own item put a
            // second, unanimated size in the middle of that travel.
            // Its own declared height when the grid is under it, so neither moves while
            // the island grows; the whole surface otherwise.
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: content.overviewArea > 0 ? content.searchFaceHeight : parent.height

            active: Config.ready
            visible: content.isSearch
            opacity: content.isSearch ? 1 : 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(searchLoader)
            }

            sourceComponent: SearchWidget {
                inNotchMode: true
                hostWidth: searchLoader.width
                hostHeight: searchLoader.height
            }

            /**
             * A query handed over by another surface (a keybind, the bar) opens with
             * that text already in place instead of an empty field.
             *
             * Taken the moment search becomes the activity, not when its face becomes
             * visible. That is one face swap later, and for that long the island was
             * growing toward an empty search field; the clipboard shortcut's prefix
             * then arrived, the panel was built in the middle of the movement - the
             * freeze - and the island set off again for a second, larger size. Taken at
             * once, the panel is built before anything moves and the island grows once.
             */
            function takeQuery() {
                if (!searchLoader.item)
                    return;
                if (GlobalStates.activeSearchQuery) {
                    searchLoader.item.setSearchingText(GlobalStates.activeSearchQuery);
                    GlobalStates.activeSearchQuery = "";
                } else {
                    searchLoader.item.cancelSearch();
                }
            }

            property bool queryTaken: false
            readonly property bool wanted: content.activityId === "search"
            onWantedChanged: {
                searchLoader.queryTaken = searchLoader.wanted && searchLoader.item !== null;
                if (searchLoader.queryTaken)
                    searchLoader.takeQuery();
            }

            onVisibleChanged: {
                if (!searchLoader.visible || !searchLoader.item)
                    return;
                // Shown without having been the activity first (the first paint).
                if (!searchLoader.queryTaken)
                    searchLoader.takeQuery();
                Qt.callLater(() => searchLoader.item.focusSearchInput());
            }
        }

        // ── The workspace overview, under the search field ───────────────────────
        Loader {
            id: overviewLoader
            // Built off the UI thread: the workspace grid (a tile and a screen copy per
            // window) is the heaviest thing search opens, and building it synchronously
            // stalled the island's morph for its first frames.
            asynchronous: true
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: content.searchFaceHeight + content.overviewGap
            /**
             * Built once and kept, like the dashboard. Tied to `isSearch` it was
             * destroyed on every close and rebuilt asynchronously on the next open, so
             * the island sized itself to the search field first and jumped again when
             * the grid arrived a few frames later.
             */
            active: content.overviewBuilt
            visible: opacity > 0.01
            opacity: content.overviewFade

            sourceComponent: OverviewWidget {
                hosted: true
                panelWindow: content.overviewPanelWindow
                monitorIndex: content.overviewMonitorIndex
                gridRows: content.overviewRows
                gridColumns: content.overviewColumns
                fixedScale: content.overviewScale
                suppressEntrance: true
            }
        }

        // ── A picked colour, and an incoming transfer ────────────────────────────
        // Both are the popups' own cards, hosted: the island is the surface, so their
        // background, border, shadow and elevation margin come off and what is left is
        // the layout the user already knows.
        Loader {
            id: bluetoothCardLoader
            anchors.centerIn: parent
            active: content.isBluetoothCard
            visible: content.isBluetoothCard
            opacity: content.isBluetoothCard ? 1 : 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(bluetoothCardLoader)
            }

            sourceComponent: BluetoothConnectionPopupContent {
                hosted: true
                device: GlobalStates.floatingNotchBtDevice
                onDisconnectRequested: {
                    if (GlobalStates.floatingNotchBtDevice) {
                        GlobalStates.floatingNotchBtDevice.connecting = false;
                        GlobalStates.floatingNotchBtDevice.connected = false;
                    }
                    content.controller.sources.bluetooth.dismiss();
                }
                onDismissed: content.controller.sources.bluetooth.dismiss()
            }
        }

        Loader {
            id: colorPickerLoader
            anchors.centerIn: parent
            active: content.isColorPicker || content.activityId === "colorPicker"
            visible: content.isColorPicker
            opacity: content.isColorPicker ? 1 : 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(colorPickerLoader)
            }

            sourceComponent: ColorPickerPopupContent {
                hosted: true
                onDismissed: GlobalStates.colorPickerPopupOpen = false
            }
        }

        Loader {
            id: localSendRequestLoader
            anchors.centerIn: parent
            active: content.isLocalSendRequest
            visible: content.isLocalSendRequest
            opacity: content.isLocalSendRequest ? 1 : 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(localSendRequestLoader)
            }

            sourceComponent: LocalSendPopupContent {
                hosted: true
                transfer: LocalSend.currentTransfer
                onAcceptRequested: LocalSend.acceptTransfer()
                onRejectRequested: LocalSend.denyTransfer()
            }
        }

        // ── Session menu ─────────────────────────────────────────────────────────
        // Unloaded when closed: eight buttons are cheap to build, and holding the
        // keyboard focus chain of a menu nobody is looking at only invites trouble.
        Loader {
            id: sessionLoader
            anchors.fill: parent

            active: content.isSession || content.activityId === "session"
            visible: content.isSession
            opacity: content.isSession ? 1 : 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(sessionLoader)
            }

            sourceComponent: IslandSessionMenu {
                active: content.isSession
                onCloseRequested: GlobalStates.sessionOpen = false
            }

            onVisibleChanged: {
                if (sessionLoader.visible && sessionLoader.item)
                    Qt.callLater(() => sessionLoader.item.forceActiveFocus());
            }
        }

        // ── Wallpapers ───────────────────────────────────────────────────────────
        /**
         * The wallpaper picker, as one row inside the island.
         *
         * It is the same WallpaperSelectorContent the full-screen selector draws, in its
         * compact layout: sidebar off, the folder path on top, one row of four
         * wallpapers with a fade at each end, and the toolbars in a row beneath. Reusing
         * it rather than writing a second browser is what keeps the thumbnails, the
         * colour filter, sorting, favourites and the online search working here without
         * a line of their own.
         *
         * Unloaded when closed, unlike search: a directory of thumbnails is far too much
         * to hold for a surface the user may not open again this session, and the browser
         * restores its own directory and query from Wallpapers when it comes back.
         */
        Loader {
            id: wallpaperLoader
            anchors.fill: parent

            active: content.isWallpaper || content.activityId === "wallpaper"
            visible: content.isWallpaper
            opacity: content.isWallpaper ? 1 : 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(wallpaperLoader)
            }

            sourceComponent: WallpaperSelectorContent {
                compact: true
                surfaceColor: content.surfaceColor
                // The island's crossfade is the open animation; this only says whether
                // the contents should have made their entrance.
                active: content.isWallpaper || content.activityId === "wallpaper"
                onCloseRequested: GlobalStates.wallpaperSelectorOpen = false
            }
        }

        // ── OSD ──────────────────────────────────────────────────────────────────
        Loader {
            id: osdLoader
            anchors.fill: parent
            active: content.isOsd
            source: {
                if (!content.isOsd)
                    return "";
                const indicators = {
                    "volume": "VolumeIndicator.qml",
                    "brightness": "BrightnessIndicator.qml",
                    "playerVolume": "PlayerVolumeIndicator.qml",
                    "gamma": "GammaIndicator.qml",
                    "keyboardBrightness": "KeyboardBrightnessIndicator.qml"
                };
                const file = indicators[GlobalStates.osdCurrentIndicator];
                if (!file)
                    return "";
                return Quickshell.shellPath("modules/ii/topLayer/osd/indicators/" + file);
            }
        }

        // The resting face: the clock, with the side widgets beside it.
        NotchRestingFace {
            id: restingFace
            anchors.fill: parent
            sideIds: content.sideIds
            restHeight: content.restingHeight
            visible: !content.hasWidget && !content.isSearch && !content.isOsd && !content.isWallpaper
                && !content.isSession && !content.isColorPicker && !content.isLocalSendRequest
                && !content.isBluetoothCard
        }
    }

    // ── Dashboard ────────────────────────────────────────────────────────────
    Loader {
        id: dashboardLoader
        anchors.fill: parent
        /**
         * Built once and kept, like the overview grid. Building the quick-toggle grid
         * when the island decided to expand took a good part of the expansion itself,
         * so the dashboard arrived as the island finished growing; it is also built in
         * the background shortly after start, so the first expand is as quick.
         */
        active: content.dashboardBuilt || content.isDashboard
        asynchronous: !content.isDashboard
        // The other half of the crossfade: it arrives soft and sharpens as the faces go.
        opacity: content.dashboardReveal
        visible: content.dashboardReveal > 0.001
        layer.enabled: content.dashboardReveal > 0.001 && content.dashboardReveal < 0.999
        layer.smooth: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 24
            blur: 1 - content.dashboardReveal
        }
        source: Quickshell.shellPath("modules/ii/dynamicIsland/dashboard/IslandDashboard.qml")

        Binding {
            target: dashboardLoader.item
            property: "availableWidth"
            value: content.dashboardAvailableWidth
            when: dashboardLoader.item !== null
        }
        Binding {
            target: dashboardLoader.item
            property: "availableHeight"
            value: content.dashboardAvailableHeight
            when: dashboardLoader.item !== null
        }
    }
}
