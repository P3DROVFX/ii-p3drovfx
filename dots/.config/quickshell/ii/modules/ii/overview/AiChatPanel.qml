pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.services.ai
import qs.services.ai.blocks
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarPolicies.aiChat
import qs.modules.common.functions
import qs.modules.ii.sidebarPolicies
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

/**
 * Floating Bubbles 3-rectangle AI Chat panel for Overview Search (Figma Prototype Design).
 *
 * 1. Top Header Rectangle:
 *    - Left: Brain shape icon ("network_intelligence", fill: 1) that switches to "arrow_back" on hover (returns to search)
 *    - Middle: AI Task Title (with clean fallback)
 *    - Right: History toggle & New Chat buttons (with fill: 1)
 *
 * 2. Middle Canvas Rectangle:
 *    - Hosts the transcript, history, model picker and keyboard shortcut page
 *      with the same fade + directional slide used by the sidebar AiChat
 *
 * 3. Bottom Composer Rectangle:
 *    - Multi-line keyboard-first prompt input, model selector pill, and send button
 */
Item {
    id: root

    signal requestBackToSearch()
    signal requestFocusComposer()
    signal requestSendMessage(string text)
    signal requestContinueInSidebar()

    // The Loader keeps this item alive for the fade-out.  Keep its shortcuts
    // scoped to the actual AI surface so a just-closed panel cannot swallow
    // the Escape that should close ordinary Search.
    property bool activeSurface: false
    // Assigned by SearchWidget while this panel is hosted in Overview. Keep
    // the signal fallback below so the panel remains embeddable elsewhere.
    property var searchHost: null
    focus: root.activeSurface
    property bool historyOpen: false
    property bool modelsOpen: false
    property bool shortcutsOpen: false
    property bool capabilitiesOpen: false
    property string loadingSessionId: ""

    onModelsOpenChanged: {
        if (root.modelsOpen) {
            root.historyOpen = false;
            root.shortcutsOpen = false;
            root.capabilitiesOpen = false;
        }
    }
    onHistoryOpenChanged: {
        if (root.historyOpen) {
            root.modelsOpen = false;
            root.shortcutsOpen = false;
            root.capabilitiesOpen = false;
            Ai.sessions.ensureLoaded();
        }
    }
    onShortcutsOpenChanged: {
        if (root.shortcutsOpen) {
            root.historyOpen = false;
            root.modelsOpen = false;
            root.capabilitiesOpen = false;
        }
    }
    onCapabilitiesOpenChanged: {
        if (root.capabilitiesOpen) {
            root.historyOpen = false;
            root.modelsOpen = false;
            root.shortcutsOpen = false;
        }
    }

    readonly property var orderedModels: {
        const models = Ai.catalog.modelIds.map(modelId => Ai.catalog.models[modelId]).filter(model => !!model);
        models.sort((first, second) => {
            const firstLocal = Ai.catalog.isModelLocal(first) ? 0 : 1;
            const secondLocal = Ai.catalog.isModelLocal(second) ? 0 : 1;
            if (firstLocal !== secondLocal)
                return firstLocal - secondLocal;
            return String(first.title ?? first.value ?? "").localeCompare(String(second.title ?? second.value ?? ""));
        });
        return models;
    }

    Component.onCompleted: {
        Ai.sessions.ensureLoaded();
        root.refreshVisibleMessageIds();
    }

    function refreshVisibleMessageIds() {
        const ids = Array.from(Ai.messageIDs ?? []);
        const byId = Ai.messageByID ?? ({});
        root.visibleMessageIds = ids.filter(id => {
            const message = byId[id];
            return message && message.role !== Ai.interfaceRole && Ai.isTranscriptEntry(id);
        });
    }

    Connections {
        target: Ai
        function onMessageIDsChanged() { root.refreshVisibleMessageIds(); }
        function onMessageByIDChanged() { root.refreshVisibleMessageIds(); }
    }

    Connections {
        target: Ai.sessions
        function onSessionOpened(session) {
            const openedId = String(session?.id ?? "");
            if (openedId.length === 0 || openedId !== root.loadingSessionId)
                return;
            root.loadingSessionId = "";
            root.historyOpen = false;
            Qt.callLater(root.focusComposer);
        }
        function onLoadFailed(operationId, sessionId, reason) {
            if (String(sessionId ?? "") !== root.loadingSessionId)
                return;
            root.loadingSessionId = "";
            Ai.submissionNotice = String(reason ?? Translation.tr("Unable to open that chat."));
        }
        function onOpenFailed(sessionId, reason) {
            if (String(sessionId ?? "") !== root.loadingSessionId)
                return;
            root.loadingSessionId = "";
            Ai.submissionNotice = String(reason ?? Translation.tr("Unable to open that chat."));
        }
    }

    onActiveSurfaceChanged: {
        if (root.activeSurface)
            Qt.callLater(root.focusComposer);
    }

    onFocusChanged: {
        if (root.focus && root.activeSurface)
            Qt.callLater(root.focusComposer);
    }
    property string pendingTrashId: ""

    readonly property real headerControlExtent: Math.round(Appearance.font.pixelSize.huge * 2)
    readonly property real headerControlPadding: Appearance.rounding.small
    readonly property real headerHeight: headerControlExtent + headerControlPadding * 2
    readonly property real canvasHeight: 380
    readonly property real composerHeight: headerControlExtent + headerControlPadding * 2
    readonly property real columnSpacing: Appearance.rounding.verysmall
    readonly property real pageSlideDistance: Appearance.font.pixelSize.huge * 1.5
    /**
     * What the transcript keeps clear of the surface's rounded corners. The
     * same measure the sidebar uses, so a bubble never looks like it is
     * overflowing the panel it sits in.
     */
    readonly property real transcriptInset: Appearance.rounding.small

    /** The hello on an empty chat, rolled fresh every time one appears. */
    property string emptyStateGreeting: ""

    function refreshEmptyStateGreeting() {
        root.emptyStateGreeting = AiTranscriptRegistry.greetingLine();
    }
    readonly property bool canvasViewOpen: root.historyOpen || root.modelsOpen || root.shortcutsOpen || root.capabilitiesOpen

    implicitWidth: 720
    implicitHeight: headerHeight + canvasHeight + composerHeight + columnSpacing * 2
    width: parent ? parent.width : implicitWidth
    height: implicitHeight

    function focusComposer() {
        composer.focusInput();
    }

    function navigateUp() {
        if (root.historyOpen) {
            sessionList.contentY = Math.max(0, sessionList.contentY - root.canvasHeight / 2);
            return;
        }
        if (root.modelsOpen) {
            modelList.contentY = Math.max(0, modelList.contentY - root.canvasHeight / 2);
            return;
        }
        if (root.shortcutsOpen) {
            shortcutSheetLoader.item?.navigateUp?.();
            return;
        }
        if (root.capabilitiesOpen) {
            capabilitiesSheetLoader.item?.navigateUp?.();
            return;
        }
        if (messageList.contentHeight > messageList.height)
            messageList.contentY = Math.max(0, messageList.contentY - messageList.height / 2);
    }

    function navigateDown() {
        if (root.historyOpen) {
            sessionList.contentY = Math.min(
                Math.max(0, sessionList.contentHeight - sessionList.height),
                sessionList.contentY + sessionList.height / 2);
            return;
        }
        if (root.modelsOpen) {
            modelList.contentY = Math.min(
                Math.max(0, modelList.contentHeight - modelList.height),
                modelList.contentY + modelList.height / 2);
            return;
        }
        if (root.shortcutsOpen) {
            shortcutSheetLoader.item?.navigateDown?.();
            return;
        }
        if (root.capabilitiesOpen) {
            capabilitiesSheetLoader.item?.navigateDown?.();
            return;
        }
        if (messageList.contentHeight > messageList.height)
            messageList.contentY = Math.min(messageList.contentHeight - messageList.height, messageList.contentY + messageList.height / 2);
    }

    function captureHandoffState() {
        const anchor = {
            messageId: "",
            offset: 0,
            following: messageList.following === true
        };
        if (messageList.count <= 0)
            return anchor;
        const probeY = Math.min(8, Math.max(0, messageList.height - 1));
        const index = messageList.indexAt(8, probeY);
        if (index < 0 || index >= root.visibleMessageIds.length)
            return anchor;
        anchor.messageId = String(root.visibleMessageIds[index] ?? "");
        const delegate = messageList.itemAtIndex(index);
        if (delegate)
            anchor.offset = Math.max(0, Number(delegate.y) - Number(messageList.contentY));
        return anchor;
    }

    function restoreHandoffAnchor(anchor) {
        const source = anchor && typeof anchor === "object" ? anchor : ({});
        if (source.following === true) {
            messageList.following = true;
            messageList.positionViewAtEnd();
            return true;
        }
        const anchorId = String(source.messageId ?? "");
        const index = root.visibleMessageIds.indexOf(anchorId);
        if (index < 0)
            return false;
        messageList.following = false;
        messageList.positionViewAtIndex(index, ListView.Beginning);
        const offset = Number(source.offset ?? 0);
        if (isFinite(offset) && offset > 0)
            messageList.contentY = Math.max(0, messageList.contentY - offset);
        return true;
    }

    function focusMessageTarget(messageId, anchor) {
        const targetId = String(messageId ?? "");
        const index = root.visibleMessageIds.indexOf(targetId);
        if (index < 0)
            return false;
        messageList.following = false;
        messageList.positionViewAtIndex(index, ListView.Center);
        const offset = Number(anchor?.offset ?? 0);
        if (isFinite(offset) && offset > 0)
            messageList.contentY = Math.max(0, messageList.contentY - offset);
        Qt.callLater(function() {
            const delegate = messageList.itemAtIndex(index);
            if (delegate && typeof delegate.forceActiveFocus === "function")
                delegate.forceActiveFocus();
            else
                messageList.forceActiveFocus();
        });
        return true;
    }

    function applySurfaceIntent(intent) {
        if (!intent)
            return false;
        const hasExplicitTarget = String(intent.messageId ?? "").length > 0 || String(intent.blockId ?? "").length > 0;
        if (hasExplicitTarget) {
            const targetId = Ai.surfaceRouter.resolveTargetMessageId(intent);
            return root.focusMessageTarget(targetId, intent.scrollAnchor);
        }
        const anchor = intent.scrollAnchor ?? ({});
        const hasAnchor = String(anchor.messageId ?? "").length > 0 || anchor.following === true;
        if (hasAnchor && !root.restoreHandoffAnchor(anchor))
            return false;
        if (String(intent.focusIntent ?? "composer") === "composer")
            root.focusComposer();
        return hasAnchor || String(intent.focusIntent ?? "composer") === "composer";
    }

    function handleEscape() {
        if (root.shortcutsOpen) {
            root.shortcutsOpen = false;
            root.focusComposer();
            return true;
        }
        if (root.capabilitiesOpen) {
            root.capabilitiesOpen = false;
            root.focusComposer();
            return true;
        }
        if (root.historyOpen) {
            root.historyOpen = false;
            return true;
        }
        if (root.modelsOpen) {
            root.modelsOpen = false;
            return true;
        }
        return false;
    }

    function openShortcuts() {
        root.shortcutsOpen = true;
        Qt.callLater(function() {
            if (root.shortcutsOpen)
                shortcutsBackButton.forceActiveFocus();
        });
    }

    /** The tool catalog and example prompts — the same canvas as "Keys". */
    function openCapabilities() {
        root.capabilitiesOpen = true;
        Qt.callLater(function() {
            if (root.capabilitiesOpen)
                capabilitiesBackButton.forceActiveFocus();
        });
    }

    function handleComposerEscape() {
        if (!root.handleEscape())
            root.returnToSearch();
    }

    function returnToSearch() {
        const host = root.searchHost;
        if (host && typeof host.exitAiMode === "function") {
            host.exitAiMode();
            return;
        }
        root.requestBackToSearch();
    }

    function openSession(sessionId: string) {
        const id = String(sessionId ?? "").trim();
        if (id.length === 0)
            return;
        root.loadingSessionId = id;
        Ai.openSession(id);
    }

    function focusNext() {
        if (root.shortcutsOpen) {
            shortcutsBackButton.forceActiveFocus();
            return;
        }
        if (root.capabilitiesOpen) {
            capabilitiesBackButton.forceActiveFocus();
            return;
        }
        if (brainBackButton.activeFocus)
            historyToggleBtn.forceActiveFocus();
        else if (historyToggleBtn.activeFocus)
            newChatBtn.forceActiveFocus();
        else if (newChatBtn.activeFocus)
            composer.focusInput();
        else
            composer.focusFirstButton();
    }

    function focusPrev() {
        if (root.shortcutsOpen) {
            shortcutsBackButton.forceActiveFocus();
            return;
        }
        if (root.capabilitiesOpen) {
            capabilitiesBackButton.forceActiveFocus();
            return;
        }
        if (brainBackButton.activeFocus)
            composer.focusLastButton();
        else if (newChatBtn.activeFocus)
            historyToggleBtn.forceActiveFocus();
        else if (historyToggleBtn.activeFocus)
            brainBackButton.forceActiveFocus();
        else
            brainBackButton.forceActiveFocus();
    }

    property var visibleMessageIds: []

    // This panel is a parent of the focused composer and header controls.
    // Capture Esc first so a child cannot send focus to the background before
    // the AI surface has a chance to return to normal Search.
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => {
        if (!root.activeSurface)
            return;
        if (event.text === "?" && String(Ai.draft ?? "").trim().length === 0) {
            root.openShortcuts();
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_L) {
            root.historyOpen = !root.historyOpen;
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_M) {
            root.modelsOpen = !root.modelsOpen;
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_J) {
            root.requestContinueInSidebar();
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_I) {
            root.openCapabilities();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            if (!root.handleEscape())
                root.returnToSearch();
            event.accepted = true;
        } else if (root.canvasViewOpen && (event.key === Qt.Key_Up || event.key === Qt.Key_PageUp)) {
            root.navigateUp();
            event.accepted = true;
        } else if (root.canvasViewOpen && (event.key === Qt.Key_Down || event.key === Qt.Key_PageDown)) {
            root.navigateDown();
            event.accepted = true;
        } else if (event.key === Qt.Key_Tab) {
            if (event.modifiers & Qt.ShiftModifier)
                root.focusPrev();
            else
                root.focusNext();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backtab) {
            root.focusPrev();
            event.accepted = true;
        } else if (event.key === Qt.Key_O && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
            Ai.newChat();
            root.historyOpen = false;
            root.shortcutsOpen = false;
            root.capabilitiesOpen = false;
        }
    }

    ColumnLayout {
        id: chatColumn
        anchors.fill: parent
        spacing: root.columnSpacing

        // ════════════════════════════════════════════════════════
        // 1. TOP HEADER RECTANGLE
        // ════════════════════════════════════════════════════════

        Rectangle {
            id: headerSurface
            Layout.fillWidth: true
            implicitHeight: root.headerHeight
            Layout.preferredHeight: root.headerHeight
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.full
            clip: true

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: root.headerControlPadding
                spacing: Appearance.rounding.verysmall

                // Brain shape button (switches to back arrow on hover)
                RippleButton {
                    id: brainBackButton
                    implicitWidth: root.headerControlExtent
                    implicitHeight: root.headerControlExtent
                    buttonRadius: Appearance.rounding.full
                    focusPolicy: Qt.StrongFocus
                    colBackground: brainBackButton.activeFocus
                        ? Appearance.colors.colLayer2Active
                        : (brainBackButton.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: root.returnToSearch()

                    Accessible.name: Translation.tr("Back to search")

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Space || event.key === Qt.Key_Enter) {
                            root.returnToSearch();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            root.returnToSearch();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            if (event.modifiers & Qt.ShiftModifier)
                                newChatBtn.forceActiveFocus();
                            else
                                root.focusComposer();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backtab) {
                            newChatBtn.forceActiveFocus();
                            event.accepted = true;
                        }
                    }

                    contentItem: MaterialSymbol {
                        text: (brainBackButton.hovered || brainBackButton.activeFocus) ? "arrow_back" : "network_intelligence"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.larger
                        color: (brainBackButton.hovered || brainBackButton.activeFocus) ? Appearance.m3colors.m3primary : Appearance.colors.colOnLayer1
                    }

                    StyledToolTip {
                        text: Translation.tr("Back to search (Esc)")
                    }
                }

                // AI Task Title
                StyledText {
                    id: taskTitleText
                    Layout.fillWidth: true
                    Layout.leftMargin: Appearance.rounding.verysmall
                    Layout.rightMargin: Appearance.rounding.verysmall
                    text: {
                        const title = Ai.sessions?.currentTitle?.trim()
                            || Ai.sessions?.titleFor?.(Ai.sessions?.currentId ?? "")?.trim()
                            || "";
                        return title.length > 0 ? title : Translation.tr("New conversation");
                    }
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    font.variableAxes: Appearance.font.variableAxes.main
                    color: Appearance.colors.colOnLayer1
                }

                // Right action toggles: History & New Chat
                RowLayout {
                    spacing: Appearance.rounding.verysmall

                    RippleButton {
                        id: historyToggleBtn
                        implicitWidth: root.headerControlExtent
                        implicitHeight: root.headerControlExtent
                        buttonRadius: Appearance.rounding.full
                        focusPolicy: Qt.StrongFocus
                        toggled: root.historyOpen
                        colBackground: historyToggleBtn.activeFocus
                            ? (root.historyOpen ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active)
                            : (root.historyOpen ? Appearance.colors.colPrimary : Appearance.colors.colLayer2)
                        colBackgroundHover: root.historyOpen ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: root.historyOpen = !root.historyOpen

                        Accessible.name: Translation.tr("History")

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Space || event.key === Qt.Key_Enter) {
                                root.historyOpen = !root.historyOpen;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.focusComposer();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab) {
                                if (event.modifiers & Qt.ShiftModifier)
                                    composer.focusLastButton();
                                else
                                    newChatBtn.forceActiveFocus();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Backtab) {
                                composer.focusLastButton();
                                event.accepted = true;
                            }
                        }

                        contentItem: MaterialSymbol {
                            text: "history"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.larger
                            color: root.historyOpen ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: Translation.tr("History (Ctrl+L)")
                        }
                    }

                    RippleButton {
                        id: newChatBtn
                        implicitWidth: root.headerControlExtent
                        implicitHeight: root.headerControlExtent
                        buttonRadius: Appearance.rounding.full
                        focusPolicy: Qt.StrongFocus
                        colBackground: newChatBtn.activeFocus
                            ? Appearance.colors.colLayer2Active
                            : (newChatBtn.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: {
                            Ai.newChat();
                            root.historyOpen = false;
                            root.shortcutsOpen = false;
                            root.capabilitiesOpen = false;
                            root.requestFocusComposer();
                        }

                        Accessible.name: Translation.tr("New chat")

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Space || event.key === Qt.Key_Enter) {
                                Ai.newChat();
                                root.historyOpen = false;
                                root.shortcutsOpen = false;
                                root.capabilitiesOpen = false;
                                root.focusComposer();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.focusComposer();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab) {
                                if (event.modifiers & Qt.ShiftModifier)
                                    historyToggleBtn.forceActiveFocus();
                                else
                                    brainBackButton.forceActiveFocus();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Backtab) {
                                historyToggleBtn.forceActiveFocus();
                                event.accepted = true;
                            }
                        }

                        contentItem: MaterialSymbol {
                            text: "add_comment"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.larger
                            color: newChatBtn.activeFocus ? Appearance.m3colors.m3primary : Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: Translation.tr("New chat (Ctrl+Shift+O)")
                        }
                    }
                }
            }
        }

        // ════════════════════════════════════════════════════════
        // 2. MIDDLE CANVAS RECTANGLE (Messages & History)
        // ════════════════════════════════════════════════════════

        Rectangle {
            id: canvasSurface
            Layout.fillWidth: true
            Layout.preferredHeight: root.canvasHeight
            implicitHeight: root.canvasHeight
            Layout.minimumHeight: 180
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.large
            clip: true

            MouseArea {
                anchors.fill: parent
                onClicked: root.focusComposer()
            }

            // Messages view (Transcript & Starters)
            Item {
                id: messagesView
                anchors.fill: parent
                opacity: root.canvasViewOpen ? 0.0 : 1.0
                visible: opacity > 0.001
                transform: Translate {
                    id: messagesViewSlide
                    x: root.canvasViewOpen ? -root.pageSlideDistance : 0

                    // Animate Translate.x, not the transform list itself.
                    // The latter is an object and cannot be interpolated
                    // reliably, which made the old page transitions snap.
                    Behavior on x {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }
                // The same empty state the sidebar shows, down to the line
                // that greets the reader: it is rolled by the shared registry
                // so the two surfaces cannot drift apart again.
                PagePlaceholder {
                    id: emptyStatePlaceholder
                    z: 2
                    shown: root.visibleMessageIds.length === 0
                    icon: Ai.currentPersona?.icon ?? "neurology"
                    title: {
                        const personaName = Ai.currentPersona?.name;
                        if (personaName)
                            return personaName;
                        return root.emptyStateGreeting.length > 0 ? root.emptyStateGreeting : Translation.tr("Hello");
                    }
                    description: Ai.currentPersona?.description ?? Translation.tr("Ask anything")
                    shape: MaterialShape.Shape.PixelCircle
                    animateIconOnShow: true
                    Component.onCompleted: root.refreshEmptyStateGreeting()

                    onShownChanged: {
                        if (emptyStatePlaceholder.shown)
                            root.refreshEmptyStateGreeting();
                    }
                }

                RowLayout {
                    id: emptyStateHints
                    z: 3
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Appearance.rounding.normal
                    spacing: Appearance.rounding.verysmall
                    visible: root.visibleMessageIds.length === 0 && !root.canvasViewOpen

                    RippleButton {
                        id: shortcutsHint
                        implicitHeight: root.headerControlExtent
                        implicitWidth: shortcutsHintContent.implicitWidth + Appearance.rounding.normal * 2
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colBackgroundActive: Appearance.colors.colLayer2Active
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: root.openShortcuts()

                        Accessible.name: Translation.tr("Keyboard shortcuts")

                        contentItem: RowLayout {
                            id: shortcutsHintContent
                            spacing: Appearance.rounding.verysmall

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "keyboard"
                                fill: 1
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: Translation.tr("Keyboard shortcuts")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: Math.max(
                                    Appearance.font.pixelSize.small + Appearance.rounding.small,
                                    Appearance.font.pixelSize.huge * 0.65)
                                implicitHeight: Appearance.font.pixelSize.huge
                                radius: Appearance.rounding.verysmall
                                color: Appearance.colors.colLayer3

                                StyledText {
                                    anchors.centerIn: parent
                                    text: "?"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer3
                                }
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Keyboard shortcuts (?)")
                        }
                    }

                    RippleButton {
                        id: capabilitiesHint
                        implicitHeight: root.headerControlExtent
                        implicitWidth: capabilitiesHintContent.implicitWidth + Appearance.rounding.normal * 2
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colBackgroundActive: Appearance.colors.colLayer2Active
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: root.openCapabilities()

                        Accessible.name: Translation.tr("What this chat can do")

                        contentItem: RowLayout {
                            id: capabilitiesHintContent
                            spacing: Appearance.rounding.verysmall

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "auto_awesome"
                                fill: 1
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: Translation.tr("What this chat can do")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Capabilities and example prompts (Ctrl+I)")
                        }
                    }
                }

                ScrollEdgeFade {
                    // The same soft ends the sidebar transcript has: they
                    // appear only when there is something past them, and the
                    // band blurs before it fades.
                    z: 1
                    target: messageList
                    vertical: true
                    blurEdges: true
                    fadeSize: Math.round(Appearance.font.pixelSize.huge * 1.6)
                    color: Appearance.colors.colLayer1
                }

                // Messages list
                StyledListView {
                    id: messageList
                    z: 0
                    anchors.fill: parent
                    anchors.leftMargin: root.transcriptInset
                    anchors.rightMargin: root.transcriptInset
                    clip: true
                    spacing: Appearance.rounding.small
                    topMargin: root.transcriptInset
                    bottomMargin: root.transcriptInset
                    popin: false
                    animateAppearance: false
                    boundsBehavior: Flickable.StopAtBounds
                    visible: root.visibleMessageIds.length > 0
                    model: ScriptModel {
                        values: root.visibleMessageIds
                    }

                    /**
                     * Following the end is a decision about direction, not
                     * distance: any move upward hands the view to the reader
                     * and nothing pulls it back until they return to the end
                     * themselves. Copied deliberately from the sidebar, which
                     * is where this behaviour was got right.
                     */
                    property bool following: true
                    property bool pinning: false
                    property real previousContentY: 0
                    readonly property real followThreshold: Appearance.rounding.large
                    readonly property real bottomGap: Math.max(0, messageList.originY + messageList.contentHeight - messageList.height - messageList.contentY)
                    readonly property real maximumContentY: Math.max(messageList.originY - messageList.topMargin,
                        messageList.originY + messageList.contentHeight - messageList.height + messageList.bottomMargin)

                    function pinToEnd() {
                        messageList.following = true;
                        messageList.pinning = true;
                        messageList.contentY = messageList.maximumContentY;
                        messageList.previousContentY = messageList.contentY;
                        pinReleaseTimer.restart();
                    }

                    Timer {
                        id: pinReleaseTimer
                        interval: Appearance.animation.scroll.duration + 80
                        onTriggered: messageList.pinning = false
                    }

                    onUserScrolled: (targetY, maxY) => {
                        messageList.pinning = false;
                        if (targetY < messageList.previousContentY - 0.5) {
                            messageList.following = false;
                            return;
                        }
                        messageList.following = (maxY - targetY) <= messageList.followThreshold;
                    }

                    onDraggingChanged: {
                        if (messageList.dragging)
                            messageList.pinning = false;
                    }

                    onMovementEnded: messageList.following = messageList.bottomGap <= messageList.followThreshold

                    onContentYChanged: {
                        const previous = messageList.previousContentY;
                        messageList.previousContentY = messageList.contentY;
                        if (messageList.pinning)
                            return;
                        if (messageList.contentY < previous - 0.5) {
                            messageList.following = false;
                            return;
                        }
                        messageList.following = messageList.bottomGap <= messageList.followThreshold;
                    }

                    onContentHeightChanged: {
                        if (!messageList.following)
                            return;
                        Qt.callLater(function () {
                            messageList.pinToEnd();
                        });
                    }

                    onCountChanged: {
                        if (!messageList.following)
                            return;
                        Qt.callLater(function () {
                            messageList.pinToEnd();
                        });
                    }

                    onHeightChanged: {
                        if (messageList.following)
                            Qt.callLater(function () {
                                messageList.pinToEnd();
                            });
                    }

                    delegate: AiMessage {
                        // The same turn the sidebar draws, in its compact
                        // density. There used to be a second implementation
                        // here, and the two had already drifted apart.
                        id: messageDelegate
                        required property string modelData
                        required property int index
                        width: messageList.width
                        density: "compact"
                        messageId: modelData
                        messageData: Ai.messageByID[modelData]
                        onRegenerateRequested: id => Ai.regenerate(id)
                        onModelPickerRequested: root.modelsOpen = true
                    }
                }
            }

            // Inlined Session History view
            Item {
                id: historyView
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 0
                anchors.bottomMargin: 0
                opacity: root.historyOpen ? 1.0 : 0.0
                visible: opacity > 0.001
                transform: Translate {
                    id: historyViewSlide
                    x: root.historyOpen ? 0 : root.pageSlideDistance

                    Behavior on x {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                    }
                }

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(historyView)
                }

                // Empty history placeholder
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Appearance.rounding.verysmall
                    visible: (Ai.sessions.index ?? []).length === 0

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "history"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("No conversation history")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                }

                ListView {
                    id: sessionList
                    anchors.fill: parent
                    clip: false
                    spacing: Appearance.rounding.verysmall
                    topMargin: Appearance.rounding.normal
                    bottomMargin: Appearance.rounding.normal
                    visible: (Ai.sessions.index ?? []).length > 0
                    model: Ai.sessions.index ?? []

                    header: Item {
                        width: sessionList.width
                        implicitHeight: headerRow.implicitHeight + 12
                        height: implicitHeight

                        RowLayout {
                            id: headerRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 0
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4

                            StyledText {
                                text: Translation.tr("Conversations")
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }

                            Item { Layout.fillWidth: true }

                            StyledText {
                                text: Translation.tr("%1 sessions").arg((Ai.sessions.index ?? []).length)
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    delegate: Item {
                        id: sessionRow
                        required property var modelData
                        width: sessionList.width
                        implicitHeight: root.headerControlExtent
                        height: implicitHeight

                        readonly property bool isActive: sessionRow.modelData?.id === Ai.sessions.currentId

                        RowLayout {
                            anchors.fill: parent
                            spacing: Appearance.rounding.verysmall

                            // Main Conversation Info Card
                            RippleButton {
                                id: sessionCard
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                buttonRadius: Appearance.rounding.full
                                toggled: sessionRow.isActive
                                colBackground: sessionRow.isActive ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                                colBackgroundHover: sessionRow.isActive ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                colBackgroundToggled: Appearance.colors.colPrimary
                                colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                                colBackgroundToggledActive: Appearance.colors.colPrimaryActive

                                onClicked: {
                                    root.openSession(sessionRow.modelData.id);
                                }

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Appearance.rounding.normal
                                    anchors.rightMargin: Appearance.rounding.normal
                                    spacing: Appearance.rounding.small

                                    MaterialSymbol {
                                        text: "chat_bubble"
                                        fill: 1
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: sessionRow.isActive ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: sessionRow.modelData.title || Translation.tr("Untitled chat")
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.DemiBold
                                        color: sessionRow.isActive ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Right Circle Arrow Button
                            RippleButton {
                                id: openSessionBtn
                                implicitWidth: root.headerControlExtent
                                implicitHeight: root.headerControlExtent
                                Layout.preferredWidth: root.headerControlExtent
                                Layout.preferredHeight: root.headerControlExtent
                                buttonRadius: Appearance.rounding.full
                                toggled: sessionRow.isActive
                                colBackground: sessionRow.isActive ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                                colBackgroundHover: sessionRow.isActive ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                colBackgroundToggled: Appearance.colors.colPrimary
                                colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                                colBackgroundToggledActive: Appearance.colors.colPrimaryActive

                                onClicked: {
                                    root.openSession(sessionRow.modelData.id);
                                }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "arrow_forward"
                                    fill: 1
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: sessionRow.isActive ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                                }

                                StyledToolTip {
                                    text: Translation.tr("Open chat")
                                }
                            }
                        }
                    }
                }
            }

            // Inlined Models view (Identical design to historyView)
            Item {
                id: modelsView
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 0
                anchors.bottomMargin: 0
                opacity: root.modelsOpen ? 1.0 : 0.0
                visible: opacity > 0.001
                transform: Translate {
                    id: modelsViewSlide
                    x: root.modelsOpen ? 0 : root.pageSlideDistance

                    Behavior on x {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                    }
                }

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(modelsView)
                }

                // Empty models placeholder
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Appearance.rounding.verysmall
                    visible: root.orderedModels.length === 0

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "smart_toy"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("No models available")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                }

                ListView {
                    id: modelList
                    anchors.fill: parent
                    clip: false
                    spacing: Appearance.rounding.verysmall
                    topMargin: Appearance.rounding.normal
                    bottomMargin: Appearance.rounding.normal
                    visible: root.orderedModels.length > 0
                    model: root.orderedModels

                    header: Item {
                        width: modelList.width
                        implicitHeight: modelHeaderRow.implicitHeight + 12
                        height: implicitHeight

                        RowLayout {
                            id: modelHeaderRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 0
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4

                            StyledText {
                                text: Translation.tr("Models")
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }

                            Item { Layout.fillWidth: true }

                            StyledText {
                                text: Translation.tr("%1 models").arg(root.orderedModels.length)
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    delegate: Item {
                        id: modelRow
                        required property var modelData
                        width: modelList.width
                        implicitHeight: root.headerControlExtent
                        height: implicitHeight

                        readonly property bool isActive: modelRow.modelData?.id === Ai.currentModelId

                        RowLayout {
                            anchors.fill: parent
                            spacing: Appearance.rounding.verysmall

                            // Main Model Info Card
                            RippleButton {
                                id: modelCard
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                buttonRadius: Appearance.rounding.full
                                toggled: modelRow.isActive
                                colBackground: modelRow.isActive ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                                colBackgroundHover: modelRow.isActive ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                colBackgroundToggled: Appearance.colors.colPrimary
                                colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                                colBackgroundToggledActive: Appearance.colors.colPrimaryActive

                                onClicked: {
                                    Ai.setModel(modelRow.modelData.id, false);
                                    root.modelsOpen = false;
                                    root.requestFocusComposer();
                                }

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Appearance.rounding.normal
                                    anchors.rightMargin: Appearance.rounding.normal
                                    spacing: Appearance.rounding.small

                                    Loader {
                                        Layout.alignment: Qt.AlignVCenter
                                        active: (modelRow.modelData.icon ?? "").length > 0
                                        visible: active
                                        sourceComponent: CustomIcon {
                                            source: modelRow.modelData.icon ?? ""
                                            width: Appearance.font.pixelSize.larger
                                            height: Appearance.font.pixelSize.larger
                                            colorize: true
                                            color: modelRow.isActive ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                                        }
                                    }

                                    MaterialSymbol {
                                        visible: !(modelRow.modelData.icon ?? "").length
                                        text: modelRow.modelData.materialIcon ?? "auto_awesome"
                                        fill: 1
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: modelRow.isActive ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelRow.modelData.title || modelRow.modelData.name || modelRow.modelData.value || Translation.tr("Unknown model")
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.DemiBold
                                        color: modelRow.isActive ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        visible: Ai.catalog.isModelLocal(modelRow.modelData)
                                        text: Translation.tr("Local")
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        color: modelRow.isActive ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                                    }
                                }
                            }

                            // Right Circle Check/Select Button
                            RippleButton {
                                id: selectModelBtn
                                implicitWidth: root.headerControlExtent
                                implicitHeight: root.headerControlExtent
                                Layout.preferredWidth: root.headerControlExtent
                                Layout.preferredHeight: root.headerControlExtent
                                buttonRadius: Appearance.rounding.full
                                toggled: modelRow.isActive
                                colBackground: modelRow.isActive ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                                colBackgroundHover: modelRow.isActive ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                colBackgroundToggled: Appearance.colors.colPrimary
                                colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                                colBackgroundToggledActive: Appearance.colors.colPrimaryActive

                                onClicked: {
                                    Ai.setModel(modelRow.modelData.id, false);
                                    root.modelsOpen = false;
                                    root.requestFocusComposer();
                                }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: modelRow.isActive ? "check" : "arrow_forward"
                                    fill: 1
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: modelRow.isActive ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                                }

                                StyledToolTip {
                                    text: modelRow.isActive
                                        ? Translation.tr("Active model (Ctrl+M)")
                                        : Translation.tr("Select model (Ctrl+M)")
                                }
                            }
                        }
                    }
                }
            }
        }

        // Keyboard shortcuts page. This is the same canvas page used by the
        // sidebar chat, so `?` teaches one vocabulary instead of creating a
        // second, Search-only cheatsheet.
        Item {
            id: shortcutsView
            parent: canvasSurface
            anchors.fill: parent
            z: 2
            opacity: root.shortcutsOpen ? 1.0 : 0.0
            visible: opacity > 0.001
            transform: Translate {
                id: shortcutsViewSlide
                x: root.shortcutsOpen ? 0 : root.pageSlideDistance

                Behavior on x {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }
            }

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(shortcutsView)
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Appearance.rounding.large
                spacing: Appearance.rounding.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.rounding.normal

                    RippleButton {
                        id: shortcutsBackButton
                        implicitWidth: root.headerControlExtent
                        implicitHeight: root.headerControlExtent
                        buttonRadius: Appearance.rounding.full
                        focusPolicy: Qt.StrongFocus
                        colBackground: shortcutsBackButton.activeFocus
                            ? Appearance.colors.colLayer2Active
                            : (shortcutsBackButton.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: root.handleEscape()

                        Accessible.name: Translation.tr("Back to chat")

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Space || event.key === Qt.Key_Enter) {
                                root.handleEscape();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.handleEscape();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                                root.focusComposer();
                                event.accepted = true;
                            }
                        }

                        contentItem: MaterialSymbol {
                            text: "arrow_back"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.larger
                            color: shortcutsBackButton.activeFocus
                                ? Appearance.m3colors.m3primary
                                : Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: Translation.tr("Back to chat (Esc)")
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Keys")
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                }

                Loader {
                    id: shortcutSheetLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // Keep the page mounted while it fades out so closing
                    // does not replace the content with a blank frame.
                    active: true
                    source: Qt.resolvedUrl("../sidebarPolicies/aiChat/ChatShortcutSheet.qml")
                }
            }
        }

        // Tool catalog and example prompts — the same canvas page as "Keys",
        // shared with the sidebar chat via the same component.
        Item {
            id: capabilitiesView
            parent: canvasSurface
            anchors.fill: parent
            z: 2
            opacity: root.capabilitiesOpen ? 1.0 : 0.0
            visible: opacity > 0.001
            transform: Translate {
                id: capabilitiesViewSlide
                x: root.capabilitiesOpen ? 0 : root.pageSlideDistance

                Behavior on x {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }
            }

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(capabilitiesView)
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Appearance.rounding.large
                spacing: Appearance.rounding.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.rounding.normal

                    RippleButton {
                        id: capabilitiesBackButton
                        implicitWidth: root.headerControlExtent
                        implicitHeight: root.headerControlExtent
                        buttonRadius: Appearance.rounding.full
                        focusPolicy: Qt.StrongFocus
                        colBackground: capabilitiesBackButton.activeFocus
                            ? Appearance.colors.colLayer2Active
                            : (capabilitiesBackButton.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: root.handleEscape()

                        Accessible.name: Translation.tr("Back to chat")

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Space || event.key === Qt.Key_Enter) {
                                root.handleEscape();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.handleEscape();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                                root.focusComposer();
                                event.accepted = true;
                            }
                        }

                        contentItem: MaterialSymbol {
                            text: "arrow_back"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.larger
                            color: capabilitiesBackButton.activeFocus
                                ? Appearance.m3colors.m3primary
                                : Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: Translation.tr("Back to chat (Esc)")
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Capabilities")
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                }

                Loader {
                    id: capabilitiesSheetLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // Keep the page mounted while it fades out so closing
                    // does not replace the content with a blank frame.
                    active: true
                    source: Qt.resolvedUrl("../sidebarPolicies/aiChat/AiCapabilitiesSheet.qml")

                    Connections {
                        target: capabilitiesSheetLoader.item
                        function onPromptChosen(text) {
                            root.capabilitiesOpen = false;
                            composer.insertPromptExample(text);
                        }
                    }
                }
            }
        }

        // ════════════════════════════════════════════════════════
        // 3. BOTTOM COMPOSER RECTANGLE
        // ════════════════════════════════════════════════════════

        AiSearchComposer {
            id: composer
            Layout.fillWidth: true
            modelsOpen: root.modelsOpen
            onRequestSend: text => root.requestSendMessage(text)
            onRequestEscape: root.handleComposerEscape()
            onRequestOpenHistory: root.historyOpen = !root.historyOpen
            onRequestOpenModels: root.modelsOpen = !root.modelsOpen
            onRequestOpenShortcuts: root.openShortcuts()
            onRequestFocusNext: historyToggleBtn.forceActiveFocus()
            onRequestFocusPrev: brainBackButton.forceActiveFocus()
        }
    }
}
