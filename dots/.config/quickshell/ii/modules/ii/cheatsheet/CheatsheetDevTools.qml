pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The Search Tools panel as a full-size cheatsheet page.
 *
 * Tools, their options and the engine are the shared DevToolsRegistry and
 * devtools.js, so a tool added there appears here and in Search alike. This
 * page only owns the larger arrangement: a rail of categories and tools beside
 * the workspace when there is width for it, input and output side by side on
 * wide screens, and one stacked column on small ones.
 */
Item {
    id: root

    property Item keyNavTarget: null
    readonly property bool isCurrentTab: {
        try {
            return swipeView.currentIndex === index;
        } catch (error) {
            return true;
        }
    }
    readonly property bool isTabActive: root.visible && root.isCurrentTab

    // Width tiers. Below ~1100px the rail would squeeze the workspace, so its
    // content moves above it; paired editors need more room still.
    readonly property bool railVisible: root.width >= 1100
    readonly property bool editorsSideBySide: root.width >= 1380
    readonly property bool compact: root.width < 720
    readonly property real gap: Appearance.sizes.elevationMargin

    property string filterText: ""
    property string selectedCategory: "all"
    property int selectedIndex: -1
    property string currentToolId: ""
    property string inputText: ""
    property string modifiedText: ""
    property var activeOptions: ({})
    property string outputText: ""
    property string errorText: ""
    property var outputMeta: ({})
    property string noticeText: ""
    // Per-tool work for this session, so moving between tools loses nothing.
    property var toolInputs: ({})
    property var toolModified: ({})
    property var toolOptions: ({})

    readonly property string diffSeparator: "\n===DIFF_SPLIT===\n"
    readonly property var categories: DevToolsRegistry.categories
    readonly property var tools: DevToolsRegistry.search(root.filterText, root.selectedCategory)
    readonly property var selectedTool: root.selectedIndex >= 0 && root.selectedIndex < root.tools.length
        ? root.tools[root.selectedIndex]
        : null
    readonly property bool isGenerator: root.selectedTool?.type === "generator"
    readonly property bool isDiff: root.selectedTool?.id === "text_diff"
    readonly property var metaEntries: {
        const meta = root.outputMeta ?? {};
        return Object.keys(meta)
            .filter(key => ["string", "number", "boolean"].indexOf(typeof meta[key]) !== -1 && String(meta[key]).length <= 40)
            .slice(0, 6)
            .map(key => ({ key: key, value: String(meta[key]) }));
    }
    readonly property string statusText: root.noticeText.length > 0
        ? root.noticeText
        : Translation.tr("%1 tools · offline, processed locally").arg(String(DevToolsRegistry.tools.length))

    function toolTypeLabel(tool) {
        if (tool?.type === "generator")
            return Translation.tr("Generator");
        return tool?.type === "analyzer" ? Translation.tr("Analyzer") : Translation.tr("Transformer");
    }

    function textStats(text) {
        const value = String(text ?? "");
        if (value.length === 0)
            return "";
        return Translation.tr("%1 chars · %2 lines").arg(String(value.length)).arg(String(value.split("\n").length));
    }

    function selectTool(targetIndex) {
        if (targetIndex < 0 || targetIndex >= root.tools.length) {
            root.selectedIndex = -1;
            root.outputText = "";
            root.errorText = "";
            root.outputMeta = ({});
            return;
        }
        const tool = root.tools[targetIndex];
        root.selectedIndex = targetIndex;
        root.currentToolId = tool.id;
        if (!root.toolOptions[tool.id])
            root.toolOptions[tool.id] = Object.assign({}, tool.defaultOptions ?? {});
        root.activeOptions = Object.assign({}, root.toolOptions[tool.id]);
        if (root.toolInputs[tool.id] === undefined) {
            const sample = tool.type !== "generator" ? String(tool.sampleInput ?? "") : "";
            const parts = tool.id === "text_diff" ? sample.split(root.diffSeparator) : [sample];
            root.toolInputs[tool.id] = parts[0] ?? "";
            root.toolModified[tool.id] = parts[1] ?? "";
        }
        root.inputText = root.toolInputs[tool.id];
        root.modifiedText = root.toolModified[tool.id] ?? "";
        if (Persistent.ready)
            Persistent.states.cheatsheet.devToolsToolId = tool.id;
        root.execute(false);
        Qt.callLater(() => {
            railList.positionViewAtIndex(targetIndex, ListView.Contain);
            stripList.positionViewAtIndex(targetIndex, ListView.Contain);
        });
    }

    function stepTool(step) {
        if (root.tools.length === 0)
            return;
        root.selectTool((Math.max(0, root.selectedIndex) + step + root.tools.length) % root.tools.length);
    }

    function selectCategory(categoryId) {
        root.selectedCategory = String(categoryId);
        if (Persistent.ready)
            Persistent.states.cheatsheet.devToolsCategory = root.selectedCategory;
    }

    function stepCategory(step) {
        let current = root.categories.findIndex(category => category.id === root.selectedCategory);
        current = (Math.max(0, current) + step + root.categories.length) % root.categories.length;
        root.selectCategory(root.categories[current].id);
    }

    function execute(showFeedback) {
        const tool = root.selectedTool;
        if (!tool)
            return false;
        const input = tool.type === "generator"
            ? ""
            : (root.isDiff ? root.inputText + root.diffSeparator + root.modifiedText : root.inputText);
        const result = DevToolsRegistry.run(tool.id, input, root.activeOptions);
        root.errorText = result.error ? String(result.error) : "";
        root.outputText = result.error ? "" : String(result.output ?? "");
        root.outputMeta = result.meta ?? ({});
        if (showFeedback && !result.error)
            root.showNotice(tool.type === "generator" ? Translation.tr("Generated again") : Translation.tr("Ran %1").arg(tool.name));
        return true;
    }

    function setInput(text) {
        root.inputText = String(text ?? "");
        if (root.selectedTool)
            root.toolInputs[root.selectedTool.id] = root.inputText;
        root.execute(false);
    }

    function setModified(text) {
        root.modifiedText = String(text ?? "");
        if (root.selectedTool)
            root.toolModified[root.selectedTool.id] = root.modifiedText;
        root.execute(false);
    }

    function setOption(key, value) {
        const next = Object.assign({}, root.activeOptions);
        next[key] = value;
        root.activeOptions = next;
        if (root.selectedTool)
            root.toolOptions[root.selectedTool.id] = next;
        root.execute(false);
    }

    function optionValue(option) {
        const value = root.activeOptions[option.id];
        return value !== undefined ? value : option.default;
    }

    function copyOutput() {
        if (root.outputText.length === 0)
            root.execute(false);
        if (root.outputText.length === 0)
            return false;
        Quickshell.clipboardText = root.outputText;
        root.showNotice(Translation.tr("Output copied to clipboard"));
        return true;
    }

    function pasteIntoInput() {
        const clip = String(Quickshell.clipboardText ?? "");
        if (root.isGenerator || clip.length === 0)
            return;
        root.setInput(clip);
        root.showNotice(Translation.tr("Clipboard pasted into the input"));
    }

    // Chaining: encode, then decode what came out, without copy and paste.
    function useOutputAsInput() {
        if (root.isGenerator || root.outputText.length === 0)
            return;
        root.setInput(root.outputText);
        root.showNotice(Translation.tr("Output moved to the input"));
    }

    function restoreSample() {
        const tool = root.selectedTool;
        if (!tool || root.isGenerator)
            return;
        const parts = root.isDiff ? String(tool.sampleInput ?? "").split(root.diffSeparator) : [String(tool.sampleInput ?? "")];
        if (root.isDiff)
            root.setModified(parts[1] ?? "");
        root.setInput(parts[0] ?? "");
    }

    function clearInput() {
        if (root.isGenerator)
            return;
        if (root.isDiff)
            root.setModified("");
        root.setInput("");
    }

    function focusFilter() {
        (root.railVisible ? railFilter : stripFilter).forceActiveFocus();
    }

    function showNotice(message) {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    function escapeHtml(text) {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, "&nbsp;");
    }

    function diffHtml(text) {
        const added = String(Appearance.colors.colPrimary);
        const removed = String(Appearance.colors.colError);
        const muted = String(Appearance.colors.colSubtext);
        return String(text).split("\n").map(line => {
            const safe = root.escapeHtml(line) || "&nbsp;";
            if (/^(\+\+\+|---|@@)/.test(line))
                return `<span style="color:${muted}">${safe}</span>`;
            if (line.startsWith("+ "))
                return `<span style="color:${added}">${safe}</span>`;
            if (line.startsWith("- "))
                return `<span style="color:${removed}">${safe}</span>`;
            return safe;
        }).join("<br>");
    }

    // Filtering keeps the current tool when it is still listed.
    onToolsChanged: {
        const kept = root.tools.findIndex(tool => tool.id === root.currentToolId);
        root.selectTool(kept >= 0 ? kept : (root.tools.length > 0 ? 0 : -1));
    }

    onIsTabActiveChanged: {
        if (root.isTabActive)
            Qt.callLater(root.focusFilter);
    }

    Component.onCompleted: {
        const savedCategory = String(Persistent.states.cheatsheet.devToolsCategory ?? "all");
        if (root.categories.some(category => category.id === savedCategory))
            root.selectedCategory = savedCategory;
        root.currentToolId = String(Persistent.states.cheatsheet.devToolsToolId ?? "");
        const saved = root.tools.findIndex(tool => tool.id === root.currentToolId);
        root.selectTool(saved >= 0 ? saved : (root.tools.length > 0 ? 0 : -1));
    }

    Timer {
        id: noticeTimer
        interval: 3200
        onTriggered: root.noticeText = ""
    }

    // Window shortcuts, so they only run while this page is the visible tab.
    // Ctrl+digits stay with the cheatsheet, which switches tabs with them.
    Shortcut { enabled: root.isTabActive; sequence: "Ctrl+F"; onActivated: root.focusFilter() }
    Shortcut { enabled: root.isTabActive; sequences: ["Ctrl+Return", "Ctrl+Enter"]; onActivated: root.copyOutput() }
    Shortcut { enabled: root.isTabActive; sequence: "Ctrl+R"; onActivated: root.execute(true) }
    Shortcut { enabled: root.isTabActive; sequence: "Ctrl+Shift+V"; onActivated: root.pasteIntoInput() }
    Shortcut { enabled: root.isTabActive; sequence: "Ctrl+L"; onActivated: root.clearInput() }
    Shortcut { enabled: root.isTabActive; sequence: "Ctrl+U"; onActivated: root.useOutputAsInput() }
    Shortcut { enabled: root.isTabActive; sequence: "Alt+Up"; onActivated: root.stepTool(-1) }
    Shortcut { enabled: root.isTabActive; sequence: "Alt+Down"; onActivated: root.stepTool(1) }
    Shortcut { enabled: root.isTabActive; sequence: "Alt+Left"; onActivated: root.stepCategory(-1) }
    Shortcut { enabled: root.isTabActive; sequence: "Alt+Right"; onActivated: root.stepCategory(1) }

    component ChipButton: RippleButton {
        id: chip
        property string label: ""
        // Not `icon` or `text`: both are FINAL on the Button RippleButton
        // derives from, and redeclaring either leaves the whole page blank.
        property string symbol: ""
        property bool active: false
        implicitHeight: Appearance.sizes.elevationMargin * 3
        implicitWidth: chipRow.implicitWidth + Appearance.sizes.elevationMargin * 1.8
        buttonRadius: Appearance.rounding.full
        colBackground: chip.active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: chip.active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
        colRipple: chip.active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: Appearance.sizes.elevationMargin / 2

            MaterialSymbol {
                visible: chip.symbol.length > 0
                text: chip.symbol
                iconSize: Appearance.font.pixelSize.normal
                color: chip.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
            }
            StyledText {
                text: chip.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: chip.active ? Font.DemiBold : Font.Normal
                color: chip.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
            }
        }
    }

    component ActionButton: RippleButton {
        id: action
        property string symbol: ""
        property string tip: ""
        property bool primary: false
        implicitWidth: Appearance.sizes.elevationMargin * 4.2
        implicitHeight: implicitWidth
        buttonRadius: Appearance.rounding.full
        opacity: action.enabled ? 1 : 0.4
        colBackground: action.primary ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
        colBackgroundHover: action.primary ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover
        colRipple: action.primary ? Appearance.colors.colPrimaryActive : Appearance.colors.colSurfaceContainerHighestActive

        MaterialSymbol {
            anchors.centerIn: parent
            text: action.symbol
            iconSize: Appearance.font.pixelSize.normal
            color: action.primary ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
        }
        StyledToolTip {
            text: action.tip
        }
    }

    component EditorCard: Rectangle {
        id: card
        property string title: ""
        property string icon: ""
        property string text: ""
        property string countText: ""
        property string errorText: ""
        property string emptyText: ""
        property bool readOnly: false
        property bool rich: false
        signal edited(string text)

        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainerHigh

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin
            spacing: Appearance.sizes.elevationMargin / 2

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                MaterialSymbol {
                    text: card.icon
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: card.title
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: card.countText
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.normal
                color: cardEdit.activeFocus ? Appearance.colors.colSurfaceContainerHighestHover : Appearance.colors.colSurfaceContainerHighest

                StyledFlickable {
                    id: cardFlick
                    anchors.fill: parent
                    anchors.margins: Appearance.sizes.elevationMargin
                    visible: card.errorText.length === 0
                    contentWidth: width
                    contentHeight: Math.max(height, cardEdit.implicitHeight)
                    clip: true

                    TextEdit {
                        id: cardEdit
                        width: cardFlick.width
                        text: card.text
                        readOnly: card.readOnly
                        textFormat: card.rich ? TextEdit.RichText : TextEdit.PlainText
                        wrapMode: TextEdit.WrapAnywhere
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurface
                        selectByMouse: true
                        selectionColor: Appearance.colors.colSecondaryContainer
                        selectedTextColor: Appearance.colors.colOnSecondaryContainer
                        onTextChanged: {
                            if (!card.readOnly && text !== card.text)
                                card.edited(text);
                        }
                        Keys.onEscapePressed: event => {
                            cardEdit.focus = false;
                            event.accepted = true;
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - Appearance.sizes.elevationMargin * 4
                    visible: card.readOnly && card.text.length === 0 && card.errorText.length === 0
                    text: card.emptyText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Appearance.sizes.elevationMargin
                    visible: card.errorText.length > 0
                    implicitHeight: errorRow.implicitHeight + Appearance.sizes.elevationMargin * 1.6
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colErrorContainer

                    RowLayout {
                        id: errorRow
                        anchors.fill: parent
                        anchors.margins: Appearance.sizes.elevationMargin
                        spacing: Appearance.sizes.elevationMargin / 2

                        MaterialSymbol {
                            text: "error"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnErrorContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: card.errorText
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnErrorContainer
                        }
                    }
                }
            }
        }
    }

    component ToolRow: RippleButton {
        id: toolRow
        required property int index
        required property var modelData
        readonly property bool selected: root.selectedIndex === index
        implicitHeight: toolRowContent.implicitHeight + Appearance.sizes.elevationMargin * 1.4
        buttonRadius: Appearance.rounding.normal
        colBackground: toolRow.selected ? Appearance.colors.colSecondaryContainer : "transparent"
        colBackgroundHover: toolRow.selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
        colRipple: toolRow.selected ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
        onClicked: root.selectTool(index)

        RowLayout {
            id: toolRowContent
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin * 0.7
            spacing: Appearance.sizes.elevationMargin

            MaterialSymbol {
                text: toolRow.modelData.icon
                iconSize: Appearance.font.pixelSize.large
                color: toolRow.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: toolRow.modelData.name
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: toolRow.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: toolRow.modelData.description
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: toolRow.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: root.gap
        spacing: root.gap

        // ── Rail: filter, categories and every tool ─────────────────────
        Rectangle {
            visible: root.railVisible
            Layout.preferredWidth: Math.min(360, Math.max(290, root.width * 0.24))
            Layout.fillHeight: true
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.gap
                spacing: root.gap * 0.8

                ToolbarTextField {
                    id: railFilter
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    implicitHeight: root.gap * 3.6
                    placeholderText: Translation.tr("Filter tools (Ctrl+F)")
                    text: root.filterText
                    onTextChanged: root.filterText = text
                    keyNavTarget: root.keyNavTarget
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: root.gap / 2

                    Repeater {
                        model: root.categories
                        delegate: ChipButton {
                            required property var modelData
                            label: modelData.label
                            symbol: modelData.icon
                            active: root.selectedCategory === modelData.id
                            onClicked: root.selectCategory(modelData.id)
                        }
                    }
                }

                ListView {
                    id: railList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.tools
                    delegate: ToolRow {
                        width: railList.width
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.tools.length === 0
                        text: Translation.tr("No tool matches")
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        // ── Workspace ───────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.gap

            // The rail's content, stacked above the workspace on narrow pages.
            ColumnLayout {
                visible: !root.railVisible
                Layout.fillWidth: true
                spacing: root.gap / 2

                ToolbarTextField {
                    id: stripFilter
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    implicitHeight: root.gap * 3.6
                    placeholderText: Translation.tr("Filter tools (Ctrl+F)")
                    text: root.filterText
                    onTextChanged: root.filterText = text
                    keyNavTarget: root.keyNavTarget
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: root.gap / 2

                    Repeater {
                        model: root.categories
                        delegate: ChipButton {
                            required property var modelData
                            label: root.compact ? "" : modelData.label
                            symbol: modelData.icon
                            active: root.selectedCategory === modelData.id
                            onClicked: root.selectCategory(modelData.id)
                        }
                    }
                }

                ListView {
                    id: stripList
                    Layout.fillWidth: true
                    implicitHeight: root.gap * 3.6
                    orientation: ListView.Horizontal
                    clip: true
                    spacing: root.gap / 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.tools

                    delegate: ChipButton {
                        required property int index
                        required property var modelData
                        implicitHeight: root.gap * 3.6
                        label: modelData.name
                        symbol: modelData.icon
                        active: root.selectedIndex === index
                        onClicked: root.selectTool(index)
                    }
                }
            }

            // Tool header: identity on one side, actions on the other.
            Rectangle {
                Layout.fillWidth: true
                visible: root.selectedTool !== null
                implicitHeight: headerGrid.implicitHeight + root.gap * 2
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHigh

                GridLayout {
                    id: headerGrid
                    anchors.fill: parent
                    anchors.margins: root.gap
                    columns: root.compact ? 1 : 2
                    columnSpacing: root.gap
                    rowSpacing: root.gap / 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.gap

                        MaterialSymbol {
                            text: root.selectedTool?.icon ?? "handyman"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                spacing: root.gap / 2
                                StyledText {
                                    text: root.selectedTool?.name ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnSurface
                                }
                                Rectangle {
                                    implicitWidth: typeLabel.implicitWidth + root.gap
                                    implicitHeight: typeLabel.implicitHeight + root.gap / 3
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colSecondaryContainer
                                    StyledText {
                                        id: typeLabel
                                        anchors.centerIn: parent
                                        text: root.toolTypeLabel(root.selectedTool)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.selectedTool?.description ?? ""
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: root.compact ? Qt.AlignLeft : (Qt.AlignRight | Qt.AlignVCenter)
                        spacing: root.gap * 0.6

                        ActionButton {
                            visible: !root.isGenerator
                            symbol: "content_paste"
                            tip: Translation.tr("Replace the input with the clipboard (Ctrl+Shift+V)")
                            onClicked: root.pasteIntoInput()
                        }
                        ActionButton {
                            visible: !root.isGenerator
                            symbol: "clear_all"
                            tip: Translation.tr("Clear the input (Ctrl+L)")
                            onClicked: root.clearInput()
                        }
                        ActionButton {
                            visible: !root.isGenerator && String(root.selectedTool?.sampleInput ?? "").length > 0
                            symbol: "science"
                            tip: Translation.tr("Load the example input")
                            onClicked: root.restoreSample()
                        }
                        ActionButton {
                            visible: !root.isGenerator
                            enabled: root.outputText.length > 0
                            symbol: "move_up"
                            tip: Translation.tr("Use the output as the next input (Ctrl+U)")
                            onClicked: root.useOutputAsInput()
                        }
                        ActionButton {
                            symbol: "refresh"
                            tip: root.isGenerator ? Translation.tr("Generate again (Ctrl+R)") : Translation.tr("Run again (Ctrl+R)")
                            onClicked: root.execute(true)
                        }
                        ActionButton {
                            primary: true
                            symbol: "content_copy"
                            tip: Translation.tr("Copy the output (Ctrl+Enter)")
                            onClicked: root.copyOutput()
                        }
                    }
                }
            }

            // Options wrap as whole groups; many choices become a menu.
            Flow {
                Layout.fillWidth: true
                visible: root.selectedTool !== null && (root.selectedTool?.options?.length ?? 0) > 0
                spacing: root.gap

                Repeater {
                    model: root.selectedTool?.options ?? []

                    delegate: ColumnLayout {
                        id: optionGroup
                        required property var modelData
                        readonly property bool asMenu: modelData.type === "choice"
                            && (root.compact || (modelData.choices ?? []).length > 5)
                        spacing: root.gap / 3

                        StyledText {
                            // Toggles have no caption, but keep its height: the Flow
                            // top-aligns groups, so a missing caption lifted every
                            // toggle above the choices beside it.
                            opacity: optionGroup.modelData.type === "toggle" ? 0 : 1
                            text: optionGroup.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        RowLayout {
                            visible: optionGroup.modelData.type === "choice" && !optionGroup.asMenu
                            spacing: 4

                            Repeater {
                                model: optionGroup.modelData.type === "choice" && !optionGroup.asMenu ? optionGroup.modelData.choices : []
                                delegate: ChipButton {
                                    required property var modelData
                                    implicitHeight: root.gap * 2.8
                                    label: modelData.label
                                    active: root.optionValue(optionGroup.modelData) === modelData.value
                                    onClicked: root.setOption(optionGroup.modelData.id, modelData.value)
                                }
                            }
                        }

                        StyledComboBox {
                            visible: optionGroup.asMenu
                            implicitWidth: root.gap * 22
                            model: (optionGroup.modelData.choices ?? []).map(choice => String(choice.label))
                            currentIndex: Math.max(0, (optionGroup.modelData.choices ?? []).findIndex(choice => choice.value === root.optionValue(optionGroup.modelData)))
                            onActivated: choiceIndex => root.setOption(optionGroup.modelData.id, optionGroup.modelData.choices[choiceIndex].value)
                        }

                        ChipButton {
                            visible: optionGroup.modelData.type === "toggle"
                            implicitHeight: root.gap * 2.8
                            label: optionGroup.modelData.label
                            symbol: Boolean(root.optionValue(optionGroup.modelData)) ? "check_box" : "check_box_outline_blank"
                            active: Boolean(root.optionValue(optionGroup.modelData))
                            onClicked: root.setOption(optionGroup.modelData.id, !Boolean(root.optionValue(optionGroup.modelData)))
                        }

                        ToolbarTextField {
                            visible: optionGroup.modelData.type === "text"
                            Layout.fillHeight: false
                            implicitWidth: optionGroup.modelData.id === "flags" ? root.gap * 8 : Math.min(root.gap * 40, root.width - root.gap * 6)
                            implicitHeight: root.gap * 3.2
                            font.family: Appearance.font.family.monospace
                            text: String(root.optionValue(optionGroup.modelData) ?? "")
                            onTextEdited: root.setOption(optionGroup.modelData.id, text)
                            keyNavTarget: root.keyNavTarget
                        }
                    }
                }
            }

            // Input and output: side by side when wide, stacked otherwise.
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.selectedTool !== null
                columns: root.editorsSideBySide && !root.isGenerator ? 2 : 1
                columnSpacing: root.gap
                rowSpacing: root.gap

                GridLayout {
                    visible: !root.isGenerator
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 1
                    Layout.preferredWidth: 1
                    Layout.minimumHeight: root.gap * 9
                    // The diff compares two texts; they sit side by side when they fit.
                    columns: root.isDiff && root.width >= 900 && !(root.editorsSideBySide && root.width < 1600) ? 2 : 1
                    columnSpacing: root.gap
                    rowSpacing: root.gap

                    EditorCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 1
                        title: root.isDiff ? Translation.tr("Original") : Translation.tr("Input")
                        icon: "edit_note"
                        text: root.inputText
                        countText: root.textStats(root.inputText)
                        onEdited: text => root.setInput(text)
                    }

                    EditorCard {
                        visible: root.isDiff
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 1
                        title: Translation.tr("Modified")
                        icon: "edit_document"
                        text: root.modifiedText
                        countText: root.textStats(root.modifiedText)
                        onEdited: text => root.setModified(text)
                    }
                }

                EditorCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 1
                    Layout.preferredWidth: 1
                    Layout.minimumHeight: root.gap * 9
                    title: root.selectedTool?.type === "analyzer" ? Translation.tr("Analysis") : Translation.tr("Output")
                    icon: root.isGenerator ? "wand_stars" : "output"
                    readOnly: true
                    rich: root.isDiff && root.outputText.length > 0
                    text: root.isDiff && root.outputText.length > 0 ? root.diffHtml(root.outputText) : root.outputText
                    countText: root.textStats(root.outputText)
                    errorText: root.errorText
                    emptyText: root.isGenerator
                        ? Translation.tr("Press Ctrl+R or the refresh button to generate a value")
                        : Translation.tr("Type or paste something into the input to see the result")
                }
            }

            // Nothing matched the filter.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.selectedTool === null
                spacing: root.gap / 2

                Item { Layout.fillHeight: true }
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "search_off"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No tool matches this filter")
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.fillHeight: true }
            }

            // Status, result facts and shortcuts.
            RowLayout {
                Layout.fillWidth: true
                spacing: root.gap / 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.statusText
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Repeater {
                    model: root.railVisible ? root.metaEntries : root.metaEntries.slice(0, root.compact ? 1 : 3)

                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: metaLabel.implicitWidth + root.gap
                        implicitHeight: metaLabel.implicitHeight + root.gap / 2
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSurfaceContainerHigh

                        StyledText {
                            id: metaLabel
                            anchors.centerIn: parent
                            text: modelData.key + " " + modelData.value
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }

            KeyHintBar {
                Layout.fillWidth: true
                visible: Config.options.search.appearance.showKeyHintBar && !PanelFamily.touchFirst
                showKeys: Config.options.search.appearance.showKeyHints
                hints: [
                    { label: Translation.tr("Copy"), keys: ["Ctrl", "↵"] },
                    { label: Translation.tr("Run"), keys: ["Ctrl", "R"] },
                    { label: Translation.tr("Filter"), keys: ["Ctrl", "F"] },
                    { label: Translation.tr("Tool"), keys: ["Alt", "↑", "↓"] },
                    { label: Translation.tr("Category"), keys: ["Alt", "←", "→"] },
                    { label: Translation.tr("Paste"), keys: ["Ctrl", "Shift", "V"] },
                    { label: Translation.tr("Chain"), keys: ["Ctrl", "U"] },
                    { label: Translation.tr("Clear"), keys: ["Ctrl", "L"] }
                ]
                surface: Appearance.colors.colSurfaceContainerHigh
                onSurface: Appearance.colors.colOnSurface
            }
        }
    }
}
