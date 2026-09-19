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
    readonly property var sharpFaces: ["media", "search", "dashboard"]
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

            active: content.hasWidget && !content.isSearch && !content.isOsd
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

        // The resting face: the clock, with the side widgets beside it.
        NotchRestingFace {
            id: restingFace
            anchors.fill: parent
            sideIds: content.sideIds
            restHeight: content.restingHeight
            visible: !content.hasWidget && !content.isSearch && !content.isOsd
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
