pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview.typing
import qs.services

/**
 * The typing test as a cheatsheet page.
 *
 * The test itself is TypingTestSurface — the exact component the Overview
 * search panel hosts — so the two are the same test rather than two copies of
 * it. This page only supplies the frame: the same margins the launcher gives
 * it, the same key hint bar, and the focus and Escape wiring the cheatsheet
 * expects from a page.
 */
Item {
    id: root

    property Item keyNavTarget: null
    readonly property bool isCurrentTab: {
        try {
            return swipeView.currentIndex === index;
        } catch (error) {
            return true;
        }
    }
    readonly property bool isTabActive: root.visible && root.isCurrentTab

    // The cheatsheet focuses the page; the test wants the focus on its own
    // input sink, or the first keystroke goes nowhere.
    onFocusChanged: focus => {
        if (focus)
            surface.focusInput();
    }
    onIsTabActiveChanged: {
        if (root.isTabActive)
            Qt.callLater(surface.focusInput);
    }

    // Escape closes an open settings or history page before it reaches the
    // cheatsheet and closes the whole overlay.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && surface.handleEscape())
            event.accepted = true;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        spacing: Appearance.sizes.elevationMargin / 2

        TypingTestSurface {
            id: surface
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        // Mirrors SearchPanelScaffold's footer so the page reads identically
        // to the launcher panel under the same settings.
        RowLayout {
            Layout.fillWidth: true
            visible: surface.statusText.length > 0
                || (Config.options.search.appearance.showKeyHintBar
                    && (surface.hints.length > 0 || Object.keys(surface.primaryHint).length > 0))

            StyledText {
                Layout.fillWidth: true
                visible: surface.statusText.length > 0
                text: surface.statusText
                elide: Text.ElideRight
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
            }

            Item {
                Layout.fillWidth: true
                visible: surface.statusText.length === 0
            }

            KeyHintBar {
                visible: Config.options.search.appearance.showKeyHintBar
                hints: surface.primaryHint.label
                    ? [surface.primaryHint].concat(surface.hints) : surface.hints
                showKeys: Config.options.search.appearance.showKeyHints
                surface: Appearance.colors.colSurfaceContainerHigh
                onSurface: Appearance.colors.colOnSurface
            }
        }
    }
}
