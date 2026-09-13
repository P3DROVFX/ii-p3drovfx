pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets

/**
 * Inline page host for Search AI.
 *
 * The default child is the chat page. Future pages replace that child in the
 * same surface; they are not popup windows and do not create a second overlay.
 * Fixture pages intentionally stay small until the dedicated model/history/
 * tools commits migrate their real content.
 */
Item {
    id: root
    // Keep the host focusable so keyboard navigation remains local to Search.
    focus: true
    activeFocusOnTab: true
    property AiSearchNavigator navigator: AiSearchNavigator {}
    // Search and the sidebar transcript intentionally share this preference:
    // choosing less motion must not depend on which AI surface is open.
    property bool reducedMotion: Config.options.sidebar.ai.reducedMotion
    property string pageTitle: root.navigator.currentPage
    default property alias contentData: chatPage.data

    implicitWidth: chatPage.implicitWidth
    implicitHeight: chatPage.implicitHeight

    function navigateTo(page) {
        return root.navigator.push(page);
    }

    function replacePage(page) {
        return root.navigator.replace(page);
    }

    function handleEscape() {
        return root.navigator.handleEscape();
    }

    function pageOpacity(page) {
        const target = String(page ?? "");
        if (!root.navigator.transitioning)
            return root.navigator.currentPage === target ? 1 : 0;
        if (root.navigator.incomingPage === target)
            return root.navigator.transitionProgress;
        if (root.navigator.outgoingPage === target)
            return 1 - root.navigator.transitionProgress;
        return 0;
    }

    readonly property string activeSubpageId: {
        if (root.navigator.incomingPage.length > 0 && root.navigator.incomingPage !== "chat")
            return root.navigator.incomingPage;
        if (root.navigator.outgoingPage.length > 0 && root.navigator.outgoingPage !== "chat")
            return root.navigator.outgoingPage;
        if (root.navigator.currentPage !== "chat")
            return root.navigator.currentPage;
        return "";
    }

    Binding {
        target: root.navigator
        property: "reducedMotion"
        value: root.reducedMotion
    }

    Connections {
        target: root.navigator
        function onPageTransitionFinished(page) {
            const title = page === "chat" ? Translation.tr("AI chat") : page;
            AiAccessibilityAnnouncer.announce(Translation.tr("Opened %1").arg(title));
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (!root.handleEscape())
                return;
            event.accepted = true;
        } else if (event.key === Qt.Key_O && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
            Ai.newChat();
            root.navigator.replace("chat");
            event.accepted = true;
        }
    }

    Item {
        width: 1
        height: 1
        Accessible.name: AiAccessibilityAnnouncer.liveText
        Accessible.description: Translation.tr("AI Search status")
    }

    Item {
        id: chatPage
        anchors.fill: parent
        visible: root.pageOpacity("chat") > 0
        opacity: root.pageOpacity("chat")
        x: root.navigator.pageOffset("chat") * width
        clip: true

        Behavior on opacity {
            enabled: !root.reducedMotion
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
    }

    Loader {
        id: fixturePage
        anchors.fill: parent
        active: root.activeSubpageId.length > 0
        visible: active && root.pageOpacity(root.activeSubpageId) > 0
        opacity: root.pageOpacity(root.activeSubpageId)
        x: root.navigator.pageOffset(root.activeSubpageId) * width
        sourceComponent: AiSearchPage {
            pageId: root.activeSubpageId
            onRequestBack: root.navigator.back()
        }

        Behavior on opacity {
            enabled: !root.reducedMotion
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
    }
}
