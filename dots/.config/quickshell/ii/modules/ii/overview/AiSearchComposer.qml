pragma ComponentBehavior: Bound

import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.services.ai.blocks
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Keyboard-first composer for the overview AI surface.
 *
 * The compact rail keeps the prompt, model and send action on one line. Its
 * chevron changes the rail in place instead of opening a popup: tools, models
 * and response effort slide inside the same clipped, full-radius surface.
 */
ColumnLayout {
    id: root

    signal requestSend(string text)
    signal requestEscape
    signal requestOpenHistory
    signal requestOpenModels
    signal requestOpenShortcuts
    signal requestFocusNext
    signal requestFocusPrev

    readonly property int maximumLines: 6
    readonly property int maximumCharacters: 12000
    readonly property real lineHeight: Math.round(draftInput.font.pixelSize * 1.5)
    readonly property real maximumEditorHeight: root.lineHeight * root.maximumLines + root.controlPadding * 2
    readonly property real controlExtent: Math.round(Appearance.font.pixelSize.huge * 2)
    readonly property real controlPadding: Appearance.rounding.small
    readonly property real controlGap: Appearance.rounding.verysmall
    readonly property real horizontalInset: Appearance.rounding.normal
    readonly property real chipPadding: Appearance.rounding.small
    readonly property real iconTextGap: Appearance.rounding.verysmall
    readonly property real railSlideDistance: Math.max(root.controlExtent, Appearance.rounding.large)
    readonly property bool hasDraft: draftInput.text.trim().length > 0
    readonly property real maximumCompactModelWidth: Math.max(root.controlExtent * 2, composerSurface.width * 0.45)
    // Zero when the voice button is hidden, so the reserved margin below
    // collapses back to the original two-button layout instead of leaving
    // a gap where a disabled feature used to be.
    readonly property real voiceButtonReserve: Config.options.ai.voice.enabled ? (root.controlExtent + root.controlGap) : 0
    readonly property real compactDraftWidth: Math.max(0, composerStage.width - root.controlExtent * 2 - root.controlGap * 2 - modelButton.implicitWidth - root.voiceButtonReserve)
    // The probe is always measured at the compact-row width. Unlike the live
    // editor, its width never changes when this condition turns true, which
    // prevents multiline expansion from feeding back into itself.
    readonly property bool longDraft: compactDraftProbe.lineCount > 1
    readonly property real expandedEditorHeight: Math.max(root.controlExtent, Math.min(root.maximumEditorHeight, draftInput.contentHeight + root.controlPadding * 2))
    readonly property string modelTitle: Ai.currentModelEntry?.title ?? Translation.tr("No model")
    readonly property string modelSymbol: Ai.currentModelEntry?.materialIcon ?? "auto_awesome"
    readonly property string modelIcon: Ai.currentModelEntry?.icon ?? ""
    readonly property bool webActive: Ai.webMode !== "off"

    // Only one rail is visible at a time. This preserves the prompt while a
    // keyboard user changes a setting and mirrors the one-surface navigation
    // used by the Wi-Fi and Bluetooth dialogs.
    property string activeRail: "composer"
    property bool syncingDraft: false

    // ── Prompt history (Up/Down, like a shell) ──────────────────────────
    // -1 means "not navigating": the composer holds whatever the user is
    // actually writing. Pressing Up from an empty draft starts the walk at
    // the most recent prompt; Down retraces it and hands the original draft
    // back once it walks off the newest end. Shared with the sidebar
    // composer through `Ai.ownPromptHistory` — one conversation, one history.
    property int promptHistoryIndex: -1
    property string promptHistoryDraftBackup: ""
    property bool navigatingPromptHistory: false
    property bool modelsOpen: false

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

    Layout.fillWidth: true
    implicitHeight: composerSurface.implicitHeight

    function setDraft(value) {
        root.syncingDraft = true;
        draftInput.text = String(value ?? "");
        root.syncingDraft = false;
    }

    function applyPromptHistoryText(text) {
        root.navigatingPromptHistory = true;
        root.setDraft(text);
        Ai.draft = text;
        draftInput.cursorPosition = draftInput.length;
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
            root.promptHistoryDraftBackup = draftInput.text;
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

    function send() {
        if (Ai.isGenerating) {
            Ai.stopGeneration();
            return;
        }
        const text = draftInput.text.trim();
        if (text.length === 0)
            return;
        root.requestSend(text);
    }

    function focusInput() {
        root.activeRail = "composer";
        draftInput.forceActiveFocus();
        draftInput.cursorPosition = draftInput.length;
    }

    function showRail(rail) {
        root.activeRail = root.activeRail === rail ? "composer" : rail;
        if (root.activeRail === "composer")
            root.focusInput();
    }

    function closeRail() {
        if (root.activeRail === "composer")
            return false;
        root.focusInput();
        return true;
    }

    function focusFirstButton() {
        if (root.activeRail !== "composer") {
            railSendButton.forceActiveFocus();
            return;
        }
        if (compactChevron.visible)
            compactChevron.forceActiveFocus();
        else
            modelButton.forceActiveFocus();
    }

    function focusLastButton() {
        if (root.activeRail !== "composer") {
            railSendButton.forceActiveFocus();
            return;
        }
        sendButton.forceActiveFocus();
    }

    function cycleWebMode() {
        const modes = ["off", "auto", "on"];
        const index = modes.indexOf(Ai.webMode);
        Ai.setWebMode(modes[(index + 1 + modes.length) % modes.length], false);
    }

    function webModeLabel(mode) {
        switch (mode) {
        case "on": return Translation.tr("Web on");
        case "auto": return Translation.tr("Web auto");
        default: return Translation.tr("Web off");
        }
    }

    function toolModeLabel(mode) {
        switch (mode) {
        case "safe": return Translation.tr("Tools safe");
        case "none": return Translation.tr("Tools off");
        default: return Translation.tr("Tools all");
        }
    }

    function cycleFunctionExposure() {
        const values = ["all", "safe", "none"];
        const index = values.indexOf(Ai.functionExposure);
        Ai.setFunctionExposure(values[(index + 1 + values.length) % values.length], false);
    }

    function pasteClipboard() {
        const value = String(Quickshell.clipboardText ?? "");
        if (value.length === 0)
            return;
        const next = (draftInput.text.slice(0, draftInput.cursorPosition) + value + draftInput.text.slice(draftInput.cursorPosition)).slice(0, root.maximumCharacters);
        root.setDraft(next);
        Ai.draft = next;
        root.focusInput();
    }

    /** Start/stop/retry, driven by the shared voice service's own state. */
    function activateVoice() {
        switch (Ai.voiceService.state) {
        case "recording":
            Ai.voiceService.stopRecording();
            break;
        case "transcribing":
            break;
        case "error":
            Ai.voiceService.cancel();
            Ai.voiceService.startRecording("search");
            break;
        default:
            Ai.voiceService.startRecording("search");
            break;
        }
    }

    /** Appends a finished dictation into the draft, the same way pasting does. */
    function insertVoiceText(text) {
        if (text.length === 0)
            return;
        const next = (draftInput.text.length > 0 ? `${draftInput.text} ${text}` : text).slice(0, root.maximumCharacters);
        root.setDraft(next);
        Ai.draft = next;
        root.focusInput();
    }

    /** Drops an example prompt from the Capabilities page straight into the draft, replacing whatever was there — a fresh start, not an append. */
    function insertPromptExample(text) {
        if (text.length === 0)
            return;
        root.setDraft(text);
        Ai.draft = text;
        root.focusInput();
    }

    function selectModel(modelId) {
        if (Ai.setModel(modelId, false))
            root.focusInput();
    }

    function selectResponseMode(mode) {
        Ai.setResponseMode(mode, false);
        root.focusInput();
    }

    function railItems(railName) {
        if (railName === "actions") {
            return [
                { id: "back", kind: "icon", icon: "chevron_left", tooltip: Translation.tr("Return to message (Esc)") },
                { id: "web", kind: "text", icon: "travel_explore", label: root.webModeLabel(Ai.webMode), tooltip: Translation.tr("Web search: %1\nAlso /web").arg(Ai.webMode) },
                { id: "tools", kind: "text", icon: "service_toolbox", label: root.toolModeLabel(Ai.functionExposure), tooltip: Translation.tr("Tools: %1\nAlso /tools").arg(Ai.functionExposure) },
                { id: "paste", kind: "icon", icon: "content_paste", tooltip: Translation.tr("Paste clipboard (Ctrl+V)") },
                { id: "attach-clipboard", kind: "icon", icon: "content_paste", tooltip: Translation.tr("Attach clipboard text as context") },
                { id: "attach-launcher", kind: "icon", icon: "select_window", tooltip: Translation.tr("Attach selected launcher result") },
                { id: "attach-window", kind: "icon", icon: "desktop_windows", tooltip: Translation.tr("Attach active application metadata") },
                { id: "history", kind: "icon", icon: "history", tooltip: Translation.tr("Chat history (Ctrl+L)") },
                { id: "response", kind: "icon", icon: "speed", tooltip: Translation.tr("Response effort: %1\nAlso /effort").arg(Ai.responseMode) }
            ];
        }
        if (railName === "models") {
            const start = [{ id: "back", kind: "icon", icon: "chevron_left", tooltip: Translation.tr("Return to message (Esc)") }];
            return start.concat(root.orderedModels.map(model => ({
                id: String(model.id ?? ""),
                kind: "text",
                icon: model.materialIcon ?? "auto_awesome",
                customIcon: model.icon ?? "",
                label: model.title ?? model.value ?? "",
                tooltip: Translation.tr("Select %1 (Ctrl+M)").arg(model.name ?? model.title ?? "")
            })));
        }
        return [
            { id: "back", kind: "icon", icon: "chevron_left", tooltip: Translation.tr("Return to message (Esc)") },
            { id: "fast", kind: "text", icon: "speed", label: Translation.tr("Fast"), tooltip: Translation.tr("Response effort: Fast\nAlso /effort") },
            { id: "balanced", kind: "text", icon: "speed", label: Translation.tr("Medium"), tooltip: Translation.tr("Response effort: Medium\nAlso /effort") },
            { id: "deep", kind: "text", icon: "speed", label: Translation.tr("High"), tooltip: Translation.tr("Response effort: High\nAlso /effort") }
        ];
    }

    function railItemActive(railName, item) {
        if (railName === "actions") {
            if (item.id === "web")
                return root.webActive;
            return item.id === "response" && Ai.responseMode !== "balanced";
        }
        if (railName === "models")
            return item.id === Ai.currentModelId;
        return item.id === Ai.responseMode;
    }

    function activateRailItem(railName, item) {
        if (item.id === "back") {
            root.focusInput();
            return;
        }
        if (railName === "models") {
            root.selectModel(item.id);
            return;
        }
        if (railName === "response") {
            root.selectResponseMode(item.id);
            return;
        }
        switch (item.id) {
        case "web": root.cycleWebMode(); break;
        case "tools": root.cycleFunctionExposure(); break;
        case "paste": root.pasteClipboard(); break;
        case "attach-clipboard": Ai.attachClipboardContext(); break;
        case "attach-launcher": Ai.attachLauncherContext(); break;
        case "attach-window": Ai.attachActiveWindowContext(); break;
        case "history": root.requestOpenHistory(); break;
        case "response": root.showRail("response"); break;
        }
    }

    Connections {
        target: Ai
        function onDraftChanged() {
            if (draftInput.text !== Ai.draft)
                root.setDraft(Ai.draft);
            // A change that did not come from walking the history — typing,
            // sending, switching chats — means the reader is done recalling.
            if (!root.navigatingPromptHistory && root.promptHistoryIndex !== -1)
                root.resetPromptHistory();
        }
    }

    Connections {
        // The voice service is shared with the sidebar composer, so only the
        // surface that started the recording — tracked by `activeSurface` —
        // consumes the finished draft here.
        target: Ai.voiceService
        function onStateChanged() {
            if (Ai.voiceService.state !== "review" || Ai.voiceService.activeSurface !== "search")
                return;
            const text = Ai.voiceService.draftText;
            Ai.voiceService.attachDraft(text);
            root.insertVoiceText(text);
        }
    }

    Component.onCompleted: root.setDraft(Ai.draft)

    AiAttachmentTray {
        Layout.fillWidth: true
    }

    Rectangle {
        id: composerSurface

        Layout.fillWidth: true
        implicitHeight: composerStage.implicitHeight + root.controlPadding * 2
        color: Appearance.colors.colLayer1
        radius: root.longDraft ? Appearance.rounding.large : Appearance.rounding.full
        clip: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: composerSurface.width
                height: composerSurface.height
                radius: composerSurface.radius
            }
        }

        Behavior on radius {
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(composerSurface)
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.focusInput()
        }

        Item {
            id: composerStage
            anchors {
                fill: parent
                margins: root.controlPadding
            }
            implicitHeight: root.activeRail === "composer" ? composerRail.implicitHeight : root.controlExtent

            TextEdit {
                id: compactDraftProbe
                visible: false
                width: root.compactDraftWidth
                text: draftInput.text
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                font.variableAxes: Appearance.font.variableAxes.main
            }

            // ── Compact composer ──────────────────────────────

            Item {
                id: composerRail
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.longDraft ? root.expandedEditorHeight + root.controlGap + root.controlExtent : root.controlExtent
                implicitHeight: height
                opacity: root.activeRail === "composer" ? 1 : 0
                visible: opacity > 0.001

                Behavior on height {
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(composerRail)
                }

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(composerRail)
                }

                transform: Translate {
                    id: composerRailSlide
                    x: root.activeRail === "composer" ? 0 : -root.railSlideDistance

                    Behavior on x {
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(composerRailSlide)
                    }
                }

                StyledTextArea {
                    id: draftInput
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        leftMargin: root.longDraft ? root.horizontalInset : root.controlExtent + root.controlGap
                        rightMargin: root.longDraft ? root.horizontalInset : modelButton.implicitWidth + sendButton.implicitWidth + root.voiceButtonReserve + root.controlGap * 2
                    }
                    height: root.longDraft ? root.expandedEditorHeight : root.controlExtent
                    color: Appearance.colors.colOnLayer1
                    placeholderText: Translation.tr("Ask something · @window or @clipboard")
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    verticalAlignment: root.longDraft ? TextEdit.AlignTop : TextEdit.AlignVCenter
                    topPadding: root.longDraft ? root.controlPadding : 0
                    bottomPadding: root.longDraft ? root.controlPadding : 0
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    selectByMouse: true
                    persistentSelection: true
                    background: Item {}
                    Accessible.name: Translation.tr("AI message")
                    Accessible.description: Translation.tr("Multiline draft. Enter sends; Shift+Enter inserts a line break; @window and @clipboard add visible context; ? opens keyboard shortcuts when empty.")

                    Behavior on height {
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(draftInput)
                    }
                    Behavior on anchors.leftMargin {
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(draftInput)
                    }
                    Behavior on anchors.rightMargin {
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(draftInput)
                    }

                    onTextChanged: {
                        const nextText = String(text ?? "");
                        if (nextText.length > root.maximumCharacters) {
                            const boundedText = nextText.slice(0, root.maximumCharacters);
                            if (boundedText !== nextText) {
                                root.syncingDraft = true;
                                text = boundedText;
                                root.syncingDraft = false;
                                if (!root.syncingDraft)
                                    Ai.draft = boundedText;
                                return;
                            }
                        }
                        if (!root.syncingDraft)
                            Ai.draft = text;
                    }

                    Keys.onPressed: event => {
                        if (event.text === "?" && draftInput.text.trim().length === 0) {
                            root.requestOpenShortcuts();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            if (!root.closeRail())
                                root.requestEscape();
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                            root.send();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            if (event.modifiers & Qt.ShiftModifier) {
                                root.requestFocusPrev();
                            } else {
                                root.focusFirstButton();
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backtab) {
                            root.requestFocusPrev();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up && event.modifiers === Qt.NoModifier
                                && (draftInput.text.length === 0 || root.promptHistoryIndex !== -1)) {
                            // Recall an earlier prompt, like a shell's history — only
                            // from an empty draft, so mid-line cursor movement in a
                            // real multi-line message is never hijacked.
                            if (root.stepPromptHistory(-1))
                                event.accepted = true;
                        } else if (event.key === Qt.Key_Down && event.modifiers === Qt.NoModifier
                                && (draftInput.text.length === 0 || root.promptHistoryIndex !== -1)) {
                            if (root.stepPromptHistory(1))
                                event.accepted = true;
                        }
                    }
                }

                RowLayout {
                    id: composerActions
                    anchors {
                        left: parent.left
                        right: parent.right
                    }
                    y: root.longDraft ? root.expandedEditorHeight + root.controlGap : 0
                    height: root.controlExtent
                    spacing: root.controlGap

                    Behavior on y {
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(composerActions)
                    }

                    RailIconButton {
                        id: compactChevron
                        symbol: "chevron_right"
                        tooltip: Translation.tr("Show chat controls (Ctrl+T or Tab)")
                        active: false
                        onClicked: root.showRail("actions")

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Space || event.key === Qt.Key_Enter) {
                                root.showRail("actions");
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.focusInput();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab) {
                                if (event.modifiers & Qt.ShiftModifier)
                                    root.focusInput();
                                else
                                    modelButton.forceActiveFocus();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Backtab) {
                                root.focusInput();
                                event.accepted = true;
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                    }

                    RailTextButton {
                        id: modelButton
                        symbol: root.modelSymbol
                        customIcon: root.modelIcon
                        label: root.modelTitle
                        maximumWidth: root.maximumCompactModelWidth
                        active: true
                        highlightTertiary: root.modelsOpen
                        tooltip: Translation.tr("Choose model: %1 (Ctrl+M)").arg(root.modelTitle)
                        onClicked: root.requestOpenModels()

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Space || event.key === Qt.Key_Enter) {
                                root.requestOpenModels();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.focusInput();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab) {
                                if (event.modifiers & Qt.ShiftModifier)
                                    compactChevron.forceActiveFocus();
                                else
                                    (voiceButton.visible ? voiceButton : sendButton).forceActiveFocus();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Backtab) {
                                compactChevron.forceActiveFocus();
                                event.accepted = true;
                            }
                        }
                    }

                    VoiceButton {
                        id: voiceButton
                        Layout.alignment: Qt.AlignVCenter

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Space || event.key === Qt.Key_Enter) {
                                root.activateVoice();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.focusInput();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab) {
                                if (event.modifiers & Qt.ShiftModifier)
                                    modelButton.forceActiveFocus();
                                else
                                    sendButton.forceActiveFocus();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Backtab) {
                                modelButton.forceActiveFocus();
                                event.accepted = true;
                            }
                        }
                    }

                    SendButton {
                        id: sendButton
                        Layout.alignment: Qt.AlignVCenter

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Space || event.key === Qt.Key_Enter) {
                                root.send();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.focusInput();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab) {
                                if (event.modifiers & Qt.ShiftModifier)
                                    (voiceButton.visible ? voiceButton : modelButton).forceActiveFocus();
                                else
                                    root.requestFocusNext();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Backtab) {
                                (voiceButton.visible ? voiceButton : modelButton).forceActiveFocus();
                                event.accepted = true;
                            }
                        }
                    }
                }
            }

            // ── Collapsed controls rail ───────────────────────

            RailPage {
            id: actionsRail
            railName: "actions"
            scrollable: true
        }

            // The model selector is a horizontal rail as well. Keeping it as
            // a real page gives the edge fade a source item and prevents the
            // Ctrl+M shortcut from switching to a non-existent surface.
            RailPage {
                id: modelsRail
                railName: "models"
                scrollable: true
            }

            // ── Response effort carousel ───────────────────────

            RailPage {
                id: responseRail
                railName: "response"
                scrollable: true
            }
        }

        // The send action remains visually fixed above every horizontal rail.
        // Its surface-colored fade makes scrolling content disappear naturally
        // below it instead of meeting a separate invisible viewport wall.
        Rectangle {
            id: sendFade
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            width: root.controlExtent * 2 + root.horizontalInset
            visible: root.activeRail === "response"
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: ColorUtils.transparentize(Appearance.colors.colLayer1)
                }
                GradientStop {
                    position: 0.28
                    color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.65)
                }
                GradientStop {
                    position: 0.62
                    color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.1)
                }
                GradientStop {
                    position: 1
                    color: Appearance.colors.colLayer1
                }
            }
            z: 3
        }

        Item {
            id: modelEdgeBlur
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            width: sendFade.width
            visible: root.activeRail === "models"
            z: 2
            layer.enabled: visible
            layer.effect: OpacityMask {
                maskSource: modelEdgeBlurMask
            }

            ShaderEffectSource {
                id: modelRailCapture
                anchors.fill: parent
                sourceItem: modelsRail
                sourceRect: {
                    const edgeOrigin = modelEdgeBlur.mapToItem(modelsRail, 0, 0);
                    return Qt.rect(edgeOrigin.x, edgeOrigin.y, width, height);
                }
                live: modelEdgeBlur.visible
                hideSource: false
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: modelRailCapture
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: root.controlExtent
                blur: 0.6
            }
        }

        Item {
            id: modelEdgeBlurMask
            x: modelEdgeBlur.x
            y: modelEdgeBlur.y
            width: modelEdgeBlur.width
            height: modelEdgeBlur.height
            visible: false

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: ColorUtils.transparentize(Appearance.colors.colLayer1)
                    }
                    GradientStop {
                        position: 0.3
                        color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.8)
                    }
                    GradientStop {
                        position: 0.72
                        color: Appearance.colors.colLayer1
                    }
                    GradientStop {
                        position: 1
                        color: Appearance.colors.colLayer1
                    }
                }
            }
        }

        SendButton {
            id: railSendButton
            anchors {
                right: parent.right
                rightMargin: root.controlPadding
                verticalCenter: parent.verticalCenter
            }
            visible: root.activeRail !== "composer"
            z: 4
        }
    }

    component RailPage: Item {
        id: page

        required property string railName
        property bool scrollable: false

        anchors.fill: parent
        opacity: root.activeRail === page.railName ? 1 : 0
        visible: opacity > 0.001
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(page)
        }

        transform: Translate {
            id: pageSlide
            x: root.activeRail === page.railName ? 0 : -root.railSlideDistance

            Behavior on x {
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(pageSlide)
            }
        }

        Flickable {
            id: railFlickable
            anchors.fill: parent
            contentWidth: railRow.implicitWidth
            contentHeight: height
            boundsBehavior: Flickable.StopAtBounds
            interactive: page.scrollable && contentWidth > width
            clip: false

            RowLayout {
                id: railRow
                height: parent.height
                spacing: root.controlGap

                Repeater {
                    model: root.railItems(page.railName)
                    delegate: RailControl {
                        required property var modelData
                        railName: page.railName
                        railItem: modelData
                    }
                }
            }
        }
    }

    component RailControl: Item {
        id: railControl

        required property string railName
        required property var railItem
        readonly property bool isTextControl: railItem?.kind === "text"

        implicitWidth: isTextControl ? textControl.implicitWidth : iconControl.implicitWidth
        implicitHeight: root.controlExtent

        RailIconButton {
            id: iconControl
            anchors.fill: parent
            visible: !railControl.isTextControl
            symbol: String(railControl.railItem?.icon ?? "")
            tooltip: String(railControl.railItem?.tooltip ?? "")
            active: root.railItemActive(railControl.railName, railControl.railItem)
            onClicked: root.activateRailItem(railControl.railName, railControl.railItem)
        }

        RailTextButton {
            id: textControl
            anchors.fill: parent
            visible: railControl.isTextControl
            symbol: String(railControl.railItem?.icon ?? "")
            customIcon: String(railControl.railItem?.customIcon ?? "")
            label: String(railControl.railItem?.label ?? "")
            tooltip: String(railControl.railItem?.tooltip ?? "")
            active: root.railItemActive(railControl.railName, railControl.railItem)
            onClicked: root.activateRailItem(railControl.railName, railControl.railItem)
        }
    }

    component RailIconButton: RippleButton {
        id: iconButton

        property string symbol: ""
        property string tooltip: ""
        property bool active: false
        // Set while the button represents ongoing background work (e.g.
        // transcription) rather than an idle/pressable action.
        property bool spinning: false

        implicitWidth: root.controlExtent
        implicitHeight: root.controlExtent
        buttonRadius: Appearance.rounding.full
        focusPolicy: Qt.StrongFocus
        toggled: iconButton.active
        colBackground: iconButton.activeFocus
            ? (iconButton.active ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active)
            : (iconButton.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer2)
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active
        colRipple: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colPrimary
        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
        colBackgroundToggledActive: Appearance.colors.colPrimaryActive
        colRippleToggled: Appearance.colors.colPrimaryActive
        Accessible.name: iconButton.tooltip

        contentItem: MaterialSymbol {
            text: iconButton.symbol
            iconSize: Appearance.font.pixelSize.larger
            fill: 1
            color: (iconButton.active || iconButton.activeFocus) ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2

            RotationAnimator on rotation {
                running: iconButton.spinning
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
            }
        }

        StyledToolTip {
            text: iconButton.tooltip
        }
    }

    component RailTextButton: RippleButton {
        id: textButton

        property string symbol: ""
        property string label: ""
        property string tooltip: ""
        property string customIcon: ""
        property bool active: false
        property bool highlightTertiary: false
        property real maximumWidth: Number.POSITIVE_INFINITY

        implicitWidth: Math.min(contentRow.implicitWidth + root.chipPadding * 2, maximumWidth)
        implicitHeight: root.controlExtent
        buttonRadius: Appearance.rounding.full
        focusPolicy: Qt.StrongFocus
        toggled: textButton.active
        colBackground: textButton.highlightTertiary
            ? (textButton.activeFocus ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colTertiaryContainer)
            : (textButton.activeFocus
                ? (textButton.active ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active)
                : (textButton.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer2))
        colBackgroundHover: textButton.highlightTertiary ? Appearance.colors.colTertiaryContainerHover : Appearance.colors.colLayer2Hover
        colBackgroundActive: textButton.highlightTertiary ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colLayer2Active
        colRipple: textButton.highlightTertiary ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colLayer2Active
        colBackgroundToggled: textButton.highlightTertiary ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimary
        colBackgroundToggledHover: textButton.highlightTertiary ? Appearance.colors.colTertiaryContainerHover : Appearance.colors.colPrimaryHover
        colBackgroundToggledActive: textButton.highlightTertiary ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colPrimaryActive
        colRippleToggled: textButton.highlightTertiary ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colPrimaryActive
        Accessible.name: textButton.tooltip

        readonly property color contentColor: textButton.highlightTertiary
            ? Appearance.m3colors.m3onTertiaryContainer
            : ((textButton.active || textButton.activeFocus) ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2)

        contentItem: RowLayout {
            id: contentRow
            spacing: root.iconTextGap

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: textButton.customIcon.length > 0
                visible: active
                sourceComponent: CustomIcon {
                    source: textButton.customIcon
                    width: Appearance.font.pixelSize.larger
                    height: Appearance.font.pixelSize.larger
                    colorize: true
                    color: textButton.contentColor
                }
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                visible: textButton.customIcon.length === 0
                text: textButton.symbol
                iconSize: Appearance.font.pixelSize.larger
                fill: 1
                color: textButton.contentColor
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: Math.max(Appearance.font.pixelSize.huge * 8, root.controlExtent * 2)
                text: textButton.label
                elide: Text.ElideRight
                maximumLineCount: 1
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: textButton.contentColor
            }
        }

        StyledToolTip {
            text: textButton.tooltip
        }
    }

    component SendButton: RailIconButton {
        symbol: Ai.isGenerating ? "stop" : "send"
        tooltip: Ai.isGenerating ? Translation.tr("Stop response") : Translation.tr("Send message (Enter)")
        // Disabled send remains fully opaque; it changes to the neutral layer
        // instead of inheriting RippleButton's generic disabled fade.
        active: enabled && !Ai.isGenerating
        enabled: Ai.isGenerating || root.hasDraft
        opacity: 1
        onClicked: root.send()
    }

    component VoiceButton: RailIconButton {
        visible: Config.options.ai.voice.enabled
        symbol: {
            switch (Ai.voiceService.state) {
            case "recording": return "stop";
            case "transcribing": return "progress_activity";
            default: return "mic";
            }
        }
        active: Ai.voiceService.state === "recording"
        spinning: Ai.voiceService.state === "transcribing"
        enabled: Ai.voiceService.state !== "transcribing"
        tooltip: {
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
        onClicked: root.activateVoice()
    }
}
