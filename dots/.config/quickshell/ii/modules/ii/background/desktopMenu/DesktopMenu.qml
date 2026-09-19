import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common

/**
 * The desktop right-click menu's surface: one per screen, built on that
 * screen's first open and then kept alive (unmapped) so the next open is a
 * remap, not a rebuild — the rebuild was the delay before the animation.
 *
 * Why a surface of its own: the menu is asked for from two windows - the
 * widget canvas when it is mapped, the wallpaper window when it is not - and
 * outside Edit Mode there is no chrome to draw it on. An Overlay surface is
 * the honest shape: a menu is a rare gesture, not a mode.
 *
 * The surface is the whole screen so a click anywhere else dismisses, and
 * takes keyboard focus while it is up so Escape does too.
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: menuLoader
            required property var modelData

            readonly property string screenName: modelData ? modelData.name : ""
            // The open flag stays true through the exit: the card plays its
            // way out and only then calls finishDesktopMenuClose. Beyond that,
            // the surface is KEPT ALIVE once this screen has used the menu:
            // building a PanelWindow plus a seven-row card and mapping a fresh
            // layershell surface was the dead time between the right-click and
            // the first frame of the animation. Hidden (unmapped), it costs a
            // small QML tree and no surface, no frame and no grabs; the next
            // open remaps and replays the enter.
            readonly property bool wanted: GlobalStates.desktopMenuOpen
                && GlobalStates.desktopMenuScreenName === menuLoader.screenName
            property bool everOpened: false
            active: menuLoader.wanted || menuLoader.everOpened
            onWantedChanged: { if (menuLoader.wanted) menuLoader.everOpened = true; }

            component: PanelWindow {
                id: menuWindow
                screen: menuLoader.modelData
                color: "transparent"
                // The whole open/close lifecycle is this one binding: the
                // window maps when the menu is wanted (and stays mapped
                // through the card's exit), unmaps the moment it is not.
                visible: menuLoader.wanted
                // A remap is the enter: replay the reveal (the scalar is at
                // 0 after the exit) and re-arm the click-to-dismiss guard,
                // which the last session left disarmed.
                onVisibleChanged: {
                    if (!visible)
                        return;
                    dismissGuard.armed = true;
                    menuCard.beginEnter();
                }
                WlrLayershell.namespace: "quickshell:desktopMenu"
                WlrLayershell.layer: WlrLayer.Overlay
                // Exclusive: a menu is modal for as long as it is up, and Escape must
                // reach it whichever window had focus before the right-click. Gated on
                // visibility: the kept-alive window must never hold the keyboard.
                WlrLayershell.keyboardFocus: menuWindow.visible
                    ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: 0
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onPressed: GlobalStates.closeDesktopMenu()
                }

                // The menu opens with its corner under the pointer, so the row it
                // opened on is already beneath the cursor. Until the pointer has
                // actually gone somewhere, a second click - either button - is the
                // user waving the menu away, not choosing that row; this sheet takes
                // it and dismisses. It stops mattering the moment the pointer moves,
                // and every following click reaches the card as usual.
                MouseArea {
                    id: dismissGuard
                    anchors.fill: parent
                    z: 100
                    readonly property real moveThreshold: 6
                    property bool armed: true
                    enabled: menuWindow.visible && dismissGuard.armed && !PanelFamily.touchFirst
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onPositionChanged: mouse => {
                        if (Math.abs(mouse.x - GlobalStates.desktopMenuX) <= dismissGuard.moveThreshold
                            && Math.abs(mouse.y - GlobalStates.desktopMenuY) <= dismissGuard.moveThreshold)
                            return;
                        dismissGuard.armed = false;
                    }
                    onPressed: mouse => {
                        if (Math.abs(mouse.x - GlobalStates.desktopMenuX) > dismissGuard.moveThreshold
                            || Math.abs(mouse.y - GlobalStates.desktopMenuY) > dismissGuard.moveThreshold) {
                            dismissGuard.armed = false;
                            mouse.accepted = false;
                            return;
                        }
                        GlobalStates.closeDesktopMenu();
                    }
                }

                Item {
                    anchors.fill: parent
                    focus: true
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            event.accepted = true;
                            GlobalStates.closeDesktopMenu();
                            return;
                        }
                        // Ctrl+V: the keyboard form of the Paste row. The
                        // card owns the probe and the guard; pasteNow is a
                        // no-op when the clipboard carries no file list.
                        if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                            event.accepted = true;
                            menuCard.pasteNow();
                        }
                    }
                }

                DesktopMenuCard {
                    id: menuCard
                    origin: GlobalStates.desktopMenuOrigin
                    closing: GlobalStates.desktopMenuClosing
                    x: Math.min(Math.max(GlobalStates.desktopMenuX, 8), menuWindow.width - width - 8)
                    y: Math.min(Math.max(GlobalStates.desktopMenuY, 8), menuWindow.height - height - 8)
                    onDismissRequested: GlobalStates.closeDesktopMenu()
                    onExitFinished: GlobalStates.finishDesktopMenuClose()
                }
            }
        }
    }
}
