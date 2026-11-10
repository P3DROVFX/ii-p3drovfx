pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The assistant's prompt pill and its answer, for one subject.
 *
 * The pill is Modes' bar (AssistantPromptBar) with two differences: an empty send asks
 * the default question, and the answer is printed here instead of in the chat. A fix
 * the model proposed is a button under the answer; it runs only when clicked.
 *
 * The answer shown is the one streaming in while its run lasts, and the saved one from
 * HealthAnswers after: it stays through tab switches, closed windows and restarts until
 * the card's close button. The fold button shrinks the card to its question.
 */
ColumnLayout {
    id: root

    required property HealthAssistant assistant
    required property string key
    property string placeholder: Translation.tr("Ask about this — “how do I fix it?”")
    /// The answer card's colours; a surface already on primary container passes another pair.
    property color colCard: ClockStyle.colPrimaryContainer
    property color colOnCard: ClockStyle.colOnPrimaryContainer
    /// The owner's facts about the subject, as its ✦ button passes them: Follow up
    /// opens the pill with them.
    property var provider: null

    readonly property bool mine: root.assistant.subjectKey === root.key
    readonly property var saved: HealthAnswers.entries[root.key] ?? null
    readonly property bool live: root.assistant.isLive(root.key)
    readonly property bool running: root.live && root.assistant.phase === "running"
    /// The thread, oldest first: the saved turns, or while a run lasts, the turns it
    /// follows up on and the one streaming in.
    readonly property var turns: root.live
        ? root.assistant.priorTurns.concat([{ q: root.assistant.question, a: root.assistant.answer, proposal: root.assistant.proposal }])
        : HealthAnswers.turnsOf(root.saved)
    readonly property var earlierTurns: root.turns.slice(0, -1)
    readonly property var lastTurn: root.turns.length > 0 ? root.turns[root.turns.length - 1] : null
    readonly property string shownQuestion: String(root.lastTurn?.q ?? "")
    readonly property string shownAnswer: String(root.lastTurn?.a ?? "")
    readonly property var shownProposal: root.lastTurn?.proposal ?? null
    /// A send here follows up rather than starting over.
    readonly property bool hasThread: !root.running && HealthAnswers.turnsOf(root.saved).length > 0
    /// Earlier turns are folded behind a "2 earlier questions" line until asked for.
    property bool showEarlier: false
    readonly property bool folded: root.live ? root.assistant.liveFolded : root.saved?.folded === true
    readonly property bool showAnswer: root.live || root.saved !== null
    /// One answer's text: prose as Markdown, fenced code as blocks with Copy and Run.
    component AnswerText: ColumnLayout {
        id: answerText
        property string answer: ""
        /// Still streaming: an unclosed fence is code being written, not yet runnable.
        property bool live: false
        spacing: ClockStyle.gapSmall

        Repeater {
            // A new list on every streamed chunk: compared by position and content,
            // so only the segment that grew updates, and a code block keeps its state.
            model: ScriptModel {
                values: root.segmentsOf(answerText.answer)
            }

            Loader {
                id: segment
                required property var modelData
                Layout.fillWidth: true
                sourceComponent: segment.modelData.code ? codeSegment : textSegment

                Component {
                    id: textSegment
                    StyledText {
                        text: segment.modelData.text
                        textFormat: Text.MarkdownText
                        wrapMode: Text.Wrap
                        font.pixelSize: ClockStyle.textNormal
                        color: root.colOnCard
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }

                Component {
                    id: codeSegment
                    HealthCodeBlock {
                        code: segment.modelData.text
                        lang: segment.modelData.lang
                        streaming: segment.modelData.open && answerText.live
                        colOnCard: root.colOnCard
                    }
                }
            }
        }
    }

    /// Opens the pill on this subject for a follow-up question.
    function followUp(): void {
        if (!root.assistant.isOpenOn(root.key))
            root.assistant.toggle(root.key, root.provider ?? root.assistant.subjectProvider);
        Qt.callLater(bar.focusInput);
    }

    /// The saved answer's subject has gone: the unit recovered, the crash group aged
    /// out. Its fix has nothing left to act on.
    readonly property bool gone: !root.live && root.saved !== null && HealthService.synced && !HealthService.subjectExists(root.key)

    // Folded once when its subject goes, so a fixed problem's answer shrinks out of
    // the way; unfolding it again sticks.
    onGoneChanged: {
        if (root.gone && root.saved?.autoFolded !== true)
            HealthAnswers.patch(root.key, { folded: true, autoFolded: true });
    }

    /// An answer cut at its ``` fences: [{ code, text, lang, open }]. A fence not yet
    /// closed (the answer is still streaming into it) is code already, marked open.
    function segmentsOf(answer): var {
        const text = String(answer ?? "");
        const out = [];
        const fence = /```([^\n`]*)\n?([\s\S]*?)(```|$)/g;
        let last = 0;
        let m;
        while ((m = fence.exec(text)) !== null) {
            if (m.index > last)
                out.push({ code: false, text: text.slice(last, m.index), lang: "", open: false });
            out.push({ code: true, text: m[2].replace(/\n+$/, ""), lang: m[1].trim(), open: m[3] !== "```" });
            last = fence.lastIndex;
            if (m[3] !== "```")
                break;
        }
        if (last < text.length)
            out.push({ code: false, text: text.slice(last), lang: "", open: false });
        return out.filter(s => s.code ? s.text.length > 0 || s.open : s.text.trim().length > 0);
    }

    /// The finding whose proposed fix was clicked on this card, for its status line.
    property string ranFindingId: ""

    /// The card is folding away; the answer is cleared only once it is gone, so its text
    /// does not vanish first and leave a header-sized card to snap out.
    property bool closing: false

    readonly property bool wanted: (root.mine && root.assistant.expanded) || root.showAnswer || root.closing

    /// 1 open, 0 gone. Hiding on `wanted` alone cut the pill's own fold off on its first
    /// frame, and the owner's spacing above the panel snapped shut with it; the panel
    /// stays until this has folded that gap away, in step with the pill's height.
    property real openness: root.wanted ? 1 : 0

    Behavior on openness {
        enabled: !ClockStyle.reducedMotion
        NumberAnimation {
            id: opennessAnim
            duration: ClockStyle.motionDefault.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasized
        }
    }

    /// 1 with the answer showing, 0 folded to the question line.
    property real bodyShown: root.folded ? 0 : 1

    // Standard, not emphasized: emphasized covers most of its distance in a tenth of its
    // time and then creeps, which on a tall card read as a snap followed by a crawl.
    Behavior on bodyShown {
        enabled: !ClockStyle.reducedMotion
        NumberAnimation {
            duration: ClockStyle.motionDefault.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.standard
        }
    }

    visible: root.wanted || opennessAnim.running
    Layout.topMargin: -(root.parent?.spacing ?? 0) * (1 - root.openness)
    spacing: ClockStyle.gapSmall

    function toggleFold(): void {
        root.assistant.setFolded(root.key, !root.folded);
    }

    function closeAnswer(): void {
        if (root.closing)
            return;
        if (root.running)
            root.assistant.stop();
        if (ClockStyle.reducedMotion) {
            root.assistant.clearAnswer(root.key);
            return;
        }
        card.foldHeight = card.height;
        root.closing = true;
        closeAnim.restart();
    }

    function endClose(clear): void {
        closeAnim.stop();
        if (clear)
            root.assistant.clearAnswer(root.key);
        card.foldHeight = -1;
        card.foldMargin = 0;
        card.opacity = 1;
        root.closing = false;
    }

    Component.onDestruction: {
        if (root.closing)
            root.assistant.clearAnswer(root.key);
    }

    SequentialAnimation {
        id: closeAnim

        ParallelAnimation {
            NumberAnimation {
                target: card
                property: "opacity"
                to: 0
                duration: ClockStyle.motionExit.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: ClockStyle.motionExit.bezierCurve
            }
            // Height and the gap above fold together, so nothing below jumps at the end.
            // Standard, not the spatial spring (an overshoot would drive the height
            // negative) nor emphasized (a snap, then a crawl).
            NumberAnimation {
                target: card
                property: "foldHeight"
                to: 0
                duration: ClockStyle.motionDefault.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.standard
            }
            NumberAnimation {
                target: card
                property: "foldMargin"
                to: -root.spacing
                duration: ClockStyle.motionDefault.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.standard
            }
        }

        ScriptAction {
            script: root.endClose(true)
        }
    }

    AssistantPromptBar {
        id: bar
        Layout.fillWidth: true
        expanded: root.mine && root.assistant.expanded
        // The run's state shows on the pill of the subject it was asked about.
        phase: root.assistant.runKey === root.key ? (root.assistant.phase === "running" ? "running" : root.assistant.phase === "error" ? "error" : "idle") : "idle"
        errorText: root.assistant.errorText
        // With an answer to build on, a send follows up on it and needs words; an
        // empty send asks the default question only on a fresh subject.
        placeholder: root.hasThread ? Translation.tr("Ask a follow-up…") : root.placeholder
        allowEmpty: !root.hasThread
        showChatHop: false
        onSubmitted: text => {
            if (root.closing)
                root.endClose(false);
            root.assistant.submit(text);
            bar.clear();
        }
        onStopRequested: root.assistant.stop()
        onDismissed: root.assistant.dismiss()
    }

    Rectangle {
        id: card
        Layout.fillWidth: true
        visible: root.showAnswer
        implicitHeight: answerColumn.implicitHeight + ClockStyle.gapLarge * 2
        Layout.preferredHeight: foldHeight
        Layout.topMargin: foldMargin
        clip: root.closing
        radius: ClockStyle.radiusLarge
        color: root.colCard

        /// -1 lets the layout use implicitHeight; the close animation drives both.
        property real foldHeight: -1
        property real foldMargin: 0

        StaggeredEntrance {
            index: 0
        }

        ColumnLayout {
            id: answerColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: ClockStyle.gapLarge
            }
            spacing: ClockStyle.gapSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    text: "auto_awesome"
                    iconSize: ClockStyle.iconSmall
                    fill: 1
                    color: root.colOnCard
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.shownQuestion
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.Bold
                    color: root.colOnCard
                    opacity: 0.8

                    // The question line is the folded card's handle too.
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleFold()
                    }
                }

                // How old a saved answer is, and whether what it was about is fixed.
                Rectangle {
                    visible: root.gone
                    implicitWidth: goneText.implicitWidth + ClockStyle.gap * 2
                    implicitHeight: goneText.implicitHeight + 4
                    radius: height / 2
                    color: Qt.rgba(root.colOnCard.r, root.colOnCard.g, root.colOnCard.b, 0.14)

                    StyledText {
                        id: goneText
                        anchors.centerIn: parent
                        text: Translation.tr("Fixed since")
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.Bold
                        color: root.colOnCard
                    }
                }

                StyledText {
                    visible: !root.live && (root.saved?.at ?? 0) > 0
                    text: HealthText.age(root.saved?.at, Date.now())
                    font.pixelSize: ClockStyle.textSmall
                    font.features: { "tnum": 1 }
                    color: root.colOnCard
                    opacity: 0.7
                }

                ClockIconButton {
                    visible: root.shownAnswer.length > 0 && !root.running && !root.folded
                    symbol: "content_copy"
                    size: 30
                    iconSize: ClockStyle.iconSmall
                    colIcon: root.colOnCard
                    tooltip: Translation.tr("Copy the answer")
                    onClicked: Quickshell.clipboardText = root.shownAnswer
                }

                ClockIconButton {
                    symbol: root.folded ? "expand_more" : "expand_less"
                    size: 30
                    iconSize: ClockStyle.iconSmall
                    colIcon: root.colOnCard
                    enabled: !root.closing
                    tooltip: root.folded ? Translation.tr("Show the answer") : Translation.tr("Fold the answer")
                    onClicked: root.toggleFold()
                }

                ClockIconButton {
                    symbol: "close"
                    size: 30
                    iconSize: ClockStyle.iconSmall
                    colIcon: root.colOnCard
                    enabled: !root.closing
                    tooltip: root.running ? Translation.tr("Stop and close the answer") : Translation.tr("Close the answer")
                    onClicked: root.closeAnswer()
                }
            }

            // Folds under the question: height, the gap above it and opacity together,
            // so the card shrinks smoothly instead of dropping its text in one frame.
            Item {
                id: body
                Layout.fillWidth: true
                Layout.preferredHeight: bodyColumn.implicitHeight * root.bodyShown
                Layout.topMargin: -answerColumn.spacing * (1 - root.bodyShown)
                visible: root.bodyShown > 0.001
                // The text is gone before the card is half folded, and comes back only
                // once there is room for it, so it never slides about half-clipped.
                opacity: Math.max(0, root.bodyShown * 1.6 - 0.6)
                clip: root.bodyShown < 1

                ColumnLayout {
                    id: bodyColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    spacing: ClockStyle.gapSmall

                    // The thread's earlier questions, folded behind one line.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.earlierTurns.length > 0
                        spacing: ClockStyle.gapTiny

                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: root.showEarlier = !root.showEarlier
                        }

                        MaterialSymbol {
                            text: root.showEarlier ? "expand_less" : "history"
                            iconSize: ClockStyle.iconSmall
                            color: root.colOnCard
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.showEarlier ? Translation.tr("Hide the earlier questions")
                                : HealthText.plural(root.earlierTurns.length, Translation.tr("%1 earlier question"), Translation.tr("%1 earlier questions"))
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.Bold
                            color: root.colOnCard
                            opacity: 0.8
                        }
                    }

                    Repeater {
                        model: root.showEarlier ? root.earlierTurns : []

                        ColumnLayout {
                            id: earlier
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapTiny

                            StyledText {
                                Layout.fillWidth: true
                                text: earlier.modelData.q
                                wrapMode: Text.Wrap
                                font.pixelSize: ClockStyle.textSmall
                                font.weight: Font.Bold
                                color: root.colOnCard
                                opacity: 0.8
                            }
                            AnswerText {
                                Layout.fillWidth: true
                                answer: earlier.modelData.a
                                opacity: 0.85
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.topMargin: ClockStyle.gapTiny
                                implicitHeight: 1
                                color: Qt.rgba(root.colOnCard.r, root.colOnCard.g, root.colOnCard.b, 0.15)
                            }
                        }
                    }

                    // With the earlier turns open, the newest question is said again above
                    // its answer; the header line holds it otherwise.
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.showEarlier && root.earlierTurns.length > 0
                        text: root.shownQuestion
                        wrapMode: Text.Wrap
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.Bold
                        color: root.colOnCard
                        opacity: 0.8
                    }

                    AnswerText {
                        Layout.fillWidth: true
                        answer: root.shownAnswer
                        live: root.running
                    }

                    ClockButton {
                        visible: root.shownProposal !== null && !root.running
                        Layout.topMargin: ClockStyle.gapTiny
                        variant: "filled"
                        symbol: root.gone ? "check" : "touch_app"
                        enabled: !root.gone
                        label: root.gone ? Translation.tr("This problem is gone") : (root.shownProposal?.label ?? "")
                        onClicked: {
                            root.ranFindingId = String(root.shownProposal?.findingId ?? "");
                            root.assistant.runProposal(root.key);
                        }
                    }

                    // The button is used up once clicked; how its action went shows here.
                    HealthActionStatus {
                        Layout.fillWidth: true
                        Layout.topMargin: ClockStyle.gapTiny
                        findingId: root.ranFindingId
                        colContent: root.colOnCard
                    }

                    ClockButton {
                        visible: !root.running && root.shownAnswer.length > 0 && !(root.mine && root.assistant.expanded)
                        Layout.leftMargin: -ClockStyle.gap
                        variant: "text"
                        symbol: "reply"
                        label: Translation.tr("Follow up")
                        onClicked: root.followUp()
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: HealthService.redact
                        text: Translation.tr("Sent with your user, host and home path redacted. Crash dumps are never sent.")
                        wrapMode: Text.Wrap
                        font.pixelSize: ClockStyle.textSmall
                        color: root.colOnCard
                        opacity: 0.7
                    }
                }
            }
        }
    }
}
