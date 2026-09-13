pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets

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
    readonly property string correctedText: String(task.resultText ?? "").trim()
    readonly property bool finished: task.status === "done" && root.correctedText.length > 0
    readonly property string grammarPrompt: "Correct every spelling, grammar, punctuation and agreement error in the text below. Keep its meaning, vocabulary, formatting and style exactly. Write in the same language as the text. Return only the corrected text, with nothing before or after it."
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
     * The corrected text with every word that is not in the original drawn in
     * the primary colour. Word-level LCS; past ~500×500 tokens the plain text
     * is shown instead of paying for the table.
     */
    function highlightChanges(before, after) {
        const a = String(before).split(/(\s+)/);
        const b = String(after).split(/(\s+)/);
        if (a.length * b.length > 250000)
            return root.escapeHtml(after);
        const width = b.length + 1;
        const table = new Int32Array((a.length + 1) * width);
        for (let i = a.length - 1; i >= 0; i--) {
            for (let j = b.length - 1; j >= 0; j--) {
                table[i * width + j] = a[i] === b[j]
                    ? table[(i + 1) * width + j + 1] + 1
                    : Math.max(table[(i + 1) * width + j], table[i * width + j + 1]);
            }
        }
        const accent = String(Appearance.colors.colPrimary);
        let html = "";
        let i = 0;
        let j = 0;
        while (j < b.length) {
            if (i < a.length && a[i] === b[j]) {
                html += root.escapeHtml(b[j]);
                i++;
                j++;
            } else if (i < a.length && table[(i + 1) * width + j] >= table[i * width + j + 1]) {
                i++;
            } else {
                html += /^\s*$/.test(b[j])
                    ? root.escapeHtml(b[j])
                    : `<span style="color:${accent}; font-weight:600">${root.escapeHtml(b[j])}</span>`;
                j++;
            }
        }
        return html;
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

    component TextCard: Rectangle {
        id: card
        property string caption: ""
        property string captionIcon: ""
        property string body: ""
        property bool rich: false
        property bool emphasized: false
        radius: Appearance.rounding.large
        color: card.emphasized ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin
            spacing: Appearance.sizes.elevationMargin / 2

            RowLayout {
                spacing: Appearance.sizes.elevationMargin / 2
                MaterialSymbol {
                    text: card.captionIcon
                    iconSize: Appearance.font.pixelSize.normal
                    color: card.emphasized ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOutline
                }
                StyledText {
                    text: card.caption
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: card.emphasized ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: cardText.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                StyledText {
                    id: cardText
                    width: parent.width
                    text: card.body
                    textFormat: card.rich ? Text.RichText : Text.PlainText
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: card.emphasized ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                }
            }
        }
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Fix grammar")
        icon: "spellcheck"
        accent: true
        showStatus: true
        statusText: root.statusText
        primaryHint: root.searchQuery.trim().length > 0 && root.searchQuery.trim() !== root.submittedQuery
            ? ({ label: Translation.tr("Fix typed text"), actionId: "activate", keys: ["↵"] })
            : ({ label: Translation.tr("Copy and close"), actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("Try again"), actionId: "secondary", keys: ["Ctrl", "↵"] },
            { label: Translation.tr("Use clipboard"), actionId: "edit", keys: ["Ctrl", "E"] },
            { label: Translation.tr("Copy"), actionId: "copy", keys: ["Ctrl", "C"] }
        ]

        ColumnLayout {
            width: parent.width
            height: parent.height
            spacing: Appearance.sizes.elevationMargin

            TextCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 2
                visible: root.sourceText.length > 0
                caption: root.sourceLabel
                captionIcon: "notes"
                body: root.sourceText
            }

            TextCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 3
                visible: root.sourceText.length > 0
                emphasized: true
                caption: Translation.tr("Corrected")
                captionIcon: "spellcheck"
                rich: root.finished
                body: root.finished ? root.highlightChanges(root.sourceText, root.correctedText) : root.correctedText

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: task.running && root.correctedText.length === 0
                    implicitWidth: Appearance.sizes.elevationMargin * 3
                    implicitHeight: implicitWidth
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.sourceText.length === 0
                spacing: Appearance.sizes.elevationMargin / 2

                Item { Layout.fillHeight: true }
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: task.status === "error" ? "error" : "spellcheck"
                    iconSize: Appearance.font.pixelSize.huge
                    color: task.status === "error" ? Appearance.colors.colError : Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.statusText
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
}
