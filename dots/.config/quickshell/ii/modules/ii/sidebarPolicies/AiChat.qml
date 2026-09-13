import qs
import qs.services
import qs.services.ai
import qs.services.ai.blocks
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarPolicies.aiChat
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

Item {
    id: root
    property real padding: 4
    property var inputField: messageInputField
    property string commandPrefix: "/"
    readonly property bool autoScrollEnabled: Config.options.sidebar.ai.autoScroll
    readonly property bool reducedMotion: Config.options.sidebar.ai.reducedMotion

    property var suggestionQuery: ""
    property var suggestionList: []

    property bool containsDrag: false

    /** Whichever control's view is filling the chat area, "" for the transcript. */
    readonly property bool canvasViewOpen: controlBar.viewOpen

    // Three-surface geometry, kept on the same tokens the Overview
    // AiChatPanel uses so the sidebar and the search panel stay one design
    // rather than two that happen to look alike. Nothing here is a pixel
    // constant: every value is derived from the type scale and the rounding
    // scale, so it follows the user's font size and sharp-mode settings.
    readonly property real toolControlExtent: Math.round(Appearance.font.pixelSize.huge * 2)
    readonly property real toolControlPadding: Appearance.rounding.small
    readonly property real toolsBarHeight: root.toolControlExtent + root.toolControlPadding * 2
    // Floor for the chat area, so a composer that has grown a lot still
    // leaves a readable transcript instead of collapsing it to nothing.
    readonly property real chatAreaMinimumHeight: root.toolsBarHeight * 2
    readonly property real surfaceSpacing: Appearance.rounding.verysmall

    // ── Transcript ──
    /** Space between one turn and the next. */
    readonly property real messageGap: Appearance.rounding.small
    /** What the transcript keeps clear of its own rounded corners. */
    readonly property real messageListInset: Appearance.rounding.small

    // ── Composer ──
    readonly property real composerControlExtent: Math.round(Appearance.font.pixelSize.huge * 2)
    readonly property real composerGap: Appearance.rounding.unsharpenmore
    // A composer's own inset, not a card's: its controls are already round and
    // carry their own optical margin, so the box around them can be tight.
    readonly property real composerInset: Appearance.rounding.verysmall
    /** Whether the plus has slid its ways of attaching out. */
    property bool attachmentsExpanded: false
    onCanvasViewOpenChanged: {
        if (root.canvasViewOpen)
            root.attachmentsExpanded = false;
    }
    readonly property var thinkingShortLabels: ({
        "off": "",
        "low": Translation.tr("Low"),
        "medium": Translation.tr("Med"),
        "high": Translation.tr("High")
    })
    readonly property string thinkingShortLabel: root.thinkingShortLabels[Ai.thinkingLevel] ?? ""

    property int entranceTrigger: -1
    // New delegates are the only ones that animate while a response streams.
    // Reopening a saved chat explicitly advances this token once, letting the
    // already visible turns make a short, ordered entrance instead.
    property int transcriptRevealToken: -1

    function pinnedModelIds() {
        return Array.from(Config.options.sidebar.ai.pinnedModels ?? [])
            .filter(id => Ai.catalog.models[id]);
    }

    function selectPinnedModel(index) {
        const id = root.pinnedModelIds()[index];
        return id ? Ai.setModel(id, false) : false;
    }

    // ── Editing a question ────────────────────────────────────────────────
    /** The question being rewritten, "" when the composer is writing a new one. */
    property string editingMessageId: ""

    // ── Prompt history (Up/Down, like a shell) ──────────────────────────
    // -1 means "not navigating": the composer holds whatever the user is
    // actually writing. Pressing Up from an empty draft starts the walk at
    // the most recent prompt; Down retraces it and hands the original draft
    // back once it walks off the newest end.
    property int promptHistoryIndex: -1
    property string promptHistoryDraftBackup: ""
    property bool navigatingPromptHistory: false

    function applyPromptHistoryText(text) {
        root.navigatingPromptHistory = true;
        messageInputField.text = text;
        messageInputField.cursorPosition = messageInputField.text.length;
        root.navigatingPromptHistory = false;
    }

    function resetPromptHistory() {
        root.promptHistoryIndex = -1;
        root.promptHistoryDraftBackup = "";
    }

    /** delta -1 walks to an older prompt (Up); +1 walks back toward the live draft (Down). */
    function stepPromptHistory(delta) {
        const history = Ai.ownPromptHistory;
        if (history.length === 0)
            return false;
        if (root.promptHistoryIndex === -1) {
            if (delta > 0)
                return false; // already at the live draft, nothing newer
            root.promptHistoryDraftBackup = messageInputField.text;
            root.promptHistoryIndex = history.length - 1;
        } else if (delta < 0) {
            if (root.promptHistoryIndex === 0)
                return true; // already at the oldest prompt; consume the key
            root.promptHistoryIndex -= 1;
        } else {
            if (root.promptHistoryIndex >= history.length - 1) {
                root.applyPromptHistoryText(root.promptHistoryDraftBackup);
                root.resetPromptHistory();
                return true;
            }
            root.promptHistoryIndex += 1;
        }
        root.applyPromptHistoryText(history[root.promptHistoryIndex]);
        return true;
    }
    // ── Finding something in this chat ────────────────────────────────────
    /** Whether the find-in-chat field is open over the transcript. */
    property bool transcriptSearchOpen: false
    property string transcriptQuery: ""
    property int transcriptMatchIndex: 0

    /** Indices in the visible list whose text holds the query. */
    readonly property var transcriptMatches: {
        const needle = root.transcriptQuery.trim().toLowerCase();
        if (needle.length === 0)
            return [];
        const ids = Ai.messageIDs.filter(id => Ai.isTranscriptEntry(id));
        const found = [];
        for (let i = 0; i < ids.length; i++) {
            const message = Ai.messageByID[ids[i]];
            const content = message && message.content ? message.content : "";
            const thought = message && message.thought ? message.thought : "";
            const haystack = (content + "\n" + thought).toLowerCase();
            if (haystack.indexOf(needle) >= 0)
                found.push(i);
        }
        return found;
    }

    function goToMatch(step) {
        const matches = root.transcriptMatches;
        if (matches.length === 0)
            return;
        root.transcriptMatchIndex = ((root.transcriptMatchIndex + step) % matches.length + matches.length) % matches.length;
        const index = matches[root.transcriptMatchIndex];
        messageListView.following = false;
        messageListView.focusedIndex = index;
        messageListView.positionViewAtIndex(index, ListView.Center);
        // The list keeps the mark; the focus stays in the field so the next
        // Enter is another step rather than a new search.
        Qt.callLater(function () {
            messageListView.positionViewAtIndex(index, ListView.Center);
        });
    }

    onTranscriptSearchOpenChanged: {
        if (!root.transcriptSearchOpen) {
            root.transcriptQuery = "";
            root.transcriptMatchIndex = 0;
            messageInputField.forceActiveFocus();
        }
    }

    function beginEdit(messageId, content) {
        root.editingMessageId = messageId;
        messageInputField.text = String(content ?? "");
        messageInputField.cursorPosition = messageInputField.text.length;
        messageInputField.forceActiveFocus();
    }

    function cancelEdit() {
        if (root.editingMessageId.length === 0)
            return;
        root.editingMessageId = "";
        messageInputField.clear();
    }

    /**
     * Sends the rewritten question. Everything that followed it answered the
     * old wording, so the service forks first and leaves that branch behind
     * rather than deleting it.
     */
    function commitEdit(text) {
        const id = root.editingMessageId;
        root.editingMessageId = "";
        messageInputField.clear();
        Ai.editAndResend(id, String(text ?? ""));
        messageListView.pinToEnd();
    }

    /**
     * Play the whole panel in. Called when the chat becomes the page on
     * screen, which is also the moment the transcript should cascade rather
     * than simply be there — a chat with history used to fade its container
     * in around messages that were already settled inside it.
     */
    function triggerContentEntrance() {
        root.entranceTrigger++;
        root.revealTranscript();
    }

    /** Stagger whatever turns are in view, once. */
    function revealTranscript() {
        if (root.reducedMotion)
            return;
        // Never mid-answer. A reveal is an opening transition, and replaying
        // it over a turn that is still being written asks every settled turn
        // to enter again around it — on top of which the turn in flight
        // cannot take part, having nothing finished to show yet.
        if (Ai.isGenerating)
            return;
        // Delegates in view receive the same token; offscreen rows are
        // created settled, so only what is actually visible enters.
        root.transcriptRevealToken = Math.max(0, root.transcriptRevealToken + 1);
        transcriptRevealWindow.restart();
    }

    // ── Empty-state hello ────────────────────────────────────────────────
    // The line itself is rolled by `AiTranscriptRegistry`, which both
    // transcripts share; what belongs here is only when to roll a new one.
    property string emptyStateGreeting: ""

    function refreshEmptyStateGreeting() {
        const configured = String(Config.options.sidebar.ai.greeting ?? "").trim();
        root.emptyStateGreeting = configured.length > 0 ? configured : AiTranscriptRegistry.greetingLine();
    }

    Connections {
        target: Config.options.sidebar.ai
        function onGreetingChanged() {
            if (emptyStatePlaceholder.shown)
                root.refreshEmptyStateGreeting();
        }
    }

    Connections {
        target: Ai.sessions
        function onSessionOpened(session) {
            root.revealTranscript();
        }
    }

    Connections {
        // Coming back from a control's view is an arrival too: the transcript
        // slides in from the left with nothing moving inside it otherwise.
        target: controlBar
        function onViewOpenChanged() {
            if (!controlBar.viewOpen)
                root.revealTranscript();
        }
    }

    Timer {
        id: transcriptRevealWindow
        // Covers the stagger while keeping delegates later created by scrolling
        // settled. This is an opening transition, never a list-populate one.
        interval: Appearance.animation.elementMoveEnter.duration
            + Appearance.animation.elementMoveSmall.duration * 2
        onTriggered: root.transcriptRevealToken = -1
    }

    Connections {
        target: emptyStatePlaceholder
        function onShownChanged() {
            if (emptyStatePlaceholder.shown)
                root.refreshEmptyStateGreeting();
        }
        function onEntranceTriggerChanged() {
            if (emptyStatePlaceholder.shown)
                root.refreshEmptyStateGreeting();
        }
    }

    // Handoff state is logical, not a reference to a sidebar delegate. The
    // Search surface can therefore recreate this chat at another width (or
    // after hot reload) without retaining an invalid QML object.
    function captureHandoffState() {
        const anchor = {
            messageId: "",
            offset: 0,
            following: messageListView.following === true
        };
        if (messageListView.count <= 0)
            return anchor;
        const probeY = Math.min(8, Math.max(0, messageListView.height - 1));
        const index = messageListView.indexAt(8, probeY);
        if (index < 0)
            return anchor;
        const modelIds = Ai.messageIDs.filter(id => Ai.isTranscriptEntry(id));
        anchor.messageId = String(modelIds[index] ?? "");
        const delegate = messageListView.itemAtIndex(index);
        if (delegate)
            anchor.offset = Math.max(0, Number(delegate.y) - Number(messageListView.contentY));
        return anchor;
    }

    function restoreHandoffAnchor(anchor) {
        const source = anchor && typeof anchor === "object" ? anchor : ({});
        if (source.following === true) {
            messageListView.pinToEnd();
            return true;
        }
        const modelIds = Ai.messageIDs.filter(id => Ai.isTranscriptEntry(id));
        const index = modelIds.indexOf(String(source.messageId ?? ""));
        if (index < 0)
            return false;
        messageListView.following = false;
        messageListView.positionViewAtIndex(index, ListView.Beginning);
        const offset = Number(source.offset ?? 0);
        if (isFinite(offset) && offset > 0)
            messageListView.contentY = Math.max(0, messageListView.contentY - offset);
        return true;
    }

    function focusMessageTarget(messageId, anchor) {
        const targetId = String(messageId ?? "");
        const modelIds = Ai.messageIDs.filter(id => Ai.isTranscriptEntry(id));
        const index = modelIds.indexOf(targetId);
        if (index < 0)
            return false;
        messageListView.following = false;
        messageListView.positionViewAtIndex(index, ListView.Center);
        const offset = Number(anchor && anchor.offset !== undefined ? anchor.offset : 0);
        if (isFinite(offset) && offset > 0)
            messageListView.contentY = Math.max(0, messageListView.contentY - offset);
        Qt.callLater(function() {
            const delegate = messageListView.itemAtIndex(index);
            if (delegate && typeof delegate.forceActiveFocus === "function")
                delegate.forceActiveFocus();
            else
                messageListView.forceActiveFocus();
        });
        return true;
    }

    // Returning false leaves a deep-link pending until a streamed target is
    // present in this host. Composer handoffs may be acknowledged immediately
    // once the AI tab is the visible SwipeView page.
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
            messageInputField.forceActiveFocus();
        return hasAnchor || String(intent.focusIntent ?? "composer") === "composer";
    }

    onFocusChanged: focus => {
        if (focus) {
            root.inputField.forceActiveFocus();
        }
    }

    // ── Keyboard ──────────────────────────────────────────────────────────
    // Everything the chat can do has a key, and `?` on an empty composer says
    // what they are. The handlers live here rather than on each control so a
    // key works wherever the focus happens to be inside the panel.

    /** The newest question, which is what Ctrl+E takes back. */
    function lastMessageIdOfRole(role) {
        for (let at = Ai.messageIDs.length - 1; at >= 0; at--) {
            const id = Ai.messageIDs[at];
            const msg = Ai.messageByID[id];
            if (msg && msg.role === role)
                return id;
        }
        return "";
    }

    function editLastQuestion() {
        const id = root.lastMessageIdOfRole("user");
        if (id.length === 0)
            return false;
        const msg = Ai.messageByID[id];
        root.beginEdit(id, String(msg && msg.content ? msg.content : ""));
        return true;
    }

    function regenerateLastAnswer() {
        const id = root.lastMessageIdOfRole("assistant");
        if (id.length === 0)
            return false;
        Ai.regenerate(id);
        return true;
    }

    /**
     * Moves the focus from turn to turn. A transcript nobody can walk with a
     * keyboard is a transcript a screen reader cannot walk either.
     */
    function stepThroughTurns(delta) {
        const count = messageListView.count;
        if (count <= 0)
            return;
        const current = messageListView.focusedIndex;
        const next = current < 0
            ? (delta > 0 ? 0 : count - 1)
            : Math.max(0, Math.min(count - 1, current + delta));
        messageListView.focusedIndex = next;
        messageListView.following = false;
        messageListView.positionViewAtIndex(next, ListView.Contain);
        const delegate = messageListView.itemAtIndex(next);
        if (delegate)
            delegate.forceActiveFocus();
    }

    /** Runs a panel shortcut. Returns whether the key belonged to one. */
    function handleShortcut(event) {
        const control = (event.modifiers & Qt.ControlModifier) !== 0;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const alt = (event.modifiers & Qt.AltModifier) !== 0;

        if (event.key === Qt.Key_Escape) {
            if (root.canvasViewOpen) {
                controlBar.closePopover();
                return true;
            }
            if (root.editingMessageId.length > 0) {
                root.cancelEdit();
                return true;
            }
            return false;
        }

        if (alt && !control) {
            if (event.key === Qt.Key_Up) {
                root.stepThroughTurns(-1);
                return true;
            }
            if (event.key === Qt.Key_Down) {
                root.stepThroughTurns(1);
                return true;
            }
        }

        if (!control)
            return false;

        if (!shift && !alt) {
            const pinnedIndex = [Qt.Key_1, Qt.Key_2, Qt.Key_3, Qt.Key_4, Qt.Key_5,
                                 Qt.Key_6, Qt.Key_7, Qt.Key_8, Qt.Key_9].indexOf(event.key);
            if (pinnedIndex >= 0)
                return root.selectPinnedModel(pinnedIndex);
        }

        if (shift && event.key === Qt.Key_O) {
            Ai.newChat();
            return true;
        }
        switch (event.key) {
        case Qt.Key_J:
            Ai.surfaceRouter.open({
                surface: "search",
                monitorName: GlobalStates.activeLeftSidebarMonitor,
                sessionId: Ai.sessions.currentId,
                focusIntent: "composer",
                scrollAnchor: root.captureHandoffState()
            });
            return true;
        case Qt.Key_L:
            controlBar.togglePopover("sessions");
            return true;
        case Qt.Key_M:
            controlBar.togglePopover("model");
            return true;
        case Qt.Key_T:
            controlBar.togglePopover("tools");
            return true;
        case Qt.Key_K:
            controlBar.togglePopover("keys");
            return true;
        case Qt.Key_I:
            controlBar.togglePopover("capabilities");
            return true;
        case Qt.Key_F:
            root.transcriptSearchOpen = !root.transcriptSearchOpen;
            return true;
        case Qt.Key_E:
            return root.editLastQuestion();
        case Qt.Key_R:
            return root.regenerateLastAnswer();
        case Qt.Key_End:
            messageListView.pinToEnd();
            return true;
        }
        return false;
    }

    Keys.onPressed: event => {
        if (root.handleShortcut(event)) {
            event.accepted = true;
            return;
        }
        // A canvas page can own a text field. Some printable keys do not mark
        // themselves accepted on every Qt input method, so forcing the
        // composer here would move its focus and send that key to the chat.
        if (root.canvasViewOpen)
            return;
        messageInputField.forceActiveFocus();
        if (event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageUp) {
                messageListView.contentY = Math.max(0, messageListView.contentY - messageListView.height / 2);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageDown) {
                messageListView.contentY = Math.min(messageListView.contentHeight - messageListView.height / 2, messageListView.contentY + messageListView.height / 2);
                event.accepted = true;
            }
        }
    }

    // ── References ────────────────────────────────────────────────────────
    // `@` pulls a visible or explicitly attached item into the prompt. The
    // service owns these sources so Search resolves the same marker too.
    readonly property var referenceSources: Ai.composerReferenceSources()

    property var allCommands: [
        {
            name: "attach",
            description: Translation.tr("Attach a file to the next message. Also: the paperclip, drag and drop, or Ctrl+V."),
            execute: args => {
                const path = args.join(" ").trim();
                if (path.length === 0) {
                    Ai.pickFiles();
                    return;
                }
                Ai.attachFile(path);
            }
        },
        {
            name: "model",
            description: Translation.tr("Choose model"),
            execute: args => {
                Ai.setModel(args.join(" ").trim());
            }
        },
        {
            name: "provider",
            description: Translation.tr("Choose provider"),
            execute: args => {
                Ai.setProvider(args.join(" ").trim());
            }
        },
        {
            name: "tool",
            description: Translation.tr("Set the tool to use for the model."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.addMessage(Translation.tr("Usage: %1tool TOOL_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                } else {
                    const tool = args[0];
                    const switched = Ai.setTool(tool);
                    if (switched) {
                        Ai.addMessage(Translation.tr("Tool set to: %1").arg(tool), Ai.interfaceRole);
                    }
                }
            }
        },
        {
            name: "prompt",
            description: Translation.tr("Set the system prompt for the model."),
            execute: args => {
                if (args.length === 0 || args[0] === "get") {
                    Ai.printPrompt();
                    return;
                }
                Ai.loadPrompt(args.join(" ").trim());
            }
        },
        {
            name: "persona",
            description: Translation.tr("Answer as a saved persona: prompt, model, thinking and temperature at once."),
            execute: args => {
                const wanted = args.join(" ").trim();
                if (wanted.length === 0) {
                    controlBar.togglePopover("prompt");
                    return;
                }
                if (wanted === "none" || wanted === "off") {
                    Ai.setPersona("");
                    return;
                }
                const needle = wanted.toLowerCase();
                const persona = Ai.personas.all.find(entry => entry.id === needle || (entry.name ?? "").toLowerCase() === needle);
                if (!persona) {
                    Ai.addMessage(Translation.tr("No persona called %1. Known: %2").arg(wanted).arg(Ai.personas.all.map(entry => entry.id).join(", ")), Ai.interfaceRole);
                    return;
                }
                Ai.setPersona(persona.id);
            }
        },
        {
            name: "key",
            description: Translation.tr("API keys. On its own it opens the key panel."),
            execute: args => {
                // Never `/key get` into the transcript: a chat is screenshot
                // and screen-shared, and a secret written into it stays there.
                if (args.length === 0 || args[0].trim().length === 0) {
                    controlBar.openKeyManager();
                } else if (args[0] == "get") {
                    Ai.printApiKey();
                } else {
                    Ai.setApiKey(args[0]);
                }
            }
        },
        {
            name: "capabilities",
            description: Translation.tr("Show what this chat's tools can do, with example prompts for each."),
            execute: () => {
                controlBar.openCapabilities();
            }
        },
        {
            name: "save",
            description: Translation.tr("Name this chat. Chats are kept whether they are named or not."),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1save CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.nameCurrentChat(joinedArgs);
            }
        },
        {
            name: "load",
            description: Translation.tr("Open a saved chat by name"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1load CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.openChatByName(joinedArgs);
            }
        },
        {
            name: "chats",
            description: Translation.tr("Show the list of saved chats"),
            execute: () => {
                controlBar.activePopover = "sessions";
            }
        },
        {
            name: "clear",
            description: Translation.tr("Put this chat away and start an empty one"),
            execute: () => {
                Ai.newChat();
            }
        },
        {
            name: "temp",
            description: Translation.tr("Set temperature (randomness) of the model. Values range between 0 to 2 for Gemini, 0 to 1 for other models. Default is 0.5."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.printTemperature();
                } else {
                    const temp = parseFloat(args[0]);
                    Ai.setTemperature(temp);
                }
            }
        },
        {
            name: "think",
            description: Translation.tr("How hard the model should think: off, low, medium or high. Models that cannot be told to stop reasoning use the smallest budget instead."),
            execute: args => {
                if (args.length == 0 || args[0] == "get") {
                    const model = Ai.currentModelEntry;
                    if (!model || !model.thinking) {
                        const modelName = model && model.name ? model.name : Translation.tr("This model");
                        Ai.addMessage(Translation.tr("%1 does not think out loud.").arg(modelName), Ai.interfaceRole);
                        return;
                    }
                    Ai.addMessage(Translation.tr("Thinking: %1").arg(Ai.thinkingLevel), Ai.interfaceRole);
                    return;
                }
                if (Ai.setThinkingLevel(args[0]))
                    Ai.addMessage(Translation.tr("Thinking set to %1").arg(Ai.thinkingLevel), Ai.interfaceRole);
            }
        },
        {
            name: "effort",
            description: Translation.tr("Set response effort: fast, balanced or deep."),
            execute: args => {
                Ai.setResponseMode(args.length > 0 ? args[0] : "balanced");
            }
        },
        {
            name: "web",
            description: Translation.tr("Set web search mode: off, auto or on."),
            execute: args => {
                Ai.setWebMode(args.length > 0 ? args[0] : "auto");
            }
        },
        {
            name: "tools",
            description: Translation.tr("Set tool exposure: none, safe or all."),
            execute: args => {
                Ai.setFunctionExposure(args.length > 0 ? args[0] : "all");
            }
        },
        {
            name: "test",
            description: Translation.tr("Markdown test"),
            execute: () => {
                Ai.addMessage(`
<think>
A longer think block to test revealing animation
OwO wem ipsum dowo sit amet, consekituwet awipiscing ewit, sed do eiuwsmod tempow inwididunt ut wabowe et dowo mawa. Ut enim ad minim weniam, quis nostwud exeucitation uwuwamcow bowowis nisi ut awiquip ex ea commowo consequat. Duuis aute iwuwe dowo in wepwependewit in wowuptate velit esse ciwwum dowo eu fugiat nuwa pawiatuw. Excepteuw sint occaecat cupidatat non pwowoident, sunt in cuwpa qui officia desewunt mowit anim id est wabowum. Meouw! >w<
Mowe uwu wem ipsum!
</think>
## ✏️ Markdown test
### Formatting

- *Italic*, \`Monospace\`, **Bold**, [Link](https://example.com)
- Arch lincox icon <img src="${Quickshell.shellPath("assets/icons/arch-symbolic.svg")}" height="${Appearance.font.pixelSize.small}"/>

### Table

Quickshell vs AGS/Astal

|                          | Quickshell       | AGS/Astal         |
|--------------------------|------------------|-------------------|
| UI Toolkit               | Qt               | Gtk3/Gtk4         |
| Language                 | QML              | Js/Ts/Lua         |
| Reactivity               | Implied          | Needs declaration |
| Widget placement         | Mildly difficult | More intuitive    |
| Bluetooth & Wifi support | ❌               | ✅                |
| No-delay keybinds        | ✅               | ❌                |
| Development              | New APIs         | New syntax        |

### Code block

Just a hello world...

\`\`\`cpp
#include <bits/stdc++.h>
// This is intentionally very long to test scrolling
const std::string GREETING = \"UwU\";
int main(int argc, char* argv[]) {
    std::cout << GREETING;
}
\`\`\`

### LaTeX


Inline w/ dollar signs: $\\frac{1}{2} = \\frac{2}{4}$

Inline w/ double dollar signs: $$\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}$$

Inline w/ backslash and square brackets \\[\\int_0^\\infty \\frac{1}{x^2} dx = \\infty\\]

Inline w/ backslash and round brackets \\(e^{i\\pi} + 1 = 0\\)
`, Ai.interfaceRole);
            }
        },
    ]

    function handleInput(inputText) {
        if (root.editingMessageId.length > 0 && String(inputText ?? "").trim().length > 0) {
            root.commitEdit(inputText);
            messageListView.pinToEnd();
            return { accepted: true, state: "edit" };
        }
        const parsed = AiActionRegistry.parseInput(inputText, root.commandPrefix);
        if (parsed.kind === "command" || parsed.kind === "unknown-command") {
            // Handle special commands
            const commandObj = root.allCommands.find(cmd => cmd.name === `${parsed.id ?? parsed.name}` || cmd.name === `${parsed.name}`);
            if (commandObj) {
                commandObj.execute(parsed.args);
                Ai.clearDraftIfCurrent();
                messageListView.pinToEnd();
                return { accepted: true, state: "command", commandId: parsed.id };
            } else {
                Ai.addMessage(Translation.tr("Unknown command: ") + parsed.name, Ai.interfaceRole);
                messageListView.pinToEnd();
                return { accepted: false, state: "rejected", errorCode: "unknown-command" };
            }
        } else {
            const result = Ai.sendUserMessage(Ai.expandComposerReferences(parsed.text));
            // The AI service owns clearing accepted prompts. Rejected prompts
            // stay in the field so the user can correct or retry them.
            messageListView.pinToEnd();
            return result;
        }
    }

    Connections {
        // The service says a key is missing; the panel that fixes it lives
        // here. Nothing in the service knows about this bar.
        target: Ai
        function onKeyManagerRequested() {
            controlBar.openKeyManager();
        }
        function onDraftRestored(text) {
            messageInputField.text = text;
            messageInputField.cursorPosition = messageInputField.text.length;
            // A different chat has its own prompts; a walk started in the
            // old one has nothing to do with them.
            root.resetPromptHistory();
        }
        // `Ai.draft` is the source of truth once a submission actually
        // clears it (accepted chat message, or a slash command via
        // `clearDraftIfCurrent()`): that happens asynchronously, well after
        // the click/Enter that triggered `handleInput()` returns, so nothing
        // in this file can clear the field synchronously without risking
        // wiping text the service decided to keep (a rejected submission,
        // or a newer draft typed while the old one was still dispatching).
        function onDraftChanged() {
            if (messageInputField.text !== Ai.draft)
                messageInputField.text = Ai.draft;
        }
    }

    Connections {
        // Voice dictation lands here rather than through a signal on `Ai`
        // itself: the recorder is one service shared by both composers, and
        // `activeSurface` is how it remembers which one asked — so a
        // recording started from the sidebar never inserts itself into a
        // Search composer sitting loaded but hidden elsewhere.
        target: Ai.voiceService
        function onStateChanged() {
            if (Ai.voiceService.state !== "review" || Ai.voiceService.activeSurface !== "sidebar")
                return;
            const text = Ai.voiceService.draftText;
            Ai.voiceService.attachDraft(text);
            if (text.length === 0)
                return;
            messageInputField.text = messageInputField.text.length > 0
                ? `${messageInputField.text} ${text}`
                : text;
            messageInputField.cursorPosition = messageInputField.text.length;
            messageInputField.forceActiveFocus();
        }
    }

    /**
     * Opens something that will take the focus — a file dialog, the region
     * snip — without the sidebar closing behind it. The counter is lowered
     * again by whoever raised it, so two of these can overlap.
     */
    function holdSidebarOpen() {
        GlobalStates.policiesHoldOpen += 1;
    }

    function releaseSidebar() {
        GlobalStates.policiesHoldOpen = Math.max(0, GlobalStates.policiesHoldOpen - 1);
    }

    Connections {
        // The file dialog belongs to the service, so the sidebar watches it
        // rather than owning it: whichever panel asked, the one on screen is
        // the one that has to stay there until the dialog is answered.
        target: Ai
        function onPickingFilesChanged() {
            if (Ai.pickingFiles) {
                if (!root.filePickerHeld) {
                    root.filePickerHeld = true;
                    root.holdSidebarOpen();
                }
                return;
            }
            if (!root.filePickerHeld)
                return;
            root.filePickerHeld = false;
            root.releaseSidebar();
        }
    }

    property bool filePickerHeld: false

    Connections {
        // The snip is not a process this file can watch, so the hold ends when
        // the selector does, whether it took a shot or was waved away.
        target: GlobalStates
        function onRegionSelectorOpenChanged() {
            if (GlobalStates.regionSelectorOpen) {
                snipHoldTimeout.stop();
                return;
            }
            if (GlobalStates.regionSelectorOpen || !root.snipHeld)
                return;
            root.snipHeld = false;
            root.releaseSidebar();
        }
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen || !root.snipHeld)
                return;
            root.snipHeld = false;
            root.releaseSidebar();
        }
    }

    property bool snipHeld: false
    Timer {
        id: snipHoldTimeout
        interval: 10000
        repeat: false
        onTriggered: {
            if (!root.snipHeld || GlobalStates.regionSelectorOpen)
                return;
            root.snipHeld = false;
            root.releaseSidebar();
        }
    }

    Process {
        id: decodeImageAndAttachProc
        property string imageDecodePath: Directories.cliphistDecode
        property string imageDecodeFileName: "image"
        property string imageDecodeFilePath: `${imageDecodePath}/${imageDecodeFileName}`
        function handleEntry(entry) {
            imageDecodeFileName = parseInt(entry.match(/^(\d+)\t/)[1]);
            decodeImageAndAttachProc.exec(["bash", "-c", `[ -f ${imageDecodeFilePath} ] || echo '${StringUtils.shellSingleQuoteEscape(entry)}' | ${Cliphist.cliphistBinary} decode > '${imageDecodeFilePath}'`]);
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                Ai.attachFile(imageDecodeFilePath);
            } else {
                console.error("[AiChat] Failed to decode image in clipboard content");
            }
        }
    }

    /** A small round button on the composer's own row. */
    /** The round control at the head of either composer page. */
    component ComposerCircleButton: RippleButton {
        id: circleButton

        property string symbol: ""
        // Set while the button represents ongoing background work (e.g.
        // transcription) rather than an idle/pressable action — spins the
        // icon the same way the bar's own recording indicator does.
        property bool spinning: false

        signal triggered

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: root.composerControlExtent
        implicitHeight: root.composerControlExtent
        buttonRadius: Appearance.rounding.full
        topPadding: 0
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        onClicked: circleButton.triggered()

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: circleButton.symbol
            fill: 1
            iconSize: 24
            color: circleButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2

            RotationAnimator on rotation {
                running: circleButton.spinning
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
            }
        }
    }

    /** One way of attaching, as it appears on the composer's second page. */
    component ComposerActionPill: RippleButton {
        id: actionPill

        property string symbol: ""
        property string label: ""
        /** Shown instead of `label` in the tooltip while `enabled` is false. */
        property string disabledReason: ""

        signal triggered

        implicitHeight: root.composerControlExtent
        implicitWidth: actionPillRow.implicitWidth + root.composerControlExtent * 0.55
        buttonRadius: Appearance.rounding.full
        topPadding: 0
        bottomPadding: 0
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        onClicked: actionPill.triggered()

        contentItem: RowLayout {
            id: actionPillRow
            spacing: Appearance.rounding.unsharpenmore

            MaterialSymbol {
                text: actionPill.symbol
                fill: 1
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.fillWidth: true
                text: actionPill.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.bold: true
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer2
            }
        }

        StyledToolTip {
            text: actionPill.enabled || actionPill.disabledReason.length === 0 ? actionPill.label : actionPill.disabledReason
        }
    }

    /** One of the round controls on the find row. */
    component FindStep: RippleButton {
        id: findStep

        property string symbol: ""
        property string tooltipText: ""

        signal triggered

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Math.round(Appearance.font.pixelSize.huge * 1.5)
        implicitHeight: implicitWidth
        buttonRadius: Appearance.rounding.full
        topPadding: 0
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0
        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active
        onClicked: findStep.triggered()

        Accessible.name: findStep.tooltipText

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: findStep.symbol
            fill: 1
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer2
        }

        StyledToolTip {
            text: findStep.tooltipText
        }
    }

    component ComposerButton: RippleButton {
        id: composerButton

        property string symbol: ""
        property string tooltipText: ""

        signal triggered

        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        onClicked: composerButton.triggered()
        // Same reason as the control chips: leave the whole button to the
        // glyph, so its line box is centred instead of overflowing the
        // padded content rect downwards. Anchoring the content item fights
        // the geometry a Control assigns it, so it centres itself instead.
        topPadding: 0
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: composerButton.symbol
            fill: 1
            iconSize: 20
            color: Appearance.colors.colOnLayer2
        }

        StyledToolTip {
            text: composerButton.tooltipText
        }
    }

    /**
     * Files land anywhere on the chat, not only on the composer.
     *
     * The drop target used to be the input box alone, which meant aiming at a
     * strip a few rows tall while the transcript above it — the part of the
     * panel the eye is actually on — turned every file away. A DropArea
     * accepts drag events without taking mouse input, so covering the whole
     * panel costs the controls underneath nothing.
     */
    DropArea {
        id: panelDropArea
        anchors.fill: parent
        z: 200

        onContainsDragChanged: root.containsDrag = panelDropArea.containsDrag

        onDropped: drop => {
            if (!drop.hasUrls)
                return;
            // Gating happens per file, in the service: a text file is
            // readable by every model, whatever it can otherwise take.
            for (let i = 0; i < drop.urls.length; i++)
                Ai.attachFile(drop.urls[i]);
            drop.accept(Qt.CopyAction);
        }
    }

    ColumnLayout {
        id: columnLayout
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.surfaceSpacing

        // ════════════════════════════════════════════════════════
        // 1. TOP TOOLS BAR RECTANGLE
        // ════════════════════════════════════════════════════════

        Rectangle {
            id: toolsBarSurface
            Layout.fillWidth: true
            Layout.preferredHeight: root.toolsBarHeight
            implicitHeight: root.toolsBarHeight
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.full
            clip: true

            ChatControlBar {
                id: controlBar
                anchors.fill: parent
                anchors.margins: root.toolControlPadding
                overlayParent: chatAreaSurface
                commandPrefix: root.commandPrefix
                inputField: messageInputField
                onNewChatRequested: Ai.newChat()
            }
        }

        // ════════════════════════════════════════════════════════
        // 2. MIDDLE CHAT AREA RECTANGLE
        // ════════════════════════════════════════════════════════

        Rectangle {
            id: chatAreaSurface
            Layout.fillWidth: true
            // Takes every pixel the other two surfaces leave behind, which is
            // what lets the composer grow upward into it.
            Layout.fillHeight: true
            Layout.minimumHeight: root.chatAreaMinimumHeight
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.large
            clip: true

            Loader {
                // Says where the file is going while it is still in the air.
                // Over the transcript rather than the composer: the drop is
                // accepted anywhere on the panel now, so the hint belongs on
                // the surface the eye is already on.
                id: dropOverlay
                anchors.fill: parent
                z: 199
                active: root.containsDrag
                opacity: active ? 1 : 0
                visible: opacity > 0.01

                Behavior on opacity {
                    enabled: !root.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                sourceComponent: Rectangle {
                    radius: Appearance.rounding.large
                    color: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.12)

                    DashedBorder {
                        anchors.fill: parent
                        anchors.margins: borderWidth
                        radius: Appearance.rounding.large
                        borderWidth: Math.max(2, Math.round(Appearance.font.pixelSize.smaller / 5))
                        dashLength: Appearance.font.pixelSize.small
                        gapLength: Appearance.rounding.verysmall
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Appearance.rounding.unsharpenmore

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: Ai.currentModelTakesFiles ? "attach_file_add" : "description"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.huge * 2
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Ai.currentModelTakesFiles
                                ? Translation.tr("Drop to attach")
                                : Translation.tr("Drop to attach — text files only")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            visible: !Ai.currentModelTakesFiles
                            text: Translation.tr("%1 cannot read files").arg((Ai.currentModelEntry && Ai.currentModelEntry.title) ? Ai.currentModelEntry.title : Translation.tr("This model"))
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.78
                        }
                    }
                }
            }

            ColumnLayout {
                id: chatAreaColumn
                anchors.fill: parent
                anchors.margins: root.padding
                spacing: root.padding

                // Leaves to the left as a control's view arrives from the
                // right, so the middle rectangle reads as one surface changing
                // its content rather than something being covered up.
                opacity: root.canvasViewOpen ? 0 : 1
                visible: opacity > 0.001
                transform: Translate {
                    x: root.canvasViewOpen ? -controlBar.canvasSlideDistance : 0

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

                Loader {
                    // This chat came off another one — a fork, or a question
                    // that was rewritten. The answer it replaced is still in
                    // the chat it was left in, and this is the way back to it.
                    id: branchBar
                    Layout.fillWidth: true
                    Layout.leftMargin: root.messageListInset
                    Layout.rightMargin: root.messageListInset
                    active: Ai.sessionParentId.length > 0
                    visible: active

                    sourceComponent: Rectangle {
                        implicitHeight: Math.round(Appearance.font.pixelSize.huge * 1.7)
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer2

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Appearance.rounding.small
                            anchors.rightMargin: Appearance.rounding.unsharpen
                            spacing: Appearance.rounding.unsharpenmore

                            MaterialSymbol {
                                text: "alt_route"
                                fill: 1
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    const title = Ai.sessions.titleFor(Ai.sessionParentId);
                                    return title.length > 0
                                        ? Translation.tr("Branched from “%1”").arg(title)
                                        : Translation.tr("Branched from another chat");
                                }
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }

                            RippleButton {
                                implicitHeight: Math.round(Appearance.font.pixelSize.huge * 1.4)
                                leftPadding: Appearance.rounding.small
                                rightPadding: Appearance.rounding.small
                                topPadding: 0
                                bottomPadding: 0
                                buttonRadius: Appearance.rounding.full
                                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
                                colBackgroundHover: Appearance.colors.colLayer3Hover
                                colRipple: Appearance.colors.colLayer3Active
                                onClicked: Ai.sessions.openSession(Ai.sessionParentId)

                                Accessible.name: Translation.tr("Open the chat this one came from")

                                contentItem: StyledText {
                                    text: Translation.tr("Open the original")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer2
                                }

                                StyledToolTip {
                                    text: Translation.tr("The answer this one replaced is still there")
                                }
                            }
                        }
                    }
                }

                Item {
                    id: messagesArea
                    // Messages
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: messagesArea.width
                            height: messagesArea.height
                            radius: Appearance.rounding.small
                        }
                    }

                    // Animation properties
                    opacity: 0.0
                    scale: 0.85
                    transform: Translate {
                        id: messagesAreaTransform
                        y: 25
                    }

                    Connections {
                        target: root
                        function onEntranceTriggerChanged() {
                            if (root.entranceTrigger >= 0) {
                                messagesArea.opacity = 0.0;
                                messagesArea.scale = 0.85;
                                messagesAreaTransform.y = 25;
                                Qt.callLater(function() {
                                    messagesAreaAnim.start();
                                });
                            }
                        }
                    }

                    SequentialAnimation {
                        id: messagesAreaAnim
                        PauseAnimation { duration: 100 }
                        ParallelAnimation {
                            NumberAnimation { target: messagesArea; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                            NumberAnimation { target: messagesArea; property: "scale"; from: 0.85; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                            NumberAnimation { target: messagesAreaTransform; property: "y"; from: 25; to: 0; duration: 380; easing.type: Easing.OutCubic }
                        }
                    }

                    ScrollEdgeFade {
                        // Both ends of the transcript blur into the surface
                        // instead of stopping at it, and neither end shows
                        // itself while everything already fits.
                        z: 1
                        target: messageListView
                        vertical: true
                        blurEdges: true
                        fadeSize: Math.round(Appearance.font.pixelSize.huge * 1.8)
                        color: Appearance.colors.colLayer1
                    }

                    StyledListView { // Message list
                        id: messageListView
                        z: 0
                        // Inset rather than filled: a bubble that touches the
                        // rounded edge of the surface it sits on reads as
                        // overflowing it.
                        anchors.fill: parent
                        anchors.leftMargin: root.messageListInset
                        anchors.rightMargin: root.messageListInset
                        spacing: root.messageGap
                        popin: false
                        animateAppearance: false
                        topMargin: root.messageListInset
                        bottomMargin: root.messageListInset
                        // A flick that carries on past the last message reads as a
                        // rendering fault, not as elasticity, on a list this tall.
                        boundsBehavior: Flickable.StopAtBounds

                        touchpadScrollFactor: Config.options.interactions.scrolling.touchpadScrollFactor * 1.4
                        mouseScrollFactor: Config.options.interactions.scrolling.mouseScrollFactor * 1.4

                        /** How far the bottom of the list is from the bottom of the view. */
                        readonly property real bottomGap: Math.max(0, messageListView.originY + messageListView.contentHeight - messageListView.height - messageListView.contentY)
                        /**
                         * Whether an answer arriving should drag the view along. Asking
                         * `atYEnd` at the moment the content grows always says no — it
                         * has already grown by then — so what is remembered instead is
                         * where the reader was standing before it did.
                         */
                        property bool following: true
                        /** Which turn the keyboard is standing on, -1 for none. */
                        property int focusedIndex: -1
                        /**
                         * Set while the view is moving because it was told to. Its own
                         * scrolling would otherwise read as the reader walking away —
                         * an answer streaming in would stop being followed on its
                         * first token, and offer a button back to where it already was.
                         */
                        property bool pinning: false
                        /** Number of messages received below the reader. */
                        property int unseenMessageCount: 0
                        property int observedCount: 0

                        /**
                         * The very end, margins included. `positionViewAtEnd`
                         * stops at the last row and leaves the bottom margin
                         * below it, which is not the end as far as `atYEnd` is
                         * concerned — so the edge fade stayed on and blurred
                         * the newest message forever.
                         */
                        readonly property real maximumContentY: Math.max(messageListView.originY - messageListView.topMargin,
                            messageListView.originY + messageListView.contentHeight - messageListView.height + messageListView.bottomMargin)

                        function pinToEnd() {
                            messageListView.following = true;
                            messageListView.unseenMessageCount = 0;
                            messageListView.pinning = true;
                            messageListView.contentY = messageListView.maximumContentY;
                            messageListView.previousContentY = messageListView.contentY;
                            pinReleaseTimer.restart();
                        }

                        Component.onCompleted: messageListView.observedCount = messageListView.count

                        onFollowingChanged: {
                            if (messageListView.following)
                                messageListView.unseenMessageCount = 0;
                        }

                        Timer {
                            id: pinReleaseTimer
                            interval: Appearance.animation.scroll.duration + 80
                            onTriggered: messageListView.pinning = false
                        }

                        /**
                         * How close to the end still counts as standing at it. Only
                         * used to take the view *back* into following: moving up at
                         * all leaves it, however small the movement, because a band
                         * where an upward scroll is undone reads as the chat fighting
                         * back.
                         */
                        readonly property real followThreshold: Appearance.rounding.large

                        /** Where the view stood before this change, to read direction from. */
                        property real previousContentY: 0

                        // A gesture always has the final say, even mid-answer: it is
                        // the one thing here that is unambiguously the reader's doing.
                        onUserScrolled: (targetY, maxY) => {
                            messageListView.pinning = false;
                            if (targetY < messageListView.previousContentY - 0.5) {
                                messageListView.following = false;
                                return;
                            }
                            messageListView.following = (maxY - targetY) <= messageListView.followThreshold;
                        }
                        onDraggingChanged: {
                            if (messageListView.dragging)
                                messageListView.pinning = false;
                        }
                        onMovementEnded: messageListView.following = messageListView.bottomGap <= messageListView.followThreshold
                        onContentYChanged: {
                            const previous = messageListView.previousContentY;
                            messageListView.previousContentY = messageListView.contentY;
                            if (messageListView.pinning)
                                return;
                            // Upwards is unambiguous: the reader is walking back
                            // through the chat and nothing may pull them down again
                            // until they come back to the end themselves.
                            if (messageListView.contentY < previous - 0.5) {
                                messageListView.following = false;
                                return;
                            }
                            messageListView.following = messageListView.bottomGap <= messageListView.followThreshold;
                        }
                        onContentHeightChanged: {
                            if (!root.autoScrollEnabled || !messageListView.following)
                                return;
                            Qt.callLater(function () {
                                messageListView.pinToEnd();
                            });
                        }
                        // An answer arriving does not drag a reader who has
                        // walked back up the chat. Sending does — see
                        // `handleInput`, which pins deliberately.
                        onCountChanged: {
                            const added = messageListView.count - messageListView.observedCount;
                            if (added > 0 && !messageListView.following)
                                messageListView.unseenMessageCount += added;
                            messageListView.observedCount = messageListView.count;
                            if (!root.autoScrollEnabled || !messageListView.following)
                                return;
                            Qt.callLater(function () {
                                messageListView.pinToEnd();
                            });
                        }
                        // A chat that arrived while this list had no height —
                        // reopened from disk, or filled before the sidebar was
                        // ever shown — opens where it was left off, at the end.
                        onHeightChanged: {
                            if (root.autoScrollEnabled && messageListView.following)
                                Qt.callLater(function () {
                                    messageListView.pinToEnd();
                                });
                        }

                        add: null // Prevent function calls from being janky

                        model: ScriptModel {
                            values: Ai.messageIDs.filter(id => Ai.isTranscriptEntry(id))
                        }
                        delegate: AiMessage {
                            required property var modelData
                            required property int index

                            highlighted: messageListView.focusedIndex === index
                            // The id, not the row: this list hides messages the model
                            // sends itself, so a row number points at the wrong one.
                            messageId: modelData
                            messageData: {
                                Ai.messageByID[modelData];
                            }
                            reducedMotion: root.reducedMotion
                            transcriptRevealToken: root.transcriptRevealToken
                            transcriptRevealDelay: index * Math.max(1,
                                Math.round(Appearance.animation.elementMoveSmall.duration / 14))
                            onRegenerateRequested: id => controlBar.openRegenerate(id)
                            onModelPickerRequested: controlBar.togglePopover("model")
                            onEditRequested: (id, content) => root.beginEdit(id, content)
                        }
                    }

                    Item {
                        id: emptyStateStage
                        z: 2
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            bottom: emptyStateKeys.top
                            bottomMargin: Appearance.rounding.large
                        }
                        visible: emptyStatePlaceholder.shown

                        // Reserve the hint rail before centering the hero. The
                        // empty state therefore sits in the usable area from
                        // the rectangle's top to the hints, not behind them.
                        PagePlaceholder {
                            id: emptyStatePlaceholder
                            anchors.fill: parent
                            shown: Ai.messageIDs.length === 0
                            icon: (Ai.currentPersona && Ai.currentPersona.icon) ? Ai.currentPersona.icon : "neurology"
                            iconSize: Appearance.font.pixelSize.huge * 3
                            iconPadding: Appearance.rounding.normal
                            titlePixelSize: Appearance.font.pixelSize.huge
                            descriptionPixelSize: Appearance.font.pixelSize.normal
                            // A persona speaks with its own name; without one,
                            // the greeting rolls a fresh hello for this opening.
                            title: {
                                const personaName = Ai.currentPersona ? Ai.currentPersona.name : null;
                                if (personaName)
                                    return personaName;
                                return root.emptyStateGreeting.length > 0 ? root.emptyStateGreeting : Translation.tr("Hello");
                            }
                            description: (Ai.currentPersona && Ai.currentPersona.description) ? Ai.currentPersona.description : Translation.tr("Ask anything")
                            shape: MaterialShape.Shape.PixelCircle
                            animateIconOnShow: true
                            entranceTrigger: root.entranceTrigger
                            Component.onCompleted: root.refreshEmptyStateGreeting()
                        }

                    }

                    Loader {
                        // The keys worth knowing before the first message: one
                        // that opens the rest, and the three that decide where
                        // this sidebar lives.
                        id: emptyStateKeys
                        z: 3
                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            bottom: parent.bottom
                            bottomMargin: root.messageListInset * 2
                        }
                        width: Math.min(parent.width - root.messageListInset * 2, Appearance.font.pixelSize.huge * 20)
                        active: Config.options.sidebar.ai.emptyStateKeys && Ai.messageIDs.length === 0 && !root.canvasViewOpen
                        opacity: active ? 1 : 0
                        visible: opacity > 0.01

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        sourceComponent: ColumnLayout {
                            spacing: Appearance.rounding.unsharpenmore

                            EmptyStateKey {
                                Layout.fillWidth: true
                                keys: ["?"]
                                label: Translation.tr("All the keys this chat answers to")
                                actionable: true
                                onTriggered: controlBar.openShortcuts()
                            }

                            EmptyStateKey {
                                Layout.fillWidth: true
                                keys: ["Ctrl", "I"]
                                label: Translation.tr("What this chat can do, with example prompts")
                                actionable: true
                                onTriggered: controlBar.openCapabilities()
                            }

                            EmptyStateKey {
                                Layout.fillWidth: true
                                keys: ["Ctrl", "O"]
                                label: Translation.tr("Expand the sidebar")
                            }

                            EmptyStateKey {
                                Layout.fillWidth: true
                                keys: ["Ctrl", "D"]
                                label: Translation.tr("Detach it into its own window")
                            }

                            EmptyStateKey {
                                Layout.fillWidth: true
                                keys: ["Ctrl", "P"]
                                label: Translation.tr("Pin it open")
                            }
                        }
                    }

                    Loader {
                        // Find-in-chat, over the transcript rather than beside
                        // it: the list stays where it is and the field is one
                        // key away from being gone again.
                        id: transcriptSearchLoader
                        z: 4
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: root.messageListInset
                        }
                        active: root.transcriptSearchOpen
                        visible: active

                        sourceComponent: Rectangle {
                            implicitHeight: Math.round(Appearance.font.pixelSize.huge * 2)
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer2

                            Component.onCompleted: findField.forceActiveFocus()

                            RowLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Appearance.rounding.small
                                anchors.rightMargin: Appearance.rounding.unsharpenmore
                                spacing: Appearance.rounding.unsharpenmore

                                MaterialSymbol {
                                    text: "search"
                                    fill: 1
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colSubtext
                                }

                                StyledTextInput {
                                    id: findField
                                    Layout.fillWidth: true
                                    text: root.transcriptQuery
                                    color: Appearance.colors.colOnLayer2
                                    onTextChanged: {
                                        root.transcriptQuery = findField.text;
                                        root.transcriptMatchIndex = 0;
                                        if (root.transcriptMatches.length > 0)
                                            root.goToMatch(0);
                                    }
                                    Keys.onPressed: event => {
                                        if (event.key === Qt.Key_Escape) {
                                            root.transcriptSearchOpen = false;
                                            event.accepted = true;
                                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            root.goToMatch((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                                            event.accepted = true;
                                        }
                                    }

                                    StyledText {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        visible: findField.text.length === 0
                                        text: Translation.tr("Find in this chat")
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                StyledText {
                                    visible: root.transcriptQuery.trim().length > 0
                                    text: root.transcriptMatches.length > 0
                                        ? `${root.transcriptMatchIndex + 1}/${root.transcriptMatches.length}`
                                        : Translation.tr("none")
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }

                                FindStep {
                                    symbol: "keyboard_arrow_up"
                                    tooltipText: Translation.tr("Previous match")
                                    onTriggered: root.goToMatch(-1)
                                }

                                FindStep {
                                    symbol: "keyboard_arrow_down"
                                    tooltipText: Translation.tr("Next match")
                                    onTriggered: root.goToMatch(1)
                                }

                                FindStep {
                                    symbol: "close"
                                    tooltipText: Translation.tr("Close")
                                    onTriggered: root.transcriptSearchOpen = false
                                }
                            }
                        }
                    }

                    ScrollToBottomButton {
                        z: 3
                        target: messageListView
                        // Not `atYEnd`: an answer streaming in moves the view itself,
                        // and this would offer a way back to where the reader already
                        // was on every token.
                        shown: !emptyStatePlaceholder.shown && Ai.messageIDs.length > 0 && !messageListView.following && (messageListView.contentHeight > messageListView.height)
                        newItemCount: messageListView.unseenMessageCount
                        downAction: () => messageListView.pinToEnd()
                    }
                }
                DescriptionBox {
                    id: descriptionBox
                    text: (root.suggestionList[suggestions.selectedIndex] && root.suggestionList[suggestions.selectedIndex].description) ? root.suggestionList[suggestions.selectedIndex].description : ""
                    showArrows: root.suggestionList.length > 1

                    opacity: 0.0
                    scale: 0.85
                    transform: Translate {
                        id: descriptionBoxTransform
                        y: 25
                    }

                    Connections {
                        target: root
                        function onEntranceTriggerChanged() {
                            if (root.entranceTrigger >= 0) {
                                descriptionBox.opacity = 0.0;
                                descriptionBox.scale = 0.85;
                                descriptionBoxTransform.y = 25;
                                Qt.callLater(function() {
                                    descriptionBoxAnim.start();
                                });
                            }
                        }
                    }

                    SequentialAnimation {
                        id: descriptionBoxAnim
                        PauseAnimation { duration: 160 }
                        ParallelAnimation {
                            NumberAnimation { target: descriptionBox; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                            NumberAnimation { target: descriptionBox; property: "scale"; from: 0.85; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                            NumberAnimation { target: descriptionBoxTransform; property: "y"; from: 25; to: 0; duration: 380; easing.type: Easing.OutCubic }
                        }
                    }
                }
                FlowButtonGroup { // Suggestions
                    id: suggestions
                    visible: root.suggestionList.length > 0 && messageInputField.text.length > 0
                    property int selectedIndex: 0
                    Layout.fillWidth: true
                    spacing: 5

                    opacity: visible ? 1.0 : 0.0
                    scale: visible ? 1.0 : 0.85
                    transform: Translate {
                        id: suggestionsTransform
                        y: visible ? 0 : 25
                    }

                    Connections {
                        target: root
                        function onEntranceTriggerChanged() {
                            if (root.entranceTrigger >= 0 && suggestions.visible) {
                                suggestions.opacity = 0.0;
                                suggestions.scale = 0.85;
                                suggestionsTransform.y = 25;
                                Qt.callLater(function() {
                                    suggestionsAnim.start();
                                });
                            }
                        }
                    }

                    SequentialAnimation {
                        id: suggestionsAnim
                        PauseAnimation { duration: 280 }
                        ParallelAnimation {
                            NumberAnimation { target: suggestions; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                            NumberAnimation { target: suggestions; property: "scale"; from: 0.85; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                            NumberAnimation { target: suggestionsTransform; property: "y"; from: 25; to: 0; duration: 380; easing.type: Easing.OutCubic }
                        }
                    }

                    Repeater {
                        id: suggestionRepeater
                        model: {
                            suggestions.selectedIndex = 0;
                            return root.suggestionList.slice(0, 10);
                        }
                        delegate: ApiCommandButton {
                            id: commandButton
                            required property int index
                            required property var modelData
                            colBackground: suggestions.selectedIndex === index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                            bounce: false
                    
                            opacity: 0.0
                            transform: Translate {
                                id: cmdBtnTranslate
                                y: 10
                            }

                            Component.onCompleted: {
                                btnEntranceAnim.start();
                            }

                            SequentialAnimation {
                                id: btnEntranceAnim
                                PauseAnimation { duration: index * 40 }
                                ParallelAnimation {
                                    NumberAnimation { target: commandButton; property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: cmdBtnTranslate; property: "y"; from: 10; to: 0; duration: 280; easing.type: Easing.OutBack }
                                }
                            }

                            contentItem: StyledText {
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.m3colors.m3onSurface
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.displayName ?? modelData.name
                            }

                            onHoveredChanged: {
                                if (commandButton.hovered) {
                                    suggestions.selectedIndex = index;
                                }
                            }
                            onClicked: {
                                suggestions.acceptSuggestion(modelData.name);
                            }
                        }
                    }

                    function acceptSuggestion(word) {
                        const words = messageInputField.text.trim().split(/\s+/);
                        if (words.length > 0) {
                            words[words.length - 1] = word;
                        } else {
                            words.push(word);
                        }
                        const updatedText = words.join(" ") + " ";
                        messageInputField.text = updatedText;
                        messageInputField.cursorPosition = messageInputField.text.length;
                        messageInputField.forceActiveFocus();
                    }

                    function acceptSelectedWord() {
                        if (suggestions.selectedIndex >= 0 && suggestions.selectedIndex < suggestionRepeater.count) {
                            const word = root.suggestionList[suggestions.selectedIndex].name;
                            suggestions.acceptSuggestion(word);
                        }
                    }
                }
            }
        }

        // ════════════════════════════════════════════════════════
        // 3. BOTTOM COMPOSER RECTANGLE
        // ════════════════════════════════════════════════════════

        Rectangle {
            id: composerSurface
            Layout.fillWidth: true
            // Deliberately never fillHeight: the composer owns exactly the
            // height its content needs, and the chat area above absorbs the
            // difference, so attachments and extra input lines push this
            // surface upward instead of squashing its own contents.
            implicitHeight: composerColumn.implicitHeight + root.padding * 2
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.large
            clip: true

            ColumnLayout {
                id: composerColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: root.padding
                }
                spacing: root.padding

                Rectangle { // Input area
                    id: inputWrapper
                    property real spacing: 5
                    Layout.fillWidth: true
                    radius: 0
                    color: "transparent"
                    // The room above the row belongs to the attachment tray, so with
                    // nothing attached it is given back: an empty tray still charging
                    // for its spacing left the whole composer sitting low in its own
                    // box, which reads as the buttons being off-centre.
                    // The tray and the column are the whole composer now, so
                    // its height is simply theirs; an empty tray charges nothing.
                    implicitHeight: composerColumnLayout.implicitHeight + root.composerInset * 2
                        + (attachmentTray.implicitHeight > 0
                            ? attachmentTray.implicitHeight + root.composerGap + attachmentTray.anchors.topMargin
                            : 0)
                    clip: true

                    FastBlur {
                        id: inputBlur
                        radius: 0
                    }

                    layer.enabled: inputBlur.radius > 0
                    layer.effect: Component {
                        FastBlur {
                            radius: inputBlur.radius
                        }
                    }

                    opacity: 0.0
                    transform: Translate {
                        id: inputWrapperTransform
                        y: 40
                    }

                    Connections {
                        target: root
                        function onEntranceTriggerChanged() {
                            if (root.entranceTrigger >= 0) {
                                inputWrapper.opacity = 0.0;
                                inputBlur.radius = 20;
                                inputWrapperTransform.y = 40;
                                Qt.callLater(function() {
                                    inputWrapperAnim.start();
                                });
                            }
                        }
                    }

                    SequentialAnimation {
                        id: inputWrapperAnim
                        PauseAnimation { duration: 320 }
                        ParallelAnimation {
                            NumberAnimation { target: inputWrapper; property: "opacity"; from: 0.0; to: 1.0; duration: 320; easing.type: Easing.OutCubic }
                            NumberAnimation { target: inputBlur; property: "radius"; from: 20; to: 0; duration: 350; easing.type: Easing.OutCubic }
                            NumberAnimation { target: inputWrapperTransform; property: "y"; from: 40; to: 0; duration: 450; easing.type: Easing.OutExpo }
                        }
                    }

                    Behavior on implicitHeight {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }

                    AiAttachmentTray {
                        id: attachmentTray
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            margins: visible ? 5 : 0
                        }
                        // The sheet over the transcript is the one that speaks
                        // during a drag now that the whole panel accepts one.
                        // Saying it here too put the same sentence on screen
                        // twice, a few rows apart.
                        dragHint: ""
                    }

                    ColumnLayout {
                        id: composerColumnLayout
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                            margins: root.composerInset
                        }
                        spacing: root.composerGap

                        // A quiet ruler makes the request budget legible
                        // before sending. The service estimates the same
                        // prompt, attachments, history and saved summary that
                        // `historyWithinWindow()` will use when it submits.
                        Item {
                            id: contextRuler
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(Appearance.rounding.small,
                                contextRuler.thickness + Appearance.rounding.unsharpenmore)
                            visible: contextRuler.window > 0

                            readonly property int window: Number((Ai.currentModelEntry && Ai.currentModelEntry.contextWindow) ? Ai.currentModelEntry.contextWindow : 0)
                            readonly property int historyTokens: Number(Ai.estimatedContextTokens ?? 0)
                            readonly property int memoryTokens: Ai.estimateTokens(Ai.contextSummary)
                            readonly property int promptTokens: Ai.estimateTokens(messageInputField.text)
                            readonly property int attachmentTokens: Ai.estimateMessageTokens({ attachments: Ai.attachments })
                            readonly property int totalTokens: historyTokens + promptTokens + attachmentTokens
                            readonly property int safeLimit: Math.max(0, window - Ai.contextReserve)
                            readonly property bool pruningOnNextPrompt: totalTokens > safeLimit
                            readonly property real fraction: window > 0 ? Math.min(1, totalTokens / window) : 0
                            readonly property real thickness: Math.max(1, Math.round(Appearance.rounding.unsharpenmore / 3))
                            readonly property color tint: pruningOnNextPrompt
                                ? Appearance.m3colors.m3tertiary
                                : Appearance.colors.colPrimary

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: contextRuler.thickness
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colOutlineVariant
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                width: parent.width * contextRuler.fraction
                                height: contextRuler.thickness
                                radius: Appearance.rounding.full
                                color: contextRuler.tint

                                Behavior on width {
                                    enabled: !root.reducedMotion
                                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                                }

                                Behavior on color {
                                    enabled: !root.reducedMotion
                                    ColorAnimation {
                                        duration: Appearance.animation.elementMoveSmall.duration
                                        easing.type: Appearance.animation.elementMoveSmall.type
                                        easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                                    }
                                }
                            }

                            MouseArea {
                                id: contextRulerHover
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }

                            StyledToolTip {
                                extraVisibleCondition: false
                                alternativeVisibleCondition: contextRulerHover.containsMouse
                                text: {
                                    const parts = [
                                        Translation.tr("History: %1 tokens").arg(String(contextRuler.historyTokens)),
                                        Translation.tr("Saved memory: %1 tokens").arg(String(contextRuler.memoryTokens)),
                                        Translation.tr("Draft: %1 tokens").arg(String(contextRuler.promptTokens)),
                                        Translation.tr("Attachments: %1 tokens").arg(String(contextRuler.attachmentTokens)),
                                        Translation.tr("Reserve for the answer: %1 tokens").arg(String(Ai.contextReserve))
                                    ];
                                    if (contextRuler.pruningOnNextPrompt)
                                        parts.push(Translation.tr("Sending this prompt will summarize the oldest turns."));
                                    return parts.join("\n");
                                }
                            }

                            Accessible.name: contextRuler.pruningOnNextPrompt
                                ? Translation.tr("Context ruler: the next prompt will summarize older turns")
                                : Translation.tr("Context ruler: %1 of %2 tokens").arg(String(contextRuler.totalTokens)).arg(String(contextRuler.window))
                        }

                        // ── the message, always on its own line above the controls ──
                        ScrollView {
                            Layout.fillWidth: true
                            // Grows with the message and then scrolls, so a long
                            // draft pushes the composer up instead of running past it.
                            Layout.preferredHeight: Math.min(root.height * 0.4, messageInputField.implicitHeight)
                            id: inputScrollView
                            clip: true
                            ScrollBar.vertical.policy: ScrollBar.AsNeeded

                            StyledTextArea { // The actual TextArea (inside ScrollView to enable scrolling)
                                id: messageInputField
                                anchors.fill: parent
                                wrapMode: TextArea.Wrap
                                padding: 10
                                color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                                placeholderText: root.editingMessageId.length > 0
                                    ? Translation.tr("Rewrite the question — Esc to leave it as it was")
                                    : Translation.tr('Message the model... "%1" for commands').arg(root.commandPrefix)

                                background: null

                                onTextChanged: {
                                    // Kept per chat, so switching away and back does
                                    // not throw away a half-written message.
                                    Ai.draft = messageInputField.text;

                                    // Any change that did not come from
                                    // walking the history — typing, pasting,
                                    // the async draft clear after a send —
                                    // means the reader is done recalling.
                                    if (!root.navigatingPromptHistory && root.promptHistoryIndex !== -1)
                                        root.resetPromptHistory();

                                    // Handle suggestions
                                    if (messageInputField.text.length === 0) {
                                        root.suggestionQuery = "";
                                        root.suggestionList = [];
                                        return;
                                    } else if (messageInputField.text.startsWith(`${root.commandPrefix}provider`)) {
                                        root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                
                                        const providers = Ai.providerIds

                                        const providerResults = Fuzzy.go(root.suggestionQuery, providers.map(p => ({
                                            name: Fuzzy.prepare(p),
                                            obj: p
                                        })), {
                                            all: true,
                                            key: "name"
                                        });
                                
                                        root.suggestionList = providerResults.map(result => {
                                            const providerName = result.target;
                                            const providerInfo = Ai.providers[providerName];
                                            return {
                                                name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "provider ") : ""}${providerName}`,
                                                displayName: (providerInfo && providerInfo.name) ? providerInfo.name : providerName,
                                                description: (providerInfo && providerInfo.description) ? providerInfo.description : ""
                                            };
                                        });
                                    } else if (messageInputField.text.startsWith(`${root.commandPrefix}model`)) {
                                        root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                            
                                        const providerModels = Ai.modelsOfProviders[Ai.currentProvider] ?? [];
                            
                                        const modelList = providerModels.map(model => ({
                                            name: Fuzzy.prepare(model.value),
                                            obj: model
                                        }));

                                        const modelResults = Fuzzy.go(root.suggestionQuery, modelList, {
                                            all: true,
                                            key: "name"
                                        });
                            
                                        root.suggestionList = modelResults.map(result => {
                                            const modelValue = result.target;
                                            const model = providerModels.find(m => m.value === modelValue);
                                    
                                            return {
                                                name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "model ") : ""}${model.value}`,
                                                displayName: model.title,
                                                description: `Provider: ${model.modelProvider || Ai.currentProvider}`
                                            };
                                        });
                                    } else if (messageInputField.text.startsWith(`${root.commandPrefix}prompt`)) {
                                        root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                        const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.promptFiles.map(file => {
                                            return {
                                                name: Fuzzy.prepare(file),
                                                obj: file
                                            };
                                        }), {
                                            all: true,
                                            key: "name"
                                        });
                                        root.suggestionList = promptFileResults.map(file => {
                                            return {
                                                name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "prompt ") : ""}${file.target}`,
                                                displayName: `${FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target))}`,
                                                description: Translation.tr("Load prompt from %1").arg(file.target)
                                            };
                                        });
                                    } else if (messageInputField.text.startsWith(`${root.commandPrefix}load`)) {
                                        root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                        const chatResults = Fuzzy.go(root.suggestionQuery, Ai.sessions.index.map(entry => {
                                            return {
                                                name: Fuzzy.prepare(entry.title),
                                                obj: entry
                                            };
                                        }), {
                                            all: true,
                                            key: "name"
                                        });
                                        root.suggestionList = chatResults.map(result => {
                                            const chatName = result.obj.title;
                                            return {
                                                name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "load ") : ""}${chatName}`,
                                                displayName: `${chatName}`,
                                                description: result.obj.preview
                                            };
                                        });
                                    } else if (messageInputField.text.startsWith(`${root.commandPrefix}tool`)) {
                                        root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                        const toolResults = Fuzzy.go(root.suggestionQuery, Ai.availableTools.map(tool => {
                                            return {
                                                name: Fuzzy.prepare(tool),
                                                obj: tool
                                            };
                                        }), {
                                            all: true,
                                            key: "name"
                                        });
                                        root.suggestionList = toolResults.map(tool => {
                                            const toolName = tool.target;
                                            return {
                                                name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "tool ") : ""}${tool.target}`,
                                                displayName: toolName,
                                                description: Ai.toolDescriptions[toolName]
                                            };
                                        });
                                    } else if (/(^|\s)@[^\s]*$/.test(messageInputField.text)) {
                                        // Only the token being typed is matched, so
                                        // `@` in the middle of a sentence still works.
                                        const typed = messageInputField.text.match(/(^|\s)@([^\s]*)$/)[2] ?? "";
                                        root.suggestionQuery = typed;
                                        const needle = typed.toLowerCase();
                                        root.suggestionList = root.referenceSources
                                            .filter(source => needle.length === 0
                                                || source.token.toLowerCase().indexOf(needle) >= 0
                                                || source.label.toLowerCase().indexOf(needle) >= 0)
                                            .map(source => ({
                                                name: `@${source.token}`,
                                                displayName: source.label,
                                                description: source.detail
                                            }));
                                    } else if (messageInputField.text.startsWith(root.commandPrefix)) {
                                        root.suggestionQuery = messageInputField.text;
                                        root.suggestionList = root.allCommands.filter(cmd => cmd.name.startsWith(messageInputField.text.substring(1))).map(cmd => {
                                            return {
                                                name: `${root.commandPrefix}${cmd.name}`,
                                                description: `${cmd.description}`
                                            };
                                        });
                                    }
                                }

                                Keys.onPressed: event => {
                                    // `?` on an empty composer is the way into the
                                    // list of keys; with anything typed it is just a
                                    // question mark.
                                    if (event.text === "?" && messageInputField.text.length === 0) {
                                        controlBar.openShortcuts();
                                        event.accepted = true;
                                        return;
                                    }
                                    if (root.handleShortcut(event)) {
                                        event.accepted = true;
                                        return;
                                    }
                                    if (event.key === Qt.Key_Tab && suggestions.visible) {
                                        suggestions.acceptSelectedWord();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Tab) {
                                        // With nothing to complete, Tab is what it is
                                        // everywhere else: the way to the next control.
                                        event.accepted = false;
                                    } else if (event.key === Qt.Key_Up && suggestions.visible) {
                                        suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Down && suggestions.visible) {
                                        suggestions.selectedIndex = Math.min(root.suggestionList.length - 1, suggestions.selectedIndex + 1);
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Up && event.modifiers === Qt.NoModifier && root.editingMessageId.length === 0
                                            && (messageInputField.text.length === 0 || root.promptHistoryIndex !== -1)) {
                                        // Recall an earlier prompt, like a shell's history — only
                                        // from an empty draft, so mid-line cursor movement in a
                                        // real multi-line message is never hijacked.
                                        if (root.stepPromptHistory(-1))
                                            event.accepted = true;
                                    } else if (event.key === Qt.Key_Down && event.modifiers === Qt.NoModifier && root.editingMessageId.length === 0
                                            && (messageInputField.text.length === 0 || root.promptHistoryIndex !== -1)) {
                                        if (root.stepPromptHistory(1))
                                            event.accepted = true;
                                    } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                                        const useCtrlEnter = Config.options.sidebar.ai.sendKey === "ctrlEnter";
                                        const holdsControl = (event.modifiers & Qt.ControlModifier) !== 0;
                                        const holdsShift = (event.modifiers & Qt.ShiftModifier) !== 0;
                                        const shouldSend = useCtrlEnter
                                            ? (holdsControl && !holdsShift)
                                            : (!holdsControl && !holdsShift);
                                        if (shouldSend) {
                                            const inputText = messageInputField.text;
                                            root.handleInput(inputText);
                                            event.accepted = true;
                                        } else {
                                            // Shift+Enter always writes a new
                                            // line; Ctrl+Enter does too when
                                            // the configured send shortcut is
                                            // the ordinary Enter key.
                                            messageInputField.insert(messageInputField.cursorPosition, "\n");
                                            event.accepted = true;
                                        }
                                    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                        // Intercept Ctrl+V to handle image/file pasting
                                        if (event.modifiers & Qt.ShiftModifier) {
                                            // Let Shift+Ctrl+V = plain paste
                                            messageInputField.text += Quickshell.clipboardText;
                                            event.accepted = true;
                                            return;
                                        }
                                        // Try image paste first
                                        const currentClipboardEntry = Cliphist.entries[0];
                                        const cleanCliphistEntry = StringUtils.cleanCliphistEntry(currentClipboardEntry);
                                        if (/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(currentClipboardEntry)) {
                                            // First entry = currently copied entry = image?
                                            decodeImageAndAttachProc.handleEntry(currentClipboardEntry);
                                            event.accepted = true;
                                            return;
                                        } else if (cleanCliphistEntry.startsWith("file://")) {
                                            // First entry = currently copied entry = image?
                                            const fileName = decodeURIComponent(cleanCliphistEntry);
                                            Ai.attachFile(fileName);
                                            event.accepted = true;
                                            return;
                                        }
                                        event.accepted = false; // No image, let text pasting proceed
                                    } else if (event.key === Qt.Key_Escape) {
                                        // Esc backs out of whatever the composer is
                                        // in the middle of, one step at a time.
                                        if (root.editingMessageId.length > 0) {
                                            root.cancelEdit();
                                            event.accepted = true;
                                        } else if (Ai.attachments.length > 0) {
                                            Ai.clearAttachments();
                                            event.accepted = true;
                                        } else {
                                            event.accepted = false;
                                        }
                                    }
                                }
                            }
                        }

                        // ── the controls ──
                        // ── the controls ──
                        //
                        // Two pages that slide, the way the Bluetooth dialog
                        // shows a device and then what can be done with it.
                        // The ways of attaching take the place of the model and
                        // the send button instead of shoving them sideways.
                        Flickable {
                            id: composerControlsRow
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.composerControlExtent
                            contentWidth: composerControlsRow.width * 2 + root.composerGap
                            contentHeight: composerControlsRow.height
                            interactive: false
                            clip: true

                            contentX: root.attachmentsExpanded
                                ? (composerControlsRow.width + root.composerGap)
                                : 0

                            Behavior on contentX {
                                NumberAnimation {
                                    duration: 400
                                    easing.type: Easing.OutExpo
                                }
                            }

                            Row {
                                height: composerControlsRow.height
                                spacing: root.composerGap

                                // PAGE 1 — write and send
                                RowLayout {
                                    width: composerControlsRow.width
                                    height: composerControlsRow.height
                                    spacing: root.composerGap

                                    ComposerCircleButton {
                                        symbol: "add"
                                        onTriggered: root.attachmentsExpanded = true

                                        StyledToolTip {
                                            extraVisibleCondition: false
                                            alternativeVisibleCondition: parent.hovered
                                            text: Translation.tr("Attach something")
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 1
                                    }

                                    // Which model is answering, and a way to
                                    // change it without leaving the composer.
                                    RippleButton {
                                        id: composerModelPill

                                        /**
                                         * Everything the fixed controls leave over.
                                         *
                                         * This was a flat 62% of the row, which on a
                                         * narrow sidebar is more than what is actually
                                         * free: the plus, the microphone and the send
                                         * button plus their gaps take the rest and then
                                         * some. A RowLayout cannot shrink an item below
                                         * its implicit width, so the overflow went to
                                         * the trailing controls and pushed them off the
                                         * edge. Counting the circles exactly is what
                                         * keeps a long model name cutting itself
                                         * instead of cutting the send button.
                                         */
                                        readonly property int fixedCircles: 2 + (voiceButton.visible ? 1 : 0)
                                        readonly property real widthLimit: Math.max(root.composerControlExtent,
                                            composerControlsRow.width
                                                - root.composerControlExtent * composerModelPill.fixedCircles
                                                - root.composerGap * (composerModelPill.fixedCircles + 1))

                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.maximumWidth: composerModelPill.widthLimit
                                        // Says the pill may be squeezed. Without it the
                                        // layout would rather overflow than shrink it.
                                        Layout.minimumWidth: root.composerControlExtent
                                        implicitHeight: root.composerControlExtent
                                        // Measured off the label rather than off the row
                                        // it sits in: a filling child inside a Control's
                                        // content item feeds the Control's own width back
                                        // into itself, and Layouts abort the pass.
                                        implicitWidth: Math.min(composerModelPill.widthLimit,
                                            composerModelLabel.implicitWidth + composerModelIcon.implicitWidth
                                            + composerModelRow.spacing + root.composerControlExtent * 0.6)
                                        buttonRadius: Appearance.rounding.full
                                        topPadding: 0
                                        bottomPadding: 0
                                        colBackground: Appearance.colors.colPrimary
                                        colBackgroundHover: Appearance.colors.colPrimaryHover
                                        colRipple: Appearance.colors.colPrimaryActive
                                        onClicked: controlBar.togglePopover("model")

                                        contentItem: RowLayout {
                                            id: composerModelRow
                                            spacing: Appearance.rounding.unsharpenmore

                                            MaterialSymbol {
                                                id: composerModelIcon
                                                text: (Ai.currentModelEntry && Ai.currentModelEntry.materialIcon) ? Ai.currentModelEntry.materialIcon : "auto_awesome"
                                                fill: 1
                                                iconSize: Appearance.font.pixelSize.larger
                                                color: Appearance.colors.colOnPrimary
                                            }

                                            StyledText {
                                                id: composerModelLabel
                                                Layout.maximumWidth: Math.max(0, composerModelPill.widthLimit
                                                    - composerModelIcon.implicitWidth - composerModelRow.spacing
                                                    - root.composerControlExtent * 0.6)
                                                text: (Ai.currentModelEntry && Ai.currentModelEntry.title) ? Ai.currentModelEntry.title : Translation.tr("No model")
                                                font.pixelSize: Appearance.font.pixelSize.normal
                                                font.bold: true
                                                elide: Text.ElideRight
                                                color: Appearance.colors.colOnPrimary
                                            }

                                        }

                                        StyledToolTip {
                                            // The reasoning level lives here
                                            // rather than in the pill: the name
                                            // is what has to be readable at a
                                            // glance, and the level is a detail
                                            // worth a hover.
                                            text: {
                                                const name = (Ai.currentModelEntry && Ai.currentModelEntry.name) ? Ai.currentModelEntry.name : Translation.tr("none");
                                                if (!Ai.currentModelThinks || root.thinkingShortLabel.length === 0)
                                                    return Translation.tr("Model: %1").arg(name);
                                                return Translation.tr("Model: %1\nThinking: %2").arg(name).arg(root.thinkingShortLabel);
                                            }
                                        }
                                    }

                                    ComposerCircleButton { // Dictate a message with the local voice backend
                                        id: voiceButton
                                        visible: Config.options.ai.voice.enabled
                                        toggled: Ai.voiceService.state === "recording"
                                        spinning: Ai.voiceService.state === "transcribing"
                                        enabled: Ai.voiceService.state !== "transcribing"
                                        symbol: {
                                            switch (Ai.voiceService.state) {
                                            case "recording": return "stop";
                                            case "transcribing": return "progress_activity";
                                            default: return "mic";
                                            }
                                        }
                                        onTriggered: {
                                            switch (Ai.voiceService.state) {
                                            case "recording":
                                                Ai.voiceService.stopRecording();
                                                break;
                                            case "transcribing":
                                                break;
                                            case "error":
                                                Ai.voiceService.cancel();
                                                Ai.voiceService.startRecording("sidebar");
                                                break;
                                            default:
                                                Ai.voiceService.startRecording("sidebar");
                                                break;
                                            }
                                        }

                                        StyledToolTip {
                                            extraVisibleCondition: false
                                            alternativeVisibleCondition: parent.hovered
                                            text: {
                                                switch (Ai.voiceService.state) {
                                                case "recording":
                                                    return Translation.tr("Recording… %1s — click to stop").arg(Math.round(Ai.voiceService.recordingElapsedMs / 1000));
                                                case "transcribing":
                                                    return Translation.tr("Transcribing…");
                                                case "error":
                                                    return Ai.voiceService.errorText;
                                                default:
                                                    return Ai.voiceService.available ? Translation.tr("Dictate a message") : Ai.voiceService.unavailableReason();
                                                }
                                            }
                                        }
                                    }

                                    RippleButton { // Send button, or Stop while a reply is coming in
                                        id: sendButton
                                        readonly property bool stopping: Ai.isGenerating

                                        implicitWidth: root.composerControlExtent
                                        implicitHeight: root.composerControlExtent
                                        buttonRadius: Appearance.rounding.full
                                        enabled: sendButton.stopping || messageInputField.text.length > 0
                                        toggled: enabled
                                        topPadding: 0
                                        bottomPadding: 0
                                        leftPadding: 0
                                        rightPadding: 0

                                        Behavior on enabled {
                                            SequentialAnimation {
                                                PauseAnimation { duration: 50 }
                                                NumberAnimation {
                                                    target: sendButton
                                                    property: "opacity"
                                                    to: sendButton.enabled ? 1.0 : 0.5
                                                    duration: 200
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: sendButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (sendButton.stopping) {
                                                    Ai.stopGeneration();
                                                    return;
                                                }
                                                const inputText = messageInputField.text;
                                                root.handleInput(inputText);
                                            }
                                        }

                                        contentItem: MaterialSymbol {
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            iconSize: 22
                                            color: sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                                            text: sendButton.stopping ? "stop" : "arrow_upward"
                                            fill: 1
                                        }

                                        StyledToolTip {
                                            text: AiActionRegistry.tooltip(sendButton.stopping ? "stop" : "send", {
                                                surface: "sidebar",
                                                busy: sendButton.stopping,
                                                text: messageInputField.text
                                            })
                                        }
                                    }
                                }

                                // PAGE 2 — what can be attached
                                RowLayout {
                                    width: composerControlsRow.width
                                    height: composerControlsRow.height
                                    spacing: root.composerGap

                                    ComposerCircleButton {
                                        symbol: "arrow_forward"
                                        onTriggered: root.attachmentsExpanded = false

                                        StyledToolTip {
                                            extraVisibleCondition: false
                                            alternativeVisibleCondition: parent.hovered
                                            text: Translation.tr("Back")
                                        }
                                    }

                                    // The options scroll on their own: the
                                    // composer is as wide as the sidebar and
                                    // this list is not, and it only grows as
                                    // more ways of attaching are added.
                                    Flickable {
                                        id: composerActionsFlick
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        contentWidth: composerActionsRow.implicitWidth
                                        contentHeight: composerActionsFlick.height
                                        flickableDirection: Flickable.HorizontalFlick
                                        boundsBehavior: Flickable.StopAtBounds
                                        interactive: composerActionsFlick.contentWidth > composerActionsFlick.width
                                        clip: true

                                        MouseArea {
                                            // Most mice only send a vertical
                                            // wheel, so it is turned sideways
                                            // here — and left alone when
                                            // everything already fits.
                                            anchors.fill: parent
                                            acceptedButtons: Qt.NoButton
                                            enabled: composerActionsFlick.interactive
                                            onWheel: wheel => {
                                                const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                                                const limit = composerActionsFlick.contentWidth - composerActionsFlick.width;
                                                composerActionsFlick.contentX = Math.max(0, Math.min(limit, composerActionsFlick.contentX - delta));
                                                wheel.accepted = true;
                                            }
                                        }

                                        Row {
                                            id: composerActionsRow
                                            height: composerActionsFlick.height
                                            spacing: root.composerGap

                                            ComposerActionPill {
                                                symbol: "attach_file"
                                                label: Translation.tr("Attach files")
                                                onTriggered: {
                                                    Ai.pickFiles();
                                                    root.attachmentsExpanded = false;
                                                }
                                            }

                                            ComposerActionPill {
                                                symbol: "screenshot_region"
                                                label: Translation.tr("Send part of the screen")
                                                enabled: Ai.currentModelSupportsVision
                                                disabledReason: Translation.tr("%1 cannot look at images.").arg((Ai.currentModelEntry && Ai.currentModelEntry.title) ? Ai.currentModelEntry.title : Translation.tr("This model"))
                                                onTriggered: {
                                                    if (!root.snipHeld) {
                                                        root.snipHeld = true;
                                                        root.holdSidebarOpen();
                                                        snipHoldTimeout.restart();
                                                    }
                                                    GlobalStates.snipForAiRequested();
                                                    root.attachmentsExpanded = false;
                                                }
                                            }

                                            ComposerActionPill {
                                                symbol: "content_paste"
                                                label: Translation.tr("Attach clipboard text")
                                                onTriggered: {
                                                    Ai.attachClipboardContext();
                                                    root.attachmentsExpanded = false;
                                                }
                                            }

                                            ComposerActionPill {
                                                symbol: "select_window"
                                                label: Translation.tr("Attach launcher result")
                                                onTriggered: {
                                                    Ai.attachLauncherContext();
                                                    root.attachmentsExpanded = false;
                                                }
                                            }

                                            ComposerActionPill {
                                                symbol: "desktop_windows"
                                                label: Translation.tr("Attach active application")
                                                onTriggered: {
                                                    Ai.attachActiveWindowContext();
                                                    root.attachmentsExpanded = false;
                                                }
                                            }
                                        }
                                    }

                                    ScrollEdgeFade {
                                        // Says there is more to the right, and
                                        // fades out once the end is reached.
                                        parent: composerActionsFlick
                                        target: composerActionsFlick
                                        vertical: false
                                        color: Appearance.colors.colLayer1
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

}
