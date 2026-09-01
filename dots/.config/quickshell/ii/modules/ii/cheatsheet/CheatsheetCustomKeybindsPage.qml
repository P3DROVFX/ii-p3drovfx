pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    required property string pageId
    property Item keyNavTarget: null
    property bool tabActive: true
    property string searchText: ""
    property bool confirmingDelete: false
    readonly property var page: {
        const revision = KeybindsService.revision;
        return KeybindsService.pageById(root.pageId);
    }
    readonly property bool isTabActive: root.visible && root.tabActive
    readonly property var groups: {
        const revision = KeybindsService.revision;
        const query = root.searchText.trim().toLowerCase();
        const grouped = [];
        const byName = {};
        for (const entry of root.page?.keybinds ?? []) {
            if (query && !KeybindsService.searchMatches(entry, query))
                continue;
            const name = String(entry.category ?? "").trim() || Translation.tr("General");
            if (!byName[name]) {
                byName[name] = { name: name, entries: [] };
                grouped.push(byName[name]);
            }
            byName[name].entries.push(entry);
        }
        return grouped;
    }
    readonly property int totalMatches: root.groups.reduce((total, group) => total + group.entries.length, 0)
    // Keep the masonry rhythm aligned with the Hyprland keybind page.
    readonly property real cardGap: 12
    readonly property real minimumCardWidth: 280
    readonly property int columnCount: Math.max(1, Math.min(4,
        Math.floor((groupsArea.width + root.cardGap) / (root.minimumCardWidth + root.cardGap))))
    readonly property real cardWidth: Math.max(1, (groupsArea.width - root.cardGap * (root.columnCount - 1)) / root.columnCount)
    readonly property int categoryCount: root.groups.length

    signal requestEditPage

    // Keep category delegates alive while filtering or editing so masonry
    // positions can animate from their previous coordinates.
    ListModel {
        id: groupOrderModel
    }

    function sourceLabel(kind): string {
        const value = String(kind ?? "");
        if (value === "template") return Translation.tr("starter set");
        if (value === "json") return Translation.tr("JSON import");
        if (value === "vscode") return Translation.tr("VS Code import");
        if (value === "jetbrains") return Translation.tr("JetBrains import");
        if (value === "neovim-static") return Translation.tr("partial Neovim import");
        return value;
    }

    function sourceIcon(kind): string {
        const value = String(kind ?? "");
        if (value === "template") return "auto_awesome";
        if (value === "json") return "data_object";
        if (value === "vscode") return "code";
        if (value === "jetbrains") return "developer_mode";
        if (value === "neovim-static") return "terminal";
        return "edit_note";
    }

    function categoryIcon(name): string {
        const value = String(name ?? "").toLowerCase();
        if (value.includes("move") || value.includes("motion") || value.includes("navigation")) return "open_with";
        if (value.includes("edit") || value.includes("change")) return "edit_note";
        if (value.includes("select") || value.includes("visual")) return "select";
        if (value.includes("search") || value.includes("find")) return "search";
        if (value.includes("file") || value.includes("project")) return "folder_open";
        if (value.includes("window") || value.includes("pane") || value.includes("split")) return "view_quilt";
        if (value.includes("git") || value.includes("version")) return "commit";
        if (value.includes("debug") || value.includes("test")) return "bug_report";
        if (value.includes("terminal") || value.includes("command")) return "terminal";
        if (value.includes("code") || value.includes("refactor")) return "code_blocks";
        return "keyboard_command_key";
    }

    function hasContext(context): bool {
        const value = String(context ?? "").trim();
        return value.length > 0 && value.toLowerCase() !== "general" && value.toLowerCase() !== "global";
    }

    function contextIcon(context): string {
        const value = String(context ?? "").toLowerCase().trim();
        if (!value) return "";
        if (value.includes("normal") || value === "n mode" || value === "n") return "arrow_selector_tool";
        if (value.includes("insert") || value.includes("edit") || value === "i mode" || value === "i") return "edit";
        if (value.includes("visual") || value.includes("select") || value === "v mode" || value === "v") return "select";
        if (value.includes("command") || value.includes("terminal") || value === "c mode" || value === "c") return "terminal";
        if (value.includes("debug")) return "bug_report";
        if (value.includes("editor")) return "code_blocks";
        return "label";
    }

    function bumpLayout(): void {
        layoutTimer.restart();
    }

    function syncGroupModel(): void {
        const nextGroups = root.groups.map(group => ({
            key: String(group.name ?? Translation.tr("General"))
        }));

        for (let index = groupOrderModel.count - 1; index >= 0; index--) {
            const current = groupOrderModel.get(index);
            if (!nextGroups.some(candidate => candidate.key === String(current.groupKey ?? "")))
                groupOrderModel.remove(index);
        }

        for (let targetIndex = 0; targetIndex < nextGroups.length; targetIndex++) {
            const desired = nextGroups[targetIndex];
            let currentIndex = -1;
            for (let index = targetIndex; index < groupOrderModel.count; index++) {
                if (String(groupOrderModel.get(index).groupKey ?? "") === desired.key) {
                    currentIndex = index;
                    break;
                }
            }

            if (currentIndex < 0) {
                groupOrderModel.insert(targetIndex, {
                    groupKey: desired.key
                });
            } else {
                if (currentIndex !== targetIndex)
                    groupOrderModel.move(currentIndex, targetIndex, 1);
            }
        }

        root.bumpLayout();
    }

    function groupForKey(key): var {
        for (const group of root.groups) {
            if (String(group.name ?? Translation.tr("General")) === String(key ?? ""))
                return group;
        }
        return { name: String(key ?? ""), entries: [] };
    }

    function groupHeight(index): real {
        const card = groupRepeater.itemAt(index);
        return card ? Math.max(0, card.implicitHeight) : 0;
    }

    function emptyColumnHeights(): var {
        const heights = [];
        for (let index = 0; index < root.columnCount; index++)
            heights.push(0);
        return heights;
    }

    function getColumnIndex(targetIndex): int {
        const heights = root.emptyColumnHeights();
        for (let index = 0; index < targetIndex; index++) {
            const cardHeight = root.groupHeight(index);
            if (cardHeight <= 0)
                continue;
            let column = 0;
            for (let candidate = 1; candidate < root.columnCount; candidate++) {
                if (heights[candidate] < heights[column])
                    column = candidate;
            }
            heights[column] += cardHeight + root.cardGap;
        }
        let shortest = 0;
        for (let candidate = 1; candidate < root.columnCount; candidate++) {
            if (heights[candidate] < heights[shortest])
                shortest = candidate;
        }
        return shortest;
    }

    function getGroupY(targetIndex): real {
        const heights = root.emptyColumnHeights();
        for (let index = 0; index < targetIndex; index++) {
            const cardHeight = root.groupHeight(index);
            if (cardHeight <= 0)
                continue;
            let column = 0;
            for (let candidate = 1; candidate < root.columnCount; candidate++) {
                if (heights[candidate] < heights[column])
                    column = candidate;
            }
            heights[column] += cardHeight + root.cardGap;
        }
        return heights[root.getColumnIndex(targetIndex)];
    }

    function editEntry(entry): void {
        editorSidebar.openEdit(entry);
    }

    onPageIdChanged: {
        root.searchText = "";
        filterField.text = "";
        root.confirmingDelete = false;
        editorSidebar.close();
        Qt.callLater(() => root.syncGroupModel());
    }

    onGroupsChanged: Qt.callLater(() => root.syncGroupModel())

    Component.onCompleted: Qt.callLater(() => root.syncGroupModel())

    onFocusChanged: {
        if (!focus)
            return;
        if (root.isTabActive)
            filterField.forceActiveFocus();
    }

    property bool aiSuccess: false
    readonly property bool isCategorizing: KeybindsService.aiCategorizing && KeybindsService.aiCategorizingPageId === root.pageId
    property int aiProgressStep: 0

    Timer {
        id: aiProgressTimer
        interval: 2200
        repeat: true
        running: root.isCategorizing
        onTriggered: root.aiProgressStep = (root.aiProgressStep + 1) % 3
        onRunningChanged: {
            if (running) root.aiProgressStep = 0;
        }
    }

    function aiProgressMessage(): string {
        switch (root.aiProgressStep) {
        case 0:
            return Translation.tr("Analyzing %1 shortcuts and context...").arg(String((root.page?.keybinds ?? []).length));
        case 1:
            return Translation.tr("Clustering into intelligent semantic categories with AI...");
        case 2:
            return Translation.tr("Refining action descriptions and reorganizing layout...");
        default:
            return Translation.tr("Categorizing with AI...");
        }
    }

    Timer {
        id: aiSuccessTimer
        interval: 3500
        repeat: false
        onTriggered: root.aiSuccess = false
    }

    Connections {
        target: KeybindsService

        function onOperationFinished(success, message, pageId) {
            if (pageId === root.pageId) {
                if (success) {
                    root.aiSuccess = true;
                    aiSuccessTimer.restart();
                } else {
                    root.aiSuccess = false;
                    aiSuccessTimer.stop();
                }
            }
        }
    }

    Timer {
        id: deleteConfirmationTimer
        interval: 5000
        repeat: false
        onTriggered: root.confirmingDelete = false
    }

    Timer {
        id: layoutTimer
        interval: 100
        repeat: false
        onTriggered: groupsArea.layoutRevision++
    }

    component KeybindRow: Item {
        id: keybindRow
        required property var entry
        property string categoryName: ""
        property bool isEditing: false

        readonly property bool isEditAreaHovered: (descriptionMouseArea.containsMouse || modeOrEditButton.hovered) && !keybindRow.isEditing

        readonly property string accessibleSummary: [
            String(keybindRow.entry.keys ?? ""),
            String(keybindRow.entry.description ?? ""),
            String(keybindRow.entry.context ?? ""),
            String(keybindRow.entry.notes ?? "")
        ].filter(value => value.trim().length > 0).join(" · ")

        Layout.fillWidth: true
        implicitHeight: Math.max(34, rowContent.implicitHeight + 6)

        Rectangle {
            id: rowBackground
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: keybindRowHoverHandler.hovered && !keybindRow.isEditing
                ? ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.94)
                : (keybindRow.isEditing ? ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.90) : "transparent")

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(rowBackground)
            }
        }

        HoverHandler {
            id: keybindRowHoverHandler
        }

        readonly property real keybindReserveWidth: (keybindRow.isEditing ? editActionsRow.implicitWidth : normalActionsRow.implicitWidth)
            + rowContent.spacing * (2 + (shortcutIcon.visible ? 1 : 0) + (!keybindRow.isEditing && modeOrEditButton.visible ? 1 : 0))
            + (shortcutIcon.visible ? shortcutIcon.implicitWidth : 0)
            + (!keybindRow.isEditing && modeOrEditButton.visible ? modeOrEditButton.implicitWidth : 0)

        RowLayout {
            id: rowContent
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 4
            spacing: 8

            KeybindShortcutSequence {
                id: keybindSequence
                Layout.alignment: Qt.AlignVCenter
                maximumWidth: Math.max(1, keybindRow.width - keybindRow.keybindReserveWidth)
                shortcutText: String(keybindRow.entry.keys ?? "")
                compact: true
            }

            MaterialSymbol {
                id: shortcutIcon
                visible: Boolean(String(keybindRow.entry.icon ?? "").trim())
                Layout.alignment: Qt.AlignVCenter
                text: String(keybindRow.entry.icon ?? "")
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }

            Item {
                id: descriptionContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignVCenter

                StyledText {
                    id: descriptionText
                    visible: !keybindRow.isEditing
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(keybindRow.entry.description ?? "")
                    elide: Text.ElideRight
                    font.pixelSize: Config.options.cheatsheet.fontSize.comment || Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface

                    MouseArea {
                        id: descriptionMouseArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                            keybindRow.isEditing = true;
                            inlineEditField.text = String(keybindRow.entry.description ?? "");
                            inlineEditField.forceActiveFocus();
                            inlineEditField.selectAll();
                        }

                        StyledToolTip {
                            extraVisibleCondition: descriptionMouseArea.containsMouse && !keybindRow.isEditing
                            text: Translation.tr("Click to rename")
                        }
                    }
                }

                Rectangle {
                    id: inlineEditBox
                    visible: keybindRow.isEditing
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 28
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    border.width: 1.5
                    border.color: Appearance.colors.colPrimary

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        onClicked: (mouse) => {
                            inlineEditField.forceActiveFocus();
                            mouse.accepted = false;
                        }
                    }

                    TextInput {
                        id: inlineEditField
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Appearance.colors.colOnSurface
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        clip: true
                        selectByMouse: true
                        selectionColor: Appearance.colors.colPrimary
                        selectedTextColor: Appearance.colors.colOnPrimary

                        function commitEdit() {
                            if (!keybindRow.isEditing) return;
                            const newDesc = inlineEditField.text.trim();
                            if (newDesc && newDesc !== keybindRow.entry.description) {
                                KeybindsService.updateKeybind(
                                    root.pageId,
                                    keybindRow.entry.id,
                                    keybindRow.entry.keys,
                                    newDesc,
                                    keybindRow.entry.category,
                                    keybindRow.entry.context,
                                    keybindRow.entry.notes,
                                    keybindRow.entry.icon
                                );
                                KeybindsService.flush();
                            }
                            keybindRow.isEditing = false;
                        }

                        function cancelEdit() {
                            keybindRow.isEditing = false;
                        }

                        onAccepted: commitEdit()
                        Keys.onEscapePressed: cancelEdit()
                    }
                }
            }

            Row {
                id: editActionsRow
                visible: keybindRow.isEditing
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                RippleButton {
                    id: saveButton
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colBackgroundActive: Appearance.colors.colPrimaryActive
                    Accessible.name: Translation.tr("Save changes")
                    onClicked: inlineEditField.commitEdit()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "done"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnPrimary
                    }

                    StyledToolTip {
                        extraVisibleCondition: saveButton.hovered
                        text: Translation.tr("Save (Enter)")
                    }
                }

                RippleButton {
                    id: cancelButton
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    Accessible.name: Translation.tr("Cancel")
                    onClicked: inlineEditField.cancelEdit()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledToolTip {
                        extraVisibleCondition: cancelButton.hovered
                        text: Translation.tr("Cancel (Esc)")
                    }
                }
            }

            Row {
                id: normalActionsRow
                visible: !keybindRow.isEditing
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                RippleButton {
                    id: modeOrEditButton
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    visible: root.hasContext(keybindRow.entry.context) || keybindRow.isEditAreaHovered
                    colBackground: modeOrEditButton.hovered ? ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.90) : "transparent"
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.86)
                    Accessible.name: keybindRow.isEditAreaHovered
                        ? Translation.tr("Rename shortcut")
                        : String(keybindRow.entry.context ?? "")
                    onClicked: {
                        keybindRow.isEditing = true;
                        inlineEditField.text = String(keybindRow.entry.description ?? "");
                        inlineEditField.forceActiveFocus();
                        inlineEditField.selectAll();
                    }

                    contentItem: Item {
                        anchors.fill: parent

                        MaterialSymbol {
                            id: contextSymbol
                            anchors.centerIn: parent
                            visible: root.hasContext(keybindRow.entry.context)
                            opacity: (keybindRow.isEditAreaHovered || keybindRow.isEditing) ? 0 : 1
                            text: root.contextIcon(keybindRow.entry.context)
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colTertiary

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(contextSymbol)
                            }
                        }

                        MaterialSymbol {
                            id: editSymbol
                            anchors.centerIn: parent
                            opacity: keybindRow.isEditAreaHovered ? 1 : 0
                            text: "edit"
                            iconSize: Appearance.font.pixelSize.normal
                            color: modeOrEditButton.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(editSymbol)
                            }
                        }
                    }

                    StyledToolTip {
                        extraVisibleCondition: modeOrEditButton.hovered
                        text: keybindRow.isEditAreaHovered
                            ? Translation.tr("Click to rename")
                            : String(keybindRow.entry.context ?? "")
                    }
                }

                RippleButton {
                    id: chevronButton
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: chevronButton.hovered ? ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.90) : "transparent"
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.86)
                    Accessible.name: Translation.tr("Open sidebar details")
                    onClicked: root.editEntry(keybindRow.entry)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_right"
                        iconSize: Appearance.font.pixelSize.normal
                        color: chevronButton.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    }

                    StyledToolTip {
                        extraVisibleCondition: chevronButton.hovered
                        text: Translation.tr("Open details in sidebar")
                    }
                }
            }
        }
    }

    component StatChip: Rectangle {
        id: statChip
        property string symbol: ""
        property string label: ""
        property color chipColor: Appearance.colors.colSecondaryContainer
        property color chipTextColor: Appearance.colors.colOnSecondaryContainer

        implicitWidth: statRow.implicitWidth + 16
        implicitHeight: 28
        radius: Appearance.rounding.full
        color: statChip.chipColor

        Row {
            id: statRow
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: statChip.symbol
                iconSize: Appearance.font.pixelSize.small
                color: statChip.chipTextColor
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: statChip.label
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: statChip.chipTextColor
            }
        }
    }

    component SectionCard: Rectangle {
        id: sectionCard
        required property var group
        required property int index
        readonly property int accentIndex: index % 3
        readonly property color accentColor: accentIndex === 0
            ? Appearance.colors.colPrimaryContainer
            : (accentIndex === 1 ? Appearance.colors.colSecondaryContainer : Appearance.colors.colTertiaryContainer)
        readonly property color onAccentColor: accentIndex === 0
            ? Appearance.colors.colOnPrimaryContainer
            : (accentIndex === 1 ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnTertiaryContainer)
        width: root.cardWidth
        implicitHeight: sectionContent.implicitHeight + 24
        readonly property int columnIndex: root.getColumnIndex(index)
        readonly property real groupY: root.getGroupY(index)
        x: columnIndex * (root.cardWidth + root.cardGap)
        y: groupY
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh
        opacity: root.isCategorizing ? 0 : 1

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(sectionCard)
        }

        Behavior on x {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(sectionCard)
        }

        Behavior on y {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(sectionCard)
        }

        onImplicitHeightChanged: root.bumpLayout()

        ColumnLayout {
            id: sectionContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.categoryIcon(sectionCard.group.name)
                    iconSize: Appearance.font.pixelSize.larger
                    fill: 1
                    color: sectionCard.accentIndex === 0
                        ? Appearance.colors.colPrimary
                        : (sectionCard.accentIndex === 1 ? Appearance.colors.colSecondary : Appearance.colors.colTertiary)
                }

                StyledText {
                    Layout.fillWidth: true
                    text: String(sectionCard.group.name ?? Translation.tr("General"))
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                Rectangle {
                    implicitWidth: Math.max(28, sectionCount.implicitWidth + 12)
                    implicitHeight: 28
                    radius: Appearance.rounding.full
                    color: sectionCard.accentColor

                    StyledText {
                        id: sectionCount
                        anchors.centerIn: parent
                        text: String((sectionCard.group.entries ?? []).length)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: sectionCard.onAccentColor
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: sectionCard.group.entries ?? []
                    delegate: KeybindRow {
                        required property var modelData
                        Layout.fillWidth: true
                        entry: modelData
                        categoryName: String(sectionCard.group.name ?? "")
                    }
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 10

        Item {
            id: mainContent
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                id: mainColumn
                anchors.fill: parent
                spacing: 10

            RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 10

            MaterialShape {
                implicitSize: 50
                shape: MaterialShape.Shape.Cookie9Sided
                color: Appearance.colors.colPrimaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: String(root.page?.icon ?? "keyboard")
                    iconSize: Appearance.font.pixelSize.huge
                    fill: 1
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: String(root.page?.name ?? Translation.tr("Shortcuts"))
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.title
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 5

                    StatChip {
                        visible: Boolean(root.page?.program) && String(root.page?.program) !== String(root.page?.name)
                        symbol: "apps"
                        label: String(root.page?.program ?? "")
                    }

                    StatChip {
                        symbol: "keyboard"
                        label: String((root.page?.keybinds ?? []).length)
                    }

                    StatChip {
                        symbol: "category"
                        label: String(root.categoryCount)
                        chipColor: Appearance.colors.colTertiaryContainer
                        chipTextColor: Appearance.colors.colOnTertiaryContainer
                    }

                    StatChip {
                        visible: Boolean(root.page?.sourceKind) && root.page?.sourceKind !== "manual"
                        symbol: root.sourceIcon(root.page?.sourceKind)
                        label: root.sourceLabel(root.page?.sourceKind)
                        chipColor: Appearance.colors.colPrimaryContainer
                        chipTextColor: Appearance.colors.colOnPrimaryContainer
                    }
                }
            }

            RippleButton {
                id: aiCategorizeButton
                implicitWidth: 42
                implicitHeight: 42
                buttonRadius: Appearance.rounding.full
                readonly property bool isCategorizing: KeybindsService.aiCategorizing && KeybindsService.aiCategorizingPageId === root.pageId
                readonly property bool isDone: root.aiSuccess && !isCategorizing
                readonly property string activeAiModelName: (typeof Ai !== "undefined" && Ai.currentModelEntry?.name)
                    ? Ai.currentModelEntry.name
                    : ((typeof Ai !== "undefined" && Ai.currentModelId) ? Ai.currentModelId : "AI")
                toggled: isCategorizing || isDone
                colBackground: isDone
                    ? Appearance.colors.colPrimary
                    : (isCategorizing ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2)
                colBackgroundHover: isDone
                    ? Appearance.colors.colPrimaryHover
                    : (isCategorizing ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover)
                enabled: !KeybindsService.aiCategorizing && (root.page?.keybinds ?? []).length > 0
                Accessible.name: Translation.tr("Organize categories with %1").arg(activeAiModelName)
                onClicked: KeybindsService.aiCategorizePage(
                    root.pageId,
                    typeof Ai !== "undefined" ? Ai.currentModelId : "",
                    typeof Translation !== "undefined" ? Translation.languageCode : ""
                )

                contentItem: Item {
                    anchors.fill: parent

                    MaterialSymbol {
                        id: aiIcon
                        anchors.centerIn: parent
                        text: aiCategorizeButton.isCategorizing
                            ? "progress_activity"
                            : (aiCategorizeButton.isDone ? "check" : "auto_awesome")
                        iconSize: Appearance.font.pixelSize.larger
                        fill: (aiCategorizeButton.isCategorizing || aiCategorizeButton.isDone) ? 0 : 1
                        color: aiCategorizeButton.isDone
                            ? Appearance.colors.colOnPrimary
                            : (aiCategorizeButton.isCategorizing
                                ? Appearance.colors.colOnPrimaryContainer
                                : (aiCategorizeButton.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface))

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        NumberAnimation {
                            id: spinAnim
                            target: aiIcon
                            property: "rotation"
                            running: aiCategorizeButton.isCategorizing
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 1000
                        }

                        Connections {
                            target: aiCategorizeButton
                            function onIsCategorizingChanged() {
                                if (!aiCategorizeButton.isCategorizing)
                                    aiIcon.rotation = 0;
                            }
                        }
                    }
                }

                StyledToolTip {
                    text: aiCategorizeButton.isDone
                        ? Translation.tr("Shortcuts categorized successfully!")
                        : (aiCategorizeButton.isCategorizing
                            ? Translation.tr("Organizing categories with %1...").arg(aiCategorizeButton.activeAiModelName)
                            : Translation.tr("Organize categories with %1").arg(aiCategorizeButton.activeAiModelName))
                }
            }

            RippleButton {
                implicitWidth: 42
                implicitHeight: 42
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                Accessible.name: Translation.tr("Export page as JSON")
                onClicked: KeybindsService.openExportDialog(root.pageId)

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "download"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurface
                }

                StyledToolTip { text: Translation.tr("Export page as JSON") }
            }

            RippleButton {
                implicitWidth: 42
                implicitHeight: 42
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                Accessible.name: Translation.tr("Edit page")
                onClicked: root.requestEditPage()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "edit"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurface
                }

                StyledToolTip { text: Translation.tr("Edit page") }
            }

            RippleButtonWithIcon {
                visible: root.confirmingDelete
                implicitHeight: 42
                implicitWidth: contentImplicitWidth + 24
                centerContent: true
                buttonRadius: Appearance.rounding.full
                materialIcon: "delete_forever"
                mainText: Translation.tr("Delete page")
                colBackground: Appearance.colors.colError
                colBackgroundHover: Appearance.colors.colErrorHover
                colText: Appearance.colors.colOnError
                onClicked: {
                    root.confirmingDelete = false;
                    KeybindsService.deletePage(root.pageId);
                }
            }

            RippleButton {
                implicitWidth: 42
                implicitHeight: 42
                buttonRadius: Appearance.rounding.full
                colBackground: root.confirmingDelete ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                colBackgroundHover: root.confirmingDelete ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colErrorContainer
                Accessible.name: root.confirmingDelete ? Translation.tr("Cancel") : Translation.tr("Delete page")
                onClicked: {
                    root.confirmingDelete = !root.confirmingDelete;
                    if (root.confirmingDelete)
                        deleteConfirmationTimer.restart();
                    else
                        deleteConfirmationTimer.stop();
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.confirmingDelete ? "close" : "delete"
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.confirmingDelete ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                }

                StyledToolTip { text: root.confirmingDelete ? Translation.tr("Cancel") : Translation.tr("Delete page") }
            }
        }

        StyledFlickable {
            id: contentFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: contentColumn.implicitHeight + 12

            ColumnLayout {
                id: contentColumn
                width: contentFlickable.width
                spacing: 10

                Item {
                    id: aiLoadingContainer
                    visible: opacity > 0.001
                    opacity: root.isCategorizing ? 1 : 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.isCategorizing ? Math.max(280, contentFlickable.height - 40) : 0
                    clip: true

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(aiLoadingContainer)
                    }
                    Behavior on Layout.preferredHeight {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(aiLoadingContainer)
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 20
                        width: Math.min(420, parent.width - 40)

                        MaterialLoadingIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            implicitSize: 64
                            loading: root.isCategorizing
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: Translation.tr("Organizing shortcuts with %1").arg(aiCategorizeButton.activeAiModelName)
                                font.family: Appearance.font.family.title
                                font.variableAxes: Appearance.font.variableAxes.title
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurface
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: root.aiProgressMessage()
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colPrimary
                                wrapMode: Text.Wrap
                                elide: Text.ElideNone
                            }
                        }

                        StyledIndeterminateProgressBar {
                            Layout.fillWidth: true
                            visible: root.isCategorizing
                        }
                    }
                }

                Item {
                    id: groupsArea
                    visible: opacity > 0.001
                    opacity: root.isCategorizing ? 0 : 1
                    Layout.fillWidth: true
                    implicitHeight: totalContentHeight

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(groupsArea)
                    }

                    property int layoutRevision: 0
                    readonly property real totalContentHeight: {
                        const revision = layoutRevision;
                        const heights = root.emptyColumnHeights();
                        for (let index = 0; index < groupRepeater.count; index++) {
                            const cardHeight = root.groupHeight(index);
                            if (cardHeight <= 0)
                                continue;
                            let column = 0;
                            for (let candidate = 1; candidate < root.columnCount; candidate++) {
                                if (heights[candidate] < heights[column])
                                    column = candidate;
                            }
                            heights[column] += cardHeight + root.cardGap;
                        }
                        return Math.max(0, Math.max(...heights) - root.cardGap);
                    }

                    onWidthChanged: root.bumpLayout()

                    Repeater {
                        id: groupRepeater
                        model: groupOrderModel
                        delegate: SectionCard {
                            required property string groupKey
                            group: root.groupForKey(groupKey)
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: emptyState.shown ? 240 : 0

                    PagePlaceholder {
                        id: emptyState
                        shown: root.totalMatches === 0 && !root.isCategorizing
                        icon: root.searchText ? "search_off" : "keyboard_alt"
                        title: root.searchText ? Translation.tr("No matching shortcuts") : Translation.tr("This page is ready")
                        description: root.searchText
                            ? Translation.tr("Try another phrase or clear the filter.")
                            : Translation.tr("Use Add keybind to create the first shortcut.")
                        animateIconOnShow: false
                    }
                }
            }
        }

        }

        Item {
            id: bottomActions
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            height: 56
            z: 5
            visible: opacity > 0
            opacity: root.isTabActive ? 1 : 0
            enabled: root.isTabActive

            transform: Translate {
                y: root.isTabActive ? 0 : 35
            }

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Behavior on transform {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            RippleButtonWithIcon {
                id: addKeybindButton
                anchors.right: extraOptions.left
                anchors.rightMargin: 12
                anchors.verticalCenter: extraOptions.verticalCenter
                materialIcon: "add"
                materialIconFill: true
                mainText: Translation.tr("Add keybind")
                colText: Appearance.colors.colOnPrimaryContainer
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                buttonRadius: Appearance.rounding.small
                buttonRadiusPressed: Appearance.rounding.full
                implicitHeight: 56
                leftPadding: 0
                rightPadding: 0
                readonly property real dw: width - 56
                width: hovered ? (24 + 8 + buttonText.implicitWidth + 32) : 56

                Behavior on width {
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                }

                contentItem: Item {
                    id: addButtonContent
                    clip: true

                    Row {
                        id: addButtonRow
                        anchors.centerIn: parent
                        spacing: Math.min(8, addKeybindButton.dw)

                        MaterialSymbol {
                            text: addKeybindButton.materialIcon
                            iconSize: Appearance.font.pixelSize.larger
                            color: addKeybindButton.colText
                            fill: addKeybindButton.materialIconFill ? 1 : 0
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            id: buttonText
                            text: addKeybindButton.mainText
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: addKeybindButton.colText
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, addKeybindButton.dw - addButtonRow.spacing)
                            clip: true
                            opacity: addKeybindButton.hovered ? 1 : 0

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                    }
                }

                StyledToolTip { text: Translation.tr("Ctrl + N") }
                onClicked: editorSidebar.openCreate()
            }

            Toolbar {
                id: extraOptions
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                enableShadow: false
                colBackground: Appearance.colors.colSecondaryContainer

                ToolbarTextField {
                    id: filterField
                    placeholderText: focus ? Translation.tr("Filter shortcuts") : Translation.tr("Hit \"/\" to filter")
                    clip: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    onTextChanged: root.searchText = text
                    keyNavTarget: root.keyNavTarget
                }

                IconToolbarButton {
                    implicitWidth: height
                    text: "close"
                    enabled: filterField.text.length > 0
                    onClicked: filterField.text = ""
                    StyledToolTip { text: Translation.tr("Clear filter") }
                }
            }
        }
    }

    Item {
        id: editorSlot
        Layout.fillHeight: true
        Layout.preferredWidth: editorSidebar.isOpen || editorSidebar.isAnimating
            ? Math.max(370, Math.min(440, root.width * 0.32))
            : 0
        visible: Layout.preferredWidth > 1
        clip: true

        Behavior on Layout.preferredWidth {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(editorSlot)
        }

        CheatsheetKeybindEditorSidebar {
            id: editorSidebar
            width: editorSlot.width
            height: editorSlot.height
            anchors.right: parent.right
            pageId: root.pageId
            keyNavTarget: root.keyNavTarget
            onCloseRequested: Qt.callLater(() => filterField.forceActiveFocus())
        }
    }

    Shortcut {
        enabled: root.isTabActive && !editorSidebar.isOpen && !editorSidebar.isAnimating
        sequence: "/"
        onActivated: filterField.forceActiveFocus()
    }

    Shortcut {
        enabled: root.isTabActive && !editorSidebar.isOpen && !editorSidebar.isAnimating
        sequence: "Ctrl+N"
        onActivated: editorSidebar.openCreate()
    }

    Shortcut {
        enabled: root.isTabActive
        sequence: "Escape"
        onActivated: {
            if (editorSidebar.isOpen || editorSidebar.isAnimating) {
                editorSidebar.close();
            } else if (root.searchText !== "") {
                filterField.text = "";
                filterField.forceActiveFocus();
            }
        }
    }
    }

}
