pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Alt+Tab's peek: hold still on one window and the screen dims around a live picture of it,
 * drawn exactly where the window is - on its own monitor, at its own size, even when it
 * lives on another workspace. Nothing moves in the compositor while peeking, so Escape
 * leaves everything where it was; a release switches with animations off (WindowSwitcher)
 * underneath the peek, which then fades away over the real window in the same place.
 *
 * Its own click-through layer, ordered under the island and the panel (rules.lua), so the
 * switcher stays readable above it.
 */
Scope {
    id: root

    readonly property bool wanted: WindowSwitcher.peeking && WindowSwitcher.active && WindowSwitcher.peekEntry !== null
    /// Kept for the fade-out after the switcher itself has closed.
    property bool lingering: false

    onWantedChanged: {
        if (root.wanted) {
            lingerTimer.stop();
            root.lingering = false;
        } else if (peekLoader.item) {
            root.lingering = true;
            lingerTimer.restart();
        }
    }

    Timer {
        id: lingerTimer
        interval: Appearance.animation.elementMoveFast.duration + 120
        onTriggered: root.lingering = false
    }

    Loader {
        id: peekLoader
        active: WindowSwitcher.enabled && (root.wanted || root.lingering)

        sourceComponent: PanelWindow {
            id: peekWindow

            readonly property var entry: WindowSwitcher.peekEntry
            /// The window's own monitor, so the picture lands where the window really is.
            readonly property var monitor: (HyprlandData.monitors ?? []).find(m => Number(m?.id) === Number(peekWindow.entry?.monitor ?? -1))
                ?? (HyprlandData.monitors ?? []).find(m => String(m?.name ?? "") === WindowSwitcher.screenName) ?? null
            readonly property var targetScreen: Quickshell.screens.find(s => s.name === String(peekWindow.monitor?.name ?? ""))
                ?? Quickshell.screens.find(s => s.name === WindowSwitcher.screenName)
                ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

            screen: peekWindow.targetScreen
            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }
            exclusionMode: ExclusionMode.Ignore
            // Not quickshell:*, which rules.lua blurs wholesale; see the peek's rules there.
            WlrLayershell.namespace: "ii-alt-tab-peek"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            // Seen, never touched: the switcher's own surfaces keep the pointer.
            mask: Region {}

            /// Set a turn after mapping, so the first frame is the closed state and the entry animates.
            property bool entered: false
            Component.onCompleted: {
                peekWindow.slotA = peekWindow.entry;
                Qt.callLater(() => peekWindow.entered = true);
            }
            readonly property bool open: peekWindow.entered && root.wanted
            property real reveal: peekWindow.open ? 1 : 0
            Behavior on reveal {
                NumberAnimation {
                    duration: peekWindow.open ? Appearance.animation.elementMove.duration
                        : Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: peekWindow.open ? Appearance.animationCurves.emphasizedDecel
                        : Appearance.animationCurves.standard
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Appearance.m3colors.m3shadow
                opacity: 0.6 * peekWindow.reveal
            }

            // Two pictures trade places as the selection moves, so a new window fades in over
            // the last one instead of popping.
            property var slotA: null
            property var slotB: null
            property bool showA: true
            onEntryChanged: {
                if (!peekWindow.entry)
                    return;
                const current = peekWindow.showA ? peekWindow.slotA : peekWindow.slotB;
                if (current && current.address === peekWindow.entry.address) {
                    // The same window, moved or retitled.
                    if (peekWindow.showA)
                        peekWindow.slotA = peekWindow.entry;
                    else
                        peekWindow.slotB = peekWindow.entry;
                    return;
                }
                if (peekWindow.showA)
                    peekWindow.slotB = peekWindow.entry;
                else
                    peekWindow.slotA = peekWindow.entry;
                peekWindow.showA = !peekWindow.showA;
            }

            component PeekPicture: ClippingRectangle {
                id: picture
                required property var slotEntry
                required property bool current

                readonly property real originX: Number(peekWindow.monitor?.x ?? 0)
                readonly property real originY: Number(peekWindow.monitor?.y ?? 0)
                visible: picture.slotEntry !== null && picture.opacity > 0.001
                x: (picture.slotEntry?.x ?? 0) - picture.originX
                y: (picture.slotEntry?.y ?? 0) - picture.originY
                width: picture.slotEntry?.width ?? 0
                height: picture.slotEntry?.height ?? 0
                radius: picture.slotEntry?.fullscreen ? 0 : Appearance.rounding.windowRounding
                color: Appearance.colors.colLayer1
                opacity: (picture.current ? 1 : 0) * peekWindow.reveal
                scale: 0.97 + 0.03 * peekWindow.reveal
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standard
                    }
                }

                readonly property string iconPath: {
                    const _ = TaskbarApps.iconThemeRevision;
                    return Quickshell.iconPath(AppSearch.guessIcon(picture.slotEntry?.appClass ?? ""), "image-missing");
                }

                ScreencopyView {
                    id: screencopy
                    anchors.fill: parent
                    captureSource: picture.slotEntry?.toplevel ?? null
                    live: picture.current && peekWindow.open
                }

                // Until the first frame lands, and for windows that cannot be captured.
                Image {
                    anchors.centerIn: parent
                    visible: !screencopy.hasContent
                    source: picture.iconPath
                    width: Math.round(Math.min(128, parent.height * 0.3))
                    height: width
                    sourceSize: Qt.size(width, height)
                    asynchronous: true
                }
            }

            PeekPicture {
                slotEntry: peekWindow.slotA
                current: peekWindow.showA
            }
            PeekPicture {
                slotEntry: peekWindow.slotB
                current: !peekWindow.showA
            }
        }
    }
}
