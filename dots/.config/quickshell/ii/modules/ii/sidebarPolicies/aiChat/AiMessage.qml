pragma ComponentBehavior: Bound

import qs.services
import qs.services.ai
import qs.services.ai.blocks
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * One turn of the conversation.
 *
 * A question is a pill on the right; an answer is a block on the left, under
 * however many quiet lines it took to get there — the reasoning, a search,
 * whatever tools were reached for. What can be done with an answer lives on
 * a bar beneath it rather than in a header above it, because a header put
 * six controls between the question and the answer to it.
 *
 * Nothing here is sized in pixels: every measure comes off the type scale or
 * the rounding scale, so the whole transcript follows the user's font size
 * and their sharp-corner setting.
 */
Item {
    id: root

    property string messageId
    property var messageData

    /**
     * How much room the turn is allowed to take.
     *
     * "comfortable" is the sidebar: bubbles, activity rows and the action bar
     * under the answer. "compact" is the Search panel, which is a narrow
     * strip over the desktop — there the answer drops its bubble and the bar
     * becomes the two controls worth having, so one component serves both
     * instead of two that drift apart.
     */
    property string density: Config.options.sidebar.ai.density === "compact" ? "compact" : "comfortable"
    readonly property bool compact: root.density === "compact"
    property bool reducedMotion: Config.options.sidebar.ai.reducedMotion
    /** Advanced by the sidebar only when a saved conversation is opened. */
    property int transcriptRevealToken: -1
    /** Ordered by the currently visible delegate index. */
    property int transcriptRevealDelay: 0
    property int handledRevealToken: -1
    property bool revealAnimationRunning: false

    /** Asks the control bar for another model to redo this answer with. */
    signal regenerateRequested(string messageId)
    /** Asks the control bar to open the model picker. */
    signal modelPickerRequested
    /** Asks the composer to take this question back for another go. */
    signal editRequested(string messageId, string content)

    readonly property string transcriptContent: String(root.messageData?.content ?? root.messageData?.rawContent ?? "")

    /**
     * The parsed content, rebuilt rather than re-bound.
     *
     * As a binding this ran the whole splitter on every token and handed back
     * fresh objects each time, so every block's delegate was destroyed and
     * built again sixty times a second. Now the rebuild is coalesced while an
     * answer is streaming, and the blocks that did not change keep their
     * identity so their delegates are left alone.
     */
    property list<var> messageBlocks: []

    function rebuildBlocks() {
        root.messageBlocks = AiTranscriptRegistry.reuseBlocks(root.messageBlocks, root.transcriptContent);
    }

    onTranscriptContentChanged: {
        if (!root.streaming) {
            blockRebuildTimer.stop();
            root.rebuildBlocks();
            return;
        }
        if (!blockRebuildTimer.running)
            blockRebuildTimer.start();
    }

    onDoneChanged: {
        blockRebuildTimer.stop();
        root.rebuildBlocks();
    }

    Timer {
        // Fast enough to read as text arriving, slow enough that a token does
        // not cost a full re-parse and re-layout of the whole answer.
        id: blockRebuildTimer
        interval: 60
        repeat: false
        onTriggered: root.rebuildBlocks()
    }

    readonly property string role: String(root.messageData?.role ?? "assistant")
    readonly property bool isUser: root.role === "user"
    readonly property bool isInterface: root.role === "interface"
    readonly property bool isAssistant: !root.isUser && !root.isInterface
    readonly property bool done: root.messageData?.done ?? false
    /** True while the answer is still being written into this turn. */
    readonly property bool streaming: root.isAssistant && !root.done
    readonly property var sentFiles: Array.from(root.messageData?.attachments ?? [])
    /** This exact answer is paused between automatic transport attempts. */
    readonly property bool retrying: root.isAssistant && root.messageId === Ai.retryMessageId && Ai.retryNotice.length > 0
    readonly property string activityDefaultMode: ["auto", "expanded", "collapsed"].indexOf(Config.options.sidebar.ai.activityDefault) >= 0
        ? Config.options.sidebar.ai.activityDefault : "auto"
    readonly property bool hasLongAnswer: root.isAssistant && root.done && root.transcriptContent.length > 3600
    property bool longAnswerExpanded: false
    readonly property bool collapseLongAnswer: root.hasLongAnswer && Config.options.sidebar.ai.collapseLongAnswers && !root.longAnswerExpanded
    readonly property real longAnswerCollapsedHeight: Appearance.font.pixelSize.huge * 18
    readonly property var answerVariantIds: Ai.answerVariantSessionIds(root.messageId)
    readonly property int answerVariantIndex: root.answerVariantIds.indexOf(Ai.sessions.currentId)
    readonly property bool showAnswerVariants: root.isAssistant && root.done
        && Ai.shouldShowAnswerVariants(root.messageId)

    function timestampLabel(): string {
        const timestamp = Number(root.messageData?.createdAt ?? 0);
        return timestamp > 0 ? Qt.formatDateTime(new Date(timestamp), "HH:mm") : "";
    }

    function responseTimeLabel(): string {
        const elapsedMs = Number(root.messageData?.completedAt ?? 0) - Number(root.messageData?.createdAt ?? 0);
        if (elapsedMs <= 0)
            return "";
        const seconds = elapsedMs / 1000;
        return seconds < 10 ? seconds.toFixed(1) + " s" : String(Math.round(seconds)) + " s";
    }

    /**
     * Every message in the same exchange as this one, oldest first, ending
     * with this one. A tool round-trip issues one assistant message per
     * network turn — the model calling a tool, then continuing once the
     * result is back — and `Ai.leadingActivityMessages()` finds the ones
     * that led to this delegate's own message and only exist because of
     * that. `AiChat.qml`/`AiChatPanel.qml` already hide those from getting
     * a row of their own; this is what the terminal message folds them
     * into instead.
     */
    readonly property var stepGroup: root.isAssistant ? [...Ai.leadingActivityMessages(root.messageId), root.messageData] : [root.messageData]

    /**
     * Once a turn is complete, its activity is represented by one outer row.
     * Keep the summary derived from the same step group as the expanded
     * content so a single-step turn and a tool round-trip settle identically.
     */
    function summarizeActivity(): var {
        let thoughtDurationMs = 0;
        let thoughtTokens = 0;
        let searchCount = 0;
        let toolCount = 0;
        let hasThought = false;

        for (const step of root.stepGroup) {
            hasThought = hasThought || String(step?.thought ?? "").length > 0;
            thoughtDurationMs += Number(step?.thoughtDurationMs ?? 0);
            const tokens = Number(step?.thoughtTokens ?? 0);
            if (tokens > 0)
                thoughtTokens += tokens;
            searchCount += Array.from(step?.searchQueries ?? []).length;
            toolCount += Array.from(step?.toolCalls ?? []).length;
        }

        const parts = [];
        if (thoughtDurationMs >= 100)
            parts.push(Translation.tr("Thought for %1 s").arg(String((thoughtDurationMs / 1000).toFixed(1))));
        else if (thoughtTokens > 0)
            parts.push(Translation.tr("%1 tokens").arg(String(thoughtTokens)));
        if (searchCount > 0)
            parts.push(Translation.tr("%1 searches").arg(String(searchCount)));
        if (toolCount > 0)
            parts.push(Translation.tr("%1 tool calls").arg(String(toolCount)));

        const hasActivity = hasThought || searchCount > 0 || toolCount > 0;
        return {
            hasActivity: hasActivity,
            label: parts.length > 0 ? parts.join(" · ") : Translation.tr("Completed activity")
        };
    }

    readonly property var activitySummary: root.summarizeActivity()
    readonly property bool hasActivity: root.activitySummary.hasActivity
    readonly property string finalActivityLabel: root.activitySummary.label

    // ── Measures ──────────────────────────────────────────────────────────
    /** Inside a bubble, from its edge to its text. */
    readonly property real bubblePadding: root.compact ? Appearance.rounding.unsharpenmore : Appearance.rounding.small
    /** Between the parts of one turn. */
    readonly property real blockGap: Appearance.rounding.unsharpenmore
    /** How much of the width a turn may take, so the other side stays open. */
    readonly property real userMaximumWidth: root.width * 0.86
    readonly property real answerMaximumWidth: root.width * 0.96

    /**
     * A turn that has just arrived, as opposed to one a scrolling list has
     * just built again. Only the first kind is worth an entrance.
     */
    readonly property bool arriving: Ai.isFreshMessage(root.messageId)

    // ── Surfaces ──────────────────────────────────────────────────────────
    // A question sits a step above the transcript and an answer a step below
    // it, which is the contrast the design was drawn with: two bubbles that
    // are told apart by tone and side before a word of either is read.
    // `on`-prefixed names are read as signal handlers in QML, so the ink
    // colours are named for what they are rather than for what they sit on.
    // The turn the keyboard is standing on lifts its own surface. A ring
    // would be a border, and this design does not use them.
    /** Set by the transcript when this is the turn a search landed on. */
    property bool highlighted: false
    readonly property bool turnFocused: root.activeFocus || root.highlighted
    readonly property color questionSurface: root.turnFocused ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3
    readonly property color questionInk: Appearance.colors.colOnLayer3
    readonly property color answerSurface: root.turnFocused ? Appearance.colors.colLayer2 : Appearance.m3colors.m3surfaceContainerLowest
    readonly property color answerInk: Appearance.colors.colOnLayer1

    focus: false
    activeFocusOnTab: true
    Accessible.role: Accessible.Paragraph
    Accessible.name: root.isUser
        ? Translation.tr("Your message: %1").arg(String(root.messageData?.content ?? ""))
        : Translation.tr("Assistant response")

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: turnColumn.implicitHeight

    // ── Arrival ───────────────────────────────────────────────────────────
    // A message that has just been sent lands, the way one does in a chat
    // app. One that a recycled delegate is merely rebuilding does not.
    readonly property bool reopening: root.transcriptRevealToken >= 0
        && root.transcriptRevealToken !== root.handledRevealToken
        && !root.arriving && !root.streaming
    readonly property bool shouldAnimateArrival: !root.reducedMotion && !root.streaming
        && (root.arriving || root.reopening || root.revealAnimationRunning)
    readonly property int arrivalDelay: root.reopening ? root.transcriptRevealDelay : 0

    opacity: root.shouldAnimateArrival ? 0 : 1
    transform: Translate {
        id: arrivalTransform
        y: root.shouldAnimateArrival ? Appearance.rounding.verysmall : 0
    }

    function startArrival() {
        if (!root.shouldAnimateArrival) {
            // Declining is permanent, and has to be written rather than left
            // to the binding.
            //
            // `opacity` and the arrival transform are bound to
            // `shouldAnimateArrival`, and the animation is the only thing
            // that ever drives them back. An answer is created while it is
            // still streaming, which is exactly when that condition is false
            // — so it declines here, the binding stays intact, and no
            // animation ever runs to break it. Then the answer finishes,
            // `streaming` goes false, `arriving` is still reading true (it
            // is `Date.now()`-based and so never re-evaluates on its own),
            // the condition flips true, and the binding drives opacity to
            // zero with nothing left to bring it back. The turn stayed laid
            // out and still answered the mouse — tooltips and all — it was
            // simply never painted again until the chat was reopened.
            //
            // Writing both values drops those bindings for good: a turn that
            // is already on screen cannot be taken off it later.
            root.settleVisible();
            return;
        }
        if (root.reopening) {
            root.revealAnimationRunning = true;
            root.handledRevealToken = root.transcriptRevealToken;
        }
        arrivalAnimation.restart();
    }

    /**
     * Put this turn on screen and leave it there.
     *
     * Writing the two values is the point: both are bound to
     * `shouldAnimateArrival`, and dropping those bindings is what stops a
     * later flip of that condition from hiding a turn the reader is already
     * looking at.
     */
    function settleVisible() {
        root.handledRevealToken = root.transcriptRevealToken;
        root.revealAnimationRunning = false;
        root.opacity = 1;
        arrivalTransform.y = 0;
    }

    Component.onCompleted: {
        root.rebuildBlocks();
        Qt.callLater(root.startArrival);
    }

    onTranscriptRevealTokenChanged: {
        if (root.transcriptRevealToken >= 0)
            Qt.callLater(root.startArrival);
    }

    onStreamingChanged: {
        // Settle, never animate. An answer that has just finished writing
        // itself has been on screen the whole time — replaying an entrance
        // over it would fade out something the reader is mid-sentence in.
        if (!root.streaming && !arrivalAnimation.running)
            root.settleVisible();
    }

    SequentialAnimation {
        id: arrivalAnimation
        onFinished: root.revealAnimationRunning = false

        PauseAnimation {
            duration: root.arrivalDelay
        }

        ParallelAnimation {

            NumberAnimation {
                target: root
                property: "opacity"
                from: 0
                to: 1
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }

            NumberAnimation {
                target: arrivalTransform
                property: "y"
                from: Appearance.rounding.verysmall
                to: 0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
        }
    }

    ColumnLayout {
        id: turnColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: root.blockGap

        Loader {
            // Everything above this line is out of the model's reach now. The
            // alternative was a conversation that quietly started forgetting,
            // or one that the provider refused outright.
            Layout.fillWidth: true
            Layout.bottomMargin: active ? root.blockGap : 0
            active: Ai.contextCutMessageId.length > 0 && Ai.contextCutMessageId === root.messageId && Ai.prunedTurnCount > 0
            visible: active

            sourceComponent: RowLayout {
                spacing: Appearance.rounding.unsharpenmore

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                }

                MaterialSymbol {
                    text: "content_cut"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    text: Ai.contextSummary.length > 0
                        ? Translation.tr("%1 earlier turns, summarised for the model").arg(Ai.prunedTurnCount)
                        : Translation.tr("%1 earlier turns are past the model's window").arg(Ai.prunedTurnCount)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext

                    StyledToolTip {
                        text: Ai.contextSummary.length > 0
                            ? Translation.tr("They are still in this chat and still saved — the model gets them as a summary:\n\n%1").arg(Ai.contextSummary)
                            : Translation.tr("They are still in this chat and still saved; they are just not sent any more.")
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                }
            }
        }

        // ── The question ──────────────────────────────────────────────────

        Flow {
            // What went out with the question, kept with it: a reopened chat
            // still shows what the model was actually looking at.
            Layout.alignment: Qt.AlignRight
            Layout.maximumWidth: root.userMaximumWidth
            visible: root.isUser && root.sentFiles.length > 0
            spacing: root.blockGap
            layoutDirection: Qt.RightToLeft

            Repeater {
                model: ScriptModel {
                    values: root.isUser ? root.sentFiles : []
                }

                delegate: Rectangle {
                    id: sentFile
                    required property var modelData

                    implicitWidth: sentFileRow.implicitWidth + Appearance.font.pixelSize.large
                    implicitHeight: Math.round(Appearance.font.pixelSize.huge * 1.5)
                    radius: Appearance.rounding.full
                    color: root.questionSurface

                    RowLayout {
                        id: sentFileRow
                        anchors.centerIn: parent
                        spacing: Appearance.rounding.unsharpenmore

                        MaterialSymbol {
                            text: {
                                const kind = sentFile.modelData.kind ?? "";
                                if (kind === "image")
                                    return "image";
                                if (kind === "pdf")
                                    return "picture_as_pdf";
                                if (kind === "audio")
                                    return "music_note";
                                if (kind === "video")
                                    return "movie";
                                if (kind === "text")
                                    return "description";
                                return "file_present";
                            }
                            fill: 1
                            iconSize: Appearance.font.pixelSize.larger
                            color: root.questionInk
                        }

                        StyledText {
                            Layout.maximumWidth: root.userMaximumWidth * 0.6
                            text: sentFile.modelData.name ?? ""
                            elide: Text.ElideMiddle
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.questionInk
                        }
                    }

                    HoverHandler {
                        id: sentFileHover
                    }

                    StyledToolTip {
                        // Driven by a handler of its own because the chip is a
                        // plain Rectangle. `StyledToolTip` reads `parent.hovered`
                        // and treats "no such property" as *always visible*, so
                        // attached to anything that is not a Control it pins
                        // itself open — which is how the path of every attached
                        // document ended up floating over the transcript from
                        // the moment the chat was opened.
                        extraVisibleCondition: false
                        alternativeVisibleCondition: sentFileHover.hovered
                        text: `${sentFile.modelData.path ?? ""}\n${Ai.humanSize(sentFile.modelData.bytes ?? 0)}`
                    }
                }
            }
        }

        RowLayout {
            // The pencil lives beside the bubble rather than inside it, so a
            // long question is never rewrapped by a control that is only
            // there while the pointer is.
            Layout.alignment: Qt.AlignRight
            Layout.maximumWidth: root.width
            visible: root.isUser
            spacing: Appearance.rounding.unsharpenmore

            HoverHandler {
                id: questionHover
                blocking: false
            }

            RippleButton {
                id: editButton
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.round(Appearance.font.pixelSize.huge * 1.35)
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                topPadding: 0
                bottomPadding: 0
                leftPadding: 0
                rightPadding: 0
                focusPolicy: Qt.TabFocus
                opacity: questionHover.hovered || editButton.hovered || editButton.activeFocus ? 1 : 0
                visible: opacity > 0.01
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: root.editRequested(root.messageId, String(root.messageData?.content ?? ""))

                Accessible.name: Translation.tr("Edit this question")

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "edit"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }

                StyledToolTip {
                    text: Translation.tr("Edit and ask again")
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
            }

            Rectangle {
                id: questionBubble
                Layout.alignment: Qt.AlignRight
                Layout.maximumWidth: root.userMaximumWidth
                implicitWidth: visible ? Math.min(root.userMaximumWidth, questionText.implicitWidth + root.bubblePadding * 3) : 0
                implicitHeight: visible ? questionText.implicitHeight + root.bubblePadding * 2 : 0
                // A stadium while the question is one line, and a soft box once
                // it is many: a full radius on a tall block is a circle, and the
                // text ends up inside its arc rather than inside the bubble.
                radius: Math.min(questionBubble.height / 2, Appearance.rounding.verylarge)
                color: root.questionSurface

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                Behavior on implicitHeight {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }

                StyledText {
                    id: questionText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: root.bubblePadding * 1.5
                    anchors.rightMargin: root.bubblePadding * 1.5
                    text: String(root.messageData?.content ?? "")
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: root.questionInk
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.IBeamCursor
                    onDoubleClicked: root.editRequested(root.messageId,
                        String(root.messageData?.content ?? ""))
                }
            }
        }

        // ── What the interface itself had to say ──────────────────────────

        Rectangle {
            id: interfaceNote
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.width
            visible: root.isInterface && interfaceText.text.length > 0
            implicitWidth: visible ? Math.min(root.width, interfaceText.implicitWidth + root.bubblePadding * 3) : 0
            implicitHeight: visible ? interfaceText.implicitHeight + root.bubblePadding * 1.6 : 0
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: root.bubblePadding * 1.2
                anchors.rightMargin: root.bubblePadding * 1.2
                spacing: Appearance.rounding.unsharpenmore

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: "info"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    id: interfaceText
                    Layout.fillWidth: true
                    text: String(root.messageData?.content ?? "")
                    wrapMode: Text.Wrap
                    textFormat: Text.MarkdownText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // ── What it did before answering ──────────────────────────────────

        ColumnLayout {
            id: activityColumn
            Layout.fillWidth: true
            Layout.maximumWidth: root.answerMaximumWidth
            visible: root.isAssistant
            spacing: 0

            // One message's own thinking + search + tool steps. Used
            // directly for the common single-message turn, and once per
            // message inside the "N steps" accordion below for a chain of
            // tool round-trips — each of those used to render as a full
            // turn of its own, which is what turned a several-step
            // exchange into a page-long scroll. Self-contained on purpose:
            // nothing here reads `root`, so it works the same whether it
            // is instantiated directly or from inside that accordion's
            // Repeater.
            component StepActivity: Item {
                id: step
                required property var stepData
                property string activityDefault: "auto"
                readonly property bool stepDone: step.stepData?.done ?? true
                readonly property bool stepStreaming: !step.stepDone
                readonly property int visibleStepCount: ((step.stepData?.thought?.length ?? 0) > 0 ? 1 : 0)
                    + (Array.from(step.stepData?.searchQueries ?? []).length > 0 ? 1 : 0)
                    + Array.from(step.stepData?.toolCalls ?? []).length
                readonly property bool timelineActive: step.stepStreaming
                    || Array.from(step.stepData?.toolCalls ?? []).some(call => String(call?.state ?? "") === "running")
                readonly property real rulerThickness: Math.max(1, Math.round(Appearance.rounding.unsharpenmore / 3))

                Layout.fillWidth: true
                implicitHeight: stepRows.implicitHeight

                // A timeline reads the sequence as a single operation, rather
                // than as unrelated accordions. Its length follows the live
                // rows, so it grows when the next tool step is reported.
                Rectangle {
                    id: timelineRuler
                    visible: step.visibleStepCount > 1
                    x: Math.round((Appearance.font.pixelSize.larger - width) / 2)
                    y: Appearance.rounding.unsharpenmore
                    width: step.rulerThickness
                    height: Math.max(0, stepRows.implicitHeight - y * 2)
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colOutlineVariant
                    opacity: step.timelineActive ? 0.82 : 0.42

                    Behavior on height {
                        enabled: !Config.options.sidebar.ai.reducedMotion
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                    }

                    Behavior on opacity {
                        enabled: !Config.options.sidebar.ai.reducedMotion
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                    }
                }

                ColumnLayout {
                    id: stepRows
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 0

                    AiActivityRow {
                    id: stepThinkingRow
                    onTimeline: step.visibleStepCount > 1
                    property bool userChoice: false
                    property bool userExpanded: false

                    Layout.fillWidth: true
                    shown: (step.stepData?.thought?.length ?? 0) > 0
                    symbol: "lightbulb"
                    running: step.stepStreaming && !stepThinkingRow.thoughtComplete
                    expandable: true
                    expanded: stepThinkingRow.userChoice ? stepThinkingRow.userExpanded
                        : (step.activityDefault === "expanded" || (step.activityDefault === "auto" && !stepThinkingRow.thoughtComplete))
                    maximumContentHeight: Appearance.font.pixelSize.huge * 8

                    readonly property bool thoughtComplete: ((step.stepData?.content?.length ?? 0) > 0) || step.stepDone
                    readonly property real durationMs: step.stepData?.thoughtDurationMs ?? 0
                    readonly property int thoughtTokens: step.stepData?.thoughtTokens ?? -1

                    label: {
                        if (!stepThinkingRow.thoughtComplete)
                            return Translation.tr("Thinking");
                        let parts = [];
                        if (stepThinkingRow.durationMs >= 100)
                            parts.push(Translation.tr("Thought for %1 s").arg((stepThinkingRow.durationMs / 1000).toFixed(1)));
                        else
                            parts.push(Translation.tr("Thought"));
                        if (stepThinkingRow.thoughtTokens > 0)
                            parts.push(Translation.tr("%1 tokens").arg(stepThinkingRow.thoughtTokens));
                        return parts.join(" · ");
                    }

                    onToggled: {
                        stepThinkingRow.userExpanded = !stepThinkingRow.expanded;
                        stepThinkingRow.userChoice = true;
                    }

                    onThoughtCompleteChanged: {
                        if (stepThinkingRow.thoughtComplete) {
                            stepThinkingRow.userChoice = false;
                            stepThinkingRow.userExpanded = false;
                        }
                    }

                    expandedContent: Component {
                        Flickable {
                            id: thoughtFlickable
                            implicitHeight: Math.min(thoughtColumn.implicitHeight, stepThinkingRow.maximumContentHeight)
                            height: implicitHeight
                            contentWidth: width
                            contentHeight: thoughtColumn.implicitHeight
                            interactive: contentHeight > height
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true

                            // While it is still arriving, stay at the newest line.
                            onContentHeightChanged: {
                                if (step.stepStreaming)
                                    contentY = Math.max(0, contentHeight - height);
                            }

                            Column {
                                id: thoughtColumn
                                width: thoughtFlickable.width

                                AiMessageTextBlock {
                                    width: parent.width
                                    messageData: step.stepData
                                    done: step.stepDone
                                    segmentContent: step.stepData?.thought ?? ""
                                    forceDisableChunkSplitting: true
                                }
                            }
                        }
                    }
                }

                    AiActivityRow {
                    // What it looked up. The queries are the interesting part and
                    // they are one click away rather than in the answer.
                    id: stepSearchRow
                    onTimeline: step.visibleStepCount > 1
                    property bool searchExpanded: false

                    readonly property var queries: Array.from(step.stepData?.searchQueries ?? [])

                    Layout.fillWidth: true
                    shown: stepSearchRow.queries.length > 0
                    symbol: "language"
                    running: step.stepStreaming
                    expandable: true
                    expanded: stepSearchRow.searchExpanded
                    label: step.stepStreaming ? Translation.tr("Searching the web") : Translation.tr("Searched the web")
                    onToggled: stepSearchRow.searchExpanded = !stepSearchRow.searchExpanded

                    // A peek taken while it was still running should not
                    // linger once the turn is done and there is an answer to
                    // read instead.
                    Connections {
                        target: step
                        function onStepDoneChanged() {
                            if (step.stepDone)
                                stepSearchRow.searchExpanded = false;
                        }
                    }

                    expandedContent: Component {
                        Flow {
                            spacing: Appearance.rounding.unsharpenmore

                            Repeater {
                                model: ScriptModel {
                                    values: stepSearchRow.queries
                                }

                                delegate: AiSearchQueryButton {
                                    required property var modelData
                                    query: modelData
                                }
                            }
                        }
                    }
                }

                    Repeater {
                    // Everything else it reached for, in the order it did.
                    model: ScriptModel {
                        values: Array.from(step.stepData?.toolCalls ?? [])
                    }

                    delegate: AiActivityRow {
                        id: stepToolRow
                        onTimeline: step.visibleStepCount > 1
                        required property var modelData
                        property bool toolExpanded: false

                        readonly property string toolId: String(stepToolRow.modelData?.name ?? "")
                        readonly property var definition: Ai.toolbox.definitionFor(stepToolRow.toolId)
                        readonly property string detail: Ai.toolbox.describeArgs(stepToolRow.toolId, stepToolRow.modelData?.args)
                        // Written by the broker onto the call itself as it goes.
                        // A call with no state at all is one from a session saved
                        // before the broker existed.
                        readonly property string state: String(stepToolRow.modelData?.state ?? "")
                        readonly property string outcome: String(stepToolRow.modelData?.summary ?? "")
                        readonly property bool waiting: stepToolRow.state === "running"
                            || (stepToolRow.state.length === 0 && (step.stepStreaming || (step.stepData?.functionPending ?? false)))
                        readonly property bool wentWrong: ["error", "unavailable", "needsInspection"].indexOf(stepToolRow.state) >= 0
                        readonly property bool refused: ["denied", "cancelled"].indexOf(stepToolRow.state) >= 0

                        Layout.fillWidth: true
                        symbol: {
                            if (stepToolRow.state === "needsInspection")
                                return "help";
                            if (stepToolRow.wentWrong)
                                return "error";
                            if (stepToolRow.refused)
                                return "block";
                            return (stepToolRow.definition?.icon ?? "").length > 0 ? stepToolRow.definition.icon : "build";
                        }
                        // The outcome next to the name, because "Search the web"
                        // and "Search the web · nothing came back" are different
                        // things to have read in a transcript.
                        label: stepToolRow.outcome.length > 0 && !stepToolRow.waiting
                            ? `${Ai.toolbox.titleFor(stepToolRow.toolId)} · ${stepToolRow.outcome}`
                            : Ai.toolbox.titleFor(stepToolRow.toolId)
                        running: stepToolRow.waiting
                        expandable: stepToolRow.detail.length > 0
                        expanded: stepToolRow.expandable && stepToolRow.toolExpanded
                        onToggled: stepToolRow.toolExpanded = !stepToolRow.toolExpanded

                        Connections {
                            target: step
                            function onStepDoneChanged() {
                                if (step.stepDone)
                                    stepToolRow.toolExpanded = false;
                            }
                        }

                        expandedContent: Component {
                            ColumnLayout {
                                spacing: Appearance.rounding.unsharpenmore

                                StyledText {
                                    Layout.fillWidth: true
                                    text: stepToolRow.detail
                                    wrapMode: Text.Wrap
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: stepToolRow.modelData?.networkUsed === true || stepToolRow.modelData?.truncated === true
                                    spacing: Appearance.rounding.unsharpenmore

                                    StyledText {
                                        visible: stepToolRow.modelData?.networkUsed === true
                                        text: Translation.tr("used the network")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }

                                    StyledText {
                                        visible: stepToolRow.modelData?.truncated === true
                                        text: Translation.tr("result was cut to fit")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }
                    }
                    }
                }
            }

            // While a single-step answer is streaming, keep its activity rows
            // directly visible so the user can follow it as it happens. Once
            // done, the rows move into the final accordion below.
            StepActivity {
                visible: !root.done && root.stepGroup.length <= 1
                stepData: root.messageData
                activityDefault: root.activityDefaultMode
            }

            // Every completed turn folds its activity into this one line.
            // Multi-step turns use the same row while streaming; single-step
            // turns join it only at completion. In both cases the details
            // remain one click away in the existing StepActivity delegates.
            AiActivityRow {
                id: stepsSummaryRow
                property bool userChoice: false
                property bool userExpanded: false

                Layout.fillWidth: true
                shown: root.done ? root.hasActivity : root.stepGroup.length > 1
                symbol: "checklist"
                running: root.streaming
                expandable: true
                expanded: stepsSummaryRow.userChoice ? stepsSummaryRow.userExpanded : root.streaming
                    || root.activityDefaultMode === "expanded"
                label: root.done
                    ? root.finalActivityLabel
                    : Translation.tr("Working through %1 steps…").arg(String(root.stepGroup.length))

                onToggled: {
                    stepsSummaryRow.userExpanded = !stepsSummaryRow.expanded;
                    stepsSummaryRow.userChoice = true;
                }

                Connections {
                    target: root
                    function onDoneChanged() {
                        if (root.done) {
                            stepsSummaryRow.userChoice = false;
                            stepsSummaryRow.userExpanded = false;
                        }
                    }
                }

                expandedContent: Component {
                    ColumnLayout {
                        spacing: Appearance.rounding.small

                        Repeater {
                            model: ScriptModel {
                                values: root.stepGroup
                            }

                            delegate: StepActivity {
                                id: groupedStep
                                required property var modelData
                                Layout.fillWidth: true
                                stepData: groupedStep.modelData
                                activityDefault: root.activityDefaultMode
                            }
                        }
                    }
                }
            }
        }

        // ── The answer ────────────────────────────────────────────────────

        Rectangle {
            id: answerBubble
            Layout.alignment: Qt.AlignLeft
            Layout.fillWidth: true
            Layout.maximumWidth: root.answerMaximumWidth
            visible: root.isAssistant && (root.messageBlocks.length > 0 || root.streaming)
            implicitHeight: visible ? answerContentClip.implicitHeight + root.bubblePadding * 2 : 0
            radius: Math.min(answerBubble.height / 2, Appearance.rounding.large)
            // An empty bubble is a box with nothing in it. The ground arrives
            // with the first block, so the wait reads as the model about to
            // speak rather than as a card that failed to load.
            readonly property bool holdsOnlyTheWait: root.messageBlocks.length < 1
            color: answerBubble.holdsOnlyTheWait ? "transparent" : root.answerSurface

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            // Line by line rather than in jumps: the box follows the text
            // that is arriving in it instead of snapping to each new height.
            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            Item {
                // No fade of its own: the only soft edges in the transcript
                // are the ones at the top and the bottom of the list, and a
                // second one inside a bubble read as the answer being cut.
                id: answerContentClip
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root.bubblePadding
                implicitHeight: root.collapseLongAnswer
                    ? Math.min(answerContent.implicitHeight, root.longAnswerCollapsedHeight)
                    : answerContent.implicitHeight
                height: implicitHeight
                clip: root.collapseLongAnswer

                ColumnLayout {
                    id: answerContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: root.blockGap

                    Loader {
                        // A retry has no tokens to animate, so putting the
                        // status in the answer itself is the only reliable
                        // indication that it is still alive. It is scoped to
                        // this message; old completed turns never inherit it.
                        Layout.fillWidth: true
                        active: root.retrying
                        visible: active

                        sourceComponent: Rectangle {
                            implicitHeight: retryRow.implicitHeight + root.bubblePadding
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colTertiaryContainer

                            RowLayout {
                                id: retryRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: root.bubblePadding
                                anchors.rightMargin: root.bubblePadding
                                spacing: Appearance.rounding.unsharpenmore

                                MaterialSymbol {
                                    text: "sync"
                                    fill: 1
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnTertiaryContainer
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Ai.retryNotice
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnTertiaryContainer
                                }

                                RippleButton {
                                    implicitHeight: Math.round(Appearance.font.pixelSize.huge * 1.5)
                                    leftPadding: Appearance.rounding.small
                                    rightPadding: Appearance.rounding.small
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colTertiaryContainerHover
                                    colBackgroundHover: Appearance.colors.colTertiaryContainerActive
                                    colRipple: Appearance.colors.colTertiaryContainerActive
                                    onClicked: Ai.stopGeneration()

                                    Accessible.name: Translation.tr("Cancel retry")

                                    contentItem: StyledText {
                                        text: Translation.tr("Cancel")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnTertiaryContainer
                                    }
                                }

                                RippleButton {
                                    implicitHeight: Math.round(Appearance.font.pixelSize.huge * 1.5)
                                    leftPadding: Appearance.rounding.small
                                    rightPadding: Appearance.rounding.small
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colTertiaryContainerHover
                                    colBackgroundHover: Appearance.colors.colTertiaryContainerActive
                                    colRipple: Appearance.colors.colTertiaryContainerActive
                                    onClicked: {
                                        // Selecting another model must not let
                                        // the old retry leave while the picker
                                        // is open.
                                        Ai.stopGeneration();
                                        root.modelPickerRequested();
                                    }

                                    Accessible.name: Translation.tr("Cancel retry and change model")

                                    contentItem: StyledText {
                                        text: Translation.tr("Change model")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnTertiaryContainer
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        // Before the first token there is nothing to show but
                        // that something is coming — centred, because an empty
                        // bubble with a mark in its corner reads as a fault.
                        Layout.fillWidth: true
                        implicitHeight: loadingIndicatorLoader.shown ? loadingIndicatorLoader.implicitHeight : 0
                        visible: implicitHeight > 0

                        Behavior on implicitHeight {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }

                        FadeLoader {
                            // Left, where the first line of the answer will
                            // appear: the wait belongs in the place the words
                            // are about to take, not in the middle of a box.
                            id: loadingIndicatorLoader
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            shown: root.messageBlocks.length < 1 && root.streaming

                            sourceComponent: AiTypingIndicator {
                                active: loadingIndicatorLoader.shown
                                // Before the first token, a model with a thought
                                // in flight is reasoning; one without has not
                                // started saying anything yet.
                                reasoning: (root.messageData?.thought?.length ?? 0) > 0
                            }
                        }
                    }

                    Repeater {
                        model: ScriptModel {
                            values: root.messageBlocks
                        }

                        delegate: Item {
                            id: messageBlockItem
                            required property var modelData

                            Layout.fillWidth: true
                            implicitWidth: parent ? parent.width : 0
                            implicitHeight: messageBlockLoader.implicitHeight

                            Component {
                                id: codeBlockComponent
                                AiMessageCodeBlock {
                                    width: messageBlockItem.width
                                    segmentContent: messageBlockItem.modelData?.content ?? ""
                                    segmentLang: messageBlockItem.modelData?.lang ?? "txt"
                                    messageData: root.messageData
                                }
                            }

                            Component {
                                id: thinkBlockComponent
                                AiMessageThinkBlock {
                                    width: messageBlockItem.width
                                    segmentContent: messageBlockItem.modelData?.content ?? ""
                                    messageData: root.messageData
                                    done: root.done
                                    completed: messageBlockItem.modelData?.completed ?? false
                                }
                            }

                            Component {
                                id: tableBlockComponent
                                AiMessageTableBlock {
                                    width: messageBlockItem.width
                                    block: messageBlockItem.modelData
                                    messageData: root.messageData
                                }
                            }

                            Component {
                                id: textBlockComponent
                                AiMessageTextBlock {
                                    width: messageBlockItem.width
                                    segmentContent: messageBlockItem.modelData?.content ?? ""
                                    messageData: root.messageData
                                    done: root.done
                                    forceDisableChunkSplitting: root.transcriptContent.includes("```")
                                }
                            }

                            Loader {
                                id: messageBlockLoader
                                width: parent.width
                                sourceComponent: {
                                    const blockType = messageBlockItem.modelData?.type;
                                    if (blockType === "code")
                                        return codeBlockComponent;
                                    if (blockType === "think")
                                        return thinkBlockComponent;
                                    if (blockType === "table")
                                        return tableBlockComponent;
                                    return textBlockComponent;
                                }
                            }
                        }
                    }
                }
            }
        }

        RippleButton {
            Layout.alignment: Qt.AlignLeft
            visible: root.hasLongAnswer && Config.options.sidebar.ai.collapseLongAnswers
            implicitHeight: Math.round(Appearance.font.pixelSize.huge * 1.55)
            leftPadding: Appearance.rounding.small
            rightPadding: Appearance.rounding.small
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: root.longAnswerExpanded = !root.longAnswerExpanded

            contentItem: RowLayout {
                spacing: Appearance.rounding.unsharpenmore / 2

                MaterialSymbol {
                    text: root.longAnswerExpanded ? "unfold_less" : "unfold_more"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    text: root.longAnswerExpanded ? Translation.tr("Show less") : Translation.tr("Show full answer")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        RowLayout {
            id: metaRow
            /**
             * The actions bar under a finished answer already carries the
             * model's logo and name, so naming it here too printed it twice
             * under every reply. This line keeps the model only when that
             * bar is not the one saying it.
             */
            readonly property bool modelNamedElsewhere: answerActions.visible
            readonly property bool showsModel: root.isAssistant
                && Config.options.sidebar.ai.showAnswerModel
                && !metaRow.modelNamedElsewhere
                && String(root.messageData?.model ?? "").length > 0

            Layout.fillWidth: true
            Layout.maximumWidth: root.answerMaximumWidth
            visible: root.done && ((Config.options.sidebar.ai.showTimestamps && root.timestampLabel().length > 0)
                || (root.isAssistant && Config.options.sidebar.ai.showResponseTime && root.responseTimeLabel().length > 0)
                || metaRow.showsModel)
            spacing: Appearance.rounding.unsharpenmore

            StyledText {
                visible: Config.options.sidebar.ai.showTimestamps && root.timestampLabel().length > 0
                text: root.timestampLabel()
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            StyledText {
                visible: root.isAssistant && Config.options.sidebar.ai.showResponseTime && root.responseTimeLabel().length > 0
                text: Translation.tr("Answered in %1").arg(root.responseTimeLabel())
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            StyledText {
                visible: metaRow.showsModel
                text: Ai.catalog.models[root.messageData?.model]?.title ?? String(root.messageData?.model ?? "")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        // ── When it went wrong, or wants something ────────────────────────

        // ── Cards this turn carries ───────────────────────────────────────
        // A tool that needs to show something adds a card; the component is
        // picked by its `kind`. There used to be one Loader per tool here,
        // each testing a property of its own on the message, which is three
        // edits in three files every time a tool learns to ask something.

        Repeater {
            model: ScriptModel {
                values: Ai.visibleToolCards(root.messageData)
            }

            delegate: Item {
                id: cardHost
                required property var modelData
                readonly property var card: cardHost.modelData
                readonly property string cardState: String(cardHost.card?.state ?? "")
                readonly property bool approvalCard: Ai.approvalCardKinds.indexOf(cardHost.card?.kind) >= 0
                readonly property bool pending: cardHost.cardState === "pending"
                readonly property bool resolvedApproval: cardHost.approvalCard && !cardHost.pending
                property bool retainPendingBody: cardHost.pending

                Layout.fillWidth: true
                Layout.maximumWidth: root.answerMaximumWidth
                implicitHeight: Math.max(pendingCard.height,
                    cardHost.resolvedApproval ? resolutionRow.implicitHeight : 0)

                onPendingChanged: {
                    if (cardHost.pending) {
                        cardHost.retainPendingBody = true;
                        approvalExitCleanup.stop();
                    } else if (cardHost.retainPendingBody) {
                        if (root.reducedMotion)
                            cardHost.retainPendingBody = false;
                        else
                            approvalExitCleanup.restart();
                    }
                }

                Loader {
                    id: pendingCard
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    active: cardHost.pending || cardHost.retainPendingBody
                    height: item?.implicitHeight ?? 0
                    opacity: cardHost.pending ? 1 : 0
                    transform: Translate {
                        y: cardHost.pending ? 0 : -Appearance.rounding.verysmall

                        Behavior on y {
                            enabled: !root.reducedMotion
                            animation: Appearance.animation.elementMoveExit.numberAnimation.createObject(this)
                        }
                    }

                    Behavior on opacity {
                        enabled: !root.reducedMotion
                        animation: Appearance.animation.elementMoveExit.numberAnimation.createObject(this)
                    }

                    sourceComponent: {
                    switch (String(cardHost.card?.kind ?? "")) {
                    case "settingsDiff":
                        return settingsDiffCard;
                    case "settingsResults":
                        return settingsResultsCard;
                    case "reminderPreview":
                    case "alarmPreview":
                        return reminderPreviewCard;
                    case "timerPreview":
                        return timerPreviewCard;
                    case "memoryFact":
                        return memoryFactCard;
                    case "fileResults":
                        return fileResultsCard;
                    case "fileAttachPreview":
                        return fileAttachCard;
                    case "notesPreview":
                        return notesPreviewCard;
                    case "systemControlPreview":
                        return systemControlPreviewCard;
                    case "windowMovePreview":
                        return windowMovePreviewCard;
                    case "wallpaperPreview":
                        return wallpaperPreviewCard;
                    case "mediaControlPreview":
                        return mediaControlPreviewCard;
                    case "songIdentifyPreview":
                        return songIdentifyPreviewCard;
                    case "gmailResults":
                        return gmailResultsCard;
                    case "sportsResults":
                        return sportsResultsCard;
                    case "taskPreview":
                        return taskPreviewCard;
                    case "taskResults":
                        return taskResultsCard;
                    case "ragResults":
                        return ragResultsCard;
                    case "taskMutationPreview":
                    case "calendarMutationPreview":
                        return taskMutationPreviewCard;
                    }
                    // A kind this build does not know: a session written by a
                    // newer one still opens, showing what the card says about
                    // itself rather than nothing at all.
                    return unknownCard;
                    }
                }

                Item {
                    id: resolutionRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    implicitHeight: resolutionContent.implicitHeight
                    visible: cardHost.resolvedApproval || opacity > 0.01
                    opacity: cardHost.resolvedApproval ? 1 : 0
                    transform: Translate {
                        y: cardHost.resolvedApproval ? 0 : Appearance.rounding.verysmall

                        Behavior on y {
                            enabled: !root.reducedMotion
                            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                        }
                    }

                    Behavior on opacity {
                        enabled: !root.reducedMotion
                        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                    }

                    RowLayout {
                        id: resolutionContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Appearance.rounding.unsharpenmore

                        MaterialSymbol {
                            text: {
                                if (cardHost.cardState === "done")
                                    return "check_circle";
                                if (cardHost.cardState === "denied")
                                    return "block";
                                if (cardHost.cardState === "needsInspection")
                                    return "help";
                                return "error";
                            }
                            fill: 1
                            iconSize: Appearance.font.pixelSize.larger
                            color: cardHost.cardState === "done"
                                ? Appearance.colors.colPrimary
                                : cardHost.cardState === "failed"
                                    ? Appearance.m3colors.m3error
                                    : Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: String(cardHost.card?.summary ?? "").length > 0
                                ? String(cardHost.card.summary)
                                : cardHost.cardState === "done"
                                    ? Translation.tr("Approved action completed")
                                    : Translation.tr("Approved action was not completed")
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                Timer {
                    id: approvalExitCleanup
                    interval: Appearance.animation.elementMoveExit.duration
                    onTriggered: cardHost.retainPendingBody = false
                }

                Component {
                    id: settingsDiffCard

                    AiConfigDiffCard {
                        messageData: root.messageData
                        card: cardHost.card
                    }
                }

                Component {
                    id: settingsResultsCard

                    ColumnLayout {
                        spacing: Appearance.rounding.unsharpenmore

                        Repeater {
                            model: ScriptModel {
                                values: Array.from(cardHost.card?.data?.matches ?? [])
                            }

                            delegate: AiSettingResultCard {
                                required property var modelData
                                setting: modelData
                            }
                        }
                    }
                }

                Component {
                    id: fileResultsCard

                    ColumnLayout {
                        spacing: Appearance.rounding.unsharpenmore

                        Repeater {
                            model: ScriptModel {
                                values: Array.from(cardHost.card?.data?.files ?? [])
                            }

                            delegate: AiFileResultCard {
                                required property var modelData
                                file: modelData
                                compact: root.compact
                            }
                        }
                    }
                }

                Component {
                    id: ragResultsCard

                    ColumnLayout {
                        spacing: Appearance.rounding.unsharpenmore

                        Repeater {
                            model: ScriptModel {
                                values: Array.from(cardHost.card?.data?.results ?? [])
                            }

                            delegate: AiRagResultCard {
                                required property var modelData
                                hit: modelData
                            }
                        }
                    }
                }

                Component {
                    id: fileAttachCard

                    AiFileAttachCard {
                        messageData: root.messageData
                        card: cardHost.card
                    }
                }

                Component {
                    id: reminderPreviewCard

                    AiReminderCard {
                        messageData: root.messageData
                        card: cardHost.card
                    }
                }

                Component {
                    id: timerPreviewCard

                    AiTimerCard {
                        messageData: root.messageData
                        card: cardHost.card
                    }
                }

                Component {
                    id: notesPreviewCard

                    AiNotesCard {
                        messageData: root.messageData
                        card: cardHost.card
                    }
                }

                Component {
                    id: systemControlPreviewCard

                    AiSystemControlCard {
                        messageData: root.messageData
                        card: cardHost.card
                    }
                }

                Component {
                    id: windowMovePreviewCard

                    AiWindowMoveCard {
                        messageData: root.messageData
                        card: cardHost.card
                    }
                }

                Component {
                    id: wallpaperPreviewCard

                    AiWallpaperCard {
                        messageData: root.messageData
                        card: cardHost.card
                    }
                }

                Component {
                    id: mediaControlPreviewCard

                    AiMediaControlCard {
                        messageData: root.messageData
                        card: cardHost.card
                    }
                }

                Component {
                    id: songIdentifyPreviewCard

                    AiSongIdentifyCard {
                        messageData: root.messageData
                        card: cardHost.card
                    }
                }

                Component {
                    id: gmailResultsCard

                    AiGmailResultCard {
                        card: cardHost.card
                    }
                }

                Component {
                    id: sportsResultsCard

                    AiSportsGameCard {
                        card: cardHost.card
                    }
                }

                Component {
                    id: taskPreviewCard

                    AiTaskCard {
                        messageData: root.messageData
                        card: cardHost.card
                    }
                }

                Component {
                    id: taskResultsCard

                    AiTaskResultCard {
                        card: cardHost.card
                    }
                }

                Component {
                    id: taskMutationPreviewCard

                    AiTaskMutationCard {
                        messageData: root.messageData
                        card: cardHost.card
                    }
                }

                Component {
                    id: unknownCard

                    Rectangle {
                        implicitHeight: unknownRow.implicitHeight + root.bubblePadding * 2
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer2

                        RowLayout {
                            id: unknownRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: root.bubblePadding
                            anchors.rightMargin: root.bubblePadding
                            spacing: Appearance.rounding.unsharpenmore

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignTop
                                text: "extension"
                                fill: 1
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: String(cardHost.card?.summary ?? "").length > 0
                                    ? cardHost.card.summary
                                    : Translation.tr("This needs a newer version of the shell to show.")
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }

                Component {
                    id: memoryFactCard

                    Rectangle {
                        implicitHeight: memoryColumn.implicitHeight + root.bubblePadding * 2
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colSecondaryContainer

                        ColumnLayout {
                            id: memoryColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: root.bubblePadding
                            anchors.rightMargin: root.bubblePadding
                            spacing: Appearance.rounding.unsharpenmore

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Appearance.rounding.unsharpenmore

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignTop
                                    text: "bookmark_add"
                                    fill: 1
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.m3colors.m3onSecondaryContainer
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Remember this for later chats?")
                                        wrapMode: Text.Wrap
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: Appearance.m3colors.m3onSecondaryContainer
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: cardHost.card?.data?.fact ?? ""
                                        wrapMode: Text.Wrap
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.m3colors.m3onSecondaryContainer
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Appearance.rounding.unsharpenmore

                                Item {
                                    Layout.fillWidth: true
                                }

                                RippleButton {
                                    leftPadding: Appearance.rounding.small
                                    rightPadding: Appearance.rounding.small
                                    topPadding: Appearance.rounding.unsharpenmore / 2
                                    bottomPadding: Appearance.rounding.unsharpenmore / 2
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                                    colBackgroundHover: Appearance.colors.colLayer2Hover
                                    colRipple: Appearance.colors.colLayer2Active
                                    onClicked: Ai.rejectMemory(root.messageData)

                                    contentItem: StyledText {
                                        text: Translation.tr("No")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.m3colors.m3onSecondaryContainer
                                    }
                                }

                                RippleButton {
                                    leftPadding: Appearance.rounding.small
                                    rightPadding: Appearance.rounding.small
                                    topPadding: Appearance.rounding.unsharpenmore / 2
                                    bottomPadding: Appearance.rounding.unsharpenmore / 2
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colPrimary
                                    colBackgroundHover: Appearance.colors.colPrimaryHover
                                    colRipple: Appearance.colors.colPrimaryActive
                                    onClicked: Ai.commitMemory(root.messageData)

                                    contentItem: StyledText {
                                        text: Translation.tr("Remember it")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnPrimary
                                    }
                                }
                            }
                        }
            }
                }
            }
        }

        Loader {
            // A failed request used to leave a message that stopped, with the
            // reason in the log. What went wrong and what to do about it both
            // belong here, next to a button that tries again.
            Layout.fillWidth: true
            Layout.maximumWidth: root.answerMaximumWidth
            active: (root.messageData?.errorKind?.length ?? 0) > 0
            visible: active

            sourceComponent: Rectangle {
                implicitHeight: errorColumn.implicitHeight + root.bubblePadding * 2
                radius: Appearance.rounding.large
                color: ColorUtils.transparentize(Appearance.m3colors.m3error, 0.88)

                ColumnLayout {
                    id: errorColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: root.bubblePadding
                    anchors.rightMargin: root.bubblePadding
                    spacing: Appearance.rounding.unsharpenmore

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.rounding.unsharpenmore

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignTop
                            text: "error"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.m3colors.m3error
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: root.messageData?.errorText ?? Translation.tr("The request failed.")
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.m3colors.m3error
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: Ai.transportErrorAdvice(root.messageData?.errorKind ?? "")
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    StyledText {
                        // The provider's own words, folded away. They are
                        // usually a page of JSON that repeats what the line
                        // above already said, and occasionally the only place
                        // the real reason appears.
                        Layout.fillWidth: true
                        Layout.maximumHeight: Appearance.font.pixelSize.huge * 7
                        visible: errorDetailsToggle.visible && errorDetailsToggle.unfolded
                        text: root.messageData?.errorDetails ?? ""
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.rounding.unsharpenmore

                        RippleButton {
                            id: errorDetailsToggle
                            property bool unfolded: false

                            visible: (root.messageData?.errorDetails?.length ?? 0) > 0
                            leftPadding: Appearance.rounding.small
                            rightPadding: Appearance.rounding.small
                            topPadding: Appearance.rounding.unsharpenmore / 2
                            bottomPadding: Appearance.rounding.unsharpenmore / 2
                            buttonRadius: Appearance.rounding.full
                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: errorDetailsToggle.unfolded = !errorDetailsToggle.unfolded

                            contentItem: StyledText {
                                text: errorDetailsToggle.unfolded ? Translation.tr("Hide details") : Translation.tr("Details")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        RippleButton {
                            visible: (root.messageData?.errorKind ?? "") === "auth"
                            leftPadding: Appearance.rounding.small
                            rightPadding: Appearance.rounding.small
                            topPadding: Appearance.rounding.unsharpenmore / 2
                            bottomPadding: Appearance.rounding.unsharpenmore / 2
                            buttonRadius: Appearance.rounding.full
                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: Ai.keyManagerRequested()

                            contentItem: StyledText {
                                text: Translation.tr("Keys")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }
                        }

                        RippleButton {
                            leftPadding: Appearance.rounding.small
                            rightPadding: Appearance.rounding.small
                            topPadding: Appearance.rounding.unsharpenmore / 2
                            bottomPadding: Appearance.rounding.unsharpenmore / 2
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colRipple: Appearance.colors.colPrimaryActive
                            onClicked: Ai.retryMessage(root.messageId)

                            contentItem: RowLayout {
                                spacing: Appearance.rounding.unsharpenmore / 2

                                MaterialSymbol {
                                    text: "refresh"
                                    fill: 1
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.m3colors.m3onPrimary
                                }

                                StyledText {
                                    text: Translation.tr("Try again")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.m3colors.m3onPrimary
                                }
                            }
                        }
                    }
                }
            }
        }

        Loader {
            // "Set a key with /key VALUE" was the whole of the old advice, and
            // it meant typing a secret into the transcript.
            Layout.alignment: Qt.AlignHCenter
            active: (root.messageData?.notice ?? "") === "apiKey"
            visible: active

            sourceComponent: RippleButton {
                leftPadding: Appearance.rounding.small
                rightPadding: Appearance.rounding.small
                topPadding: Appearance.rounding.unsharpenmore
                bottomPadding: Appearance.rounding.unsharpenmore
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: Ai.keyManagerRequested()

                contentItem: RowLayout {
                    spacing: Appearance.rounding.unsharpenmore / 2

                    MaterialSymbol {
                        text: "key"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }

                    StyledText {
                        text: Translation.tr("Open the key panel")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }
                }
            }
        }

        Flow {
            // Where an answer with citations got them from.
            Layout.fillWidth: true
            Layout.maximumWidth: root.answerMaximumWidth
            visible: (root.messageData?.annotationSources?.length ?? 0) > 0
            spacing: Appearance.rounding.unsharpenmore

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.annotationSources ?? []
                }

                delegate: AiAnnotationSourceButton {
                    required property var modelData
                    displayText: modelData.text
                    url: modelData.url
                }
            }
        }

        Loader {
            // The provider stopped at its output limit. Regenerating was the
            // only way out before, and it paid for the whole context again to
            // get a different answer instead of the rest of this one.
            Layout.fillWidth: true
            Layout.maximumWidth: root.answerMaximumWidth
            active: root.isAssistant && root.done && Ai.wasTruncated(root.messageData)
            visible: active

            sourceComponent: RippleButton {
                implicitHeight: Math.round(Appearance.font.pixelSize.huge * 1.7)
                leftPadding: Appearance.rounding.small
                rightPadding: Appearance.rounding.small
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: Ai.continueMessage(root.messageId)

                Accessible.name: Translation.tr("Continue this answer")

                contentItem: RowLayout {
                    spacing: Appearance.rounding.unsharpenmore

                    MaterialSymbol {
                        text: "more_horiz"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }

                    StyledText {
                        text: Translation.tr("Continue — it stopped at the length limit")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }
                }
            }
        }

        RowLayout {
            Layout.maximumWidth: root.answerMaximumWidth
            visible: root.showAnswerVariants
            spacing: Appearance.rounding.unsharpenmore / 2

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: Math.round(Appearance.font.pixelSize.huge * 1.45)
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: Ai.openAnswerVariant(root.messageId, -1)
                Accessible.name: Translation.tr("Previous answer variant")

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "chevron_left"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                }
            }

            StyledText {
                text: "<" + String(root.answerVariantIndex + 1) + "/" + String(root.answerVariantIds.length) + ">"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: Math.round(Appearance.font.pixelSize.huge * 1.45)
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: Ai.openAnswerVariant(root.messageId, 1)
                Accessible.name: Translation.tr("Next answer variant")

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        // ── What can be done with it ──────────────────────────────────────

        AiMessageActions {
            id: answerActions
            Layout.fillWidth: true
            Layout.maximumWidth: root.answerMaximumWidth
            Layout.topMargin: visible ? root.blockGap / 2 : 0
            visible: root.isAssistant && root.done && root.messageBlocks.length > 0
            // The Search panel is a strip that is mostly composer: it gets
            // the same bar with the two actions a quick question needs.
            minimal: root.compact
            messageId: root.messageId
            messageData: root.messageData
            surfaceColor: root.answerSurface
            buttonColor: root.questionSurface
            buttonInk: root.questionInk
            onRegenerateRequested: id => root.regenerateRequested(id)
            onModelPickerRequested: root.modelPickerRequested()

            // It arrives when the answer is finished, from just under it.
            opacity: visible ? 1 : 0
            transform: Translate {
                y: answerActions.visible ? 0 : -Appearance.rounding.small

                Behavior on y {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
