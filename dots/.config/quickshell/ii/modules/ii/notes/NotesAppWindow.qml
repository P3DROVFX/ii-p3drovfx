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
    // Never past the screen: a size remembered on a bigger monitor (or a preset's) used to
    // open the window running off a laptop's edges.
    implicitWidth: Math.min(Math.round((root.screen?.width ?? 1920) * 0.95),
        Math.max(root.state.width, Math.round((root.screen?.width ?? 1920) * 0.72)))
    implicitHeight: Math.min(Math.round((root.screen?.height ?? 1080) * 0.9),
        Math.max(root.state.height, Math.round((root.screen?.height ?? 1080) * 0.78)))
    minimumSize: Qt.size(720, 480)

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
