pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.modules.common

Item {
    id: root

    property string currentPageId: "hello"
    property string previousPageId: ""
    property string incomingPageId: ""
    property string outgoingPageId: ""
    property int transitionDirection: 1
    property bool transitionRunning: false
    property bool transitionReady: false
    property bool nextButtonHovered: false
    property real navigationSafeArea: 84

    readonly property string currentNextLabel: {
        const pageLoader = root.loaderForPage(root.currentPageId);
        const page = pageLoader && pageLoader.item ? pageLoader.item : null;
        return page && page.nextLabel !== undefined
            ? page.nextLabel
            : WelcomePageRegistry.nextLabelFor(root.currentPageId);
    }
    readonly property string currentNextIcon: {
        const pageLoader = root.loaderForPage(root.currentPageId);
        const page = pageLoader && pageLoader.item ? pageLoader.item : null;
        return page && page.nextIcon !== undefined
            ? page.nextIcon
            : WelcomePageRegistry.nextIconFor(root.currentPageId);
    }

    readonly property real transitionOffset: WelcomeMotion.offsetFor(root.width)

    readonly property bool nestedPageOpen: {
        if (root.currentPageId !== "learn")
            return false;
        const pageLoader = root.loaderForPage(root.currentPageId);
        return (pageLoader && pageLoader.item && pageLoader.item.nestedPageOpen) === true;
    }

    signal pageChanged(string pageId)
    signal openSettingsPage(string pageId)
    signal openSettingsTarget(string pageId, string subPageId, string sectionId)
    signal openWifi()
    signal openBluetooth()
    signal openAudioOutput()
    signal trySidebar()
    signal trySearch()

    // Page content may intentionally overhang its body stage. The top-level
    // Welcome window remains the only clipping boundary for Pixel decorations.
    clip: false

    function pageIndex(pageId) {
        return WelcomePageRegistry.pageIndexById(pageId);
    }

    function loaderForPage(pageId) {
        const index = root.pageIndex(pageId);
        return index >= 0 ? pageLoaders.itemAt(index) : null;
    }

    function normalizePages() {
        for (let i = 0; i < pageLoaders.count; i++) {
            const pageLoader = pageLoaders.itemAt(i);
            if (!pageLoader)
                continue;
            const active = pageLoader.pageId === root.currentPageId;
            pageLoader.visualX = 0;
            pageLoader.visualOpacity = active ? 1 : 0;
            pageLoader.visualBlur = 0;
            pageLoader.visualScale = 1;
            pageLoader.visualVisible = active;
            pageLoader.visualEnabled = active;
        }
        root.incomingPageId = "";
        root.outgoingPageId = "";
        root.transitionReady = false;
        root.transitionRunning = false;
    }

    function reset() {
        transitionAnimation.stop();
        root.currentPageId = "hello";
        root.previousPageId = "";
        Qt.callLater(root.normalizePages);
    }

    function maybeStartTransition(pageLoader) {
        if (!root.transitionRunning || !pageLoader || pageLoader.pageId !== root.incomingPageId)
            return;
        if (pageLoader.status !== Loader.Ready)
            return;
        root.transitionReady = true;
        if (!WelcomeMotion.motionEnabled) {
            root.normalizePages();
            root.pageChanged(root.currentPageId);
            return;
        }
        pageLoader.visualOpacity = WelcomeMotion.pageOpacityIn;
        pageLoader.visualBlur = WelcomeMotion.blurProgress;
        pageLoader.visualScale = WelcomeMotion.pageScale;
        transitionAnimation.start();
    }

    function goToPage(pageId) {
        if (!pageId || root.transitionRunning || pageId === root.currentPageId || root.pageIndex(pageId) < 0)
            return;

        const fromIndex = root.pageIndex(root.currentPageId);
        const toIndex = root.pageIndex(pageId);
        root.previousPageId = root.currentPageId;
        root.transitionDirection = toIndex >= fromIndex ? 1 : -1;
        root.outgoingPageId = root.currentPageId;
        root.incomingPageId = pageId;
        root.transitionRunning = true;
        root.transitionReady = false;

        const outgoing = root.loaderForPage(root.outgoingPageId);
        const incoming = root.loaderForPage(root.incomingPageId);
        if (!outgoing || !incoming) {
            root.currentPageId = pageId;
            root.normalizePages();
            root.pageChanged(pageId);
            return;
        }

        outgoing.visualX = 0;
        outgoing.visualOpacity = 1;
        outgoing.visualBlur = 0;
        outgoing.visualScale = 1;
        outgoing.visualVisible = true;
        outgoing.visualEnabled = false;

        incoming.visualX = root.transitionDirection > 0 ? root.transitionOffset : -root.transitionOffset;
        incoming.visualOpacity = WelcomeMotion.pageOpacityIn;
        incoming.visualBlur = 0;
        incoming.visualScale = 1;
        incoming.visualVisible = true;
        incoming.visualEnabled = false;

        root.currentPageId = pageId;
        if (incoming.status === Loader.Error) {
            root.normalizePages();
            root.pageChanged(pageId);
            return;
        }
        if (incoming.status === Loader.Ready)
            Qt.callLater(() => root.maybeStartTransition(incoming));
    }

    function goPrevious() {
        if (root.currentPageLocksNavigation())
            return;
        const index = root.pageIndex(root.currentPageId);
        if (index > 0)
            root.goToPage(WelcomePageRegistry.pages[index - 1].id);
    }

    function goNext() {
        const index = root.pageIndex(root.currentPageId);
        if (index < 0 || index >= WelcomePageRegistry.pages.length - 1)
            return;

        const pageLoader = root.loaderForPage(root.currentPageId);
        const page = pageLoader && pageLoader.item ? pageLoader.item : null;
        if (page && page.prepareNext && !page.prepareNext())
            return;

        root.goToPage(WelcomePageRegistry.pages[index + 1].id);
    }

    function closeNestedPage(): bool {
        if (root.currentPageId !== "learn")
            return false;
        const pageLoader = root.loaderForPage(root.currentPageId);
        const page = pageLoader && pageLoader.item ? pageLoader.item : null;
        return page && page.closeNestedPage
            ? page.closeNestedPage()
            : false;
    }

    function skipCurrentPage(): void {
        if (root.currentPageLocksNavigation())
            return;
        if (root.currentPageId !== "keyboard")
            return;
        const index = root.pageIndex(root.currentPageId);
        if (index < 0 || index >= WelcomePageRegistry.pages.length - 1)
            return;
        root.goToPage(WelcomePageRegistry.pages[index + 1].id);
    }

    function currentPageLocksNavigation(): bool {
        const pageLoader = root.loaderForPage(root.currentPageId);
        const page = pageLoader && pageLoader.item ? pageLoader.item : null;
        return page && page.navigationLocked === true;
    }

    function openTutorial(tutorialId: string): void {
        if (!tutorialId)
            return;
        if (root.currentPageId !== "learn") {
            root.goToPage("learn");
            Qt.callLater(() => root.openTutorial(tutorialId));
            return;
        }
        const learnLoader = root.loaderForPage("learn");
        const learnPage = learnLoader && learnLoader.item ? learnLoader.item : null;
        if (learnPage && learnPage.openTutorial)
            learnPage.openTutorial(tutorialId);
    }

    Repeater {
        id: pageLoaders
        model: WelcomePageRegistry.pages

        delegate: Item {
            id: pageLayer
            required property var modelData
            required property int index

            readonly property string pageId: modelData.id
            readonly property var item: contentLoader.item
            readonly property int status: contentLoader.status
            property real visualX: 0
            property real visualOpacity: 0
            property real visualBlur: 0
            property real visualScale: 1
            property bool visualVisible: false
            property bool visualEnabled: false
            property bool active: root.currentPageId === pageId
                || root.incomingPageId === pageId
                || root.outgoingPageId === pageId

            width: root.width
            height: Math.max(0, root.height - (root.nestedPageOpen ? 0 : root.navigationSafeArea))
            x: visualX
            opacity: visualOpacity
            scale: visualScale
            visible: visualVisible
            enabled: visualEnabled
            z: pageId === root.incomingPageId
                ? 2
                : pageId === root.outgoingPageId
                    ? 1
                    : 0
            Loader {
                id: contentLoader
                anchors.fill: parent
                active: pageLayer.active
                asynchronous: true
                source: Qt.resolvedUrl(pageLayer.modelData.component)

                onLoaded: root.maybeStartTransition(pageLayer)
            }

            Binding {
                target: contentLoader.item
                property: "nextButtonHovered"
                value: root.nextButtonHovered
                when: contentLoader.status === Loader.Ready
                restoreMode: Binding.RestoreBinding
            }

            layer.enabled: visualBlur > 0.01 && WelcomeMotion.blurAllowed
            layer.effect: MultiEffect {
                blurEnabled: pageLayer.visualBlur > 0.01 && WelcomeMotion.blurAllowed
                blurMax: WelcomeMotion.blurMax
                blur: pageLayer.visualBlur
            }

            Connections {
                target: contentLoader.item
                ignoreUnknownSignals: true

                function onOpenSettingsPage(pageId) {
                    root.openSettingsPage(pageId);
                }

                function onOpenSettingsTarget(pageId, subPageId, sectionId) {
                    root.openSettingsTarget(pageId, subPageId, sectionId);
                }

                function onOpenTutorial(tutorialId) {
                    root.openTutorial(tutorialId);
                }

                function onOpenWifi() {
                    root.openWifi();
                }

                function onOpenBluetooth() {
                    root.openBluetooth();
                }

                function onOpenAudioOutput() {
                    root.openAudioOutput();
                }

                function onTrySidebar() {
                    root.trySidebar();
                }

                function onTrySearch() {
                    root.trySearch();
                }

                function onAdvanceRequested() {
                    if (pageLayer.pageId !== root.currentPageId || root.transitionRunning)
                        return;
                    const index = root.pageIndex(root.currentPageId);
                    if (index >= 0 && index < WelcomePageRegistry.pages.length - 1)
                        root.goToPage(WelcomePageRegistry.pages[index + 1].id);
                }
            }
        }
    }

    ParallelAnimation {
        id: transitionAnimation

        NumberAnimation {
            target: root.loaderForPage(root.outgoingPageId)
            property: "visualX"
            to: root.transitionDirection > 0 ? -root.transitionOffset : root.transitionOffset
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }

        NumberAnimation {
            target: root.loaderForPage(root.outgoingPageId)
            property: "visualOpacity"
            to: WelcomeMotion.pageOpacityOut
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }

        NumberAnimation {
            target: root.loaderForPage(root.incomingPageId)
            property: "visualX"
            to: 0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }

        NumberAnimation {
            target: root.loaderForPage(root.incomingPageId)
            property: "visualOpacity"
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }

        NumberAnimation {
            target: root.loaderForPage(root.outgoingPageId)
            property: "visualBlur"
            to: WelcomeMotion.blurProgress
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }

        NumberAnimation {
            target: root.loaderForPage(root.incomingPageId)
            property: "visualBlur"
            to: 0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }

        NumberAnimation {
            target: root.loaderForPage(root.outgoingPageId)
            property: "visualScale"
            to: WelcomeMotion.pageScale
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }

        NumberAnimation {
            target: root.loaderForPage(root.incomingPageId)
            property: "visualScale"
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }

        onFinished: {
            const completedPage = root.incomingPageId;
            root.normalizePages();
            root.pageChanged(completedPage);
        }
    }

    Component.onCompleted: root.reset()
}
