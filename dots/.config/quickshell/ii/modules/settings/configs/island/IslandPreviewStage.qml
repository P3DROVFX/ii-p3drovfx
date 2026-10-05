pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.shared
import qs.modules.ii.dynamicIsland.core
import qs.modules.ii.dynamicIsland.bubble
import qs.modules.ii.dynamicIsland.styles.notch
import qs.modules.ii.dynamicIsland.widgets
import qs.modules.ii.overview
import qs.modules.ii.wallpaperSelector
import qs.modules.settings.configs.colors
import "IslandCatalog.js" as Catalog
import "../../../../services/windowSwitcher/WindowSwitcherLogic.js" as SwitcherLogic

/**
 * The island, live, over the top of the wallpaper.
 *
 * Nothing on the island is redrawn here: the silhouette is the island's own
 * `NotchShape`, the resting face is `NotchRestingFace`, a bubble's glance is
 * `AuxiliaryBubbleContent`, and every activity is its own face file, loaded from
 * `IslandRegistry` at the registry's size. They are laid out at their real pixel
 * size and the scene is scaled down only when the page is too narrow for it (the
 * lock screen preview's trick), so what the page shows is what the island draws.
 *
 * Faces whose content only exists while something happens (a call, an alarm) get
 * example data, handed to the real component: the ones that read their source walk
 * up to the nearest `controller` and find this stage's, the few that read a service
 * take `sample`. Everything else shows what is really going on.
 *
 * Input never reaches the faces: an alarm's Stop or a call's Answer is a real
 * action. The pointer resting on the island opens its card, as on the island.
 */
Item {
    id: root

    /** The activity on show; "" is the island at rest. */
    property string activityId: ""
    /** "island" (the face in the centre), "glance" (beside the clock or in a bubble) or "card". */
    property string presentation: "island"
    /** The side widgets of the resting face while no activity is on show. */
    property var restSideIds: []
    /** The activity is switched off: the island shows it, faded, so the choice can still be made. */
    property bool activityOn: true
    /** Whole stage faded while the island itself is off. */
    property bool islandOn: IslandPolicy.enabled
    /**
     * A surface the island opens instead of an activity: "overview", "session",
     * "switcher", "wallpaper" or "askpass" (`hostProps`: kind, style). "" for none.
     */
    property string hostId: ""
    property var hostProps: ({})
    /** "notch" or "island" to try a shape on; "" follows the setting. */
    property string shapeOverride: ""

    /**
     * The height the stage needs for what it shows and no more: the island (scaled
     * like the scene when the page is narrower than it) and a little air under it.
     * Hosts bind their height to this, so the stage hugs a resting pill and opens
     * for a session menu.
     */
    property real minHeight: 68
    property real bottomRoom: 14
    readonly property real contentNeedHeight: Math.max(root.islandTargetHeight, root.bubbleTargetHeight)
        + (root.pillShape ? root.pillInset : 0)
    readonly property real widthScale: Math.min(1, root.width / Math.max(1, root.sceneNeedWidth))
    readonly property real preferredHeight: Math.max(root.minHeight,
        Math.ceil(root.contentNeedHeight * root.widthScale) + root.bottomRoom)

    implicitHeight: root.preferredHeight

    // ── What the island draws ────────────────────────────────────────────
    readonly property bool bubblesOn: Config.options.bar.floatingNotch.auxiliaryBubble === true
    readonly property bool pillShape: (root.shapeOverride !== "" ? root.shapeOverride : IslandPolicy.shape) === "island"
    readonly property real restHeight: IslandMotion.pillHeight
    readonly property real filletSize: Appearance.rounding.verysmall
    readonly property real pillInset: Appearance.sizes.hyprlandGapsOut
    readonly property real bubbleDiameter: IslandMotion.pillHeight - 6
    readonly property color islandColor: Config.options.bar.expressiveColors
        ? barThemes.getTheme(Config.options.bar.expressiveColorTheme).barBackground
        : Appearance.colors.colLayer0

    function bubbleable(id) {
        return IslandPolicy.bubbleActivities.indexOf(id) !== -1;
    }
    function restSupports(id) {
        return restFace.sideOrder.indexOf(id) !== -1;
    }
    function hasFace(id) {
        return id === "osd" || IslandRegistry.faceFor(id, "compact") !== "";
    }

    /** The presentations an activity has, in the order the page offers them. */
    function presentationsOf(id) {
        if (id === "")
            return [];
        const list = [];
        // With bubbles on, a bubble's activity goes straight out into it: its face never
        // takes the centre (IslandPolicy.bubbleDirectActivities).
        const direct = root.bubblesOn && IslandPolicy.bubbleDirectActivities.indexOf(id) !== -1;
        if (root.hasFace(id) && !direct)
            list.push("island");
        if ((root.bubblesOn && root.bubbleable(id)) || root.restSupports(id))
            list.push("glance");
        if (IslandRegistry.hasExpanded(id))
            list.push("card");
        return list;
    }
    /** Where an activity lives first: beside the clock for what lasts, the centre for the rest. */
    function defaultPresentationOf(id) {
        const list = root.presentationsOf(id);
        const tier = IslandRegistry.tierOf(id);
        if (root.bubblesOn && root.bubbleable(id) && list.indexOf("glance") !== -1)
            return "glance";
        if ((tier === "live" || tier === "ambient") && list.indexOf("glance") !== -1)
            return "glance";
        return list.length > 0 ? list[0] : "island";
    }

    /**
     * The scene the island shows, decided once from the inputs:
     *   kind     "rest" | "face" | "card" | "osd"
     *   sides    the resting face's side widgets
     *   bubble   the activity in the bubble beside the island, if any
     *   bubbleCard  the bubble is open into its card
     */
    readonly property var plan: {
        const id = root.activityId;
        const available = root.presentationsOf(id);
        let p = available.indexOf(root.presentation) !== -1 ? root.presentation : (available[0] ?? "island");
        // Resting the pointer on the island opens its card, as on the island.
        if (root.peeking && available.indexOf("card") !== -1)
            p = "card";
        if (root.hostId !== "") {
            const props = root.hostProps ?? {};
            return { kind: "host", host: root.hostId, sides: [], bubble: "", bubbleCard: false,
                id: "host:" + root.hostId + ":" + (props.kind ?? "") + ":" + (props.style ?? "") };
        }
        if (id === "")
            return { kind: "rest", sides: root.restSideIds, bubble: "", bubbleCard: false, id: "" };
        if (id === "osd")
            return { kind: "osd", sides: [], bubble: "", bubbleCard: false, id: id };
        const inBubble = root.bubblesOn && root.bubbleable(id);
        if (p === "glance") {
            if (inBubble)
                return { kind: "rest", sides: [], bubble: id, bubbleCard: false, id: id };
            return { kind: "rest", sides: [id], bubble: "", bubbleCard: false, id: id };
        }
        if (p === "card") {
            if (inBubble)
                return { kind: "rest", sides: [], bubble: id, bubbleCard: true, id: id };
            return { kind: "card", sides: [], bubble: "", bubbleCard: false, id: id };
        }
        return { kind: "face", sides: [], bubble: "", bubbleCard: false, id: id };
    }
    readonly property string planKey: root.plan.kind + "|" + root.plan.id + "|" + root.plan.bubble + "|" + root.plan.bubbleCard
        + "|" + root.plan.sides.join(",")
    /** Whether what is on show is example data rather than the real thing. */
    readonly property bool showsExample: {
        if (root.plan.kind === "host")
            return root.plan.host === "askpass";
        const id = root.plan.kind === "face" || root.plan.kind === "card" || root.plan.bubbleCard ? root.plan.id : "";
        return id !== "" && (Catalog.sources[id] !== undefined || root.samples[id] !== undefined);
    }

    // ── Example data ────────────────────────────────────────────────────
    readonly property var samples: Catalog.samplesFor(Math.floor(Date.now() / 1000))
    /** Found by the faces that read their source; see the header. */
    readonly property QtObject controller: QtObject {
        readonly property var sources: Catalog.sources
    }

    BarThemes {
        id: barThemes
    }
    Item {
        id: focusSink
        focus: false
    }

    // ── Pointer ─────────────────────────────────────────────────────────
    property bool peeking: false
    /** The pointer is anywhere on the stage. */
    readonly property bool pointerInside: stageArea.containsMouse || islandArea.containsMouse || bubbleArea.containsMouse
    Timer {
        id: peekTimer
        interval: Math.max(150, Config.options.bar.floatingNotch.hoverExpandDelayMs ?? 300)
        onTriggered: root.peeking = true
    }

    // ── Sizes ───────────────────────────────────────────────────────────
    readonly property real cardWidth: {
        const item = cardLoader.item;
        if (item && item.preferredExpandedWidth !== undefined && item.preferredExpandedWidth > 0)
            return item.preferredExpandedWidth;
        return IslandRegistry.widthFor(root.shownPlan.id, "expanded");
    }
    readonly property real cardHeight: {
        const item = cardLoader.item;
        const cap = IslandRegistry.heightFor(root.shownPlan.id, "expanded");
        if (!item)
            return cap;
        if (item.preferredExpandedHeight !== undefined && item.preferredExpandedHeight > 0)
            return item.preferredExpandedHeight;
        if (item.expandedHeight !== undefined && item.expandedHeight > 0)
            return Math.min(cap, item.expandedHeight);
        if (IslandRegistry.hasPresentation(root.shownPlan.id, "expanded") && item.implicitHeight > 0)
            return Math.min(cap, item.implicitHeight);
        return cap;
    }
    readonly property real islandTargetWidth: {
        switch (root.shownPlan.kind) {
        case "face": return IslandRegistry.widthFor(root.shownPlan.id, "compact");
        case "card": return root.cardWidth;
        case "osd": return IslandRegistry.widthFor("osd", "compact");
        case "host": return root.hostWidth;
        }
        return restFace.targetWidth;
    }
    readonly property real islandTargetHeight: {
        switch (root.shownPlan.kind) {
        case "face": return IslandRegistry.heightFor(root.shownPlan.id, "compact");
        case "card": return root.cardHeight;
        case "osd": return IslandRegistry.heightFor("osd", "compact");
        case "host": return root.hostHeight;
        }
        return root.restHeight;
    }
    readonly property real bubbleTargetWidth: root.shownPlan.bubble === "" ? 0
        : root.shownPlan.bubbleCard ? root.cardWidth
        : Math.max(root.bubbleDiameter, bubbleGlance.preferredWidth)
    readonly property real bubbleTargetHeight: root.shownPlan.bubbleCard ? root.cardHeight : root.bubbleDiameter
    readonly property real bubbleGap: 8

    /** What the scene needs around the centred island, so it never has to move to fit. */
    readonly property real sceneNeedWidth: root.islandTargetWidth + 2 * root.filletSize
        + 2 * (root.bubbleTargetWidth > 0 ? root.bubbleGap + root.bubbleTargetWidth : 0) + 48
    readonly property real sceneNeedHeight: root.contentNeedHeight + root.bottomRoom
    readonly property real sceneScale: Math.min(1, root.width / Math.max(1, root.sceneNeedWidth),
        root.height / Math.max(1, root.sceneNeedHeight))
    property real liveScale: root.sceneScale
    Behavior on liveScale {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    // ── Hosted surfaces ─────────────────────────────────────────────────
    /** The switcher's metrics, as NotchContent derives them from the screen. */
    readonly property real screenWidth: Screen.width > 0 ? Screen.width : 1920
    readonly property real switcherCoverWidth: Math.round(Math.max(240, Math.min(560, root.screenWidth * 0.2)))
    readonly property real switcherCoverHeight: Math.round(root.switcherCoverWidth * 0.625)
    /** The windows a switch would show now; read only while the switcher is on the stage. */
    readonly property var switcherEntries: {
        if (root.shownPlan.host !== "switcher")
            return root.lastSwitcherEntries;
        const filter = Object.assign({}, WindowSwitcher.makeFilter(), { "includeOtherWorkspaces": true, "monitor": -1 });
        return SwitcherLogic.snapshot(HyprlandData.windowList, WindowSwitcher.toplevelsByAddress(), filter,
            WindowSwitcher.currentAddress, appClass => WindowSwitcher.appName(appClass)).slice(0, 7);
    }
    property var lastSwitcherEntries: []
    onSwitcherEntriesChanged: root.lastSwitcherEntries = root.switcherEntries
    readonly property real hostWidth: {
        const item = root.hostItem;
        switch (root.shownPlan.host) {
        case "switcher": {
            const n = root.switcherEntries.length;
            const spread = n <= 1 ? 1.25 : n === 2 ? 1.6 : n === 3 ? 2.0 : n === 4 ? 2.4 : 2.8;
            return Math.round(root.switcherCoverWidth * spread);
        }
        case "session": return item && item.contentTargetWidth > 0 ? item.contentTargetWidth : 394;
        case "askpass": return item && item.contentTargetWidth > 0 ? item.contentTargetWidth : 400;
        case "wallpaper": return item && item.contentTargetWidth > 0 ? item.contentTargetWidth : 1156;
        case "overview": return item && item.contentTargetWidth > 0 ? item.contentTargetWidth : 440;
        }
        return root.restHeight;
    }
    readonly property real hostHeight: {
        const item = root.hostItem;
        switch (root.shownPlan.host) {
        case "switcher": return 16 + root.switcherCoverHeight + 10 + 22 + 14;
        case "session": return item && item.contentTargetHeight > 0 ? item.contentTargetHeight : 236;
        case "askpass": return item && item.contentTargetHeight > 0 ? item.contentTargetHeight : 214;
        case "wallpaper": return item && item.contentTargetHeight > 0 ? item.contentTargetHeight : 300;
        case "overview": return item && item.contentTargetHeight > 0 ? item.contentTargetHeight : 54;
        }
        return root.restHeight;
    }
    readonly property var askpassRequest: {
        const kind = root.hostProps?.kind ?? "sudo";
        switch (kind) {
        case "polkit":
            return { kind: "polkit", prompt: "Password:", attempt: 0 };
        case "ssh":
            return { kind: "ssh", prompt: "Enter passphrase for key '~/.ssh/id_ed25519':", command: "git push", attempt: 0 };
        default:
            return { kind: "sudo", prompt: "Password:", command: "sudo pacman -Syu", attempt: 0 };
        }
    }

    /** The surface on show, once its slot has built it. */
    readonly property var hostItem: {
        const slots = [sessionSlot, askpassSlot, switcherSlot, wallpaperSlot, overviewSlot];
        for (let i = 0; i < slots.length; i++) {
            if (slots[i].host === root.shownPlan.host)
                return slots[i].status === Loader.Ready ? slots[i].item : null;
        }
        return null;
    }

    /**
     * One loader per surface, its source fixed, built off the GUI thread.
     *
     * A surface (the overview's screen copies, a folder of thumbnails) built in one go
     * froze the page for the first frames of a hover. Asynchronous loading is only safe
     * because nothing is ever swapped or torn down mid-build: the source never changes,
     * and a slot stays active until its build finishes (a cancelled incubation crashed
     * the shell in QQmlConnections, see AGENTS.md). Kept for 30 s after the pointer
     * leaves, so going back to a tile shows it at once; hidden meanwhile, so nothing
     * of it is drawn.
     */
    component HostSlot: Loader {
        id: slot
        required property string host
        readonly property bool wanted: root.shownPlan.kind === "host" && root.shownPlan.host === slot.host && root.visible
        property bool retained: false

        anchors.horizontalCenter: parent.horizontalCenter
        asynchronous: true
        active: slot.wanted || slot.retained || slot.status === Loader.Loading
        opacity: slot.wanted && slot.status === Loader.Ready ? 1 : 0
        visible: slot.opacity > 0.01
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        onWantedChanged: {
            if (slot.wanted) {
                retainTimer.stop();
                slot.retained = true;
            } else {
                retainTimer.restart();
            }
        }
        Timer {
            id: retainTimer
            interval: 30000
            onTriggered: slot.retained = false
        }
        // Laid out only while on show: a hidden one keeps its last box.
        Binding {
            target: slot
            property: "width"
            value: root.hostWidth
            when: slot.wanted
        }
        Binding {
            target: slot
            property: "height"
            value: root.hostHeight
            when: slot.wanted
        }
    }

    Component {
        id: sessionHost
        IslandSessionMenu {
            active: true
        }
    }
    Component {
        id: askpassHost
        IslandAskpassCard {
            request: root.askpassRequest
            style: root.hostProps?.style ?? "card"
            shown: true
            focused: false
        }
    }
    Component {
        id: switcherHost
        IslandWindowSwitcher {
            // Live window captures only while on show, not while kept.
            shown: switcherSlot.wanted
            previewEntries: root.switcherEntries
            coverWidth: root.switcherCoverWidth
            coverHeight: root.switcherCoverHeight
            topPadding: 16
            titleGap: 10
            titleHeight: 22
            hintsHeight: 0
        }
    }
    Component {
        id: wallpaperHost
        WallpaperSelectorContent {
            compact: true
            compactStyle: root.hostProps?.style ?? Config.options.bar.floatingNotch.wallpaperBrowserStyle
            screenAspect: Screen.height > 0 ? Screen.width / Screen.height : 16 / 10
            active: wallpaperSlot.wanted
        }
    }
    Component {
        id: overviewHost
        Item {
            id: overviewFace
            readonly property real searchHeight: 54
            readonly property real gap: 8
            readonly property real contentTargetWidth: Math.max(Config.options.search.baseWidth ?? 440, grid.implicitWidth)
            readonly property real contentTargetHeight: overviewFace.searchHeight + overviewFace.gap + grid.implicitHeight

            SearchBar {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                y: 4
                height: overviewFace.searchHeight - 8
                searchingText: ""
            }
            OverviewWidget {
                id: grid
                anchors.horizontalCenter: parent.horizontalCenter
                y: overviewFace.searchHeight + overviewFace.gap
                hosted: true
                panelWindow: root.QsWindow.window
                monitorIndex: Math.max(0, Quickshell.screens.indexOf(root.QsWindow.window?.screen ?? null))
                gridRows: 2
                gridColumns: 3
                fixedScale: 0.15
                suppressEntrance: true
            }
        }
    }

    // ── The swap: the old scene leaves before the new one is laid out ──────
    property var shownPlan: ({ kind: "rest", sides: [], bubble: "", bubbleCard: false, id: "" })
    property real contentOpacity: 1
    property real contentLift: 0
    Component.onCompleted: {
        root.shownPlan = root.plan;
        restFace.sideIds = root.plan.sides;
    }
    onPlanKeyChanged: {
        if (Appearance.reducedMotion) {
            root.shownPlan = root.plan;
            restFace.sideIds = root.plan.sides;
            return;
        }
        swap.restart();
    }
    SequentialAnimation {
        id: swap
        NumberAnimation {
            target: root
            property: "contentOpacity"
            to: 0
            duration: Appearance.animation.elementMoveFast.duration * 0.6
            easing.type: Easing.InCubic
        }
        ScriptAction {
            script: {
                root.shownPlan = root.plan;
                restFace.sideIds = root.plan.sides;
                root.contentLift = 6;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "contentOpacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root
                property: "contentLift"
                to: 0
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }
    }

    // ── Backdrop: the top of the desktop ─────────────────────────────────
    ClippingRectangle {
        id: backdrop
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer2

        Item {
            // The wallpaper at the screen's proportions, of which the stage sees the top.
            width: parent.width
            height: Math.max(parent.height, parent.width * 9 / 16)
            ColorsWallpaperImage {
                anchors.fill: parent
                targetMode: "desktop"
                visible: root.visible
            }
        }
        // Keeps a light wallpaper from swallowing a light island, and the other way round.
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0
            opacity: 0.18
        }

        // Swallows every press and wheel on the stage: the faces stay pictures.
        MouseArea {
            id: stageArea
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            preventStealing: true
            onWheel: wheel => wheel.accepted = true
        }

        // ── The scene, at the island's own pixel size ────────────────────
        Item {
            id: scene
            width: root.width / root.liveScale
            height: root.height / root.liveScale
            scale: root.liveScale
            transformOrigin: Item.TopLeft
            opacity: root.islandOn ? 1 : 0.45
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            property real islandWidth: root.islandTargetWidth
            property real islandHeight: root.islandTargetHeight
            property real bubbleWidth: root.bubbleTargetWidth
            property real bubbleHeight: root.bubbleTargetHeight
            Behavior on islandWidth {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on islandHeight {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on bubbleWidth {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on bubbleHeight {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            readonly property real topY: root.pillShape ? root.pillInset : 0

            // ── Island body ──────────────────────────────────────────────
            Item {
                id: island
                x: Math.round((scene.width - width) / 2)
                y: scene.topY
                width: scene.islandWidth + 2 * root.filletSize
                height: scene.islandHeight
                opacity: root.activityOn ? 1 : 0.5
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                // An analytic shadow under the body, not a blurred copy of it: the copy
                // re-rendered the whole island into a texture on every frame of a morph.
                RectangularShadow {
                    x: root.filletSize
                    y: 0
                    width: scene.islandWidth
                    height: scene.islandHeight
                    visible: Config.options.bar.floatingNotch.dropShadow ?? false
                    radius: body.bottomRadius
                    blur: 14
                    offset.y: 3
                    color: Appearance.colors.colShadow
                }

                NotchShape {
                    id: body
                    anchors.fill: parent
                    shoulder: root.filletSize
                    attached: !root.pillShape
                    topRadius: root.pillShape ? body.bottomRadius : 0
                    bottomRadius: Math.min(scene.islandHeight / 2, Appearance.rounding.large)
                    color: root.islandColor

                }

                // The straight body; everything drawn in the island is cut by it.
                Item {
                    id: clipBox
                    x: root.filletSize
                    width: scene.islandWidth
                    height: scene.islandHeight
                    clip: true

                    Item {
                        id: content
                        anchors.fill: parent
                        opacity: root.contentOpacity
                        transform: Translate {
                            y: root.contentLift
                        }

                        NotchRestingFace {
                            id: restFace
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: root.shownPlan.kind === "rest" ? scene.islandWidth : restFace.targetWidth
                            height: root.restHeight
                            restHeight: root.restHeight
                            visible: root.shownPlan.kind === "rest"
                        }

                        // A face is laid out once at its own box, never at the morphing one.
                        Loader {
                            id: faceLoader
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: IslandRegistry.widthFor(root.shownPlan.id, "compact")
                            height: IslandRegistry.heightFor(root.shownPlan.id, "compact")
                            active: root.shownPlan.kind === "face" && root.visible
                            source: active ? IslandRegistry.faceFor(root.shownPlan.id, "compact") : ""
                            asynchronous: false

                            Binding {
                                target: faceLoader.item && faceLoader.item.hasOwnProperty("isExpanded") ? faceLoader.item : null
                                property: "isExpanded"
                                value: false
                            }
                            Binding {
                                target: faceLoader.item && faceLoader.item.hasOwnProperty("panelWidgetsCount") ? faceLoader.item : null
                                property: "panelWidgetsCount"
                                value: 1
                            }
                            Binding {
                                target: faceLoader.item && faceLoader.item.hasOwnProperty("sample") ? faceLoader.item : null
                                property: "sample"
                                value: root.samples[root.shownPlan.id] ?? null
                            }
                            Binding {
                                target: faceLoader.item && faceLoader.item.hasOwnProperty("heldNotif")
                                    && Notifications.popupList.length === 0 ? faceLoader.item : null
                                property: "heldNotif"
                                value: root.samples.notification
                            }
                        }

                        Loader {
                            id: osdLoader
                            anchors.fill: parent
                            active: root.shownPlan.kind === "osd" && root.visible
                            source: !active ? ""
                                : Quickshell.shellPath(Config.options.osd.style === "tuner"
                                    ? "modules/ii/onScreenDisplay/tuner/TunerIndicator.qml"
                                    : "modules/ii/topLayer/osd/indicators/VolumeIndicator.qml")
                        }

                        // A surface the island opens. Keyboard focus never stays inside it: a
                        // focused Lock button or password field would act on Enter.
                        FocusScope {
                            id: hostGuard
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: root.hostWidth
                            height: root.hostHeight
                            onActiveFocusChanged: {
                                if (hostGuard.activeFocus)
                                    focusSink.forceActiveFocus();
                            }
                            HostSlot {
                                id: sessionSlot
                                host: "session"
                                sourceComponent: sessionHost
                            }
                            HostSlot {
                                id: askpassSlot
                                host: "askpass"
                                sourceComponent: askpassHost
                            }
                            HostSlot {
                                id: switcherSlot
                                host: "switcher"
                                sourceComponent: switcherHost
                            }
                            HostSlot {
                                id: wallpaperSlot
                                host: "wallpaper"
                                sourceComponent: wallpaperHost
                            }
                            HostSlot {
                                id: overviewSlot
                                host: "overview"
                                sourceComponent: overviewHost
                            }
                        }

                        Item {
                            id: islandCardSlot
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: root.cardWidth
                            height: root.cardHeight
                        }
                    }
                }

                // The pointer resting on the island opens its card.
                MouseArea {
                    id: islandArea
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    hoverEnabled: true
                    onWheel: wheel => wheel.accepted = true
                    onContainsMouseChanged: {
                        if (containsMouse) {
                            peekTimer.restart();
                        } else {
                            peekTimer.stop();
                            root.peeking = false;
                        }
                    }
                }
            }

            // ── Auxiliary bubble ─────────────────────────────────────────
            Rectangle {
                id: bubble
                readonly property bool present: root.shownPlan.bubble !== ""
                x: island.x + island.width - root.filletSize + root.bubbleGap
                y: scene.topY + (root.pillShape ? 0 : 3)
                width: Math.max(1, scene.bubbleWidth)
                height: scene.bubbleHeight
                radius: Math.min(height / 2, Appearance.rounding.large)
                color: root.islandColor
                opacity: bubble.present ? root.contentOpacity * (root.activityOn ? 1 : 0.5) : 0
                visible: opacity > 0.01
                clip: true
                transform: Translate {
                    y: root.contentLift
                }

                AuxiliaryBubbleContent {
                    id: bubbleGlance
                    x: 0
                    width: bubble.width
                    activityId: root.shownPlan.bubble
                    diameter: root.bubbleDiameter
                    interactive: false
                    opacity: root.shownPlan.bubbleCard ? 0 : 1
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                Item {
                    id: bubbleCardSlot
                    width: root.cardWidth
                    height: root.cardHeight
                }

                MouseArea {
                    id: bubbleArea
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    hoverEnabled: true
                    onWheel: wheel => wheel.accepted = true
                    onContainsMouseChanged: {
                        if (containsMouse) {
                            peekTimer.restart();
                        } else {
                            peekTimer.stop();
                            root.peeking = false;
                        }
                    }
                }
            }

            // The card, reparented into whichever body holds it: the island or the bubble.
            Loader {
                id: cardLoader
                readonly property bool wanted: root.shownPlan.kind === "card" || root.shownPlan.bubbleCard
                parent: root.shownPlan.bubbleCard ? bubbleCardSlot : islandCardSlot
                anchors.fill: parent
                active: wanted && root.visible
                source: active ? IslandRegistry.faceFor(root.shownPlan.id, "expanded") : ""
                asynchronous: false
                onStatusChanged: {
                    if (status === Loader.Error && root.shownPlan.id !== "") {
                        const fallback = IslandRegistry.legacyContentFor(root.shownPlan.id);
                        if (source != fallback)
                            source = fallback;
                    }
                }

                Binding {
                    target: cardLoader.item && cardLoader.item.hasOwnProperty("isExpanded") ? cardLoader.item : null
                    property: "isExpanded"
                    value: true
                }
                Binding {
                    target: cardLoader.item && cardLoader.item.hasOwnProperty("inBubbleCard") ? cardLoader.item : null
                    property: "inBubbleCard"
                    value: root.shownPlan.bubbleCard
                }
                Binding {
                    target: cardLoader.item && cardLoader.item.hasOwnProperty("cardExpanded") ? cardLoader.item : null
                    property: "cardExpanded"
                    value: true
                }
                Binding {
                    target: cardLoader.item && cardLoader.item.hasOwnProperty("panelWidgetsCount") ? cardLoader.item : null
                    property: "panelWidgetsCount"
                    value: 1
                }
                Binding {
                    target: cardLoader.item && cardLoader.item.hasOwnProperty("activityId") ? cardLoader.item : null
                    property: "activityId"
                    value: root.shownPlan.id
                }
                Binding {
                    target: cardLoader.item && cardLoader.item.hasOwnProperty("sample") ? cardLoader.item : null
                    property: "sample"
                    value: root.samples[root.shownPlan.id] ?? null
                }
                Binding {
                    target: cardLoader.item && cardLoader.item.hasOwnProperty("heldNotif")
                        && Notifications.popupList.length === 0 ? cardLoader.item : null
                    property: "heldNotif"
                    value: root.samples.notification
                }
            }
        }
    }
}
