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
import "../../core/IslandLayout.js" as IslandLayout

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
    readonly property bool isDashboard: content.displayedId === "dashboard"

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
    /** A dashboard page may take text; the island hands it the keyboard. */
    readonly property bool dashboardWantsKeyboard: dashboardLoader.item ? dashboardLoader.item.wantsKeyboard : false

    /**
     * The size search *wants*, read before anything eases it.
     *
     * The surface animates toward this and drives the widget's size in return, so the
     * two are never chasing each other; see SearchWidget.hostDrivesSize.
     */
    readonly property Item searchItem: searchLoader.item
    readonly property real searchTargetWidth: searchLoader.item ? searchLoader.item.contentTargetWidth : 0
    readonly property real searchTargetHeight: searchLoader.item ? searchLoader.item.contentTargetHeight : 0

    function focusSearch() {
        if (searchLoader.item)
            searchLoader.item.focusSearchInput();
    }

    function cancelSearch() {
        if (searchLoader.item)
            searchLoader.item.cancelSearch();
    }

    /**
     * Changing activity is a morph, not a cut.
     *
     * A short horizontal slide with a blur, in two halves: the outgoing activity leaves
     * and blurs out, the incoming one arrives from the other side and sharpens. The
     * direction carries meaning - something more important arriving comes in from the
     * right, and falling back to what was there before comes back from the left, so the
     * island reads as moving forward and then returning rather than shuffling at random.
     *
     * Media is exempt from the blur. Its face *is* an album cover, and blurring a
     * photograph on every track change looks like a rendering fault rather than motion.
     * It still slides.
     */
    property real morphOffset: 0
    property real morphOpacity: 1.0
    property real morphBlur: 0.0

    /**
     * The swap is motion first: the outgoing face travels a good distance and only
     * dims, the incoming one comes from further still and settles with a bounce. A
     * face that fades out entirely before the next one starts read as a blink, most of
     * all on the way into the dashboard.
     */
    readonly property real morphDistance: 36
    /** How far the faces dim at the swap; the rest of the change is the slide. */
    readonly property real morphFloor: 0.3
    /**
     * The out half is short when the dashboard is involved: it is the face the island
     * is growing into, and it should be on screen early in the growth, not at its end.
     */
    property int outDuration: 110
    /**
     * Media keeps its cover sharp; see above. Search is exempt for the same reason: a
     * field the user is about to type into must not arrive out of focus, and the surface
     * behind it is travelling far enough that the blur added nothing but cost.
     */
    readonly property var sharpFaces: ["media", "search", "dashboard"]
    readonly property bool blurAllowed: content.sharpFaces.indexOf(content.activityId) === -1
        && content.sharpFaces.indexOf(content.displayedId) === -1
    property bool enteringForward: true

    transform: Translate {
        x: content.morphOffset
    }
    opacity: content.morphOpacity

    // The layer only exists while the blur is on screen: an always-on layer would cost
    // a full offscreen pass for an island that is mostly still.
    layer.enabled: content.morphBlur > 0.001
    layer.smooth: true
    layer.effect: MultiEffect {
        blurEnabled: true
        blurMax: 24
        blur: content.morphBlur
    }

    function beginMorph() {
        if (content.activityId === content.displayedId)
            return;
        // Straight to it on the first paint, and whenever there is nothing to slide out.
        if (content.displayedId === "") {
            content.displayedId = content.activityId;
            return;
        }
        // Direction carries meaning; see above. Guarded because an activity with no
        // descriptor would throw here and take the swap down with it, which is the
        // difference between a missed animation and an island frozen for the session.
        let forward = true;
        try {
            forward = IslandLayout.tierRank({ tier: IslandRegistry.tierOf(content.activityId) })
                <= IslandLayout.tierRank({ tier: IslandRegistry.tierOf(content.displayedId) });
        } catch (error) {
            forward = true;
        }
        content.enteringForward = forward;
        content.outDuration = Math.round((content.activityId === "dashboard" || content.displayedId === "dashboard"
            ? 70 : 110) * Appearance.animMultiplier);
        morph.restart();
    }

    onActivityIdChanged: content.beginMorph()
    Component.onCompleted: content.beginMorph()

    SequentialAnimation {
        id: morph
        running: false

        // Out: away from where the new one will come from.
        ParallelAnimation {
            NumberAnimation {
                target: content
                property: "morphOffset"
                from: 0
                to: content.enteringForward ? -content.morphDistance : content.morphDistance
                duration: content.outDuration
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: content
                property: "morphOpacity"
                from: 1.0
                to: content.morphFloor
                duration: content.outDuration
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: content
                property: "morphBlur"
                from: 0.0
                to: content.blurAllowed ? 1.0 : 0.0
                duration: content.outDuration
                easing.type: Easing.InQuad
            }
        }

        // The swap happens while the face is dimmed and away from centre. A script
        // rather than a PropertyAction, so the value is read when the action runs.
        ScriptAction {
            script: {
                content.displayedId = content.activityId;
                content.morphOffset = (content.enteringForward ? 1 : -1) * content.morphDistance * 1.3;
            }
        }

        // In.
        ParallelAnimation {
            NumberAnimation {
                target: content
                property: "morphOffset"
                to: 0
                duration: Math.round(400 * Appearance.animMultiplier)
                // A small overshoot so the content settles into place instead of
                // arriving and stopping dead; it matches the bounce the surface itself
                // has while it resizes.
                easing.type: Easing.OutBack
                easing.overshoot: 0.5
            }
            NumberAnimation {
                target: content
                property: "morphOpacity"
                to: 1.0
                duration: Math.round(170 * Appearance.animMultiplier)
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

    Loader {
        id: widgetLoader

        anchors.centerIn: parent
        width: parent.width
        height: parent.height

        active: content.hasWidget && !content.isSearch && !content.isOsd && !content.isDashboard
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
        anchors.fill: parent

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

        onVisibleChanged: {
            if (!searchLoader.visible || !searchLoader.item)
                return;
            // A query handed over by another surface (a keybind, the bar) opens with that
            // text already in place instead of an empty field.
            if (GlobalStates.activeSearchQuery) {
                searchLoader.item.setSearchingText(GlobalStates.activeSearchQuery);
                GlobalStates.activeSearchQuery = "";
            } else {
                searchLoader.item.cancelSearch();
            }
            Qt.callLater(() => searchLoader.item.focusSearchInput());
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
        visible: content.isDashboard
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

    // The resting face: the clock, with the side widgets beside it.
    NotchRestingFace {
        id: restingFace
        anchors.fill: parent
        sideIds: content.sideIds
        restHeight: content.restingHeight
        visible: !content.hasWidget && !content.isSearch && !content.isOsd && !content.isDashboard
    }
}
