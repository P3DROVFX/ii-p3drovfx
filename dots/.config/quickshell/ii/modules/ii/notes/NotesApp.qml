pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common

/**
 * The notes app: its lifecycle, its ways in, and nothing else.
 *
 * Same shape as the Cheatsheet, and for the same reason. This is a burst-use surface —
 * opened, used, closed — so the whole window tree is built when it is asked for and
 * released after the close animation, rather than every note staying resident for the life
 * of the shell.
 *
 * The ways in are deliberately many, because the app is only useful if capturing something
 * costs nothing: a keybind, an IPC call, a quick toggle, the game overlay, a desktop
 * widget. They all end at `GlobalStates.notesAppOpen`, which is the one piece of state
 * that says whether the window is up.
 */
Scope {
    id: root

    function requestOpen(noteId = ""): void {
        if (String(noteId ?? "").length > 0)
            GlobalStates.notesAppPendingNote = String(noteId);
        if (!GlobalStates.notesAppOpen)
            GlobalStates.notesAppOpen = true;
    }

    function requestClose(): void {
        GlobalStates.notesAppOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.notesAppOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    Loader {
        id: windowLoader
        // The window's own `visible` follows the same flag; the loader exists so the whole
        // tree — every note, every pane — is built when it is wanted and released when it
        // is not, rather than living for the lifetime of the shell.
        active: GlobalStates.notesAppOpen
        sourceComponent: NotesAppWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "notesToggle"
        description: "Toggles the notes app"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "notesOpen"
        description: "Opens the notes app"
        onPressed: root.requestOpen()
    }

    GlobalShortcut {
        name: "notesClose"
        description: "Closes the notes app"
        onPressed: root.requestClose()
    }

    IpcHandler {
        target: "notes"

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }

        /// Opens the app already showing one note. The id comes from `list`.
        function openNote(noteId: string): void {
            root.requestOpen(noteId);
        }

        /// A note from the outside — a script, a hotkey, another program. Capturing has to
        /// cost nothing, and opening a window first is not nothing.
        function capture(text: string): string {
            const result = NotesService.create("", String(text ?? ""), null);
            return result.ok ? "ok" : String(result.error ?? "failed");
        }

        /// Files a note away, by id. The counterpart of `capture`: a script that can make
        /// a note should be able to put one in the trash without a window open, and going
        /// through the service is the only way anything but the service should ever change
        /// the store.
        function trash(noteId: string): string {
            return NotesService.deleteNote(String(noteId ?? "")) ? "ok" : "unknownNote";
        }

        function list(): string {
            return NotesService.notes
                .map(note => `${note.id}\t${note.title}`)
                .join("\n");
        }
    }
}
