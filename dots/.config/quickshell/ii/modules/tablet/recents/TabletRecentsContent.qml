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

    Keys.onEscapePressed: root.dismissRequested()
}
