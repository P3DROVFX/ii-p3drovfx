pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The notes app as an ordinary application window.
 *
 * An xdg toplevel, not a layer-shell overlay. The first version was the latter — the shape
 * the Cheatsheet uses — and it was wrong for this: a layer surface floats above every
 * workspace, belongs to none of them, and is dismissed by a click anywhere outside it.
 * That is right for a reference card you glance at and close. It is not right for a place
 * you write in, where clicking another window to read something must not throw away what
 * you were looking at.
 *
 * As a toplevel the compositor owns it: it lives on a workspace, it is focused, moved,
 * resized, tiled and closed like any other program, and nothing here has to reimplement
 * any of that.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property var state: Persistent.states.notes
    readonly property bool aiBusy: content.aiBusy

    // The remembered size is the *initial* one. Where the window ends up afterwards is the
    // compositor's business now, which is the point of being a toplevel.
    title: "ii Notes"

    // Large by default. This is a document window: two panes of chrome and a page to
    // write on do not fit in the size a dialog gets.
    // The remembered size is in design pixels (1920x1080) and follows the screen the way
    // the zoomed content does, so the window keeps the same proportion on every monitor
    // instead of 1500x940 nearly filling a laptop. Capped below the screen either way, and
    // the size is the QML's alone: the Hyprland rule used to force 1500x940 over it.
    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080
    implicitWidth: Math.round(Math.min(root.screenWidth * 0.85,
        root.state.width * root.screenWidth / 1920))
    implicitHeight: Math.round(Math.min(root.screenHeight * 0.85,
        root.state.height * root.screenHeight / 1080))
    minimumSize: Qt.size(Math.min(720, Math.round(root.screenWidth * 0.6)),
        Math.min(480, Math.round(root.screenHeight * 0.6)))

    color: Appearance.colors.colLayer0
    visible: GlobalStates.notesAppOpen && !GlobalStates.screenLocked

    // Closed from the compositor — a titlebar button, a keybind, a workspace being wiped.
    // The shell's own state has to follow, or the next open would only toggle a flag that
    // was never cleared.
    onVisibleChanged: {
        if (!visible && !GlobalStates.screenLocked && GlobalStates.notesAppOpen)
            GlobalStates.notesAppOpen = false;
    }

    Component.onDestruction: {
        // Whatever is still in a debounce belongs to the user, and this window going away
        // is not a reason to lose it.
        NotesService.flush();
    }

    // Zoomed to fit a desktop smaller than the 1920x1080 design; see ScreenFitScale.
    ScreenFitScale {
        anchors.fill: parent
        focus: true
        screen: root.screen

        NotesAppContent {
            id: content
            anchors.fill: parent
            focus: true

            onCloseRequested: root.closeRequested()
        }
    }
}
