pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "../../common/functions/emojiHues.js" as EmojiHues

Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: 0
    property string selectedCategory: Config.options.search.modules.emojis.defaultCategory
    property string noticeText: ""
    property int loadedEntryLimit: Math.max(1, root.pageSize)
    property bool loadMorePending: false
    property bool pageModelUpdating: false
    property bool paginationReady: false

    readonly property bool supportsSectionToggle: true
    readonly property int gridColumns: {
        const configured = Number(Config.options?.search?.modules?.emojis?.gridColumns ?? 7);
        return isFinite(configured) ? Math.max(5, Math.min(8, Math.round(configured))) : 7;
    }
    readonly property int pageRows: 6
    readonly property int pageSize: Math.max(1, root.gridColumns * root.pageRows)
    readonly property real gridSpacing: Appearance.sizes.elevationMargin / 2
    readonly property real headerPillWidth: Appearance.sizes.elevationMargin * 21
    readonly property real emojiGlyphSize: Math.round(Appearance.font.pixelSize.hugeass * 1.6)
    readonly property var categories: {
        const rows = [
            { id: "all", label: Translation.tr("All categories"), icon: "category" },
            { id: "people", label: Translation.tr("People"), icon: "face" },
            { id: "nature", label: Translation.tr("Nature"), icon: "nature" },
            { id: "food", label: Translation.tr("Food"), icon: "restaurant" },
            { id: "objects", label: Translation.tr("Objects"), icon: "lightbulb" },
            { id: "symbols", label: Translation.tr("Symbols"), icon: "tag" }
        ];
        if (Config.options.search.modules.emojis.showRecents && (Persistent.states.search.recentEmojis?.length ?? 0) > 0)
            rows.splice(1, 0, { id: "recent", label: Translation.tr("Recent"), icon: "history" });
        return rows;
    }
    // Ask for one extra entry so pagination can detect whether another page
    // exists without evaluating the complete emoji corpus in the panel.
    readonly property var pagedEntries: root.filteredEmojiEntries(root.loadedEntryLimit + 1)
    readonly property bool hasMoreEntries: root.pagedEntries.length > root.loadedEntryLimit
    readonly property var filteredEntries: root.pagedEntries.slice(0, root.loadedEntryLimit)
    readonly property var selectedEntry: root.selectedIndex >= 0 && root.selectedIndex < root.filteredEntries.length
        ? root.filteredEntries[root.selectedIndex]
        : null
    readonly property string selectedCategoryLabel: root.categories.find(category => category.id === root.selectedCategory)?.label
        ?? Translation.tr("All categories")
    readonly property string statusText: root.noticeText.length > 0
        ? root.noticeText
        : (root.selectedEntry
            ? root.skinToneEmoji(root.selectedEntry) + "  " + String(root.selectedEntry.name ?? "")
            : (Emojis.loading ? Translation.tr("Preparing emoji library…") : Translation.tr("No emojis found")))

    implicitWidth: Config.options.search.appearance.panelWidth
    implicitHeight: scaffold.implicitHeight

    function filteredEmojiEntries(limit) {
        return Emojis.queryEntries(
            root.searchQuery,
            root.selectedCategory,
            limit,
            Persistent.states.search.recentEmojis ?? []
        );
    }

    function resetPagination(): void {
        root.loadMorePending = false;
        root.loadedEntryLimit = root.pageSize;
        root.selectedIndex = 0;
        root.pageModelUpdating = true;
        emojiPageModel.clear();
        root.pageModelUpdating = false;
        Qt.callLater(function() {
            root.syncPageModel();
            if (root.filteredEntries.length > 0)
                emojiGrid.positionViewAtIndex(0, GridView.Beginning);
        });
    }

    function syncPageModel(): void {
        const entries = root.filteredEntries;
        root.pageModelUpdating = true;
        let appendOnly = emojiPageModel.count <= entries.length;
        if (appendOnly) {
            for (let index = 0; index < emojiPageModel.count; index++) {
                const current = emojiPageModel.get(index);
                if (String(current.raw) !== String(entries[index]?.raw ?? "")) {
                    appendOnly = false;
                    break;
                }
            }
        }
        if (!appendOnly)
            emojiPageModel.clear();
        for (let index = emojiPageModel.count; index < entries.length; index++) {
            const entry = entries[index];
            emojiPageModel.append({
                raw: String(entry?.raw ?? ""),
                emoji: String(entry?.emoji ?? ""),
                name: String(entry?.name ?? ""),
                category: String(entry?.category ?? "objects")
            });
        }
        root.pageModelUpdating = false;
    }

    function loadMoreEntries(): void {
        if (root.pageModelUpdating || root.loadMorePending || !root.hasMoreEntries)
            return;
        root.loadMorePending = true;
        // Defer the model expansion until the current scroll/input frame ends.
        // GridView only keeps visible delegates plus one cached row alive and
        // reuses them as the user advances, so emojis left behind are unloaded
        // from the rendered scene without breaking upward navigation.
        Qt.callLater(function() {
            if (root.hasMoreEntries)
                root.loadedEntryLimit += root.pageSize;
            root.loadMorePending = false;
        });
    }

    function skinToneEmoji(entry) {
        const emoji = String(entry?.emoji ?? "");
        const tone = String(Config.options.search.modules.emojis.skinTone ?? "none");
        const modifiers = { light: "🏻", mediumLight: "🏼", medium: "🏽", mediumDark: "🏾", dark: "🏿" };
        if (tone === "none" || !modifiers[tone] || entry?.category !== "people" || /[🏻-🏿]/.test(emoji))
            return emoji;
        return emoji + modifiers[tone];
    }

    function toneLabel() {
        const labels = {
            none: Translation.tr("Default tone"), light: Translation.tr("Light tone"),
            mediumLight: Translation.tr("Medium-light tone"), medium: Translation.tr("Medium tone"),
            mediumDark: Translation.tr("Medium-dark tone"), dark: Translation.tr("Dark tone")
        };
        return labels[String(Config.options.search.modules.emojis.skinTone ?? "none")] ?? labels.none;
    }

    function cycleTone() {
        const tones = ["none", "light", "mediumLight", "medium", "mediumDark", "dark"];
        const current = String(Config.options.search.modules.emojis.skinTone ?? "none");
        Config.options.search.modules.emojis.skinTone = tones[(tones.indexOf(current) + 1) % tones.length];
        root.showNotice(root.toneLabel());
    }

    function remember(entry) {
        if (!entry)
            return;
        const previous = Array.from(Persistent.states.search.recentEmojis ?? []).filter(raw => raw !== entry.raw);
        Persistent.states.search.recentEmojis = [entry.raw].concat(previous).slice(0, 32);
    }
    function clampSelection() {
        root.selectedIndex = root.filteredEntries.length === 0 ? -1 : Math.max(0, Math.min(root.selectedIndex, root.filteredEntries.length - 1));
    }
    function ensureVisible() {
        if (root.selectedIndex >= 0) {
            emojiGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
            if (root.selectedIndex >= root.filteredEntries.length - root.gridColumns * 2)
                root.loadMoreEntries();
        }
    }
    function navigateUp(): bool {
        if (root.selectedIndex >= root.gridColumns)
            root.selectedIndex -= root.gridColumns;
        root.ensureVisible();
        return true;
    }
    function navigateDown(): bool {
        if (root.selectedIndex >= 0 && root.selectedIndex + root.gridColumns < root.filteredEntries.length)
            root.selectedIndex += root.gridColumns;
        root.ensureVisible();
        return true;
    }
    function navigateLeft(): bool {
        if (root.selectedIndex > 0)
            root.selectedIndex--;
        root.ensureVisible();
        return true;
    }
    function navigateRight(): bool {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.filteredEntries.length - 1)
            root.selectedIndex++;
        root.ensureVisible();
        return true;
    }
    function activateSelected(): bool {
        if (!root.selectedEntry)
            return false;
        const emoji = root.skinToneEmoji(root.selectedEntry);
        Quickshell.clipboardText = emoji;
        root.remember(root.selectedEntry);
        root.showNotice(Translation.tr("%1 copied to clipboard").arg(emoji));
        return true;
    }
    function copySelected(): bool { return root.activateSelected(); }
    function focusInput(): bool { return false; }
    function toggleSection(): bool {
        const current = root.categories.findIndex(category => category.id === root.selectedCategory);
        root.selectCategory(root.categories[(current + 1) % root.categories.length].id);
        return true;
    }
    function selectCategory(category) {
        root.selectedCategory = category;
        Config.options.search.modules.emojis.defaultCategory = category;
        root.resetPagination();
    }
    function showNotice(message) {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    onSearchQueryChanged: {
        if (root.paginationReady)
            root.resetPagination();
    }
    onGridColumnsChanged: {
        if (root.paginationReady)
            root.resetPagination();
    }
    onFilteredEntriesChanged: {
        root.clampSelection();
        root.syncPageModel();
    }
    Component.onCompleted: {
        root.paginationReady = true;
        root.resetPagination();
        Emojis.load();
    }

    Timer { id: noticeTimer; interval: 3200; onTriggered: root.noticeText = "" }
    ListModel { id: emojiPageModel }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Emojis")
        icon: "mood"
        accent: true
        showStatus: true
        statusText: root.statusText
        primaryHint: ({ label: Translation.tr("Copy"), actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("Category"), actionId: "section", keys: ["Tab"] },
            { label: Translation.tr("Navigate"), keys: ["↑", "↓", "←", "→"] }
        ]

        ColumnLayout {
            width: parent.width
            height: parent.height
            spacing: Appearance.sizes.elevationMargin

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2
                StyledText {
                    Layout.fillWidth: true
                    text: root.hasMoreEntries
                        ? Translation.tr("%1+ results").arg(String(root.filteredEntries.length))
                        : Translation.tr("%1 results").arg(String(root.filteredEntries.length))
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
                RippleButton {
                    Layout.preferredWidth: root.headerPillWidth
                    implicitHeight: categoryPicker.implicitHeight
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: root.cycleTone()
                    RowLayout {
                        id: toneContent
                        anchors.fill: parent
                        anchors.leftMargin: Appearance.sizes.elevationMargin
                        anchors.rightMargin: Appearance.sizes.elevationMargin
                        spacing: Appearance.sizes.elevationMargin / 2
                        StyledText { text: root.skinToneEmoji({ emoji: "👋", category: "people" }); font.pixelSize: Appearance.font.pixelSize.normal }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.toneLabel()
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }
                StyledComboBox {
                    id: categoryPicker
                    Layout.preferredWidth: root.headerPillWidth
                    Layout.fillWidth: false
                    model: root.categories
                    textRole: "label"
                    valueRole: "id"
                    buttonIcon: "category"
                    currentIndex: Math.max(0, root.categories.findIndex(category => category.id === root.selectedCategory))
                    onActivated: index => root.selectCategory(root.categories[index].id)
                }
            }

            GridView {
                id: emojiGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.filteredEntries.length > 0
                clip: true
                reuseItems: true
                cacheBuffer: cellHeight
                model: emojiPageModel
                cellWidth: width / root.gridColumns
                cellHeight: cellWidth
                onAtYEndChanged: {
                    if (atYEnd)
                        root.loadMoreEntries();
                }

                delegate: Item {
                    id: emojiDelegate
                    required property int index
                    required property string raw
                    required property string emoji
                    required property string name
                    required property string category
                    readonly property var entry: ({
                        raw: emojiDelegate.raw,
                        emoji: emojiDelegate.emoji,
                        name: emojiDelegate.name,
                        category: emojiDelegate.category
                    })
                    readonly property bool selected: root.selectedIndex === index
                    readonly property color selectedColor: ColorUtils.categoryAccent(
                        EmojiHues.hueForCategory(emojiDelegate.category),
                        1,
                        Appearance.m3colors.m3primary
                    )
                    width: emojiGrid.cellWidth
                    height: emojiGrid.cellHeight
                    RippleButton {
                        anchors.fill: parent
                        anchors.margins: root.gridSpacing / 2
                        toggled: root.selectedIndex === index
                        buttonRadius: emojiDelegate.selected ? Appearance.rounding.verylarge : Appearance.rounding.normal
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                        colBackgroundActive: Appearance.colors.colSurfaceContainerHighestActive
                        colBackgroundToggled: emojiDelegate.selectedColor
                        colBackgroundToggledHover: ColorUtils.mix(emojiDelegate.selectedColor, Appearance.colors.colOnSurface, 0.9)
                        colBackgroundToggledActive: ColorUtils.mix(emojiDelegate.selectedColor, Appearance.colors.colOnSurface, 0.82)
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        colRippleToggled: Appearance.colors.colPrimaryContainerActive
                        onClicked: root.selectedIndex = index
                        onDoubleClicked: root.activateSelected()
                        StyledText {
                            anchors.centerIn: parent
                            text: root.skinToneEmoji(emojiDelegate.entry)
                            font.pixelSize: root.emojiGlyphSize
                            color: Appearance.colors.colOnSurface
                        }

                        ConfiguredKeyHint {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: Appearance.sizes.elevationMargin / 2
                            visible: emojiDelegate.selected && Config.options.search.appearance.showKeyHints
                            actionId: "activate"
                            fallbackKeys: ["↵"]
                            surface: emojiDelegate.selectedColor
                            onSurface: ColorUtils.getContrastingTextColor(emojiDelegate.selectedColor)
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.filteredEntries.length === 0
                spacing: Appearance.sizes.elevationMargin / 2
                MaterialLoadingIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: Appearance.sizes.elevationMargin * 4
                    implicitHeight: implicitWidth
                    visible: Emojis.loading
                }
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !Emojis.loading
                    text: "sentiment_dissatisfied"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Emojis.loading ? Translation.tr("Preparing emoji library…") : Translation.tr("No emojis found")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
