import QtQuick
import Quickshell
import qs.modules.common

/**
 * Read-only rich text for an email body that can be selected and copied
 * (drag, double-click, Ctrl+A / Ctrl+C). Links still open, and "copy:" links
 * copy their target.
 *
 * `interacting` is true while the pointer is over the text or a selection
 * drag is in progress, so the host can stop flickables from stealing the drag.
 */
TextEdit {
    id: root

    property string html: ""
    property color linkColor: Appearance.colors.colPrimary
    readonly property bool interacting: hover.hovered || press.active

    readOnly: true
    selectByMouse: true
    selectByKeyboard: true
    persistentSelection: false
    activeFocusOnPress: true
    textFormat: TextEdit.RichText
    wrapMode: TextEdit.Wrap
    renderType: Text.QtRendering
    selectionColor: Appearance.colors.colSecondaryContainer
    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
    font.hintingPreference: Font.PreferDefaultHinting

    // TextEdit has no linkColor: the rich text engine takes it from CSS.
    text: root.html.length > 0 ? "<style>a { color: " + root.linkColor + "; }</style>" + root.html : ""

    onLinkActivated: link => {
        if (link.startsWith("copy:"))
            Quickshell.clipboardText = link.substring(5);
        else
            Qt.openUrlExternally(link);
    }

    // Leaving the text drops the selection highlight, like a browser page
    // losing focus keeps no stale blue block behind.
    onActiveFocusChanged: {
        if (!activeFocus)
            root.deselect();
    }

    HoverHandler {
        id: hover
        cursorShape: root.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.IBeamCursor
    }

    // Passive: sees the press the TextEdit itself takes, without stealing it.
    PointHandler {
        id: press
        acceptedButtons: Qt.LeftButton
    }
}
