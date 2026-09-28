pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.services

/**
 * The Search Tools panel as a full-size cheatsheet page, in the shell's
 * Material 3 Expressive vocabulary (docs/design/material3-expressive.md).
 *
 * Tools, their options and the engine are the shared DevToolsRegistry and
 * devtools.js, so a tool added there appears here and in Search alike. The
 * page owns the arrangement only, laid out like the Clock app and the usage
 * overlay's Daily limits: a rail pane of categories and tools, a coloured
 * hero pane that takes the hue of the tool type and carries the session's
 * numbers and actions, and the editors as panes one step above the page.
 *
 * The rail borrows the settings sidebar's vocabulary: every row carries a
 * background colour per state, and the group's rounding is dynamic — the
 * selected row swells to a pill while the rows facing it notch in, exactly
 * like SidebarNavButton. Shortcuts live inside their components: holding
 * Ctrl swaps each control's glyph for its keybind (TaskShortcutContent),
 * the same contract the timetable and the sidebar dashboard use.
 */
Item {
    id: root

    property Item keyNavTarget: null
    /// Driven by the cheatsheet window while Ctrl is held (Cheatsheet.qml
    /// binds it to its own ctrlPressed for every page that declares it).
    property bool showShortcutHints: false
    readonly property bool hintsVisible: root.showShortcutHints && (root.Window.window?.active ?? true)
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

    // ── The hero's hue is the tool type: one accent family per element ───
    readonly property color heroColor: root.selectedTool === null ? ClockStyle.colPane
        : root.isGenerator ? ClockStyle.colTertiaryContainer
        : root.selectedTool.type === "analyzer" ? ClockStyle.colSecondaryContainer
        : ClockStyle.colPrimary
    readonly property color heroContent: root.selectedTool === null ? ClockStyle.colOnSurfaceVariant
        : root.isGenerator ? ClockStyle.colOnTertiaryContainer
        : root.selectedTool.type === "analyzer" ? ClockStyle.colOnSecondaryContainer
        : ClockStyle.colOnPrimary

    /// One Material shape per category, so the rail and the hero do not read
    /// as columns of identical dots (the form-row rule of the design doc).
    function categoryShape(categoryId) {
        switch (String(categoryId)) {
        case "generators":
            return "Sunny";
        case "encoders":
            return "Cookie12Sided";
        case "converters":
            return "Clover4Leaf";
        case "formatters":
            return "Cookie9Sided";
        case "text":
            return "Flower";
        case "web":
            return "Cookie7Sided";
        default:
            return "SoftBurst";
        }
    }

    function toolShape(tool) {
        return root.categoryShape(tool?.category ?? "all");
    }

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

    /// Keep the chosen filter mode visible inside its single-row scroller.
    function revealCategory(list) {
        const index = root.categories.findIndex(category => category.id === root.selectedCategory);
        if (index >= 0)
            list.positionViewAtIndex(index, ListView.Contain);
    }

    onSelectedCategoryChanged: Qt.callLater(() => {
        root.revealCategory(railCatList);
        root.revealCategory(stripCatList);
    })

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
        (root.railVisible ? railFilter : stripFilter).field.forceActiveFocus();
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

    // ── Components ─────────────────────────────────────────────────────

    /// The rail's filter: a filled field on the pane with a leading glyph,
    /// and its own shortcut revealed inside while Ctrl is held.
    component FilterField: Item {
        id: fieldBox
        property alias field: innerField
        implicitHeight: 44

        ToolbarTextField {
            id: innerField
            anchors.fill: parent
            leftPadding: 40
            rightPadding: 52
            colBackground: ClockStyle.colField
            placeholderText: Translation.tr("Filter tools (Ctrl+F)")
            text: root.filterText
            onTextChanged: root.filterText = text
            keyNavTarget: root.keyNavTarget
        }

        MaterialSymbol {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: "search"
            iconSize: 18
            color: ClockStyle.colOnSurfaceVariant
        }

        StyledText {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: "Ctrl F"
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: ClockStyle.colOnSurfaceVariant
            opacity: root.hintsVisible ? 1 : 0
            Behavior on opacity {
                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
            }
        }
    }

    /// A filter mode of the rail: a filled pill on the pane's own ladder —
    /// background colour per state, secondary container once chosen. While
    /// Ctrl is held the chosen mode trades its label for the stepping keys.
    component CategoryChip: RippleButton {
        id: chip
        property string label: ""
        property string symbol: ""
        property bool active: false
        property string hint: ""
        implicitHeight: 34
        implicitWidth: chipRow.implicitWidth + 26
        buttonRadius: Appearance.rounding.full
        colBackground: chip.active ? ClockStyle.colSecondaryContainer : "transparent"
        colBackgroundHover: chip.active ? ClockStyle.colSecondaryContainerHover : ColorUtils.applyAlpha(ClockStyle.colPrimary, 0.08)
        colBackgroundActive: chip.active ? ClockStyle.colSecondaryContainerActive : ColorUtils.applyAlpha(ClockStyle.colPrimary, 0.16)
        colRipple: colBackgroundActive

        DashedBorder {
            anchors.fill: parent
            visible: !chip.active
            color: ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.8)
            borderWidth: 1
            dashLength: 4
            gapLength: 3
            radius: Appearance.rounding.full
        }

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                visible: chip.symbol.length > 0
                text: chip.symbol
                iconSize: Appearance.font.pixelSize.normal
                fill: chip.active ? 1 : 0
                color: chip.active ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
            }

            Item {
                readonly property bool swapping: root.hintsVisible && chip.active && chip.hint.length > 0
                implicitWidth: Math.max(chipLabel.implicitWidth, chipHint.implicitWidth)
                implicitHeight: Math.max(chipLabel.implicitHeight, chipHint.implicitHeight)

                StyledText {
                    id: chipLabel
                    anchors.centerIn: parent
                    text: chip.label
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.Bold
                    color: chip.active ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                    opacity: parent.swapping ? 0 : 1
                    Behavior on opacity {
                        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                    }
                }
                StyledText {
                    id: chipHint
                    anchors.centerIn: parent
                    text: chip.hint
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: chip.active ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                    opacity: parent.swapping ? 1 : 0
                    Behavior on opacity {
                        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }

    /// A tool in the rail, with the settings sidebar's dynamic radius: the
    /// group is one slab of state-coloured rows, the selected row swells to
    /// a pill and the rows facing it notch in; the group's ends keep the
    /// large corners. Holding Ctrl reveals the stepping keys in the row.
    component ToolRow: Item {
        id: toolRow
        required property int index
        required property var modelData
        property bool isFirst: false
        property bool isLast: false
        property bool prevIsSelected: false
        property bool nextIsSelected: false
        readonly property bool selected: root.selectedIndex === index

        readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(height / 2, Appearance.rounding.large)
        readonly property real rLarge: Appearance.rounding.scale === 0 ? 0 : Appearance.rounding.large
        readonly property real rSmall: Appearance.rounding.scale === 0 ? 0 : Appearance.rounding.verysmall
        readonly property bool topPill: selected || pointer.pressed || prevIsSelected
        readonly property bool bottomPill: selected || pointer.pressed || nextIsSelected

        implicitHeight: 54
        scale: pointer.pressed ? 0.97 : (pointer.containsMouse ? 1.02 : 1.0)
        z: pointer.containsMouse || pointer.pressed ? 1 : 0
        Behavior on scale {
            enabled: !ClockStyle.reducedMotion
            NumberAnimation {
                duration: ClockStyle.motionFast.duration
                easing.type: ClockStyle.motionFast.type
                easing.bezierCurve: ClockStyle.motionFast.bezierCurve
            }
        }

        Rectangle {
            id: rowBackground
            anchors.fill: parent
            antialiasing: true
            topLeftRadius: toolRow.topPill ? toolRow.rFull : (toolRow.isFirst ? toolRow.rLarge : toolRow.rSmall)
            topRightRadius: toolRow.topPill ? toolRow.rFull : (toolRow.isFirst ? toolRow.rLarge : toolRow.rSmall)
            bottomLeftRadius: toolRow.bottomPill ? toolRow.rFull : (toolRow.isLast ? toolRow.rLarge : toolRow.rSmall)
            bottomRightRadius: toolRow.bottomPill ? toolRow.rFull : (toolRow.isLast ? toolRow.rLarge : toolRow.rSmall)
            color: toolRow.selected
                ? (pointer.pressed ? ClockStyle.colSecondaryContainerActive : pointer.containsMouse ? ClockStyle.colSecondaryContainerHover : ClockStyle.colSecondaryContainer)
                : (pointer.pressed ? ClockStyle.colRailRowActive : pointer.containsMouse ? ClockStyle.colRailRowHover : ClockStyle.colRailRow)
            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }
            Behavior on topLeftRadius {
                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
            }
            Behavior on topRightRadius {
                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
            }
            Behavior on bottomLeftRadius {
                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
            }
            Behavior on bottomRightRadius {
                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 10

            MaterialShapeWrappedMaterialSymbol {
                text: toolRow.modelData.icon
                iconSize: 15
                padding: 8
                shapeString: root.toolShape(toolRow.modelData)
                color: toolRow.selected ? ClockStyle.colOnSecondaryContainer : ColorUtils.applyAlpha(ClockStyle.colPrimary, 0.14)
                colSymbol: toolRow.selected ? ClockStyle.colSecondaryContainer : ClockStyle.colPrimary
                fill: toolRow.selected ? 1 : 0
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: toolRow.modelData.name
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                    color: toolRow.selected ? ClockStyle.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    text: toolRow.modelData.description
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: toolRow.selected ? ClockStyle.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    opacity: toolRow.selected ? 0.85 : 0.75
                }
            }
            StyledText {
                visible: toolRow.selected && root.hintsVisible
                text: "Alt ↑ ↓"
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: ClockStyle.colOnSecondaryContainer
            }
        }

        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectTool(toolRow.index)
        }
    }

    /// A hero action: a pill tinted with the pane's content colour (or filled
    /// with it, when solid), whose glyph trades places with its shortcut
    /// while Ctrl is held — the TaskShortcutContent contract.
    component TintAction: RippleButton {
        id: action
        property string symbol: ""
        property string label: ""
        property string shortcut: ""
        property string tip: ""
        property bool solid: false
        property color colContent: ClockStyle.colOnSurface
        property color colSolidContent: ClockStyle.colPrimary
        property real height_: 38
        implicitHeight: action.height_
        implicitWidth: Math.max(action.height_, actionContent.implicitWidth + ClockStyle.gapHuge * 2 - 4)
        buttonRadius: ClockStyle.pill(action.height_)
        buttonRadiusPressed: ClockStyle.radiusSmall
        colBackground: action.solid ? action.colContent : ColorUtils.applyAlpha(action.colContent, action.activeFocus ? 0.2 : 0.12)
        colBackgroundHover: action.solid ? ColorUtils.mix(action.colContent, action.colSolidContent, 0.88) : ColorUtils.applyAlpha(action.colContent, 0.2)
        colBackgroundActive: action.solid ? ColorUtils.mix(action.colContent, action.colSolidContent, 0.76) : ColorUtils.applyAlpha(action.colContent, 0.28)
        colRipple: colBackgroundActive
        opacity: action.enabled ? 1 : 0.4

        contentItem: TaskShortcutContent {
            id: actionContent
            symbol: action.symbol
            labelText: action.label
            labelPixelSize: ClockStyle.textNormal
            labelFontWeight: Font.DemiBold
            shortcut: action.shortcut
            showHint: root.hintsVisible && action.shortcut.length > 0
            iconSize: ClockStyle.iconSmall + 2
            color: action.solid ? action.colSolidContent : action.colContent
        }

        StyledToolTip {
            text: action.tip
        }
    }

    /// One of the hero's numbers: tall condensed digits over a bold caption,
    /// tinted with the pane's own content colour (the Limits stat tile).
    component StatTile: Rectangle {
        id: tile
        property string value: ""
        property string caption: ""
        property string symbol: ""
        implicitHeight: 56
        radius: ClockStyle.radiusNormal
        color: ColorUtils.applyAlpha(root.heroContent, 0.12)
        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            anchors.topMargin: 7
            anchors.bottomMargin: 7
            spacing: -2

            RowLayout {
                spacing: 6

                StyledText {
                    text: tile.value
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: 22
                    color: root.heroContent
                }
                MaterialSymbol {
                    text: tile.symbol
                    iconSize: ClockStyle.iconSmall
                    color: root.heroContent
                    opacity: 0.8
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: tile.caption
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.DemiBold
                color: root.heroContent
                opacity: 0.85
                elide: Text.ElideRight
            }
        }
    }

    /// An editor: a pane one step above the page, its caption row carrying a
    /// shaped glyph, and the text on a filled field inside.
    component EditorPane: Rectangle {
        id: pane
        property string title: ""
        property string symbol: ""
        property string shape: "Cookie6Sided"
        property string text: ""
        property string countText: ""
        property string errorText: ""
        property string emptyText: ""
        property bool readOnly: false
        property bool rich: false
        signal edited(string text)

        radius: ClockStyle.radiusCard
        color: ClockStyle.colPane

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: ClockStyle.gapLarge
            spacing: ClockStyle.gapSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                MaterialShapeWrappedMaterialSymbol {
                    text: pane.symbol
                    iconSize: 13
                    padding: 8
                    shapeString: pane.shape
                    color: ClockStyle.colPrimaryContainer
                    colSymbol: ClockStyle.colOnPrimaryContainer
                    fill: 1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: pane.title
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                    color: ClockStyle.colOnSurface
                    elide: Text.ElideRight
                }
                StyledText {
                    text: pane.countText
                    visible: pane.countText.length > 0
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: ClockStyle.radiusLarge
                color: paneEdit.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField
                Behavior on color {
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }

                StyledFlickable {
                    id: paneFlick
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gapLarge
                    visible: pane.errorText.length === 0
                    contentWidth: width
                    contentHeight: Math.max(height, paneEdit.implicitHeight)
                    clip: true

                    TextEdit {
                        id: paneEdit
                        width: paneFlick.width
                        text: pane.text
                        readOnly: pane.readOnly
                        textFormat: pane.rich ? TextEdit.RichText : TextEdit.PlainText
                        wrapMode: TextEdit.WrapAnywhere
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: ClockStyle.textNormal
                        color: ClockStyle.colOnSurface
                        selectByMouse: true
                        selectionColor: ClockStyle.colSecondaryContainer
                        selectedTextColor: ClockStyle.colOnSecondaryContainer
                        onTextChanged: {
                            if (!pane.readOnly && text !== pane.text)
                                pane.edited(text);
                        }
                        Keys.onEscapePressed: event => {
                            paneEdit.focus = false;
                            event.accepted = true;
                        }
                    }

                    TouchpadScrollHandler {
                        flickable: paneFlick
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - ClockStyle.gapHuge * 2
                    spacing: ClockStyle.gapSmall
                    visible: pane.readOnly && pane.text.length === 0 && pane.errorText.length === 0

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: pane.symbol
                        iconSize: 26
                        color: ClockStyle.colOnSurfaceVariant
                        opacity: 0.55
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: pane.emptyText
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        font.pixelSize: ClockStyle.textNormal
                        color: ClockStyle.colSubtext
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: ClockStyle.gapSmall
                    visible: pane.errorText.length > 0
                    implicitHeight: errorRow.implicitHeight + ClockStyle.gapLarge
                    radius: ClockStyle.radiusNormal
                    color: ClockStyle.colErrorContainer

                    RowLayout {
                        id: errorRow
                        anchors.fill: parent
                        anchors.margins: ClockStyle.gapSmall + 2
                        spacing: ClockStyle.gapSmall

                        MaterialSymbol {
                            text: "error"
                            iconSize: ClockStyle.iconSmall + 2
                            color: ClockStyle.colOnErrorContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: pane.errorText
                            wrapMode: Text.Wrap
                            font.pixelSize: ClockStyle.textNormal
                            color: ClockStyle.colOnErrorContainer
                        }
                    }
                }
            }
        }
    }

    // ── Page ────────────────────────────────────────────────────────────

    RowLayout {
        anchors.fill: parent
        spacing: ClockStyle.paneGap

        // ── Rail: filter, categories and every tool ─────────────────────
        Rectangle {
            visible: root.railVisible
            Layout.preferredWidth: Math.round(Math.min(340, Math.max(280, root.width * 0.22)))
            Layout.fillHeight: true
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: ClockStyle.gapLarge
                spacing: ClockStyle.gap

                FilterField {
                    id: railFilter
                    Layout.fillWidth: true
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 34

                    ListView {
                        id: railCatList
                        anchors.fill: parent
                        orientation: ListView.Horizontal
                        clip: true
                        spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.categories
                        delegate: CategoryChip {
                            required property var modelData
                            label: modelData.label
                            symbol: modelData.icon
                            active: root.selectedCategory === modelData.id
                            hint: "Alt ← →"
                            onClicked: root.selectCategory(modelData.id)
                        }
                    }

                    // Rounded clip, the settings sidebar way: painted corners
                    // over the opaque pane, no offscreen mask per frame.
                    CornerCutouts {
                        anchors.fill: parent
                        radius: 17
                        color: ClockStyle.colPane
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: railList
                        anchors.fill: parent
                        clip: true
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.tools
                        delegate: ToolRow {
                            width: railList.width
                            isFirst: index === 0
                            isLast: index === root.tools.length - 1
                            prevIsSelected: root.selectedIndex === index - 1
                            nextIsSelected: root.selectedIndex === index + 1
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: root.tools.length === 0
                            text: Translation.tr("No tool matches")
                            color: ClockStyle.colSubtext
                        }

                        TouchpadScrollHandler {
                            flickable: railList
                        }
                    }

                    CornerCutouts {
                        anchors.fill: parent
                        radius: ClockStyle.radiusLarge
                        color: ClockStyle.colPane
                    }
                }
            }
        }

        // ── Workspace ───────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: ClockStyle.paneGap

            // The rail's content, stacked above the workspace on narrow pages.
            ColumnLayout {
                visible: !root.railVisible
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                FilterField {
                    id: stripFilter
                    Layout.fillWidth: true
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 34

                    ListView {
                        id: stripCatList
                        anchors.fill: parent
                        orientation: ListView.Horizontal
                        clip: true
                        spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.categories
                        delegate: CategoryChip {
                            required property var modelData
                            label: modelData.label
                            symbol: modelData.icon
                            active: root.selectedCategory === modelData.id
                            hint: "Alt ← →"
                            onClicked: root.selectCategory(modelData.id)
                        }
                    }

                    CornerCutouts {
                        anchors.fill: parent
                        radius: 17
                        color: ClockStyle.colPane
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 34

                    ListView {
                        id: stripList
                        anchors.fill: parent
                        orientation: ListView.Horizontal
                        clip: true
                        spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.tools

                        delegate: CategoryChip {
                            required property int index
                            required property var modelData
                            label: modelData.name
                            symbol: modelData.icon
                            active: root.selectedIndex === index
                            onClicked: root.selectTool(index)
                        }

                        TouchpadScrollHandler {
                            flickable: stripList
                        }
                    }

                    CornerCutouts {
                        anchors.fill: parent
                        radius: 17
                        color: ClockStyle.colPane
                    }
                }
            }

            // ── Hero: the tool, its numbers and its actions ─────────────
            Rectangle {
                id: hero
                Layout.fillWidth: true
                visible: root.selectedTool !== null
                implicitHeight: heroColumn.implicitHeight + ClockStyle.cardPadding * 2
                radius: ClockStyle.radiusCard
                color: root.heroColor
                Behavior on color {
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }

                // The pane's one ornament: a scalloped shape far larger than
                // the pane, parked off its right edge so only an arc shows. A
                // plain clip would square off the rounded corners, so the arc
                // is cut by a mask of the pane itself (kept in the tree, so
                // the window can die safely).
                Item {
                    id: heroOrnament
                    anchors.fill: parent
                    visible: false

                    MaterialShape {
                        width: Math.round(hero.height * 1.9)
                        height: width
                        x: hero.width - width * 0.32
                        y: (hero.height - height) / 2
                        shapeString: root.toolShape(root.selectedTool)
                        color: root.heroContent
                        rotation: -18
                    }
                }

                Rectangle {
                    id: heroMask
                    anchors.fill: parent
                    radius: hero.radius
                    visible: false
                    layer.enabled: true
                }

                MultiEffect {
                    anchors.fill: parent
                    source: heroOrnament
                    maskEnabled: true
                    maskSource: heroMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                    opacity: 0.1
                }

                ColumnLayout {
                    id: heroColumn
                    anchors.fill: parent
                    anchors.margins: ClockStyle.cardPadding
                    spacing: ClockStyle.gap

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapLarge

                        MaterialShapeWrappedMaterialSymbol {
                            text: root.selectedTool?.icon ?? "handyman"
                            iconSize: 26
                            padding: 14
                            shapeString: root.toolShape(root.selectedTool)
                            color: root.heroContent
                            colSymbol: root.heroColor
                            fill: 1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ClockStyle.gapSmall

                                StyledText {
                                    Layout.maximumWidth: Math.max(120, parent.width - 150)
                                    Layout.alignment: Qt.AlignVCenter
                                    text: root.selectedTool?.name ?? ""
                                    font.family: ClockStyle.fontTitle
                                    font.variableAxes: ClockStyle.axesTitle
                                    font.pixelSize: ClockStyle.textTitle
                                    color: root.heroContent
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    implicitWidth: typeLabel.implicitWidth + ClockStyle.gapLarge
                                    implicitHeight: typeLabel.implicitHeight + ClockStyle.gapSmall
                                    radius: ClockStyle.radiusFull
                                    color: ColorUtils.applyAlpha(root.heroContent, 0.2)

                                    StyledText {
                                        id: typeLabel
                                        anchors.centerIn: parent
                                        text: root.toolTypeLabel(root.selectedTool)
                                        font.pixelSize: ClockStyle.textSmall
                                        font.weight: Font.Bold
                                        color: root.heroContent
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.selectedTool?.description ?? ""
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textNormal
                                color: root.heroContent
                                opacity: 0.85
                            }
                        }

                        RowLayout {
                            spacing: 6

                            TintAction {
                                visible: !root.isGenerator
                                symbol: "content_paste"
                                label: root.compact ? "" : Translation.tr("Paste")
                                shortcut: "Ctrl ⇧ V"
                                tip: Translation.tr("Replace the input with the clipboard (Ctrl+Shift+V)")
                                colContent: root.heroContent
                                onClicked: root.pasteIntoInput()
                            }
                            TintAction {
                                visible: !root.isGenerator
                                symbol: "clear_all"
                                label: root.compact ? "" : Translation.tr("Clear")
                                shortcut: "Ctrl L"
                                tip: Translation.tr("Clear the input (Ctrl+L)")
                                colContent: root.heroContent
                                onClicked: root.clearInput()
                            }
                            TintAction {
                                visible: !root.isGenerator && String(root.selectedTool?.sampleInput ?? "").length > 0
                                symbol: "science"
                                tip: Translation.tr("Load the example input")
                                colContent: root.heroContent
                                onClicked: root.restoreSample()
                            }
                            TintAction {
                                visible: !root.isGenerator
                                enabled: root.outputText.length > 0
                                symbol: "move_up"
                                label: root.compact ? "" : Translation.tr("Chain")
                                shortcut: "Ctrl U"
                                tip: Translation.tr("Use the output as the next input (Ctrl+U)")
                                colContent: root.heroContent
                                onClicked: root.useOutputAsInput()
                            }
                            TintAction {
                                symbol: "refresh"
                                label: root.compact ? "" : Translation.tr("Run")
                                shortcut: "Ctrl R"
                                tip: root.isGenerator ? Translation.tr("Generate again (Ctrl+R)") : Translation.tr("Run again (Ctrl+R)")
                                colContent: root.heroContent
                                onClicked: root.execute(true)
                            }
                            TintAction {
                                symbol: "content_copy"
                                label: root.compact ? "" : Translation.tr("Copy")
                                shortcut: "Ctrl ↵"
                                tip: Translation.tr("Copy the output (Ctrl+Enter)")
                                colContent: root.heroContent
                                solid: true
                                colSolidContent: root.heroColor
                                onClicked: root.copyOutput()
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        StatTile {
                            Layout.fillWidth: true
                            visible: !root.isGenerator
                            value: String(root.inputText.length)
                            caption: Translation.tr("Input")
                            symbol: "edit_note"
                        }
                        StatTile {
                            Layout.fillWidth: true
                            value: String(root.outputText.length)
                            caption: Translation.tr("Output")
                            symbol: "output"
                        }
                        StatTile {
                            Layout.fillWidth: true
                            value: String(root.outputText.length > 0 ? root.outputText.split("\n").length : 0)
                            caption: Translation.tr("Lines")
                            symbol: "format_list_numbered"
                        }
                    }
                }
            }

            // ── Options: chips, toggles and fields on the page ──────────
            Flow {
                Layout.fillWidth: true
                visible: root.selectedTool !== null && (root.selectedTool?.options?.length ?? 0) > 0
                spacing: ClockStyle.gap

                Repeater {
                    model: root.selectedTool?.options ?? []

                    delegate: ColumnLayout {
                        id: optionGroup
                        required property var modelData
                        readonly property bool asMenu: modelData.type === "choice"
                            && (root.compact || (modelData.choices ?? []).length > 5)
                        spacing: 4

                        StyledText {
                            // Toggles have no caption, but keep its height: the Flow
                            // top-aligns groups, so a missing caption lifted every
                            // toggle above the choices beside it.
                            opacity: optionGroup.modelData.type === "toggle" ? 0 : 1
                            text: optionGroup.modelData.label
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.Bold
                            color: ClockStyle.colOnSurfaceVariant
                        }

                        RowLayout {
                            visible: optionGroup.modelData.type === "choice" && !optionGroup.asMenu
                            spacing: 6

                            Repeater {
                                model: optionGroup.modelData.type === "choice" && !optionGroup.asMenu ? optionGroup.modelData.choices : []
                                delegate: ClockFormChip {
                                    required property var modelData
                                    label: modelData.label
                                    selected: root.optionValue(optionGroup.modelData) === modelData.value
                                    onTriggered: root.setOption(optionGroup.modelData.id, modelData.value)
                                }
                            }
                        }

                        StyledComboBox {
                            visible: optionGroup.asMenu
                            implicitWidth: 240
                            model: (optionGroup.modelData.choices ?? []).map(choice => String(choice.label))
                            currentIndex: Math.max(0, (optionGroup.modelData.choices ?? []).findIndex(choice => choice.value === root.optionValue(optionGroup.modelData)))
                            onActivated: choiceIndex => root.setOption(optionGroup.modelData.id, optionGroup.modelData.choices[choiceIndex].value)
                        }

                        ClockFormChip {
                            visible: optionGroup.modelData.type === "toggle"
                            label: optionGroup.modelData.label
                            symbol: Boolean(root.optionValue(optionGroup.modelData)) ? "check_box" : "check_box_outline_blank"
                            selected: Boolean(root.optionValue(optionGroup.modelData))
                            onTriggered: root.setOption(optionGroup.modelData.id, !Boolean(root.optionValue(optionGroup.modelData)))
                        }

                        ToolbarTextField {
                            visible: optionGroup.modelData.type === "text"
                            Layout.fillHeight: false
                            implicitWidth: optionGroup.modelData.id === "flags" ? 96 : Math.min(360, root.width - ClockStyle.gapHuge * 2)
                            implicitHeight: 34
                            colBackground: ClockStyle.colField
                            font.family: Appearance.font.family.monospace
                            text: String(root.optionValue(optionGroup.modelData) ?? "")
                            onTextEdited: root.setOption(optionGroup.modelData.id, text)
                            keyNavTarget: root.keyNavTarget
                        }
                    }
                }
            }

            // ── Editors: input and output, side by side when wide ───────
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.selectedTool !== null
                columns: root.editorsSideBySide && !root.isGenerator ? 2 : 1
                columnSpacing: ClockStyle.paneGap
                rowSpacing: ClockStyle.paneGap

                GridLayout {
                    visible: !root.isGenerator
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 1
                    Layout.preferredWidth: 1
                    Layout.minimumHeight: 120
                    // The diff compares two texts; they sit side by side when they fit.
                    columns: root.isDiff && root.width >= 900 && !(root.editorsSideBySide && root.width < 1600) ? 2 : 1
                    columnSpacing: ClockStyle.paneGap
                    rowSpacing: ClockStyle.paneGap

                    EditorPane {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 1
                        title: root.isDiff ? Translation.tr("Original") : Translation.tr("Input")
                        symbol: "edit_note"
                        shape: "Cookie6Sided"
                        text: root.inputText
                        countText: root.textStats(root.inputText)
                        onEdited: text => root.setInput(text)
                    }

                    EditorPane {
                        visible: root.isDiff
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 1
                        title: Translation.tr("Modified")
                        symbol: "edit_document"
                        shape: "Cookie9Sided"
                        text: root.modifiedText
                        countText: root.textStats(root.modifiedText)
                        onEdited: text => root.setModified(text)
                    }
                }

                EditorPane {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 1
                    Layout.preferredWidth: 1
                    Layout.minimumHeight: 120
                    title: root.selectedTool?.type === "analyzer" ? Translation.tr("Analysis") : Translation.tr("Output")
                    symbol: root.isGenerator ? "wand_stars" : "output"
                    shape: "SoftBurst"
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
                spacing: ClockStyle.gap

                Item { Layout.fillHeight: true }
                ClockEmptyState {
                    Layout.alignment: Qt.AlignHCenter
                    symbol: "handyman"
                    title: Translation.tr("No tool matches this filter")
                    shape: "Cookie9Sided"
                }
                Item { Layout.fillHeight: true }
            }

            // ── Status and result facts ─────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    text: root.statusText
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal
                    color: ClockStyle.colOnSurfaceVariant
                }

                Repeater {
                    model: root.railVisible ? root.metaEntries : root.metaEntries.slice(0, root.compact ? 1 : 3)

                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: metaLabel.implicitWidth + ClockStyle.gapLarge
                        implicitHeight: metaLabel.implicitHeight + ClockStyle.gapSmall
                        radius: ClockStyle.radiusFull
                        color: ClockStyle.colSurfaceHigh

                        StyledText {
                            id: metaLabel
                            anchors.centerIn: parent
                            text: modelData.key + " " + modelData.value
                            font.pixelSize: ClockStyle.textSmall
                            font.family: Appearance.font.family.monospace
                            color: ClockStyle.colOnSurfaceVariant
                        }
                    }
                }
            }
        }
    }
}
