pragma ComponentBehavior: Bound

import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.tablet.menu

/**
 * Recents: every open window as a card, scrubbed sideways.
 *
 * Deliberately not the ii overview. That is a grid of workspaces with their windows laid
 * out inside, which answers "where is everything"; this answers "what was I just doing",
 * which is a flat, most-recent-first list. Android keeps the two apart and so does this
 * family — the home screens are the workspaces, recents is this.
 *
 * A **list**, not pages. Paging was tried and is the wrong model: a page is a unit the user
 * has to reason about, and Recents has no units — it has an order, and you go further back
 * along it. Android scrolls continuously for the same reason. The grid remains available as
 * a preference for anyone who wants four windows at once on a very large screen, but it is
 * no longer what this surface is.
 */
Item {
    id: root

    property real revealProgress: 1

    signal dismissRequested
    /// Asks the host to close first and run this afterwards; see TabletRecentsWindow on why
    /// anything that changes focus cannot happen while this surface is still mapped.
    signal deferredRequested(var action)

    readonly property var recentsConfig: Config.options?.tablet?.recents

    /// "list" or "grid".
    readonly property bool gridLayout: (root.recentsConfig?.layout ?? "list") === "grid"

    readonly property int gridColumns: Math.max(1, Math.min(4, root.recentsConfig?.gridColumns ?? 2))
    readonly property int gridRows: Math.max(1, Math.min(3, root.recentsConfig?.gridRows ?? 2))
    readonly property int cardsPerPage: root.gridColumns * root.gridRows

    readonly property real cardSpacing: Math.max(16, Math.round(root.width * 0.014))
    /// Room under every card, whether or not that card is showing its actions, so the row
    /// appearing never moves the cards.
    readonly property real actionRowHeight: (root.recentsConfig?.showCardActions ?? true) ? 56 : 0

    /// The windows split into pages of `cardsPerPage`, newest page first.
    readonly property var windowPages: {
        if (!root.gridLayout)
            return [];
        const pages = [];
        const all = root.windows;
        for (let i = 0; i < all.length; i += root.cardsPerPage)
            pages.push(all.slice(i, i + root.cardsPerPage));
        return pages;
    }

    /**
     * Every open window, most recently *used* first.
     *
     * This used to reverse ToplevelManager's own order and call the result most-recent-first.
     * That order is creation order — activating a window does not move it — so the screen
     * whose entire job is answering "what was I just doing" was answering "what did I open
     * last", and the two only agree if you never switch back to anything.
     *
     * Hyprland already keeps the real answer: `focusHistoryID` is 0 for the focused window
     * and counts up through the focus stack. The toplevels and the client list are two views
     * of the same windows, joined on the address — the same join GlobalStates already does to
     * find the active window when foreign-toplevel focus comes back empty.
     */
    readonly property var windows: {
        const focusOrderByAddress = {};
        for (const client of (HyprlandData.windowList ?? [])) {
            const raw = String(client?.address ?? "").trim();
            if (raw.length === 0)
                continue;
            const address = raw.startsWith("0x") ? raw : `0x${raw}`;
            focusOrderByAddress[address] = Number(client?.focusHistoryID ?? 9999);
        }

        const entries = [];
        for (const toplevel of (ToplevelManager.toplevels?.values ?? [])) {
            if (!toplevel)
                continue;
            const raw = String(toplevel.HyprlandToplevel?.address ?? "").trim();
            const address = raw.length === 0 ? "" : (raw.startsWith("0x") ? raw : `0x${raw}`);
            entries.push({
                toplevel: toplevel,
                // A window Hyprland has not listed yet sorts to the end rather than to the
                // front: an unknown position is not evidence of being the most recent one.
                focusOrder: focusOrderByAddress[address] ?? 9999
            });
        }

        entries.sort((left, right) => left.focusOrder - right.focusOrder);
        return entries.map(entry => entry.toplevel);
    }

    /// Hyprland's rows keyed by address, so a card can find its own real size without
    /// walking the whole client list once per delegate.
    readonly property var clientByAddress: {
        const map = {};
        for (const client of (HyprlandData.windowList ?? [])) {
            const raw = String(client?.address ?? "").trim();
            if (raw.length === 0)
                continue;
            map[raw.startsWith("0x") ? raw : `0x${raw}`] = client;
        }
        return map;
    }

    function addressOf(toplevel) {
        const raw = String(toplevel?.HyprlandToplevel?.address ?? "").trim();
        if (raw.length === 0)
            return "";
        return raw.startsWith("0x") ? raw : `0x${raw}`;
    }

    function clientFor(toplevel) {
        return root.clientByAddress[root.addressOf(toplevel)] ?? null;
    }

    function activate(toplevel) {
        root.deferredRequested(() => toplevel?.activate());
    }

    function closeWindow(toplevel) {
        toplevel?.close();
    }

    /// Snapshot the list first: closing walks it, and `windows` is a binding that
    /// re-evaluates as each toplevel goes away.
    function closeAll() {
        const doomed = root.windows.slice();
        for (const toplevel of doomed)
            toplevel?.close();
    }

    /**
     * What you can do to a window without going to it.
     *
     * Android puts these behind the app icon above the card; here the header pill is the
     * same handle. Float and fullscreen are the dispatches the gesture registry already
     * binds, so this is mostly wiring rather than new capability — the point is that a
     * finger had no way to reach any of it.
     *
     * The window has to be named by address: dispatching without one acts on whatever is
     * focused, which is never the card that was tapped.
     */
    function menuActionsFor(toplevel) {
        const target = root.addressOf(toplevel);
        const actions = [];

        if (root.canSplit(toplevel)) {
            actions.push({
                symbol: "splitscreen",
                label: Translation.tr("Split with current app"),
                trigger: () => root.splitWithCurrent(toplevel)
            });
        }

        if (target.length > 0) {
            actions.push({
                symbol: "screenshot_region",
                label: Translation.tr("Screenshot this window"),
                trigger: () => root.screenshotRequested(target)
            });
            actions.push({
                symbol: "picture_in_picture",
                label: Translation.tr("Float"),
                trigger: () => root.dispatchOn(target, `hl.dsp.window.float({ action = 'toggle', window = "address:${target}" })`)
            });
            actions.push({
                symbol: "fullscreen",
                label: Translation.tr("Fullscreen"),
                trigger: () => root.dispatchOn(target, `hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'toggle', window = "address:${target}" })`)
            });
        }
        actions.push({
            symbol: "close",
            label: Translation.tr("Close"),
            destructive: true,
            trigger: () => root.closeWindow(toplevel)
        });
        return actions;
    }

    /**
     * "Split with the app you were in."
     *
     * Hyprland already tiles two windows that share a workspace, so a split is not a layout
     * this shell has to compute — it is a window that has to be somewhere else. All this
     * dispatches is a move; the compositor does the splitting, which is why the shell does
     * not grow a layout manager to offer the feature.
     *
     * Only offered when it would do something: the window has to be somewhere other than the
     * workspace you are returning to, and that workspace has to have something on it to
     * split *with* — otherwise this is a plain move wearing the wrong label.
     */
    function canSplit(toplevel) {
        const target = root.addressOf(toplevel);
        if (target.length === 0)
            return false;
        const activeWorkspace = Number(HyprlandData.activeWorkspace?.id ?? -1);
        if (activeWorkspace === -1 || root.workspaceOf(target) === activeWorkspace)
            return false;
        return HyprlandData.hyprlandClientsForWorkspace(activeWorkspace).length > 0;
    }

    function splitWithCurrent(toplevel) {
        const target = root.addressOf(toplevel);
        const activeWorkspace = Number(HyprlandData.activeWorkspace?.id ?? -1);
        if (target.length === 0 || activeWorkspace === -1)
            return;
        root.dispatchOn(target,
            `hl.dsp.window.move({ workspace = ${activeWorkspace}, follow = false, window = "address:${target}" })`);
    }

    /// Raised so the delegate that owns the capture can do the grab; only it has one.
    signal screenshotRequested(string address)

    /// Which workspace a window is on, or -1. The toplevel does not carry it; Hyprland's
    /// client list does, and the two are joined on the address as everywhere else here.
    function workspaceOf(address) {
        if (!address || address.length === 0)
            return -1;
        return Number(root.clientByAddress[address]?.workspace?.id ?? -1);
    }

    /// Anything that moves or focuses a window has to wait for this surface to unmap; see
    /// TabletRecentsWindow on why running it while recents is still up is undone silently.
    function dispatchOn(address, command) {
        root.deferredRequested(() => {
            Hyprland.dispatch(command);
            Hyprland.dispatch(`hl.dsp.focus({ window = "address:${address}" })`);
        });
    }

    /// Both layouts raise the same menu from the same handle; only where they sit differs.
    function openCardMenu(toplevel, x, y) {
        const point = root.mapFromItem(null, x, y);
        cardMenu.openAt(point.x, point.y,
                        root.menuActionsFor(toplevel),
                        toplevel?.title ?? toplevel?.appId ?? "",
                        Quickshell.iconPath(TaskbarApps.getCachedIcon(toplevel?.appId ?? ""), "image-missing"),
                        "");
    }

    function newWorkspace() {
        // The Lua dispatcher API, as everything else in the shell uses; the classic
        // "workspace empty" string is a Lua syntax error here rather than a no-op. The host
        // runs it after this surface has gone — see TabletRecentsWindow.pendingDispatch.
        root.deferredRequested(() => Hyprland.dispatch("hl.dsp.focus({ workspace = 'empty' })"));
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Math.round(root.width * 0.02)
        anchors.rightMargin: Math.round(root.width * 0.02)
        anchors.topMargin: Math.round(root.height * 0.06)
        anchors.bottomMargin: Math.round(root.height * 0.04)
        spacing: 18

        opacity: root.revealProgress

        // Takes the leftover height so the cards sit in the middle of the screen, with the
        // pills pinned below them.
        Item {
            id: cardArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            /**
             * Empty space above every card, so a card being flung upwards has somewhere to
             * go inside a clipped list.
             *
             * The list has to clip — without it, the delegates the view keeps warm off both
             * sides paint over the whole screen — and clipping at the card's own top edge
             * would slice the dismiss gesture in half the moment it started.
             */
            readonly property real dragHeadroom: 56

            /**
             * One height for every card, so the row reads as a row. The width is each
             * window's own, which is what makes a portrait window a portrait card.
             *
             * Capped well below the space available. A card as tall as the viewport is a
             * card as wide as the screen, and a row you can only ever see one of is not a
             * row — Android's cards are around half the screen's height for exactly this
             * reason, so two or three are in view and the order is legible at a glance.
             */
            readonly property real cardHeight: Math.max(180, Math.min(
                cardArea.height - root.actionRowHeight - cardArea.dragHeadroom,
                Math.round(root.height * 0.5)))

            /**
             * The list. Continuous, snapping to a card on release rather than to a page.
             *
             * `indexAt` against the middle of the viewport is what decides which card owns
             * the action row. A `currentIndex` with a highlight range would do the same, but
             * only by also constraining where the view may rest — and the whole point of a
             * list here is that it may rest anywhere.
             */
            ListView {
                id: cardList
                anchors.left: parent.left
                anchors.right: parent.right
                // Centred rather than filling: the row is only as tall as a card plus its
                // action strip, and a list stretched to the viewport would pin the cards to
                // the top with the leftover space dumped underneath them.
                anchors.verticalCenter: parent.verticalCenter
                height: cardArea.dragHeadroom + cardArea.cardHeight + root.actionRowHeight
                visible: !root.gridLayout
                enabled: visible
                model: root.gridLayout ? [] : root.windows
                orientation: ListView.Horizontal
                spacing: root.cardSpacing
                snapMode: ListView.SnapToItem
                boundsBehavior: Flickable.DragOverBounds
                clip: true
                leftMargin: root.cardSpacing
                rightMargin: root.cardSpacing
                cacheBuffer: Math.round(root.width * 2)

                /**
                 * The row ends in a fade, not in a cut.
                 *
                 * The drawer's grid does the same thing vertically and for the same reason:
                 * a card sliced off at the bezel reads as a rendering fault, while one that
                 * dissolves reads as "there is more this way". It masks the list's own alpha
                 * rather than painting a band of colour over it — a band only ends content
                 * when the surface behind it is that colour, and behind this is a blurred
                 * photograph, so any colour the band could paint would itself show through.
                 *
                 * Each side fades only once there is something past it. A fade at the start
                 * of the row is the view telling you there is more to the left when there is
                 * not — and against a card whose own edge is already there, it just reads as
                 * the card being dimmed for no reason.
                 *
                 * The two ends have to be worked out from the Flickable's real limits, not
                 * from contentX alone. With side margins the resting position is not zero:
                 * it is `originX - leftMargin`, and measuring against zero left the first
                 * card sitting under a third of a fade at rest.
                 */
                readonly property real fadeWidth: Math.min(160, Math.round(cardList.width * 0.1))
                readonly property real startX: cardList.originX - cardList.leftMargin
                readonly property real endX: cardList.originX + cardList.contentWidth
                    + cardList.rightMargin - cardList.width
                readonly property real leadFade: Math.max(0, Math.min(1,
                    (cardList.contentX - cardList.startX) / 48))
                readonly property real trailFade: Math.max(0, Math.min(1,
                    (cardList.endX - cardList.contentX) / 48))

                layer.enabled: cardList.visible
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: Math.max(1, cardList.width)
                        height: Math.max(1, cardList.height)
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop {
                                position: 0.0
                                color: Qt.rgba(1, 1, 1, 1 - cardList.leadFade)
                            }
                            GradientStop {
                                position: cardList.width > 0
                                    ? Math.min(0.45, cardList.fadeWidth / cardList.width) : 0
                                color: "white"
                            }
                            GradientStop {
                                position: cardList.width > 0
                                    ? Math.max(0.55, 1 - cardList.fadeWidth / cardList.width) : 1
                                color: "white"
                            }
                            GradientStop {
                                position: 1.0
                                color: Qt.rgba(1, 1, 1, 1 - cardList.trailFade)
                            }
                        }
                    }
                }

                /// Which card is in the middle of the viewport. Kept rather than recomputed
                /// on demand: `indexAt` returns -1 in the gaps between delegates, and an
                /// action row that blinks out every time a gap crosses the centre is worse
                /// than one that lags by a few pixels.
                property int activeIndex: 0

                function refreshActiveIndex() {
                    const found = cardList.indexAt(cardList.contentX + cardList.width / 2,
                                                   cardList.height / 2);
                    if (found >= 0)
                        cardList.activeIndex = found;
                }

                onContentXChanged: cardList.refreshActiveIndex()
                onCountChanged: cardList.refreshActiveIndex()

                // The most recent window is at index 0, so the useful position is the start.
                // A ListView keeps its contentX, and resetting on the way out costs nothing.
                //
                // Set explicitly rather than through positionViewAtBeginning(), which lands
                // on `originX` and leaves the view a margin's width past its own start — far
                // enough for the leading fade to read as scrolled when nothing has been.
                function goToStart() {
                    cardList.contentX = cardList.startX;
                    cardList.activeIndex = 0;
                }

                Component.onCompleted: cardList.goToStart()
                Connections {
                    target: root
                    function onRevealProgressChanged() {
                        if (root.revealProgress < 0.02)
                            cardList.goToStart();
                    }
                }

                delegate: TabletRecentCard {
                    id: listCard
                    required property var modelData
                    required property int index

                    toplevel: modelData
                    client: root.clientFor(modelData)
                    cardHeight: cardArea.cardHeight
                    topInset: cardArea.dragHeadroom
                    actionRowHeight: root.actionRowHeight
                    showActions: root.actionRowHeight > 0 && listCard.index === cardList.activeIndex
                    // MRU order puts the window you came from first.
                    isCurrent: listCard.index === 0

                    onActivated: root.activate(listCard.modelData)
                    onClosed: root.closeWindow(listCard.modelData)
                    onSplitRequested: root.splitWithCurrent(listCard.modelData)
                    onMenuRequested: (x, y) => root.openCardMenu(listCard.modelData, x, y)

                    Connections {
                        target: root
                        function onScreenshotRequested(address) {
                            if (address === root.addressOf(listCard.modelData))
                                listCard.takeScreenshot();
                        }
                    }
                }
            }

            /**
             * The grid, kept as a preference rather than as the default.
             *
             * Four windows at once is a genuinely better answer on a very large screen, and
             * the code for it already exists; it is only the wrong *default*, because a page
             * is a unit and Recents has no units.
             */
            ListView {
                id: pager
                anchors.fill: parent
                visible: root.gridLayout
                enabled: visible
                model: root.gridLayout ? root.windowPages : []
                orientation: ListView.Horizontal
                snapMode: ListView.SnapOneItem
                highlightRangeMode: ListView.StrictlyEnforceRange
                boundsBehavior: Flickable.DragOverBounds
                clip: true
                cacheBuffer: Math.round(root.width * 2)

                Connections {
                    target: root
                    function onRevealProgressChanged() {
                        if (root.revealProgress < 0.02)
                            pager.positionViewAtBeginning();
                    }
                }

                delegate: Item {
                    id: page
                    required property var modelData
                    width: pager.width
                    height: pager.height

                    readonly property real cellWidth: (page.width - root.cardSpacing * (root.gridColumns - 1))
                        / root.gridColumns
                    readonly property real cellHeight: (page.height - root.cardSpacing * (root.gridRows - 1))
                        / root.gridRows

                    Grid {
                        anchors.centerIn: parent
                        columns: root.gridColumns
                        rows: root.gridRows
                        spacing: root.cardSpacing

                        Repeater {
                            model: page.modelData

                            delegate: Item {
                                id: gridCell
                                required property var modelData
                                required property int index
                                width: page.cellWidth
                                height: page.cellHeight

                                TabletRecentCard {
                                    id: gridCard
                                    anchors.centerIn: parent
                                    toplevel: gridCell.modelData
                                    client: root.clientFor(gridCell.modelData)
                                    // Bounded by the cell in both directions. `aspect` is
                                    // derived from the window alone, so reading it here is
                                    // not the loop that reading implicitWidth would be.
                                    cardHeight: Math.min(gridCell.height, gridCell.width / gridCard.aspect)
                                    isCurrent: gridCell.index === 0 && page.modelData === root.windowPages[0]
                                    onActivated: root.activate(gridCell.modelData)
                                    onClosed: root.closeWindow(gridCell.modelData)
                                    onSplitRequested: root.splitWithCurrent(gridCell.modelData)
                                    onMenuRequested: (x, y) => root.openCardMenu(gridCell.modelData, x, y)
                                }
                            }
                        }
                    }
                }
            }

            PagePlaceholder {
                anchors.fill: parent
                shown: root.windows.length === 0
                icon: "layers_clear"
                title: Translation.tr("Nothing open")
                description: Translation.tr("Apps you open will show up here")
                sizeScale: 1.3
                descriptionHorizontalAlignment: Text.AlignHCenter
            }
        }

        // Which page of cards you are on. Only the grid has pages; the list has an order.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            visible: root.gridLayout && root.windowPages.length > 1

            Repeater {
                model: root.windowPages.length

                delegate: Rectangle {
                    required property int index
                    readonly property bool current: index === pager.currentIndex

                    implicitWidth: current ? 22 : 8
                    implicitHeight: 8
                    radius: height / 2
                    color: Appearance.colors.colOnLayer0
                    opacity: current ? 0.95 : 0.4

                    Behavior on implicitWidth {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            // A workspace with nothing on it is Android's "new window" — the way out of
            // recents that is not going back to something you already had.
            TabletRecentsActionPill {
                symbol: "add"
                pillHeight: Math.max(Appearance.sizes.minimumTouchTarget, 52)
                label: Translation.tr("New workspace")
                onTriggered: root.newWorkspace()
            }

            /**
             * Android's "Clear all", with the one difference that matters here.
             *
             * On Android this needs no confirmation because the apps behind it save their
             * own state; here it closes real editors with unsaved buffers in them. And an
             * undo is not available: a closed window cannot be reopened, so offering one
             * would be a lie. So the pill arms instead — the same second-deliberate-tap the
             * home screen's remove badge uses — and disarms itself if the tap does not come.
             */
            TabletRecentsActionPill {
                id: clearAllPill
                visible: root.windows.length > 0
                pillHeight: Math.max(Appearance.sizes.minimumTouchTarget, 52)
                symbol: clearAllPill.armed ? "warning" : "delete_sweep"
                accent: clearAllPill.armed
                label: clearAllPill.armed
                    ? Translation.tr("Close %1 apps?").arg(root.windows.length)
                    : Translation.tr("Clear all")

                property bool armed: false

                Timer {
                    id: disarmTimer
                    interval: 3500
                    onTriggered: clearAllPill.armed = false
                }

                onTriggered: {
                    if (!clearAllPill.armed) {
                        clearAllPill.armed = true;
                        disarmTimer.restart();
                        return;
                    }
                    disarmTimer.stop();
                    clearAllPill.armed = false;
                    root.closeAll();
                }

                // Nothing left to clear, and nothing left to confirm.
                Connections {
                    target: root
                    function onWindowsChanged() {
                        if (root.windows.length === 0)
                            clearAllPill.armed = false;
                    }
                }
            }
        }

        // The taskbar, so "not this one — something else" is one tap away. See the component
        // for why it is drawn here instead of letting the real dock show through.
        TabletRecentsDockRow {
            Layout.fillWidth: true
            onLaunchRequested: action => root.deferredRequested(action)
        }
    }

    // Drawn inside this surface rather than as a popup window, for the same reason the
    // drawer's menu is: recents holds exclusive keyboard focus, and a second surface would
    // fight it for something Android draws in the launcher itself.
    TabletInlineMenu {
        id: cardMenu
        anchors.fill: parent
    }

    Keys.onEscapePressed: {
        if (cardMenu.opened) {
            cardMenu.close();
            return;
        }
        root.dismissRequested();
    }
}
