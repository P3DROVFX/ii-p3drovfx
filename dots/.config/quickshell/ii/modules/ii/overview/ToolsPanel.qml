pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: 0
    property string selectedCategory: "all"
    property string inputText: ""
    property var activeOptions: ({})
    property string outputText: ""
    property string errorText: ""
    property string noticeText: ""

    // Per-tool persistent state
    property var toolInputs: ({})
    property var toolOptions: ({})

    readonly property bool supportsSectionToggle: true
    readonly property var tools: DevToolsRegistry.search(root.searchQuery, root.selectedCategory)
    readonly property var selectedTool: root.selectedIndex >= 0 && root.selectedIndex < root.tools.length
        ? root.tools[root.selectedIndex]
        : null

    readonly property string statusText: root.noticeText.length > 0
        ? root.noticeText
        : (root.errorText.length > 0
            ? root.errorText
            : Translation.tr("Offline & private · processed locally without network"))

    implicitWidth: Config.options.search.appearance.panelWidth
    implicitHeight: scaffold.implicitHeight

    function selectTool(index: int) {
        if (index < 0 || index >= root.tools.length) {
            root.selectedIndex = -1;
            root.outputText = "";
            root.errorText = "";
            return;
        }

        root.selectedIndex = index;
        const tool = root.tools[index];
        if (!tool) return;

        // Restore or initialize options for this tool
        if (!root.toolOptions[tool.id]) {
            const initialOpts = {};
            if (tool.defaultOptions) {
                for (const key in tool.defaultOptions) {
                    initialOpts[key] = tool.defaultOptions[key];
                }
            }
            root.toolOptions[tool.id] = initialOpts;
        }
        root.activeOptions = Object.assign({}, root.toolOptions[tool.id]);

        // Restore or initialize input for this tool
        if (root.toolInputs[tool.id] === undefined) {
            root.toolInputs[tool.id] = (tool.type !== "generator" && tool.sampleInput) ? tool.sampleInput : "";
        }
        root.inputText = root.toolInputs[tool.id];

        // Execute fresh for this tool
        root.errorText = "";
        root.outputText = "";
        root.execute(false);

        // Keep horizontal list view scrolled to current selection
        Qt.callLater(() => {
            if (toolsListView && toolsListView.count > index) {
                toolsListView.positionViewAtIndex(index, ListView.Contain);
            }
        });
    }

    function execute(showFeedback = false): bool {
        const tool = root.selectedTool;
        if (!tool) {
            root.outputText = "";
            root.errorText = "";
            return false;
        }

        const input = tool.type === "generator" ? "" : root.inputText;
        const res = DevToolsRegistry.run(tool.id, input, root.activeOptions);
        if (res.error) {
            root.errorText = String(res.error);
            root.outputText = "";
        } else {
            root.errorText = "";
            root.outputText = String(res.output ?? "");
            if (showFeedback) {
                root.showNotice(Translation.tr("Generated %1").arg(tool.name));
            }
        }
        return true;
    }

    function copyOutput(): bool {
        if (root.outputText.length === 0) {
            root.execute(false);
        }
        if (root.outputText.length === 0) {
            return false;
        }
        Quickshell.clipboardText = root.outputText;
        root.showNotice(Translation.tr("Copied to clipboard"));
        return true;
    }

    function pasteFromClipboard() {
        const clip = String(Quickshell.clipboardText ?? "");
        if (clip.length > 0) {
            root.inputText = clip;
            if (root.selectedTool) {
                root.toolInputs[root.selectedTool.id] = clip;
            }
            root.execute(false);
            root.showNotice(Translation.tr("Pasted from clipboard"));
        }
    }

    function setOption(key, value) {
        const next = Object.assign({}, root.activeOptions);
        next[key] = value;
        root.activeOptions = next;
        if (root.selectedTool) {
            root.toolOptions[root.selectedTool.id] = next;
        }
        root.execute(false);
    }

    function setCategoryByIndex(index: int) {
        const cats = DevToolsRegistry.categories;
        if (index >= 0 && index < cats.length) {
            root.selectedCategory = cats[index].id;
            root.selectTool(0);
        }
    }

    function cycleCategory(step: int) {
        const cats = DevToolsRegistry.categories;
        let idx = cats.findIndex(c => c.id === root.selectedCategory);
        if (idx < 0) idx = 0;
        idx = (idx + step + cats.length) % cats.length;
        root.selectedCategory = cats[idx].id;
        root.selectTool(0);
    }

    function triggerOptionChoice(choiceIndex: int) {
        const tool = root.selectedTool;
        if (!tool || !tool.options || tool.options.length === 0) return;
        const opt = tool.options[0];
        if (opt.type === "choice" && opt.choices && opt.choices.length > choiceIndex) {
            root.setOption(opt.id, opt.choices[choiceIndex].value);
        } else if (opt.type === "toggle") {
            const curr = root.activeOptions[opt.id] !== undefined ? Boolean(root.activeOptions[opt.id]) : Boolean(opt.default);
            root.setOption(opt.id, !curr);
        }
    }

    function activateSelected(): bool {
        if (root.selectedTool?.type === "generator") {
            root.execute(false);
            return root.copyOutput();
        } else {
            if (!inputEdit || !inputEdit.activeFocus) {
                return root.focusInput();
            } else {
                root.copyOutput();
                root.unfocusInput();
                return true;
            }
        }
    }

    function secondaryActivateSelected(): bool {
        return root.execute(true);
    }

    function toggleSection(): bool {
        return root.execute(true);
    }

    function copySelected(): bool {
        return root.copyOutput();
    }

    function sectionPrevious(): bool {
        root.cycleCategory(-1);
        return true;
    }

    function sectionNext(): bool {
        root.cycleCategory(1);
        return true;
    }

    function navigateLeft(): bool {
        if (root.selectedIndex > 0) {
            root.selectTool(root.selectedIndex - 1);
            return true;
        }
        return false;
    }

    function navigateRight(): bool {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.tools.length - 1) {
            root.selectTool(root.selectedIndex + 1);
            return true;
        }
        return false;
    }

    function focusInput(): bool {
        if (root.selectedTool?.type !== "generator" && inputEdit) {
            inputEdit.forceActiveFocus();
            inputEdit.selectAll();
            return true;
        }
        return false;
    }

    function unfocusInput(): bool {
        if (inputEdit && inputEdit.activeFocus) {
            inputEdit.focus = false;
            return true;
        }
        return false;
    }

    function editSelected(): bool {
        return root.focusInput();
    }

    function showNotice(message) {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    onToolsChanged: {
        const targetIndex = root.tools.length === 0 ? -1 : Math.max(0, Math.min(root.selectedIndex, root.tools.length - 1));
        root.selectTool(targetIndex);
    }

    Component.onCompleted: {
        root.selectTool(0);
    }

    Timer {
        id: noticeTimer
        interval: 3200
        onTriggered: root.noticeText = ""
    }

    // Keyboard shortcuts for full keyboard productivity
    Shortcut { sequence: "Ctrl+I"; onActivated: root.focusInput() }
    Shortcut { sequence: "Ctrl+E"; onActivated: root.focusInput() }
    Shortcut { sequence: "Ctrl+V"; onActivated: root.pasteFromClipboard() }
    Shortcut { sequence: "Ctrl+L"; onActivated: { root.inputText = ""; if (root.selectedTool) root.toolInputs[root.selectedTool.id] = ""; root.execute(false); } }
    Shortcut { sequence: "Ctrl+1"; onActivated: root.setCategoryByIndex(0) }
    Shortcut { sequence: "Ctrl+2"; onActivated: root.setCategoryByIndex(1) }
    Shortcut { sequence: "Ctrl+3"; onActivated: root.setCategoryByIndex(2) }
    Shortcut { sequence: "Ctrl+4"; onActivated: root.setCategoryByIndex(3) }
    Shortcut { sequence: "Ctrl+5"; onActivated: root.setCategoryByIndex(4) }
    Shortcut { sequence: "Ctrl+6"; onActivated: root.setCategoryByIndex(5) }
    Shortcut { sequence: "Alt+1"; onActivated: root.triggerOptionChoice(0) }
    Shortcut { sequence: "Alt+2"; onActivated: root.triggerOptionChoice(1) }
    Shortcut { sequence: "Alt+3"; onActivated: root.triggerOptionChoice(2) }
    Shortcut { sequence: "Alt+4"; onActivated: root.triggerOptionChoice(3) }
    Shortcut { sequence: "Alt+5"; onActivated: root.triggerOptionChoice(4) }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Tools")
        icon: "wand_stars"
        accent: true
        showStatus: true
        statusText: root.statusText
        primaryHint: root.selectedTool?.type === "generator"
            ? ({ label: Translation.tr("Generate & Copy"), actionId: "activate", keys: ["↵"] })
            : (inputEdit?.activeFocus
                ? ({ label: Translation.tr("Copy & Unfocus"), actionId: "activate", keys: ["Ctrl", "↵"] })
                : ({ label: Translation.tr("Focus input"), actionId: "activate", keys: ["↵"] }))
        hints: [
            { label: Translation.tr("Unfocus"), keys: ["Esc"] },
            { label: Translation.tr("Re-run"), actionId: "section", keys: ["Tab"] },
            { label: Translation.tr("Tool"), keys: ["←", "→"] },
            { label: Translation.tr("Category"), keys: ["Ctrl", "1-6"] },
            { label: Translation.tr("Options"), keys: ["Alt", "1-5"] },
            { label: Translation.tr("Paste"), keys: ["Ctrl", "V"] },
            { label: Translation.tr("Clear"), keys: ["Ctrl", "L"] }
        ]

        ColumnLayout {
            width: parent.width
            height: parent.height
            spacing: Appearance.sizes.elevationMargin

            // ── Category Selector Bar ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                Repeater {
                    model: DevToolsRegistry.categories
                    delegate: RippleButton {
                        required property int index
                        required property var modelData

                        implicitHeight: Appearance.sizes.elevationMargin * 3
                        implicitWidth: catContent.implicitWidth + Appearance.sizes.elevationMargin * 2
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.selectedCategory === modelData.id
                            ? Appearance.colors.colPrimaryContainer
                            : Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: root.selectedCategory === modelData.id
                            ? Appearance.colors.colPrimaryContainerHover
                            : Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: root.selectedCategory === modelData.id
                            ? Appearance.colors.colPrimaryContainerActive
                            : Appearance.colors.colSurfaceContainerHighestActive
                        onClicked: {
                            root.selectedCategory = modelData.id;
                            root.selectTool(0);
                        }

                        RowLayout {
                            id: catContent
                            anchors.centerIn: parent
                            spacing: Appearance.sizes.elevationMargin / 2

                            MaterialSymbol {
                                text: modelData.icon
                                iconSize: Appearance.font.pixelSize.normal
                                color: root.selectedCategory === modelData.id
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colSubtext
                            }
                            StyledText {
                                text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: root.selectedCategory === modelData.id ? Font.DemiBold : Font.Normal
                                color: root.selectedCategory === modelData.id
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnSurface
                            }
                        }
                    }
                }
            }

            // ── Tool Selection Horizontal Strip (ListView with smooth horizontal scrolling) ──
            ListView {
                id: toolsListView
                Layout.fillWidth: true
                implicitHeight: Appearance.sizes.elevationMargin * 5.0
                orientation: ListView.Horizontal
                model: root.tools
                currentIndex: root.selectedIndex
                highlightFollowsCurrentItem: false
                clip: true
                spacing: Appearance.sizes.elevationMargin / 2
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: wheel => {
                        if (wheel.angleDelta.y !== 0) {
                            toolsListView.contentX = Math.max(0, Math.min(toolsListView.contentWidth - toolsListView.width, toolsListView.contentX - wheel.angleDelta.y));
                        } else if (wheel.angleDelta.x !== 0) {
                            toolsListView.contentX = Math.max(0, Math.min(toolsListView.contentWidth - toolsListView.width, toolsListView.contentX - wheel.angleDelta.x));
                        }
                    }
                }

                delegate: RippleButton {
                    id: toolDelegate
                    required property int index
                    required property var modelData

                    implicitHeight: toolChipContent.implicitHeight + Appearance.sizes.elevationMargin * 1.5
                    implicitWidth: toolChipContent.implicitWidth + Appearance.sizes.elevationMargin * 2.2
                    scale: down ? 0.98 : 1.0
                    buttonRadius: root.selectedIndex === index ? Appearance.rounding.large : Appearance.rounding.normal
                    colBackground: root.selectedIndex === index
                        ? Appearance.colors.colSecondaryContainer
                        : Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: root.selectedIndex === index
                        ? Appearance.colors.colSecondaryContainerHover
                        : Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: root.selectedIndex === index
                        ? Appearance.colors.colSecondaryContainerActive
                        : Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: root.selectTool(index)
                    onDoubleClicked: root.activateSelected()

                    RowLayout {
                        id: toolChipContent
                        anchors.centerIn: parent
                        spacing: Appearance.sizes.elevationMargin

                        MaterialSymbol {
                            text: modelData.icon
                            iconSize: Appearance.font.pixelSize.large
                            color: root.selectedIndex === index
                                ? Appearance.colors.colOnSecondaryContainer
                                : Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            spacing: 2
                            StyledText {
                                text: modelData.name
                                font.weight: Font.DemiBold
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: root.selectedIndex === index
                                    ? Appearance.colors.colOnSecondaryContainer
                                    : Appearance.colors.colOnSurface
                            }
                            StyledText {
                                text: modelData.type === "generator" ? Translation.tr("Generator") : (modelData.type === "analyzer" ? Translation.tr("Analyzer") : Translation.tr("Transformer"))
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.selectedIndex === index
                                    ? Appearance.colors.colOnSecondaryContainer
                                    : Appearance.colors.colSubtext
                            }
                        }
                    }

                    ConfiguredKeyHint {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Appearance.sizes.elevationMargin / 2
                        visible: root.selectedIndex === index && Config.options.search.appearance.showKeyHints
                        actionId: "activate"
                        fallbackKeys: ["↵"]
                        surface: Appearance.colors.colSecondaryContainer
                        onSurface: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }

            // ── Active Tool Work Area ──
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.tools.length > 0 && root.selectedTool !== null
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHigh

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Appearance.sizes.elevationMargin * 1.4
                    spacing: Appearance.sizes.elevationMargin * 0.8

                    // Tool Header & Circular Action Buttons Row (Space-Between)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.sizes.elevationMargin

                        RowLayout {
                            spacing: Appearance.sizes.elevationMargin
                            MaterialSymbol {
                                text: root.selectedTool?.icon ?? "wand_stars"
                                iconSize: Appearance.font.pixelSize.huge
                                color: Appearance.colors.colPrimary
                            }
                            ColumnLayout {
                                spacing: 2
                                StyledText {
                                    text: root.selectedTool?.name ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnSurface
                                }
                                StyledText {
                                    text: root.selectedTool?.description ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }

                        // Expanding spacer for space-between
                        Item {
                            Layout.fillWidth: true
                        }

                        // Circular Action Buttons (Right aligned flush to the end, Wifi/Bluetooth dialog style)
                        RowLayout {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            spacing: Appearance.sizes.elevationMargin * 0.8

                            // 1. Paste from clipboard (transformers & analyzers)
                            RippleButton {
                                visible: root.selectedTool?.type !== "generator"
                                implicitWidth: Appearance.sizes.elevationMargin * 4.2
                                implicitHeight: implicitWidth
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colSurfaceContainerHighest
                                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                                colRipple: Appearance.colors.colSurfaceContainerHighestActive
                                onClicked: root.pasteFromClipboard()

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "content_paste"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colPrimary
                                }

                                StyledToolTip {
                                    text: Translation.tr("Paste from clipboard (Ctrl+V)")
                                }
                            }

                            // 2. Clear input (transformers & analyzers)
                            RippleButton {
                                visible: root.selectedTool?.type !== "generator"
                                implicitWidth: Appearance.sizes.elevationMargin * 4.2
                                implicitHeight: implicitWidth
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colSurfaceContainerHighest
                                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                                colRipple: Appearance.colors.colSurfaceContainerHighestActive
                                onClicked: {
                                    root.inputText = "";
                                    if (root.selectedTool) root.toolInputs[root.selectedTool.id] = "";
                                    root.execute(false);
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "clear_all"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colSubtext
                                }

                                StyledToolTip {
                                    text: Translation.tr("Clear input (Ctrl+L)")
                                }
                            }

                            // 3. Re-run / Generate again button
                            RippleButton {
                                implicitWidth: Appearance.sizes.elevationMargin * 4.2
                                implicitHeight: implicitWidth
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colSecondaryContainer
                                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                colRipple: Appearance.colors.colSecondaryContainerActive
                                onClicked: root.execute(true)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "refresh"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnSecondaryContainer
                                }

                                StyledToolTip {
                                    text: root.selectedTool?.type === "generator"
                                        ? Translation.tr("Generate again (Tab)")
                                        : Translation.tr("Run tool (Tab)")
                                }
                            }

                            // 4. Copy Output (Primary prominent circle button)
                            RippleButton {
                                implicitWidth: Appearance.sizes.elevationMargin * 4.2
                                implicitHeight: implicitWidth
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
                                colRipple: Appearance.colors.colPrimaryActive
                                onClicked: root.copyOutput()

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "content_copy"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnPrimary
                                }

                                StyledToolTip {
                                    text: Translation.tr("Copy Output (↵)")
                                }
                            }
                        }
                    }

                    // Dynamic Options Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.sizes.elevationMargin
                        visible: (root.selectedTool?.options?.length ?? 0) > 0

                        StyledText {
                            text: Translation.tr("Options:")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        StyledFlickable {
                            Layout.fillWidth: true
                            implicitHeight: optionsInnerRow.implicitHeight
                            contentWidth: optionsInnerRow.implicitWidth
                            contentHeight: implicitHeight
                            flickableDirection: Flickable.HorizontalFlick
                            clip: true

                            RowLayout {
                                id: optionsInnerRow
                                spacing: Appearance.sizes.elevationMargin

                                Repeater {
                                    model: root.selectedTool?.options ?? []
                                    delegate: RowLayout {
                                        id: optionGroupItem
                                        required property var modelData
                                        readonly property var currentOptionDef: modelData
                                        spacing: 4

                                        // Choice option (segmented buttons)
                                        Repeater {
                                            model: optionGroupItem.currentOptionDef.type === "choice" ? optionGroupItem.currentOptionDef.choices : []
                                            delegate: RippleButton {
                                                id: choiceBtn
                                                required property var modelData
                                                readonly property bool isSelected: root.activeOptions[optionGroupItem.currentOptionDef.id] === modelData.value
                                                    || (root.activeOptions[optionGroupItem.currentOptionDef.id] === undefined && modelData.value === optionGroupItem.currentOptionDef.default)

                                                implicitHeight: Appearance.sizes.elevationMargin * 2.4
                                                implicitWidth: choiceText.implicitWidth + Appearance.sizes.elevationMargin * 1.5
                                                buttonRadius: Appearance.rounding.small
                                                colBackground: isSelected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHighest
                                                colBackgroundHover: isSelected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                                                colRipple: isSelected ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                                                onClicked: root.setOption(optionGroupItem.currentOptionDef.id, modelData.value)

                                                StyledText {
                                                    id: choiceText
                                                    anchors.centerIn: parent
                                                    text: choiceBtn.modelData.label
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    font.weight: choiceBtn.isSelected ? Font.DemiBold : Font.Normal
                                                    color: choiceBtn.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                                }
                                            }
                                        }

                                        // Toggle option (chip toggle)
                                        RippleButton {
                                            id: toggleBtn
                                            visible: optionGroupItem.currentOptionDef.type === "toggle"
                                            readonly property bool isChecked: root.activeOptions[optionGroupItem.currentOptionDef.id] !== undefined
                                                ? Boolean(root.activeOptions[optionGroupItem.currentOptionDef.id])
                                                : Boolean(optionGroupItem.currentOptionDef.default)

                                            implicitHeight: Appearance.sizes.elevationMargin * 2.4
                                            implicitWidth: toggleRow.implicitWidth + Appearance.sizes.elevationMargin * 1.5
                                            buttonRadius: Appearance.rounding.small
                                            colBackground: isChecked ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHighest
                                            colBackgroundHover: isChecked ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                                            colRipple: isChecked ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                                            onClicked: root.setOption(optionGroupItem.currentOptionDef.id, !isChecked)

                                            RowLayout {
                                                id: toggleRow
                                                anchors.centerIn: parent
                                                spacing: 4
                                                MaterialSymbol {
                                                    text: toggleBtn.isChecked ? "check_box" : "check_box_outline_blank"
                                                    iconSize: Appearance.font.pixelSize.small
                                                    color: toggleBtn.isChecked ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                                }
                                                StyledText {
                                                    text: optionGroupItem.currentOptionDef.label
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    color: toggleBtn.isChecked ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Input Box (for transformers & analyzers)
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.selectedTool?.type === "generator" ? 0 : Appearance.sizes.elevationMargin * 6.0
                        visible: root.selectedTool?.type !== "generator"
                        spacing: 2

                        StyledText {
                            text: Translation.tr("Input:")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Appearance.rounding.normal
                            color: inputEdit.activeFocus ? Appearance.colors.colSurfaceContainerHighestHover : Appearance.colors.colSurfaceContainerHighest

                            StyledFlickable {
                                anchors.fill: parent
                                anchors.margins: Appearance.sizes.elevationMargin * 1.3
                                contentWidth: width
                                contentHeight: Math.max(height, inputEdit.implicitHeight)
                                clip: true

                                TextEdit {
                                    id: inputEdit
                                    width: parent.width
                                    text: root.inputText
                                    wrapMode: TextEdit.WrapAnywhere
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnSurface
                                    selectByMouse: true
                                    selectionColor: Appearance.colors.colSecondaryContainer
                                    selectedTextColor: Appearance.colors.colOnSecondaryContainer
                                    Keys.onEscapePressed: event => {
                                        inputEdit.focus = false;
                                        event.accepted = true;
                                    }
                                    Keys.onReturnPressed: event => {
                                        if (event.modifiers & Qt.ControlModifier) {
                                            root.copyOutput();
                                            event.accepted = true;
                                        } else {
                                            event.accepted = false;
                                        }
                                    }
                                    Keys.onTabPressed: event => {
                                        inputEdit.focus = false;
                                        root.execute(true);
                                        event.accepted = true;
                                    }
                                    onTextChanged: {
                                        if (root.inputText !== text) {
                                            root.inputText = text;
                                            if (root.selectedTool) {
                                                root.toolInputs[root.selectedTool.id] = text;
                                            }
                                            root.execute(false);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Error Box if present
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: errorRow.implicitHeight + Appearance.sizes.elevationMargin * 1.6
                        visible: root.errorText.length > 0
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
                                text: root.errorText
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnErrorContainer
                            }
                        }
                    }

                    // Output Box / Empty State Area
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: Appearance.sizes.elevationMargin * 12
                        spacing: 2

                        StyledText {
                            text: root.selectedTool?.type === "analyzer" ? Translation.tr("Analysis:") : Translation.tr("Output:")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colSurfaceContainerHighest

                            // 1. Valid Output Display
                            StyledFlickable {
                                anchors.fill: parent
                                anchors.margins: Appearance.sizes.elevationMargin * 1.3
                                visible: root.outputText.length > 0
                                contentWidth: width
                                contentHeight: Math.max(height, outputTextEdit.implicitHeight)
                                clip: true

                                TextEdit {
                                    id: outputTextEdit
                                    width: parent.width
                                    text: root.outputText
                                    readOnly: true
                                    wrapMode: TextEdit.WrapAnywhere
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: root.selectedTool?.id === "lorem" ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnSurface
                                    selectByMouse: true
                                    selectionColor: Appearance.colors.colSecondaryContainer
                                    selectedTextColor: Appearance.colors.colOnSecondaryContainer
                                }
                            }

                            // 2. Empty State (When output is empty and no error)
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: Appearance.sizes.elevationMargin / 2
                                visible: root.outputText.length === 0 && root.errorText.length === 0

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.selectedTool?.type === "generator" ? "wand_stars" : (root.selectedTool?.type === "analyzer" ? "analytics" : "edit_note")
                                    iconSize: Appearance.font.pixelSize.huge
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.selectedTool?.type === "generator"
                                        ? Translation.tr("Ready to generate")
                                        : Translation.tr("Waiting for input")
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnSurface
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.selectedTool?.type === "generator"
                                        ? Translation.tr("Click ‘Generate again’ or press Enter to produce a value")
                                        : Translation.tr("Type or paste content in the input box above to see the result")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }
            }

            // Overall Empty state (when search filter returns 0 tools)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.tools.length === 0
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "search_off"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No tool matches this search")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
