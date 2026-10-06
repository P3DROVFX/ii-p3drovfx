pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
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

    // Every motion in the overview and its panels answers to one switch:
    // Settings -> Overview -> Animation style -> None.
    readonly property bool animationsDisabled: Config.options.overview.animationStyle === "none"
    readonly property bool supportsSectionToggle: true
    readonly property var toneIds: ["none", "light", "mediumLight", "medium", "mediumDark", "dark"]
    readonly property string currentTone: String(Config.options.search.modules.emojis.skinTone ?? "none")
    readonly property real heroWidth: 264
    readonly property int gridColumns: {
        const configured = Number(Config.options?.search?.modules?.emojis?.gridColumns ?? 7);
        return isFinite(configured) ? Math.max(5, Math.min(8, Math.round(configured))) : 7;
    }
    readonly property int pageRows: 6
    readonly property int pageSize: Math.max(1, root.gridColumns * root.pageRows)
    readonly property real gridSpacing: Appearance.sizes.elevationMargin / 2
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

    function setTone(tone) {
        Config.options.search.modules.emojis.skinTone = tone;
    }

    /// The hero's backdrop shape: each category has its own, and the shape morphs as the
    /// selection crosses from one category to the next.
    function shapeForCategory(category) {
        return ({
            people: "Sunny",
            nature: "Flower",
            food: "Cookie6Sided",
            objects: "PuffyDiamond",
            symbols: "SoftBurst"
        })[category] ?? "Cookie12Sided";
    }

    /// The corpus line after the glyph is its name followed by keywords, often with the
    /// name's words repeated; read it once each.
    function displayName(entry) {
        const seen = new Set();
        return String(entry?.name ?? "").split(/\s+/).filter(word => {
            const key = word.toLocaleLowerCase();
            if (word.length === 0 || seen.has(key))
                return false;
            seen.add(key);
            return true;
        }).join(" ");
    }

    function categoryLabel(category) {
        return root.categories.find(row => row.id === category)?.label ?? "";
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
        primaryHint: ({ label: Translation.tr("Copy"), actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("Category"), actionId: "section", keys: ["Tab"] },
            { label: Translation.tr("Navigate"), keys: ["↑", "↓", "←", "→"] }
        ]

        RowLayout {
            anchors.fill: parent
            spacing: ClockStyle.paneGap

            // ── Hero: the selected emoji, as the one thing the panel is about ──
            // The pane takes the selection's category hue; everything on it is tinted
            // with the pane's own content colour.
            Rectangle {
                id: hero
                readonly property var entry: root.selectedEntry
                readonly property color colPane: hero.entry
                    ? ColorUtils.categoryAccent(EmojiHues.hueForCategory(hero.entry.category), 1, Appearance.m3colors.m3primary)
                    : ClockStyle.colSurfaceHigh
                readonly property color colContent: hero.entry
                    ? ColorUtils.getContrastingTextColor(hero.colPane)
                    : ClockStyle.colOnSurfaceVariant

                Layout.preferredWidth: root.heroWidth
                Layout.fillWidth: false
                Layout.fillHeight: true
                radius: ClockStyle.radiusCard
                color: hero.colPane
                Behavior on color {
                    enabled: !root.animationsDisabled
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: ClockStyle.cardPadding - 4
                    spacing: ClockStyle.gapSmall

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        text: (hero.entry ? root.categoryLabel(hero.entry.category) : Translation.tr("Emojis")).toUpperCase()
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        font.letterSpacing: 1.4
                        color: hero.colContent
                        opacity: 0.72
                    }

                    Item {
                        id: stage
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly property real side: Math.min(stage.width, stage.height)

                        MaterialShape {
                            anchors.centerIn: parent
                            implicitSize: Math.round(stage.side)
                            shapeString: root.shapeForCategory(hero.entry?.category ?? "")
                            color: ColorUtils.applyAlpha(hero.colContent, 0.13)
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: hero.entry !== null
                            text: hero.entry ? root.skinToneEmoji(hero.entry) : ""
                            font.pixelSize: Math.round(stage.side * 0.5)
                            color: hero.colContent
                        }

                        MaterialLoadingIndicator {
                            anchors.centerIn: parent
                            visible: hero.entry === null && Emojis.loading
                            implicitWidth: 48
                            implicitHeight: 48
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: hero.entry === null && !Emojis.loading
                            text: "sentiment_dissatisfied"
                            iconSize: Math.round(stage.side * 0.36)
                            fill: 1
                            color: hero.colContent
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        text: hero.entry ? root.displayName(hero.entry)
                            : (Emojis.loading ? Translation.tr("Preparing emoji library…") : Translation.tr("Nothing selected"))
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        lineHeight: 0.95
                        font.family: ClockStyle.fontTitle
                        font.variableAxes: ClockStyle.axesTitle
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: hero.colContent
                    }

                    // Skin tone: six hands, the chosen one squared off.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapTiny

                        Repeater {
                            model: root.toneIds

                            delegate: RippleButton {
                                id: toneButton
                                required property string modelData
                                readonly property bool chosen: root.currentTone === toneButton.modelData
                                Layout.fillWidth: true
                                implicitHeight: 34
                                buttonRadius: toneButton.chosen ? Appearance.rounding.small : Appearance.rounding.full
                                colBackground: ColorUtils.applyAlpha(hero.colContent, toneButton.chosen ? 0.24 : 0.07)
                                colBackgroundHover: ColorUtils.applyAlpha(hero.colContent, toneButton.chosen ? 0.3 : 0.15)
                                colRipple: ColorUtils.applyAlpha(hero.colContent, 0.3)
                                onClicked: root.setTone(toneButton.modelData)

                                StyledText {
                                    anchors.centerIn: parent
                                    text: {
                                        const modifiers = { light: "🏻", mediumLight: "🏼", medium: "🏽", mediumDark: "🏾", dark: "🏿" };
                                        return "👋" + (modifiers[toneButton.modelData] ?? "");
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                }
                            }
                        }
                    }

                    RippleButton {
                        id: copyButton
                        readonly property bool copied: root.noticeText.length > 0
                        Layout.fillWidth: true
                        implicitHeight: 46
                        enabled: hero.entry !== null
                        opacity: enabled ? 1 : 0.4
                        buttonRadius: copyButton.copied ? Appearance.rounding.normal : Appearance.rounding.full
                        colBackground: hero.colContent
                        colBackgroundHover: ColorUtils.mix(hero.colContent, hero.colPane, 0.88)
                        colRipple: ColorUtils.mix(hero.colContent, hero.colPane, 0.7)
                        onClicked: root.activateSelected()

                        contentItem: Item {
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: ClockStyle.gapSmall

                                MaterialSymbol {
                                    text: copyButton.copied ? "check" : "content_copy"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: hero.colPane
                                }

                                StyledText {
                                    text: copyButton.copied ? Translation.tr("Copied") : Translation.tr("Copy")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                    color: hero.colPane
                                }
                            }
                        }
                    }
                }
            }

            // ── Library: categories, count and the grid ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: ClockStyle.gapSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapTiny

                    // Only the chosen category spells its name; the rest are round icons
                    // that widen into a pill when picked.
                    Repeater {
                        model: root.categories

                        delegate: RippleButton {
                            id: categoryChip
                            required property var modelData
                            readonly property bool chosen: root.selectedCategory === categoryChip.modelData.id
                            implicitHeight: 38
                            implicitWidth: categoryChip.chosen ? chipRow.implicitWidth + 30 : 38
                            buttonRadius: Appearance.rounding.full
                            toggled: categoryChip.chosen
                            colBackground: ClockStyle.colSurfaceHigh
                            colBackgroundHover: ClockStyle.colSurfaceHover
                            colBackgroundToggled: ClockStyle.colSecondaryContainer
                            colBackgroundToggledHover: ClockStyle.colSecondaryContainerHover
                            colRipple: ClockStyle.colSurfaceActive
                            colRippleToggled: ClockStyle.colSecondaryContainerActive
                            clip: true
                            onClicked: root.selectCategory(categoryChip.modelData.id)

                            Behavior on implicitWidth {
                                enabled: !root.animationsDisabled
                                animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                            }

                            contentItem: Item {
                                RowLayout {
                                    id: chipRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: categoryChip.chosen ? 15 : (parent.width - chipIcon.implicitWidth) / 2
                                    spacing: 6

                                    MaterialSymbol {
                                        id: chipIcon
                                        text: categoryChip.modelData.icon
                                        iconSize: Appearance.font.pixelSize.larger
                                        fill: categoryChip.chosen ? 1 : 0
                                        color: categoryChip.chosen ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                                    }

                                    StyledText {
                                        visible: categoryChip.chosen
                                        text: categoryChip.modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        font.weight: Font.Bold
                                        color: ClockStyle.colOnSecondaryContainer
                                    }
                                }
                            }

                            StyledToolTip {
                                text: categoryChip.modelData.label
                                extraVisibleCondition: !categoryChip.chosen
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // The count, as the panel's number.
                    StyledText {
                        Layout.alignment: Qt.AlignBaseline
                        text: String(root.filteredEntries.length) + (root.hasMoreEntries ? "+" : "")
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigitsBold
                        font.pixelSize: 30
                        color: ClockStyle.colPrimary
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignBaseline
                        Layout.rightMargin: 4
                        text: Translation.tr("results")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: ClockStyle.colSubtext
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

                        // Circle on hover, squared off once chosen: shape is state.
                        RippleButton {
                            anchors.fill: parent
                            anchors.margins: root.gridSpacing / 2
                            toggled: emojiDelegate.selected
                            buttonRadius: emojiDelegate.selected ? Appearance.rounding.normal : Appearance.rounding.full
                            colBackground: "transparent"
                            colBackgroundHover: ClockStyle.colSurfaceHigh
                            colBackgroundActive: ClockStyle.colSurfaceActive
                            colBackgroundToggled: ColorUtils.applyAlpha(emojiDelegate.selectedColor, 0.32)
                            colBackgroundToggledHover: ColorUtils.applyAlpha(emojiDelegate.selectedColor, 0.42)
                            colBackgroundToggledActive: ColorUtils.applyAlpha(emojiDelegate.selectedColor, 0.5)
                            colRipple: ClockStyle.colSurfaceActive
                            colRippleToggled: ColorUtils.applyAlpha(emojiDelegate.selectedColor, 0.5)
                            onClicked: root.selectedIndex = index
                            onDoubleClicked: root.activateSelected()

                            StyledText {
                                anchors.centerIn: parent
                                text: root.skinToneEmoji(emojiDelegate.entry)
                                font.pixelSize: Math.round(emojiGrid.cellWidth * 0.44)
                                color: ClockStyle.colOnSurface
                            }
                        }
                    }

                    TouchpadScrollHandler {
                        flickable: emojiGrid
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.filteredEntries.length === 0

                    ClockEmptyState {
                        anchors.centerIn: parent
                        visible: !Emojis.loading
                        symbol: "search_off"
                        shape: "Ghostish"
                        shapeSize: ClockStyle.emptyShapeSmall
                        title: Translation.tr("No emojis found")
                        subtitle: Translation.tr("Try another word or category")
                    }
                }
            }
        }
    }
}
