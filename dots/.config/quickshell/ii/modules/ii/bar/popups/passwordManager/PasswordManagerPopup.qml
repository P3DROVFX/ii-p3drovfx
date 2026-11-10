import QtQuick
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.ii.bar.shared
import qs.services

/**
 * Passwords popup. Opens on hover like every other bar popup; click into it
 * to type (OnDemand keyboard), and it stays open while you type. From the
 * `passwordManager` IPC (a keybind) it takes the keyboard right away.
 */
StyledPopup {
    id: root
    popupId: "passwords"

    stickyHover: true
    popupRadius: Appearance.rounding.verylarge
    holdOpen: content.typing

    // rbw asks through its own pinentry window, which needs the keyboard.
    readonly property bool pinentryUp: PasswordManager.busyAction === "unlock" && !PasswordManager.needsPassword
    keyboardFocus: !root.opened || root.pinentryUp ? WlrKeyboardFocus.None
        : (root._ipcActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)

    // Type-to-search binds the bare letters on an empty workspace; those binds
    // win over any surface, so they have to go while this popup is up.
    onOpenedChanged: GlobalStates.barPopupTypingOpen = root.opened
    Component.onDestruction: GlobalStates.barPopupTypingOpen = false

    contentItem: PasswordManagerPopupContent {
        id: content
        opened: root.opened
        onRequestClose: root.close()
    }
}
