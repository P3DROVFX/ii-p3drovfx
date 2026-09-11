pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.ii.overview.typing
import qs.services

/**
 * The typing test as a hosted panel of the Overview search.
 *
 * All of the test lives in TypingTestSurface, which the cheatsheet page shows
 * too. This file is only the launcher's frame around it: the scaffold, the key
 * hint bar, and the focus/escape contract the search host calls into.
 *
 * The panel owns its own input (see `inputOwner` in SearchPanelRegistry), so
 * every keystroke inside it belongs to the test and never reaches the query.
 */
Item {
    id: root

    // Every motion in the overview and its panels answers to one switch:
    // Settings -> Overview -> Animation style -> None. The cheatsheet shows the
    // same surface and is not covered by it, so the flag is handed down from
    // here rather than read inside the shared components.
    readonly property bool animationsDisabled: Config.options.overview.animationStyle === "none"
    readonly property int panelWidth: Config.options.search.appearance.panelWidth
    Component.onCompleted: console.log("[PROBE] parentdir TypingLanguages =", typeof TypingLanguages, "TypingSoundPacks =", typeof TypingSoundPacks) // PROBE

    implicitWidth: root.panelWidth
    implicitHeight: scaffold.implicitHeight

    function focusInput() {
        return surface.focusInput();
    }

    function handleEscape() {
        return surface.handleEscape();
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        showHeader: false
        showStatus: surface.statusText.length > 0
        statusText: surface.statusText
        minimumContentHeight: Config.options.search.appearance.panelBodyHeight
        primaryHint: surface.primaryHint
        hints: surface.hints

        TypingTestSurface {
            id: surface
            anchors.fill: parent
            animationsDisabled: root.animationsDisabled
        }
    }
}
