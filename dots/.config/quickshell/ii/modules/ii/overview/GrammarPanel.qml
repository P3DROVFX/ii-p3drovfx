pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Fixes the grammar of the selected text, like Raycast's "Fix Spelling and
 * Grammar".
 *
 * Opening the panel reads the primary selection — the text highlighted in the
 * app the user came from — and falls back to the clipboard. Text typed into
 * the search field replaces both when Enter is pressed. The request is a
 * single-turn `AiTextTask`, so it never creates a chat session and follows
 * the AI privacy policy exactly like the Notes actions do.
 */
Item {
    id: root

    property string searchQuery: ""
    property string sourceText: ""
    property string sourceKind: ""
    property string submittedQuery: ""
    property string noticeText: ""

    // Cap what is sent: the panel is for a paragraph, not a document.
    readonly property int maximumCharacters: 8000
    // Every motion in the overview and its panels answers to one switch:
    // Settings -> Overview -> Animation style -> None.
    readonly property bool animationsDisabled: Config.options.overview.animationStyle === "none"
    readonly property string correctedText: String(task.resultText ?? "").trim()
    readonly property bool finished: task.status === "done" && root.correctedText.length > 0
    readonly property string grammarPrompt: "Correct every spelling, grammar, punctuation and agreement error in the text below. Keep its meaning, vocabulary, formatting and style exactly. Write in the same language as the text. Return only the corrected text, with nothing before or after it."
    readonly property var diff: root.finished
        ? root.diffTexts(root.sourceText, root.correctedText)
        : ({ before: root.escapeHtml(root.sourceText), after: root.escapeHtml(root.correctedText), changes: 0 })
    readonly property string sourceIcon: root.sourceKind === "selection" ? "select"
        : root.sourceKind === "clipboard" ? "content_paste" : "keyboard"
    readonly property string sourceLabel: root.sourceKind === "selection"
        ? Translation.tr("Selected text")
        : root.sourceKind === "clipboard" ? Translation.tr("Clipboard") : Translation.tr("Typed text")
    readonly property string statusText: {
        if (root.noticeText.length > 0)
            return root.noticeText;
        if (task.status === "error")
            return task.errorText;
        if (task.running)
            return Translation.tr("Fixing with %1…").arg(task.modelName);
        if (root.finished)
            return root.correctedText === root.sourceText.trim()
                ? Translation.tr("No mistakes found")
                : Translation.tr("Corrected by %1").arg(task.modelName);
        return Translation.tr("Select or copy some text, or type it above and press Enter");
    }

    implicitWidth: Config.options.search.appearance.panelWidth
    implicitHeight: scaffold.implicitHeight

    function fix(text, kind) {
        const trimmed = String(text ?? "").slice(0, root.maximumCharacters);
        if (trimmed.trim().length === 0)
            return;
        root.sourceText = trimmed;
        root.sourceKind = kind;
        task.start(root.grammarPrompt, trimmed);
    }

    function escapeHtml(text) {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>");
    }

    /**
     * Both texts marked up from one word-level LCS: words dropped from the original
     * are struck through, words new in the correction are drawn as a marker stroke.
     * `changes` counts the corrected runs. Past ~500×500 tokens the plain texts are
     * shown instead of paying for the table.
     */
    function diffTexts(before, after) {
        const a = String(before).split(/(\s+)/);
        const b = String(after).split(/(\s+)/);
        if (a.length * b.length > 250000)
            return { before: root.escapeHtml(before), after: root.escapeHtml(after), changes: 0 };
        const width = b.length + 1;
        const table = new Int32Array((a.length + 1) * width);
        for (let i = a.length - 1; i >= 0; i--) {
            for (let j = b.length - 1; j >= 0; j--) {
                table[i * width + j] = a[i] === b[j]
                    ? table[(i + 1) * width + j + 1] + 1
                    : Math.max(table[(i + 1) * width + j], table[i * width + j + 1]);
            }
        }
        const struck = String(Appearance.colors.colError);
        const marker = String(Appearance.colors.colPrimary);
        const onMarker = String(Appearance.colors.colOnPrimary);
        const blank = token => /^\s*$/.test(token);
        // New words are gathered into runs so a rewritten phrase reads as one marker
        // stroke; whitespace inside a run joins it, whitespace at its end stays outside.
        let beforeHtml = "";
        let afterHtml = "";
        let changes = 0;
        let run = [];
        const flushRun = () => {
            let tail = "";
            while (run.length > 0 && blank(run[run.length - 1]))
                tail = run.pop() + tail;
            if (run.length > 0) {
                afterHtml += `<span style="background-color:${marker}; color:${onMarker}; font-weight:600">${root.escapeHtml(run.join(""))}</span>`;
                changes++;
            }
            afterHtml += root.escapeHtml(tail);
            run = [];
        };
        let i = 0;
        let j = 0;
        while (i < a.length || j < b.length) {
            if (i < a.length && j < b.length && a[i] === b[j]) {
                beforeHtml += root.escapeHtml(a[i]);
                if (blank(b[j]) && run.length > 0)
                    run.push(b[j]);
                else {
                    flushRun();
                    afterHtml += root.escapeHtml(b[j]);
                }
                i++;
                j++;
            } else if (i < a.length && (j >= b.length || table[(i + 1) * width + j] >= table[i * width + j + 1])) {
                beforeHtml += blank(a[i])
                    ? root.escapeHtml(a[i])
                    : `<span style="color:${struck}; text-decoration:line-through">${root.escapeHtml(a[i])}</span>`;
                i++;
            } else {
                if (blank(b[j]) && run.length === 0)
                    afterHtml += root.escapeHtml(b[j]);
                else
                    run.push(b[j]);
                j++;
            }
        }
        flushRun();
        return { before: beforeHtml, after: afterHtml, changes: changes };
    }

    function activateSelected(): bool {
        const typed = root.searchQuery.trim();
        if (typed.length > 0 && typed !== root.submittedQuery) {
            root.submittedQuery = typed;
            root.fix(typed, "typed");
            return true;
        }
        if (!root.finished)
            return false;
        Quickshell.clipboardText = root.correctedText;
        GlobalStates.closeSearchSurfaces();
        return true;
    }

    function copySelected(): bool {
        if (!root.finished)
            return false;
        Quickshell.clipboardText = root.correctedText;
        root.showNotice(Translation.tr("Corrected text copied"));
        return true;
    }

    function secondaryActivateSelected(): bool {
        if (root.sourceText.length === 0)
            return false;
        root.fix(root.sourceText, root.sourceKind);
        return true;
    }

    function editSelected(): bool {
        clipboardProc.running = true;
        return true;
    }

    function focusInput(): bool { return false; }

    function handleEscape(): bool {
        if (!task.running)
            return false;
        task.cancel();
        return true;
    }

    function showNotice(message) {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    Component.onCompleted: selectionProc.running = true
    Component.onDestruction: {
        if (task.running)
            task.cancel();
    }

    AiTextTask {
        id: task
        taskName: "search-grammar"
        scriptName: "search_grammar"
        thinkingLevel: "off"
        temperature: 0.1
    }

    Process {
        id: selectionProc
        command: ["bash", "-c", "wl-paste --primary --no-newline --type text 2>/dev/null || true"]
        stdout: StdioCollector {
            id: selectionOutput
            onStreamFinished: {
                if (selectionOutput.text.trim().length > 0)
                    root.fix(selectionOutput.text, "selection");
                else
                    clipboardProc.running = true;
            }
        }
    }

    Process {
        id: clipboardProc
        command: ["bash", "-c", "wl-paste --no-newline --type text 2>/dev/null || true"]
        stdout: StdioCollector {
            id: clipboardOutput
            onStreamFinished: {
                if (clipboardOutput.text.trim().length > 0)
                    root.fix(clipboardOutput.text, "clipboard");
            }
        }
    }

    Timer {
        id: noticeTimer
        interval: 3200
        onTriggered: root.noticeText = ""
    }


    /// A text pane: a small bold caption over the text, set in the reading face.
    component TextPane: Rectangle {
        id: pane
        property string caption: ""
        property string captionIcon: ""
        property string body: ""
        property color colContent: ClockStyle.colOnSurface
        property int textSize: Appearance.font.pixelSize.normal
        property bool busy: false
        default property alias extra: paneExtra.data
        radius: ClockStyle.radiusCard
        Behavior on color {
            enabled: !root.animationsDisabled
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: ClockStyle.cardPadding
            anchors.topMargin: ClockStyle.cardPadding - 4
            spacing: ClockStyle.gap

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    text: pane.captionIcon
                    iconSize: Appearance.font.pixelSize.normal
                    fill: 1
                    color: pane.colContent
                    opacity: 0.8
                }

                StyledText {
                    Layout.fillWidth: true
                    text: pane.caption.toUpperCase()
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    font.letterSpacing: 1.4
                    color: pane.colContent
                    opacity: 0.8
                }
            }

            Flickable {
                id: paneFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: paneText.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                StyledText {
                    id: paneText
                    width: parent.width
                    text: pane.body
                    textFormat: Text.RichText
                    wrapMode: Text.Wrap
                    lineHeight: 1.18
                    font.family: Appearance.font.family.reading
                    font.pixelSize: pane.textSize
                    color: pane.colContent
                }

                TouchpadScrollHandler {
                    flickable: paneFlickable
                }
            }

            Item {
                id: paneExtra
                Layout.fillWidth: true
                implicitHeight: childrenRect.height
                visible: children.length > 0
            }
        }

        // While the model writes, a loading shape holds the empty pane.
        MaterialLoadingIndicator {
            anchors.centerIn: parent
            visible: pane.busy
            implicitWidth: 64
            implicitHeight: 64
        }
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        primaryHint: root.searchQuery.trim().length > 0 && root.searchQuery.trim() !== root.submittedQuery
            ? ({ label: Translation.tr("Fix typed text"), actionId: "activate", keys: ["↵"] })
            : ({ label: Translation.tr("Copy and close"), actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("Try again"), actionId: "secondary", keys: ["Ctrl", "↵"] },
            { label: Translation.tr("Use clipboard"), actionId: "edit", keys: ["Ctrl", "E"] },
            { label: Translation.tr("Copy"), actionId: "copy", keys: ["Ctrl", "C"] }
        ]

        ColumnLayout {
            anchors.fill: parent
            spacing: ClockStyle.gapSmall
            visible: root.sourceText.length > 0

            // ── Status strip: where the text came from, who fixed it, how much ──
            RowLayout {
                Layout.fillWidth: true
                // Fixed, so the count appearing does not push the panes down.
                Layout.preferredHeight: 42
                spacing: ClockStyle.gapSmall

                Rectangle {
                    implicitWidth: sourceChipRow.implicitWidth + 28
                    implicitHeight: 34
                    radius: Appearance.rounding.full
                    color: ClockStyle.colSecondaryContainer

                    RowLayout {
                        id: sourceChipRow
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: root.sourceIcon
                            iconSize: Appearance.font.pixelSize.normal
                            color: ClockStyle.colOnSecondaryContainer
                        }

                        StyledText {
                            text: root.sourceLabel
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.weight: Font.Bold
                            color: ClockStyle.colOnSecondaryContainer
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    text: root.statusText
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: task.status === "error" ? ClockStyle.colError : ClockStyle.colSubtext
                }

                // The fix count is the panel's number.
                StyledText {
                    Layout.alignment: Qt.AlignBaseline
                    visible: root.finished
                    text: String(root.diff.changes)
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: 34
                    color: root.diff.changes > 0 ? ClockStyle.colPrimary : ClockStyle.colTertiary
                }

                StyledText {
                    Layout.alignment: Qt.AlignBaseline
                    Layout.rightMargin: 4
                    visible: root.finished
                    text: root.diff.changes === 1 ? Translation.tr("fix") : Translation.tr("fixes")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: ClockStyle.colSubtext
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: ClockStyle.paneGap

                // The original stays quiet: what was dropped is struck through.
                TextPane {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 10
                    color: ClockStyle.colSurfaceHigh
                    colContent: ClockStyle.colOnSurfaceVariant
                    caption: Translation.tr("Original")
                    captionIcon: "notes"
                    body: root.diff.before
                }

                // The correction is the hero: primary container, new words in marker.
                TextPane {
                    id: correctedPane
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 12
                    color: task.status === "error" ? ClockStyle.colErrorContainer : ClockStyle.colPrimaryContainer
                    colContent: task.status === "error" ? ClockStyle.colOnErrorContainer : ClockStyle.colOnPrimaryContainer
                    textSize: Appearance.font.pixelSize.large + 1
                    caption: task.status === "error" ? Translation.tr("Couldn't fix") : Translation.tr("Corrected")
                    captionIcon: task.status === "error" ? "error" : "spellcheck"
                    body: task.status === "error" ? root.escapeHtml(task.errorText) : root.diff.after
                    busy: task.running && root.correctedText.length === 0

                    RowLayout {
                        width: parent.width
                        spacing: ClockStyle.gapSmall

                        ClockSheetAction {
                            Layout.fillWidth: true
                            primary: true
                            enabled: root.finished
                            symbol: "content_copy"
                            label: Translation.tr("Copy and close")
                            onClicked: root.activateSelected()
                        }

                        RippleButton {
                            implicitWidth: 46
                            implicitHeight: 46
                            buttonRadius: Appearance.rounding.full
                            enabled: root.sourceText.length > 0 && !task.running
                            opacity: enabled ? 1 : 0.45
                            colBackground: ColorUtils.applyAlpha(correctedPane.colContent, 0.1)
                            colBackgroundHover: ColorUtils.applyAlpha(correctedPane.colContent, 0.18)
                            colRipple: ColorUtils.applyAlpha(correctedPane.colContent, 0.26)
                            onClicked: root.secondaryActivateSelected()

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "refresh"
                                iconSize: Appearance.font.pixelSize.larger
                                color: correctedPane.colContent
                            }

                            StyledToolTip {
                                text: Translation.tr("Try again (Ctrl+Enter)")
                            }
                        }

                        RippleButton {
                            implicitWidth: 46
                            implicitHeight: 46
                            buttonRadius: Appearance.rounding.full
                            colBackground: ColorUtils.applyAlpha(correctedPane.colContent, 0.1)
                            colBackgroundHover: ColorUtils.applyAlpha(correctedPane.colContent, 0.18)
                            colRipple: ColorUtils.applyAlpha(correctedPane.colContent, 0.26)
                            onClicked: root.editSelected()

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "content_paste"
                                iconSize: Appearance.font.pixelSize.larger
                                color: correctedPane.colContent
                            }

                            StyledToolTip {
                                text: Translation.tr("Use clipboard (Ctrl+E)")
                            }
                        }
                    }
                }
            }
        }

        Item {
            anchors.fill: parent
            visible: root.sourceText.length === 0

            ClockEmptyState {
                anchors.centerIn: parent
                symbol: task.status === "error" ? "error" : "spellcheck"
                shape: task.status === "error" ? "Boom" : "Clover8Leaf"
                colShape: task.status === "error" ? ClockStyle.colErrorContainer : ClockStyle.colPrimaryContainer
                colIcon: task.status === "error" ? ClockStyle.colOnErrorContainer : ClockStyle.colOnPrimaryContainer
                title: task.status === "error" ? Translation.tr("Couldn't fix") : Translation.tr("Nothing to fix yet")
                subtitle: root.statusText
            }
        }
    }
}
