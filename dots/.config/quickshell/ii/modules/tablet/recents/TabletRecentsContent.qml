pragma ComponentBehavior: Bound

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
 * The recents carousel: every open window as a card, scrubbed sideways.
 *
 * Deliberately not the ii overview. That is a grid of workspaces with their windows laid
 * out inside, which answers "where is everything"; this answers "what was I just doing",
 * which is a flat, most-recent-first list. Android keeps the two apart and so does this
 * family — the home screens are the workspaces, recents is this.
 */
Item {
    id: root

    property real revealProgress: 1

    signal dismissRequested
    /// Asks the host to close first and run this afterwards; see TabletRecentsWindow on why
    /// anything that changes focus cannot happen while this surface is still mapped.
    signal deferredRequested(var action)

    readonly property real cardWidth: Math.max(240, Math.min(460, Math.round(root.width * 0.26)))
    readonly property real cardHeight: Math.round(root.cardWidth * 0.68)
    readonly property real cardSpacing: Math.max(16, Math.round(root.cardWidth * 0.06))

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
     * Android puts these behind the app icon above the card; here the header strip is the
     * same handle. Float and fullscreen are the dispatches the gesture registry already
     * binds, so this is mostly wiring rather than new capability — the point is that a
     * finger had no way to reach any of it.
     *
     * The window has to be named by address: dispatching without one acts on whatever is
     * focused, which is never the card that was tapped.
     */
    function menuActionsFor(toplevel) {
        const address = String(toplevel?.HyprlandToplevel?.address ?? "").trim();
        const target = address.length === 0
            ? "" : (address.startsWith("0x") ? address : `0x${address}`);

        const actions = [];

        /**
         * "Split with the app you were in."
         *
         * Hyprland already tiles two windows that share a workspace, so a split is not a
         * layout this shell has to compute — it is a window that has to be somewhere else.
         * All this dispatches is a move; the compositor does the splitting, which is why the
         * shell does not grow a layout manager to offer the feature.
         *
         * Only offered when it would do something: the window has to be somewhere other than
         * the workspace you are returning to, and that workspace has to have something on it
         * to split *with* — otherwise this is a plain move wearing the wrong label.
         */
        const activeWorkspace = Number(HyprlandData.activeWorkspace?.id ?? -1);
        const onActiveWorkspace = root.workspaceOf(target) === activeWorkspace;
        const activeHasWindows = activeWorkspace !== -1
            && HyprlandData.hyprlandClientsForWorkspace(activeWorkspace).length > 0;

        if (target.length > 0 && activeWorkspace !== -1 && !onActiveWorkspace && activeHasWindows) {
            actions.push({
                symbol: "splitscreen",
                label: Translation.tr("Split with current app"),
                trigger: () => root.dispatchOn(target,
                    `hl.dsp.window.move({ workspace = ${activeWorkspace}, follow = false, window = "address:${target}" })`)
            });
        }

        if (target.length > 0) {
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

    /// Which workspace a window is on, or -1. The toplevel does not carry it; Hyprland's
    /// client list does, and the two are joined on the address as everywhere else here.
    function workspaceOf(address) {
        if (!address || address.length === 0)
            return -1;
        for (const client of (HyprlandData.windowList ?? [])) {
            const raw = String(client?.address ?? "").trim();
            if (raw.length === 0)
                continue;
            const normalized = raw.startsWith("0x") ? raw : `0x${raw}`;
            if (normalized === address)
                return Number(client?.workspace?.id ?? -1);
        }
        return -1;
    }

    /// Anything that moves or focuses a window has to wait for this surface to unmap; see
    /// TabletRecentsWindow on why running it while recents is still up is undone silently.
    function dispatchOn(address, command) {
        root.deferredRequested(() => {
            Hyprland.dispatch(command);
            Hyprland.dispatch(`hl.dsp.focus({ window = "address:${address}" })`);
        });
    }

    function newWorkspace() {
        // The Lua dispatcher API, as everything else in the shell uses; the classic
        // "workspace empty" string is a Lua syntax error here rather than a no-op. The host
        // runs it after this surface has gone — see TabletRecentsWindow.pendingDispatch.
        root.deferredRequested(() => Hyprland.dispatch("hl.dsp.focus({ workspace = 'empty' })"));
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.round(root.height * 0.06)
        spacing: 20

        opacity: root.revealProgress
        transform: Translate {
            y: (1 - root.revealProgress) * 40
        }

        // Takes the leftover height so the cards sit in the middle of the screen, with the
        // new-workspace pill pinned below them. The row itself stays card-height and is
        // centred inside, rather than stretching the cards to fill.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: carousel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Math.min(parent.height, root.cardHeight + 48)

                contentWidth: cardRow.implicitWidth
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.DragOverBounds
                clip: true

                // Inset so the first and last card are not welded to the bezel. Without it the
                // leftmost card — which is now the app you were just in — reads as clipped
                // rather than as the start of a row.
                leftMargin: root.cardSpacing
                rightMargin: root.cardSpacing

                // The most recent card is at index 0, so the useful position is the start.
                // A Flickable keeps its contentX, and this surface is rebuilt per open only as
                // long as nothing keeps it mapped — resetting on the way out costs nothing and
                // does not depend on that.
                Component.onCompleted: carousel.contentX = -carousel.leftMargin
                Connections {
                    target: root
                    function onRevealProgressChanged() {
                        if (root.revealProgress < 0.02)
                            carousel.contentX = -carousel.leftMargin;
                    }
                }

                RowLayout {
                    id: cardRow
                    height: carousel.height
                    spacing: root.cardSpacing

                    Repeater {
                        model: root.windows

                        delegate: TabletRecentCard {
                            required property var modelData
                            Layout.preferredWidth: root.cardWidth
                            Layout.preferredHeight: root.cardHeight
                            Layout.alignment: Qt.AlignVCenter
                            toplevel: modelData
                            onActivated: root.activate(modelData)
                            onClosed: root.closeWindow(modelData)
                            onMenuRequested: (x, y) => {
                                const point = root.mapFromItem(null, x, y);
                                cardMenu.openAt(point.x, point.y,
                                                root.menuActionsFor(modelData),
                                                modelData?.title ?? modelData?.appId ?? "",
                                                Quickshell.iconPath(TaskbarApps.getCachedIcon(modelData?.appId ?? ""), "image-missing"),
                                                "");
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

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            // A workspace with nothing on it is Android's "new window" — the way out of
            // recents that is not going back to something you already had.
            RecentsPill {
                symbol: "add"
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
            RecentsPill {
                id: clearAllPill
                visible: root.windows.length > 0
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
    }

    component RecentsPill: Rectangle {
        id: pill

        property string symbol: ""
        property string label: ""
        property bool accent: false

        signal triggered

        implicitWidth: pillRow.implicitWidth + 44
        implicitHeight: Math.max(Appearance.sizes.minimumTouchTarget, 52)
        radius: height / 2
        color: {
            if (pill.accent)
                return pillArea.pressed ? Appearance.colors.colErrorContainerActive : Appearance.colors.colErrorContainer;
            return pillArea.pressed ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1;
        }

        readonly property color contentColor: pill.accent
            ? Appearance.colors.colOnErrorContainer
            : Appearance.colors.colOnLayer1

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on implicitWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 10

            MaterialSymbol {
                text: pill.symbol
                iconSize: 22
                color: pill.contentColor
            }

            StyledText {
                text: pill.label
                font.pixelSize: Appearance.font.pixelSize.normal
                color: pill.contentColor
            }
        }

        MouseArea {
            id: pillArea
            anchors.fill: parent
            onClicked: pill.triggered()
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
