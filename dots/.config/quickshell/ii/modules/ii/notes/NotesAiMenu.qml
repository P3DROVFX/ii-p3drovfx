pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * AI context menu for the Notes app.
 *
 * Offers categorized single-turn tasks:
 * - 8 rewriting tones (Professional, Casual, Direct, Academic, Empathetic, Poetic, Humorous, Persuasive)
 * - Editing & improvement (Grammar/style fix, summarize paragraph/bullets/TL;DR, expand, continue writing)
 * - Transformations (checklist, markdown table, extract action items, translate)
 * - Code-specific actions (explain, bug hunter, optimize, convert language)
 * - Note-wide actions (generate title, tags, executive summary callout, topic structure)
 * - Custom user-defined styles (persisted in Persistent.states.notes.aiCustomStyles)
 * - Out-of-band ask in sidebar AI chat
 *
 * Strictly respects Config.options.policies.ai:
 * - When 0: completely hidden.
 * - When 2: restricted to local Ollama models.
 */
Item {
    id: root

    property var editor: null
    property string targetText: ""
    property string targetScope: "selection" // "selection" | "block" | "note"
    property string targetBlockId: ""
    property string activeCategory: "tones" // "tones" | "improve" | "transform" | "note" | "code" | "custom"

    signal actionRequested(string taskName, string systemPrompt, string userText, var meta)
    signal chatRequested(string contextText)
    signal closed()

    visible: Number(Config.options?.policies?.ai ?? 1) !== 0

    // Prevent clicks from falling through to the editor underneath
    MouseArea {
        anchors.fill: parent
        onClicked: {}
    }

    readonly property bool isCodeBlock: root.editor && root.editor.activeBlock && root.editor.activeBlock.type === "code"
    readonly property int policy: Number(Config.options?.policies?.ai ?? 1)
    readonly property bool localOnly: root.policy === 2

    // Current active model name
    /// `Ai.currentModel` is the model's *value* — a string — so `.title` on it was
    /// always undefined and this badge always read "AI". The entry is the object.
    readonly property string currentModelName: {
        const entry = Ai.currentModelEntry;
        if (!entry)
            return Translation.tr("No model");
        return entry.title.length > 0 ? entry.title : (entry.name.length > 0 ? entry.name : Ai.currentModel);
    }
    readonly property bool isLocalModel: Ai.currentModelEntry
        ? Ai.catalog.isModelLocal(Ai.currentModelEntry)
        : false

    // Custom styles management
    property var customStylesList: []

    function reloadCustomStyles() {
        const raw = Persistent.states.notes?.aiCustomStyles ?? [];
        const parsed = [];
        for (let i = 0; i < raw.length; i++) {
            try {
                const item = JSON.parse(raw[i]);
                if (item && item.name && item.prompt)
                    parsed.push(item);
            } catch (e) {
                // Ignore corrupt custom style entries
            }
        }
        root.customStylesList = parsed;
    }

    function saveNewCustomStyle(name, prompt) {
        if (!name || !prompt)
            return;
        const current = (Persistent.states.notes?.aiCustomStyles ?? []).slice();
        current.push(JSON.stringify({ name: name.trim(), prompt: prompt.trim() }));
        Persistent.states.notes.aiCustomStyles = current;
        root.reloadCustomStyles();
    }

    function deleteCustomStyle(index) {
        const current = (Persistent.states.notes?.aiCustomStyles ?? []).slice();
        if (index >= 0 && index < current.length) {
            current.splice(index, 1);
            Persistent.states.notes.aiCustomStyles = current;
            root.reloadCustomStyles();
        }
    }

    Component.onCompleted: root.reloadCustomStyles()

    // ── Dialog Container ──────────────────────────────────────────────────
    Rectangle {
        id: menuCard
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHighest
        clip: true

        StyledRectangularShadow {
            target: menuCard
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // ── Header ────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "auto_awesome"
                    iconSize: 22
                    color: Appearance.colors.colTertiary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: Translation.tr("Ask the AI")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }

                    RowLayout {
                        spacing: 6

                        // Scope chip
                        Rectangle {
                            implicitHeight: 18
                            implicitWidth: scopeLabel.implicitWidth + 10
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colSecondaryContainer

                            StyledText {
                                id: scopeLabel
                                anchors.centerIn: parent
                                text: {
                                    if (root.targetScope === "selection")
                                        return Translation.tr("Selection (%1 chars)").arg(root.targetText.length);
                                    if (root.isCodeBlock)
                                        return Translation.tr("Code block");
                                    if (root.targetScope === "block")
                                        return Translation.tr("Current block");
                                    return Translation.tr("Full note (%1 chars)").arg(root.targetText.length);
                                }
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        // Model badge
                        Rectangle {
                            implicitHeight: 18
                            implicitWidth: modelLabel.implicitWidth + 14
                            radius: Appearance.rounding.small
                            color: root.isLocalModel
                                ? Appearance.m3colors.m3primaryContainer
                                : Appearance.colors.colLayer2

                            RowLayout {
                                id: modelLabel
                                anchors.centerIn: parent
                                spacing: 4

                                Rectangle {
                                    implicitWidth: 6
                                    implicitHeight: 6
                                    radius: 3
                                    color: root.isLocalModel
                                        ? Appearance.colors.colPrimary
                                        : Appearance.colors.colTertiary
                                }

                                StyledText {
                                    text: root.currentModelName
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: root.isLocalModel
                                        ? Appearance.m3colors.m3onPrimaryContainer
                                        : Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 110
                                }
                            }
                        }
                    }
                }

                NotesIconButton {
                    symbol: "close"
                    size: 32
                    iconSize: 18
                    tooltipText: Translation.tr("Close")
                    onTriggered: root.closed()
                }
            }

            // ── Category Navigation Bar ───────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    toggled: root.activeCategory === "tones"
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    onClicked: root.activeCategory = "tones"

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Tones")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: root.activeCategory === "tones" ? Font.DemiBold : Font.Normal
                        color: root.activeCategory === "tones" ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                }

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    toggled: root.activeCategory === "improve"
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    onClicked: root.activeCategory = "improve"

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Improve")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: root.activeCategory === "improve" ? Font.DemiBold : Font.Normal
                        color: root.activeCategory === "improve" ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                }

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    toggled: root.activeCategory === "transform"
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    onClicked: root.activeCategory = "transform"

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Transform")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: root.activeCategory === "transform" ? Font.DemiBold : Font.Normal
                        color: root.activeCategory === "transform" ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                }

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    toggled: root.activeCategory === "note"
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    onClicked: root.activeCategory = "note"

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Note")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: root.activeCategory === "note" ? Font.DemiBold : Font.Normal
                        color: root.activeCategory === "note" ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                }

                RippleButton {
                    visible: root.isCodeBlock
                    Layout.fillWidth: true
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    toggled: root.activeCategory === "code"
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    onClicked: root.activeCategory = "code"

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Code")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: root.activeCategory === "code" ? Font.DemiBold : Font.Normal
                        color: root.activeCategory === "code" ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                }

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    toggled: root.activeCategory === "custom"
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    onClicked: root.activeCategory = "custom"

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Custom")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: root.activeCategory === "custom" ? Font.DemiBold : Font.Normal
                        color: root.activeCategory === "custom" ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                }
            }

            // ── Action List Area ──────────────────────────────────────────
            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: contentCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: contentCol
                    width: flick.width
                    spacing: 4

                    // ── Category 1: Tones (8 tones) ───────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.activeCategory === "tones"
                        spacing: 4

                        Repeater {
                            model: [
                                { id: "professional", name: Translation.tr("Professional"), icon: "work",
                                  prompt: "Rewrite the text below in a professional, polished tone. Write in the same language as the text. Return only the rewritten text, with no greeting or explanation." },
                                { id: "casual", name: Translation.tr("Casual"), icon: "chat",
                                  prompt: "Rewrite the text below in a relaxed, friendly tone, keeping it clear. Write in the same language as the text. Return only the rewritten text." },
                                { id: "direct", name: Translation.tr("Direct and short"), icon: "bolt",
                                  prompt: "Rewrite the text below so it is direct and short, cutting filler and repetition. Write in the same language as the text. Return only the rewritten text." },
                                { id: "academic", name: Translation.tr("Academic"), icon: "school",
                                  prompt: "Rewrite the text below in a formal academic register, with precise vocabulary and structure. Write in the same language as the text. Return only the rewritten text." },
                                { id: "empathetic", name: Translation.tr("Empathetic"), icon: "favorite",
                                  prompt: "Rewrite the text below in a warm, understanding tone. Write in the same language as the text. Return only the rewritten text." },
                                { id: "poetic", name: Translation.tr("Poetic"), icon: "auto_stories",
                                  prompt: "Rewrite the text below with a light lyrical quality, without losing its meaning. Write in the same language as the text. Return only the rewritten text." },
                                { id: "humorous", name: Translation.tr("Humorous"), icon: "mood",
                                  prompt: "Rewrite the text below with a touch of light, intelligent humour. Write in the same language as the text. Return only the rewritten text." },
                                { id: "persuasive", name: Translation.tr("Persuasive"), icon: "campaign",
                                  prompt: "Rewrite the text below so it persuades: clear argument, plain value, no hyperbole. Write in the same language as the text. Return only the rewritten text." }
                            ]

                            delegate: RippleButton {
                                id: toneBtn
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 38
                                buttonRadius: Appearance.rounding.small
                                colBackground: Appearance.colors.colLayer1
                                colBackgroundHover: Appearance.colors.colLayer1Hover

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    MaterialSymbol {
                                        text: toneBtn.modelData.icon
                                        iconSize: 18
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: toneBtn.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                    }

                                    MaterialSymbol {
                                        text: "arrow_forward"
                                        iconSize: 16
                                        color: Appearance.colors.colOnLayer1Inactive
                                    }
                                }

                                onClicked: {
                                    root.actionRequested(
                                        Translation.tr("Rewrite (%1)").arg(toneBtn.modelData.name),
                                        toneBtn.modelData.prompt,
                                        root.targetText,
                                        { action: "rewrite", mode: root.targetScope, blockId: root.targetBlockId }
                                    );
                                }
                            }
                        }
                    }

                    // ── Category 2: Improve & Edit ────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.activeCategory === "improve"
                        spacing: 4

                        Repeater {
                            model: [
                                { id: "grammar", name: Translation.tr("Fix the grammar"), icon: "spellcheck",
                                  desc: Translation.tr("Corrects typos, punctuation and grammar while preserving original tone."),
                                  prompt: "Correct every spelling, grammar and agreement error in the text below. Keep its meaning, vocabulary and style exactly. Write in the same language as the text. Return only the corrected text, with nothing before it." },
                                { id: "sum_para", name: Translation.tr("Summarise in a paragraph"), icon: "short_text",
                                  desc: Translation.tr("Synthesizes the core message in one well-structured paragraph."),
                                  prompt: "Summarise the main ideas of the text below in one flowing paragraph. Write in the same language as the text. Return only the paragraph." },
                                { id: "sum_bullets", name: Translation.tr("Summarise as bullet points"), icon: "format_list_bulleted",
                                  desc: Translation.tr("Extracts key takeaways into a concise markdown bullet list."),
                                  prompt: "Pull the key points out of the text below as a short Markdown list (- item). Write in the same language as the text. Return only the list." },
                                { id: "sum_tldr", name: Translation.tr("One line, and no more"), icon: "summarize",
                                  desc: Translation.tr("One punchy sentence summarizing everything."),
                                  prompt: "Summarise the text below in exactly one direct sentence. Write in the same language as the text. Return only that sentence." },
                                { id: "expand", name: Translation.tr("Say more about it"), icon: "unfold_more",
                                  desc: Translation.tr("Deepens ideas with more depth, clarity and context."),
                                  prompt: "Develop the ideas in the text below with more context and detail, without drifting from the subject or changing the tone. Write in the same language as the text. Return only the expanded text." },
                                { id: "continue", name: Translation.tr("Keep writing it"), icon: "edit_note",
                                  desc: Translation.tr("Completes the thought from the end of the text."),
                                  prompt: "Continue the text below from where it stops, following the same thought and voice. Write in the same language as the text. Return only the continuation." }
                            ]

                            delegate: RippleButton {
                                id: improveBtn
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 46
                                buttonRadius: Appearance.rounding.small
                                colBackground: Appearance.colors.colLayer1
                                colBackgroundHover: Appearance.colors.colLayer1Hover

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    MaterialSymbol {
                                        text: improveBtn.modelData.icon
                                        iconSize: 20
                                        color: Appearance.colors.colPrimary
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        StyledText {
                                            text: improveBtn.modelData.name
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnLayer0
                                        }

                                        StyledText {
                                            text: improveBtn.modelData.desc
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    MaterialSymbol {
                                        text: "arrow_forward"
                                        iconSize: 16
                                        color: Appearance.colors.colOnLayer1Inactive
                                    }
                                }

                                onClicked: {
                                    root.actionRequested(
                                        improveBtn.modelData.name,
                                        improveBtn.modelData.prompt,
                                        root.targetText,
                                        { action: improveBtn.modelData.id, mode: root.targetScope, blockId: root.targetBlockId }
                                    );
                                }
                            }
                        }
                    }

                    // ── Category 3: Transform ─────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.activeCategory === "transform"
                        spacing: 4

                        Repeater {
                            model: [
                                { id: "checklist", name: Translation.tr("Turn into a checklist"), icon: "checklist",
                                  prompt: "Turn the text below into a Markdown checklist (- [ ] item), one clear item per line. Write in the same language as the text. Return only the list." },
                                { id: "table", name: Translation.tr("Turn into a table"), icon: "table_chart",
                                  prompt: "Turn the data or comparisons in the text below into a clean Markdown table with a header row. Write in the same language as the text. Return only the table." },
                                { id: "actions", name: Translation.tr("Pull out the actions"), icon: "task_alt",
                                  prompt: "Find every task, promise and next step in the text below and list them as a Markdown checklist (- [ ] action). Write in the same language as the text. Return only the list." },
                                { id: "tr_en", name: Translation.tr("Translate to English"), icon: "translate",
                                  prompt: "Translate the following text into fluent, natural English. Keep markdown formatting and structure. Return only the translated text." },
                                { id: "tr_pt", name: Translation.tr("Translate to Portuguese"), icon: "translate",
                                  prompt: "Translate the text below into fluent, natural Brazilian Portuguese. Keep the Markdown structure. Return only the translation." },
                                { id: "tr_es", name: Translation.tr("Translate to Spanish"), icon: "translate",
                                  prompt: "Translate the text below into fluent, natural Spanish. Keep the Markdown structure. Return only the translation." }
                            ]

                            delegate: RippleButton {
                                id: transformBtn
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 38
                                buttonRadius: Appearance.rounding.small
                                colBackground: Appearance.colors.colLayer1
                                colBackgroundHover: Appearance.colors.colLayer1Hover

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    MaterialSymbol {
                                        text: transformBtn.modelData.icon
                                        iconSize: 18
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: transformBtn.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                    }

                                    MaterialSymbol {
                                        text: "arrow_forward"
                                        iconSize: 16
                                        color: Appearance.colors.colOnLayer1Inactive
                                    }
                                }

                                onClicked: {
                                    root.actionRequested(
                                        transformBtn.modelData.name,
                                        transformBtn.modelData.prompt,
                                        root.targetText,
                                        { action: transformBtn.modelData.id, mode: root.targetScope, blockId: root.targetBlockId }
                                    );
                                }
                            }
                        }
                    }

                    // ── Category 4: Full Note Actions ─────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.activeCategory === "note"
                        spacing: 4

                        Repeater {
                            model: [
                                { id: "title", name: Translation.tr("Suggest a title"), icon: "title",
                                  desc: Translation.tr("Creates a short, expressive title (max 6 words) based on content."),
                                  prompt: "Read the note below and write a short, memorable title for it — six words at most. Write in the same language as the text. Return only the title: no quotes, no full stop, no explanation." },
                                { id: "tags", name: Translation.tr("Suggest tags"), icon: "label",
                                  desc: Translation.tr("Extracts 3 to 5 relevant tags formatted as #tag."),
                                  prompt: "Read the note below and name its three to five main subjects. Write in the same language as the text. Return only the tags, as '#one #two #three', separated by spaces." },
                                { id: "callout_summary", name: Translation.tr("Summarise it at the top"), icon: "article",
                                  desc: Translation.tr("Drafts a high-level summary to place at the top of the note."),
                                  prompt: "Write a clear two or three sentence summary of the note below, the kind that belongs at the top of it. Write in the same language as the text. Return only the summary." },
                                { id: "structure", name: Translation.tr("Give it structure"), icon: "format_align_left",
                                  desc: Translation.tr("Reorganizes the note content with clean headings and sections."),
                                  prompt: "Reorganise the text below into logical sections with Markdown headings (##, ###) and structured points, keeping every piece of information. Write in the same language as the text. Return only the reorganised Markdown." }
                            ]

                            delegate: RippleButton {
                                id: noteBtn
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 46
                                buttonRadius: Appearance.rounding.small
                                colBackground: Appearance.colors.colLayer1
                                colBackgroundHover: Appearance.colors.colLayer1Hover

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    MaterialSymbol {
                                        text: noteBtn.modelData.icon
                                        iconSize: 20
                                        color: Appearance.colors.colPrimary
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        StyledText {
                                            text: noteBtn.modelData.name
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnLayer0
                                        }

                                        StyledText {
                                            text: noteBtn.modelData.desc
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    MaterialSymbol {
                                        text: "arrow_forward"
                                        iconSize: 16
                                        color: Appearance.colors.colOnLayer1Inactive
                                    }
                                }

                                onClicked: {
                                    root.actionRequested(
                                        noteBtn.modelData.name,
                                        noteBtn.modelData.prompt,
                                        root.targetText,
                                        { action: noteBtn.modelData.id, mode: (noteBtn.modelData.id === "title" ? "title" : (noteBtn.modelData.id === "tags" ? "tags" : "note")), blockId: root.targetBlockId }
                                    );
                                }
                            }
                        }
                    }

                    // ── Category 5: Code Block ────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.activeCategory === "code" && root.isCodeBlock
                        spacing: 4

                        Repeater {
                            model: [
                                { id: "code_explain", name: Translation.tr("Explain this code"), icon: "code",
                                  prompt: "Explain what the code below does: its purpose, its flow, and anything surprising in it. Be clear and concrete." },
                                { id: "code_bugs", name: Translation.tr("Look for bugs"), icon: "bug_report",
                                  prompt: "Review the code below for bugs, security problems, unhandled edge cases, race conditions and leaks. List what you find and how to fix each one." },
                                { id: "code_opt", name: Translation.tr("Suggest a faster way"), icon: "speed",
                                  prompt: "Propose a faster version of the code below. Explain briefly what you changed and why, then give the improved code." }
                            ]

                            delegate: RippleButton {
                                id: codeBtn
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 38
                                buttonRadius: Appearance.rounding.small
                                colBackground: Appearance.colors.colLayer1
                                colBackgroundHover: Appearance.colors.colLayer1Hover

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    MaterialSymbol {
                                        text: codeBtn.modelData.icon
                                        iconSize: 18
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: codeBtn.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                    }

                                    MaterialSymbol {
                                        text: "arrow_forward"
                                        iconSize: 16
                                        color: Appearance.colors.colOnLayer1Inactive
                                    }
                                }

                                onClicked: {
                                    root.actionRequested(
                                        codeBtn.modelData.name,
                                        codeBtn.modelData.prompt,
                                        root.targetText,
                                        { action: codeBtn.modelData.id, mode: "block", blockId: root.targetBlockId }
                                    );
                                }
                            }
                        }
                    }

                    // ── Category 6: Custom Styles ─────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.activeCategory === "custom"
                        spacing: 4

                        // User saved custom styles
                        Repeater {
                            model: root.customStylesList

                            delegate: RippleButton {
                                id: customStyleBtn
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 40
                                buttonRadius: Appearance.rounding.small
                                colBackground: Appearance.colors.colLayer1
                                colBackgroundHover: Appearance.colors.colLayer1Hover

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 6
                                    spacing: 8

                                    MaterialSymbol {
                                        text: "tune"
                                        iconSize: 18
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: customStyleBtn.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                        elide: Text.ElideRight
                                    }

                                    NotesIconButton {
                                        symbol: "delete"
                                        size: 28
                                        iconSize: 16
                                        colIcon: Appearance.colors.colOnLayer1Inactive
                                        tooltipText: Translation.tr("Delete style")
                                        onTriggered: root.deleteCustomStyle(customStyleBtn.index)
                                    }
                                }

                                onClicked: {
                                    root.actionRequested(
                                        customStyleBtn.modelData.name,
                                        customStyleBtn.modelData.prompt,
                                        root.targetText,
                                        { action: "customStyle", mode: root.targetScope, blockId: root.targetBlockId }
                                    );
                                }
                            }
                        }

                        // Add new custom style button / form
                        property bool addingNew: false

                        RippleButton {
                            visible: !parent.addingNew
                            Layout.fillWidth: true
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover

                            contentItem: RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialSymbol {
                                    text: "add"
                                    iconSize: 18
                                    color: Appearance.colors.colOnSecondaryContainer
                                }

                                StyledText {
                                    text: Translation.tr("Add a style of your own…")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                            }

                            onClicked: parent.addingNew = true
                        }

                        // Inline style creator form
                        Rectangle {
                            visible: parent.addingNew
                            Layout.fillWidth: true
                            implicitHeight: formCol.implicitHeight + 16
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2

                            ColumnLayout {
                                id: formCol
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28

                                    StyledTextInput {
                                        id: styleNameInput
                                        anchors.fill: parent
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Translation.tr("Style name (e.g. Corporate Voice)")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer1Inactive
                                        visible: styleNameInput.text.length === 0
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28

                                    StyledTextInput {
                                        id: stylePromptInput
                                        anchors.fill: parent
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Translation.tr("Instructions (e.g. Rewrite concisely without jargon)")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer1Inactive
                                        visible: stylePromptInput.text.length === 0
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    RippleButton {
                                        Layout.fillWidth: true
                                        implicitHeight: 28
                                        buttonRadius: Appearance.rounding.verysmall
                                        colBackground: Appearance.colors.colPrimary
                                        colBackgroundHover: Appearance.colors.colPrimaryHover
                                        enabled: styleNameInput.text.trim().length > 0 && stylePromptInput.text.trim().length > 0

                                        contentItem: StyledText {
                                            anchors.centerIn: parent
                                            text: Translation.tr("Save this style")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnPrimary
                                        }

                                        onClicked: {
                                            root.saveNewCustomStyle(styleNameInput.text, stylePromptInput.text);
                                            styleNameInput.text = "";
                                            stylePromptInput.text = "";
                                            parent.parent.parent.parent.addingNew = false;
                                        }
                                    }

                                    RippleButton {
                                        implicitWidth: 60
                                        implicitHeight: 28
                                        buttonRadius: Appearance.rounding.verysmall
                                        colBackground: Appearance.colors.colLayer1
                                        colBackgroundHover: Appearance.colors.colLayer1Hover

                                        contentItem: StyledText {
                                            anchors.centerIn: parent
                                            text: Translation.tr("Cancel")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colOnLayer1
                                        }

                                        onClicked: {
                                            styleNameInput.text = "";
                                            stylePromptInput.text = "";
                                            parent.parent.parent.parent.addingNew = false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Footer: Ask in Sidebar Chat ───────────────────────────────
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 36
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover

                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        text: "forum"
                        iconSize: 18
                        color: Appearance.colors.colTertiary
                    }

                    /// It says copy, because copy is what it does. The row used to
                    /// promise the chat would know about this note, and then opened the
                    /// sidebar with the text dropped on the floor — nothing carries it
                    /// across, so the clipboard does, and one paste finishes the job.
                    StyledText {
                        text: Translation.tr("Copy this and open the chat")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                    }
                }

                onClicked: {
                    root.chatRequested(root.targetText);
                    root.closed();
                }
            }
        }
    }
}
