import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The body of the Modes overlay: a three-tab bar and the page under it.
 *
 * Pages are loaded on demand. Only the selected page stays alive, keeping a
 * retained overlay cheap while closed and avoiding three editor trees in RAM.
 * The host restores the last page; only completed tab navigation is persisted.
 *
 * This is also where the assistant's run state lives: one phase (`idle` →
 * `running` → `success`/`error`), one agent (created on the first sent
 * request and kept alive across tab switches, since the bar that started it
 * belongs to whichever pane is showing), and the reveal seam — when a run
 * produces a definition, the tab changes, the page selects it and the list
 * scrolls to it, cold or warm alike. Nothing here reads `Ai`: the agent file
 * is the module's only door to the AI graph, and it opens on first use.
 *
 * The `id` is `content`, not `root`, because the inline `sourceComponent`
 * pages each carry their own `root`.
 */
Item {
    id: content

    property string initialTab: "modes"
    readonly property var tabs: ["modes", "routines", "activity"]
    property string tab: content.tabs.includes(content.initialTab) ? content.initialTab : "modes"

    signal requestClose()
    readonly property real headerHeight: viewTabs.implicitHeight + contentLayout.spacing

    implicitWidth: 1200
    implicitHeight: 640 + content.headerHeight

    onInitialTabChanged: content.tab = content.tabs.includes(content.initialTab) ? content.initialTab : "modes"

    // ── Assistant run ─────────────────────────────────────────────────────
    // The phase is owned here so a tab switch can destroy and rebuild the
    // pane holding the bar without touching the request in flight.
    property string aiPhase: "idle"
    property string aiErrorText: ""
    property string aiCreatedName: ""
    /// Latched on the first request: the agent — and with it the whole AI
    /// graph — is constructed only from then on, never by opening Modes.
    property bool aiTouched: false
    /// A definition waiting to be shown while its page is still building.
    property var pendingReveal: null

    function requestAi(text) {
        content.aiErrorText = "";
        content.aiCreatedName = "";
        content.aiTouched = true;
        const agent = agentLoader.item;
        if (!agent) {
            content.aiErrorText = Translation.tr("The assistant could not start.");
            content.aiPhase = "error";
            return;
        }
        agent.submit(text);
    }

    function openChatForRequest() {
        // The only reference to `Ai` in this whole module lives in
        // ModesAiAgent; the surface just asks its agent for the hop.
        const agent = agentLoader.item;
        if (agent)
            agent.openChat();
    }

    function revealDefinition(kind, id) {
        content.pendingReveal = { kind: String(kind), id: String(id) };
        content.tab = String(kind) === "routine" ? "routines" : "modes";
        if (Config.options.modes.lastTab !== content.tab)
            Config.options.modes.lastTab = content.tab;
        Qt.callLater(content.consumeReveal);
    }

    // Select the pending definition once its page actually exists. The page
    // may be async-building; the loaders call this again on loaded, and a
    // cold overlay takes the same selection from lastTab/lastModeId.
    function consumeReveal() {
        const request = content.pendingReveal;
        if (!request || !request.id)
            return;
        const page = content.currentPage();
        if (!page)
            return;
        if (request.kind === "routine") {
            if (!page.selectRoutine || !Modes.routineById(request.id))
                return;
            page.selectRoutine(request.id);
        } else {
            if (!page.selectMode || !Modes.modeById(request.id))
                return;
            page.selectMode(request.id);
        }
        if (page.revealSelected)
            page.revealSelected();
        content.pendingReveal = null;
    }

    // Warm surface, external reveal (a chat card's Open, the IPC route):
    // the engine already wrote lastTab/last*Id for the cold path; this
    // covers the case where a page is alive and must move now.
    Connections {
        target: Modes

        function onRevealRequested(request) {
            if (!request || !request.id)
                return;
            content.pendingReveal = request;
            content.tab = String(request.kind) === "routine" ? "routines" : "modes";
            Qt.callLater(content.consumeReveal);
        }
    }

    // The one file in this module that touches `Ai`; the Loader is the gate.
    Loader {
        id: agentLoader
        active: content.aiTouched
        sourceComponent: ModesAiAgent {
            onAccepted: content.aiPhase = "running"
            onRejected: reason => {
                content.aiErrorText = reason;
                content.aiPhase = "error";
            }
            onFinished: (state, errorText, created, kind, id, name) => {
                if (created) {
                    content.aiCreatedName = name;
                    content.revealDefinition(kind, id);
                    content.aiPhase = "success";
                    return;
                }
                if (state === "cancelled") {
                    // The user stopped it: no failure theatre, no verdict.
                    content.aiPhase = "idle";
                    content.aiErrorText = "";
                    return;
                }
                if (state === "completed") {
                    // The model answered without writing — a refusal, a
                    // question back. The words are in the transcript, so
                    // the bar says so and points there.
                    content.aiPhase = "answered";
                    content.aiErrorText = "";
                    return;
                }
                content.aiErrorText = errorText.length > 0
                    ? errorText : Translation.tr("The assistant did not finish.");
                content.aiPhase = "error";
            }
        }
    }

    function currentPage() {
        switch (content.tab) {
        case "routines":
            return routinesLoader.item;
        case "activity":
            return activityLoader.item;
        }
        return modesLoader.item;
    }

    // True when a picker or an inline confirm swallowed the Escape.
    function handleEscape() {
        const page = content.currentPage();
        return page && page.handleEscape ? page.handleEscape() : false;
    }

    function handleKey(key, modifiers) {
        const page = content.currentPage();
        return page && page.handleKey ? page.handleKey(key, modifiers) : false;
    }

    ColumnLayout {
        id: contentLayout
        anchors.fill: parent
        spacing: 12

        // The tabs name the overlay, so there is no title beside them.
        Item {
            Layout.fillWidth: true
            implicitHeight: viewTabs.implicitHeight

            SecondaryTabBar {
                id: viewTabs
                requestOnly: true

                width: 420
                anchors.horizontalCenter: parent.horizontalCenter
                selectedIndex: Math.max(0, content.tabs.indexOf(content.tab))

                onIndexSelected: index => {
                    const next = content.tabs[index] ?? "modes";
                    content.tab = next;
                    Config.options.modes.lastTab = next;
                }

                Repeater {
                    model: [Translation.tr("Modes"), Translation.tr("Routines"), Translation.tr("Activity")]

                    delegate: SecondaryTabButton {
                        required property string modelData
                        required property int index
                        current: index === viewTabs.selectedIndex
                        checkable: false
                        autoExclusive: false
                        Keys.forwardTo: [viewTabs]
                        onClicked: viewTabs.selectIndex(index)

                        buttonText: modelData
                    }
                }
            }

            // Engine switched off: every surface still works by hand, but
            // nothing starts on its own. Said here rather than discovered.
            Rectangle {
                visible: !Modes.enabled
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                implicitWidth: disabledRow.implicitWidth + 20
                implicitHeight: 30
                radius: Appearance.rounding.full
                color: Appearance.colors.colErrorContainer

                RowLayout {
                    id: disabledRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: "motion_photos_paused"
                        iconSize: 16
                        color: Appearance.colors.colOnErrorContainer
                    }

                    StyledText {
                        text: Translation.tr("Automatic starts are off")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnErrorContainer
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Loader {
                id: modesLoader
                anchors.fill: parent
                active: content.tab === "modes"
                visible: content.tab === "modes"
                asynchronous: true
                sourceComponent: ModesPage {
                    onRequestClose: content.requestClose()
                    aiPhase: content.aiPhase
                    aiErrorText: content.aiErrorText
                    aiCreatedName: content.aiCreatedName
                    onAiSubmitted: text => content.requestAi(text)
                    onAiStopRequested: agentLoader.item?.cancel()
                    onAiDismissed: {
                        if (content.aiPhase !== "running") {
                            content.aiPhase = "idle";
                            content.aiErrorText = "";
                        }
                    }
                    onAiSuccessFinished: content.aiPhase = "idle"
                    onAiOpenChatRequested: content.openChatForRequest()
                }
                onLoaded: content.consumeReveal()
            }

            Loader {
                id: routinesLoader
                anchors.fill: parent
                active: content.tab === "routines"
                visible: content.tab === "routines"
                asynchronous: true
                sourceComponent: RoutinesPage {
                    onRequestClose: content.requestClose()
                    aiPhase: content.aiPhase
                    aiErrorText: content.aiErrorText
                    aiCreatedName: content.aiCreatedName
                    onAiSubmitted: text => content.requestAi(text)
                    onAiStopRequested: agentLoader.item?.cancel()
                    onAiDismissed: {
                        if (content.aiPhase !== "running") {
                            content.aiPhase = "idle";
                            content.aiErrorText = "";
                        }
                    }
                    onAiSuccessFinished: content.aiPhase = "idle"
                    onAiOpenChatRequested: content.openChatForRequest()
                }
                onLoaded: content.consumeReveal()
            }

            Loader {
                id: activityLoader
                anchors.fill: parent
                active: content.tab === "activity"
                visible: content.tab === "activity"
                asynchronous: true
                sourceComponent: ActivityPage {
                    onRequestClose: content.requestClose()
                }
            }
        }
    }
}
