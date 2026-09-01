pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.modules.common

/**
 * Per-host page state for the Search AI surface.
 *
 * The navigator owns only navigation. It never owns transcript/session data,
 * which lets a second Search monitor or the sidebar keep a separate focus and
 * scroll anchor while both read the same Ai session.
 */
QtObject {
    id: root

    readonly property string rootPage: "chat"
    property string currentPage: root.rootPage
    property string incomingPage: ""
    property string outgoingPage: ""
    property int transitionDirection: 1
    property real transitionProgress: 1.0
    property bool transitioning: false
    property bool reducedMotion: Config.options.sidebar.ai.reducedMotion
    property bool pendingPop: false
    property list<string> pageStack: [root.rootPage]
    property var focusAnchors: ({})

    readonly property int activePageCount: {
        const pages = [];
        for (const page of [root.currentPage, root.incomingPage, root.outgoingPage]) {
            if (page.length > 0 && pages.indexOf(page) < 0)
                pages.push(page);
        }
        return pages.length;
    }

    readonly property bool canGoBack: root.pageStack.length > 1 || root.transitioning;

    signal pageTransitionStarted(string fromPage, string toPage, int direction)
    signal pageTransitionFinished(string page)
    signal focusRequested(string page)

    // QtObject has no visual/data default property. Keep the animation as an
    // explicit object property so the navigator can be instantiated safely
    // by AiSearchSurface (and so hot reload cannot discard a child silently).
    property NumberAnimation transitionAnimation: NumberAnimation {
        target: root
        property: "transitionProgress"
        from: 0
        to: 1
        duration: root.reducedMotion ? 0 : Appearance.animation.elementMove.duration
        easing.type: Appearance.animation.elementMove.type
        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        onFinished: root.finishTransition()
    }

    function hasPage(page) {
        return String(page ?? "").trim().length > 0;
    }

    function beginTransition(page, direction, popAfter) {
        const targetPage = String(page ?? "").trim();
        if (!root.hasPage(targetPage) || targetPage === root.currentPage && !root.transitioning)
            return false;

        root.transitionAnimation.stop();
        root.outgoingPage = root.currentPage;
        root.incomingPage = targetPage;
        root.transitionDirection = direction < 0 ? -1 : 1;
        root.pendingPop = popAfter;
        root.transitioning = true;
        root.transitionProgress = 0;
        root.pageTransitionStarted(root.outgoingPage, root.incomingPage, root.transitionDirection);

        if (root.reducedMotion) {
            root.transitionProgress = 1;
            root.finishTransition();
        } else {
            root.transitionAnimation.restart();
        }
        return true;
    }

    function push(page) {
        const targetPage = String(page ?? "").trim();
        if (!root.hasPage(targetPage) || targetPage === root.currentPage)
            return false;
        const nextStack = Array.from(root.pageStack);
        nextStack.push(targetPage);
        root.pageStack = nextStack;
        return root.beginTransition(targetPage, 1, false);
    }

    function replace(page) {
        const targetPage = String(page ?? "").trim();
        if (!root.hasPage(targetPage) || targetPage === root.currentPage)
            return false;
        const nextStack = Array.from(root.pageStack);
        nextStack[nextStack.length - 1] = targetPage;
        root.pageStack = nextStack;
        return root.beginTransition(targetPage, 1, false);
    }

    function back() {
        if (root.transitioning) {
            root.transitionAnimation.stop();
            root.incomingPage = root.outgoingPage;
            root.outgoingPage = root.currentPage;
            root.pendingPop = false;
            root.transitionDirection = -root.transitionDirection;
            root.transitionProgress = 0;
            root.transitioning = true;
            if (root.reducedMotion) {
                root.transitionProgress = 1;
                root.finishTransition();
            } else {
                root.transitionAnimation.restart();
            }
            return true;
        }
        if (root.pageStack.length <= 1)
            return false;
        const previousPage = root.pageStack[root.pageStack.length - 2];
        return root.beginTransition(previousPage, -1, true);
    }

    function handleEscape() {
        return root.back();
    }

    function finishTransition() {
        if (!root.transitioning)
            return;
        root.currentPage = root.incomingPage;
        root.outgoingPage = "";
        root.incomingPage = "";
        root.transitionProgress = 1;
        root.transitioning = false;
        if (root.pendingPop && root.pageStack.length > 1)
            root.pageStack = root.pageStack.slice(0, -1);
        root.pendingPop = false;
        root.pageTransitionFinished(root.currentPage);
        root.focusPage(root.currentPage);
    }

    function pageOffset(page) {
        const target = String(page ?? "");
        if (!root.transitioning)
            return 0;
        if (target === root.outgoingPage)
            return -root.transitionDirection * root.transitionProgress;
        if (target === root.incomingPage)
            return root.transitionDirection * (1 - root.transitionProgress);
        return 0;
    }

    function setFocusAnchor(page, target) {
        const next = Object.assign({}, root.focusAnchors);
        next[String(page ?? "")] = target;
        root.focusAnchors = next;
    }

    function clearFocusAnchor(page) {
        const next = Object.assign({}, root.focusAnchors);
        delete next[String(page ?? "")];
        root.focusAnchors = next;
    }

    function focusPage(page) {
        const target = root.focusAnchors[String(page ?? "")];
        root.focusRequested(String(page ?? ""));
        if (target && typeof target.forceActiveFocus === "function")
            Qt.callLater(target.forceActiveFocus);
    }
}
