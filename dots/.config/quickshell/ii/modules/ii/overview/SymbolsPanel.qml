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
import "symbolData.js" as SymbolData

/**
 * Symbols: typographic, mathematical, box-drawing and other text symbols, plus
 * kaomoji and one-line text art. Single characters sit in a square grid; text
 * faces and art take wide cells, two per row, in the same list.
 */
Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: 0
    property string selectedCategory: String(Config.options.search.modules.symbols.defaultCategory ?? "all")
    property string noticeText: ""

    // Every motion in the overview and its panels answers to one switch:
    // Settings -> Overview -> Animation style -> None.
    readonly property bool animationsDisabled: Config.options.overview.animationStyle === "none"
    readonly property bool supportsSectionToggle: true
    readonly property real heroWidth: 264
    readonly property int gridColumns: {
        const configured = Number(Config.options?.search?.modules?.symbols?.gridColumns ?? 8);
        return isFinite(configured) ? Math.max(5, Math.min(10, Math.round(configured))) : 8;
    }
    readonly property int wideColumns: 2
    readonly property real gridSpacing: Appearance.sizes.elevationMargin / 2
    readonly property var wideCategories: ["kaomoji", "art"]

    readonly property var baseCategories: [
        { id: "all", label: Translation.tr("All categories"), icon: "category", hue: 0, shape: "Cookie12Sided" },
        { id: "typography", label: Translation.tr("Typography"), icon: "format_quote", hue: 24, shape: "Cookie7Sided" },
        { id: "letters", label: Translation.tr("Letters"), icon: "match_case", hue: 52, shape: "Arch" },
        { id: "math", label: Translation.tr("Math"), icon: "function", hue: 210, shape: "Cookie4Sided" },
        { id: "numbers", label: Translation.tr("Numbers"), icon: "pin", hue: 186, shape: "Pentagon" },
        { id: "arrows", label: Translation.tr("Arrows"), icon: "north_east", hue: 150, shape: "Arrow" },
        { id: "currency", label: Translation.tr("Currency"), icon: "payments", hue: 96, shape: "Cookie9Sided" },
        { id: "shapes", label: Translation.tr("Shapes"), icon: "interests", hue: 300, shape: "SoftBurst" },
        { id: "lines", label: Translation.tr("Lines & blocks"), icon: "border_all", hue: 240, shape: "Square" },
        { id: "technical", label: Translation.tr("Keys & technical"), icon: "keyboard_command_key", hue: 270, shape: "PixelCircle" },
        { id: "signs", label: Translation.tr("Signs"), icon: "emoji_symbols", hue: 330, shape: "Clover4Leaf" },
        { id: "kaomoji", label: Translation.tr("Kaomoji"), icon: "sentiment_very_satisfied", hue: 12, shape: "Sunny" },
        { id: "art", label: Translation.tr("Text art"), icon: "brush", hue: 120, shape: "Flower" }
    ]
    readonly property var categories: {
        const rows = root.baseCategories.slice();
        if (Config.options.search.modules.symbols.showRecents && (Persistent.states.search.recentSymbols?.length ?? 0) > 0)
            rows.splice(1, 0, { id: "recent", label: Translation.tr("Recent"), icon: "history", hue: 0, shape: "Cookie12Sided" });
        return rows;
    }
    readonly property var categoryById: {
        const map = {};
        for (const category of root.categories)
            map[category.id] = category;
        return map;
    }

    /// The corpus, built once: every row gets its lowercase haystack so a
    /// keystroke is a substring scan, not a string build.
    readonly property var corpus: {
        const words = SymbolData.categoryKeywords;
        return SymbolData.entries.map((row, order) => {
            const text = String(row[0]);
            const points = Array.from(text);
            const code = points.length === 1 ? root.codeOf(text) : "";
            return {
                text: text,
                name: String(row[1]),
                keywords: String(row[2]),
                category: String(row[3]),
                order: order,
                code: code,
                wide: root.wideCategories.indexOf(String(row[3])) >= 0,
                hay: " " + root.fold([text, row[1], row[2], code, code.slice(2)].join(" ")),
                foldedName: root.fold(row[1]),
                foldedKeywords: " " + root.fold(row[2]) + " ",
                categoryHay: " " + root.fold(words[row[3]] ?? "")
            };
        });
    }
    readonly property var corpusByText: {
        const map = {};
        for (const entry of root.corpus) {
            if (!(entry.text in map))
                map[entry.text] = entry;
        }
        return map;
    }

    readonly property var filteredEntries: root.filterEntries(root.searchQuery, root.selectedCategory,
        Persistent.states.search.recentSymbols ?? [])
    /// Rows of the list: runs of single symbols packed `gridColumns` wide and
    /// runs of wide entries packed `wideColumns` wide.
    readonly property var layout: {
        const rows = [];
        const rowOf = [];
        const entries = root.filteredEntries;
        let index = 0;
        while (index < entries.length) {
            const wide = entries[index].wide;
            const columns = wide ? root.wideColumns : root.gridColumns;
            let count = 0;
            while (index + count < entries.length && count < columns && entries[index + count].wide === wide) {
                rowOf.push(rows.length);
                count++;
            }
            rows.push({ start: index, count: count, wide: wide });
            index += count;
        }
        return { rows: rows, rowOf: rowOf };
    }
    readonly property var selectedEntry: root.selectedIndex >= 0 && root.selectedIndex < root.filteredEntries.length
        ? root.filteredEntries[root.selectedIndex]
        : null

    implicitWidth: Config.options.search.appearance.panelWidth
    implicitHeight: scaffold.implicitHeight

    function codeOf(text) {
        const point = String(text).codePointAt(0) ?? 0;
        return "U+" + point.toString(16).toUpperCase().padStart(4, "0");
    }

    /// Lowercase, accents dropped and hyphens as spaces: "Símbolo",
    /// "simbolo" and "guarda-chuva"/"guarda chuva" find the same rows.
    function fold(text) {
        return String(text ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/-/g, " ").toLocaleLowerCase();
    }
    /// Words match from their start ("cat" is not in "indicator"); a token
    /// with no letters or digits — "(", "°" — may sit anywhere.
    function hayHas(hay, token) {
        return /[\p{L}\p{N}]/u.test(token) ? hay.indexOf(" " + token) >= 0 : hay.indexOf(token) >= 0;
    }

    function filterEntries(query, category, recents) {
        let pool;
        if (category === "recent") {
            pool = Array.from(recents).map(text => root.corpusByText[text]).filter(Boolean);
        } else if (category === "all") {
            pool = root.corpus;
        } else {
            pool = root.corpus.filter(entry => entry.category === category);
        }

        const needle = root.fold(query).trim();
        const seen = new Set();
        const unique = entry => {
            if (seen.has(entry.text))
                return false;
            seen.add(entry.text);
            return true;
        };
        if (needle.length === 0)
            return pool.filter(unique);

        const raw = String(query ?? "").trim();
        const tokens = needle.split(/\s+/);
        const scored = [];
        for (const entry of pool) {
            let score;
            if (entry.text === raw) {
                score = 0;
            } else {
                const own = tokens.every(token => root.hayHas(entry.hay, token));
                // A word that only names the category ("seta", "table") finds the
                // whole category, ranked after the symbols that answer to it.
                if (!own && !tokens.every(token => root.hayHas(entry.hay, token) || root.hayHas(entry.categoryHay, token)))
                    continue;
                const name = entry.foldedName;
                if (!own)
                    score = 5;
                else if (name === needle || entry.code.toLocaleLowerCase() === needle)
                    score = 1;
                else if (name.startsWith(needle) || entry.foldedKeywords.indexOf(" " + needle + " ") >= 0)
                    score = 2;
                else if ((" " + name).indexOf(" " + tokens[0]) >= 0)
                    score = 3;
                else
                    score = 4;
            }
            if (unique(entry))
                scored.push({ entry: entry, score: score });
        }
        // Within direct and category-only matches, wide entries go after the
        // single symbols so each kind packs into whole rows instead of breaking
        // the grid at every switch.
        const tier = row => row.score >= 5 ? 1 : 0;
        scored.sort((a, b) => (tier(a) - tier(b)) || (a.entry.wide - b.entry.wide)
            || (a.score - b.score) || (a.entry.order - b.entry.order));
        return scored.map(row => row.entry);
    }

    function categoryOf(id) {
        return root.categoryById[id] ?? root.baseCategories[0];
    }
    function accentFor(id) {
        return ColorUtils.categoryAccent(root.categoryOf(id).hue, 1, Appearance.m3colors.m3primary);
    }

    function remember(entry) {
        if (!entry)
            return;
        const previous = Array.from(Persistent.states.search.recentSymbols ?? []).filter(text => text !== entry.text);
        Persistent.states.search.recentSymbols = [entry.text].concat(previous).slice(0, 40);
    }
    function clampSelection() {
        root.selectedIndex = root.filteredEntries.length === 0 ? -1 : Math.max(0, Math.min(root.selectedIndex, root.filteredEntries.length - 1));
    }
    function ensureVisible() {
        if (root.selectedIndex >= 0)
            symbolList.positionViewAtIndex(root.layout.rowOf[root.selectedIndex], ListView.Contain);
    }
    /// Moves to the same column one row up or down; between a grid row and a
    /// wide row the column is mapped by proportion.
    function moveRow(step) {
        const rows = root.layout.rows;
        const current = root.layout.rowOf[root.selectedIndex];
        if (current === undefined)
            return;
        const target = current + step;
        if (target < 0 || target >= rows.length)
            return;
        const from = rows[current];
        const to = rows[target];
        const column = root.selectedIndex - from.start;
        const fromColumns = from.wide ? root.wideColumns : root.gridColumns;
        const toColumns = to.wide ? root.wideColumns : root.gridColumns;
        const mapped = from.wide === to.wide ? column : Math.floor((column + 0.5) * toColumns / fromColumns);
        root.selectedIndex = to.start + Math.max(0, Math.min(mapped, to.count - 1));
    }
    function navigateUp(): bool {
        root.moveRow(-1);
        root.ensureVisible();
        return true;
    }
    function navigateDown(): bool {
        root.moveRow(1);
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
    function copyText(text) {
        Quickshell.clipboardText = text;
        root.showNotice(Translation.tr("%1 copied to clipboard").arg(text.indexOf("\n") >= 0 ? Translation.tr("Text art") : text));
    }
    function activateSelected(): bool {
        if (!root.selectedEntry)
            return false;
        root.copyText(root.selectedEntry.text);
        root.remember(root.selectedEntry);
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
        Config.options.search.modules.symbols.defaultCategory = category;
        root.selectedIndex = 0;
        symbolList.positionViewAtBeginning();
        const chip = root.categories.findIndex(row => row.id === category);
        if (chip >= 0)
            chipList.positionViewAtIndex(chip, ListView.Contain);
    }
    function showNotice(message) {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    onSearchQueryChanged: {
        root.selectedIndex = 0;
        symbolList.positionViewAtBeginning();
    }
    onFilteredEntriesChanged: root.clampSelection()
    Component.onCompleted: {
        // A saved category that no longer exists (or an emptied recents list)
        // falls back to everything.
        if (!root.categories.some(category => category.id === root.selectedCategory))
            root.selectedCategory = "all";
    }

    Timer { id: noticeTimer; interval: 3200; onTriggered: root.noticeText = "" }

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

            // ── Hero: the selected symbol, its name and code ──
            Rectangle {
                id: hero
                readonly property var entry: root.selectedEntry
                readonly property var category: root.categoryOf(hero.entry?.category ?? "all")
                readonly property bool multiline: (hero.entry?.text ?? "").indexOf("\n") >= 0
                readonly property color colPane: hero.entry ? root.accentFor(hero.entry.category) : ClockStyle.colSurfaceHigh
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
                        text: (hero.entry ? hero.category.label : Translation.tr("Symbols")).toUpperCase()
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

                        // The category's shape sits behind the glyph and morphs as
                        // the selection crosses into another category.
                        MaterialShape {
                            anchors.centerIn: parent
                            implicitSize: Math.round(stage.side)
                            shapeString: hero.category.shape
                            color: ColorUtils.applyAlpha(hero.colContent, 0.13)
                        }

                        StyledText {
                            anchors.centerIn: parent
                            width: hero.entry?.wide ? stage.width - 8 : stage.side * 0.8
                            height: hero.entry?.wide ? stage.side * 0.7 : stage.side * 0.8
                            visible: hero.entry !== null
                            text: hero.entry?.text ?? ""
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            fontSizeMode: Text.Fit
                            minimumPixelSize: 8
                            font.pixelSize: Math.round(stage.side * (hero.entry?.wide ? 0.22 : 0.5))
                            font.family: hero.multiline ? Appearance.font.family.monospace : Appearance.font.family.main
                            lineHeight: hero.multiline ? 1.0 : 1.1
                            color: hero.colContent
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: hero.entry === null
                            text: "search_off"
                            iconSize: Math.round(stage.side * 0.36)
                            fill: 1
                            color: hero.colContent
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        text: hero.entry ? hero.entry.name : Translation.tr("Nothing selected")
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        lineHeight: 0.95
                        font.family: ClockStyle.fontTitle
                        font.variableAxes: ClockStyle.axesTitle
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: hero.colContent
                    }

                    // The aliases it answers to, so the next search is a word away.
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        visible: text.length > 0
                        text: (hero.entry?.keywords ?? "").split(" ").filter(word => word.length > 0).slice(0, 6).join(" · ")
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: hero.colContent
                        opacity: 0.72
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapTiny

                        // The code point, copied as text by its own tonal pill.
                        RippleButton {
                            id: codeButton
                            Layout.fillWidth: true
                            implicitHeight: 40
                            visible: (hero.entry?.code ?? "").length > 0
                            buttonRadius: Appearance.rounding.full
                            colBackground: ColorUtils.applyAlpha(hero.colContent, 0.1)
                            colBackgroundHover: ColorUtils.applyAlpha(hero.colContent, 0.18)
                            colRipple: ColorUtils.applyAlpha(hero.colContent, 0.3)
                            onClicked: root.copyText(hero.entry.code)

                            contentItem: Item {
                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol {
                                        text: "tag"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: hero.colContent
                                    }
                                    StyledText {
                                        text: hero.entry?.code ?? ""
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: hero.colContent
                                    }
                                }
                            }

                            StyledToolTip { text: Translation.tr("Copy code point") }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            visible: Boolean(hero.entry) && codeButton.visible !== true
                            text: Translation.tr("%1 characters").arg(Array.from(hero.entry?.text ?? "").length)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: hero.colContent
                            opacity: 0.72
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

            // ── Library: categories, count and the symbols ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: ClockStyle.gapSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    // Thirteen categories do not fit beside the count, so the
                    // chips scroll; only the chosen one spells its name.
                    ListView {
                        id: chipList
                        Layout.fillWidth: true
                        implicitHeight: 38
                        orientation: ListView.Horizontal
                        spacing: ClockStyle.gapTiny
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
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

                    // The count, as the panel's number.
                    StyledText {
                        Layout.alignment: Qt.AlignBaseline
                        text: String(root.filteredEntries.length)
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

                ListView {
                    id: symbolList
                    readonly property real cellSize: width / root.gridColumns
                    readonly property real wideHeight: Math.round(symbolList.cellSize * 1.3)
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.filteredEntries.length > 0
                    clip: true
                    reuseItems: true
                    cacheBuffer: symbolList.cellSize * 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.layout.rows

                    delegate: Item {
                        id: rowDelegate
                        required property var modelData
                        readonly property bool wide: rowDelegate.modelData.wide
                        readonly property real cellWidth: symbolList.width / (rowDelegate.wide ? root.wideColumns : root.gridColumns)
                        width: symbolList.width
                        height: rowDelegate.wide ? symbolList.wideHeight : symbolList.cellSize

                        Repeater {
                            model: rowDelegate.modelData.count

                            delegate: Item {
                                id: cell
                                required property int index
                                readonly property int entryIndex: rowDelegate.modelData.start + cell.index
                                readonly property var entry: root.filteredEntries[cell.entryIndex] ?? null
                                readonly property bool selected: root.selectedIndex === cell.entryIndex
                                readonly property bool multiline: (cell.entry?.text ?? "").indexOf("\n") >= 0
                                readonly property color selectedColor: root.accentFor(cell.entry?.category ?? "all")
                                x: cell.index * rowDelegate.cellWidth
                                width: rowDelegate.cellWidth
                                height: rowDelegate.height

                                // Circle (pill when wide) on hover, squared off once
                                // chosen: shape is state.
                                RippleButton {
                                    anchors.fill: parent
                                    anchors.margins: root.gridSpacing / 2
                                    toggled: cell.selected
                                    buttonRadius: cell.selected ? Appearance.rounding.normal : Appearance.rounding.full
                                    colBackground: rowDelegate.wide ? ClockStyle.colSurfaceHigh : "transparent"
                                    colBackgroundHover: rowDelegate.wide ? ClockStyle.colSurfaceHover : ClockStyle.colSurfaceHigh
                                    colBackgroundActive: ClockStyle.colSurfaceActive
                                    colBackgroundToggled: ColorUtils.applyAlpha(cell.selectedColor, 0.32)
                                    colBackgroundToggledHover: ColorUtils.applyAlpha(cell.selectedColor, 0.42)
                                    colBackgroundToggledActive: ColorUtils.applyAlpha(cell.selectedColor, 0.5)
                                    colRipple: ClockStyle.colSurfaceActive
                                    colRippleToggled: ColorUtils.applyAlpha(cell.selectedColor, 0.5)
                                    onClicked: root.selectedIndex = cell.entryIndex
                                    onDoubleClicked: {
                                        root.selectedIndex = cell.entryIndex;
                                        root.activateSelected();
                                    }

                                    StyledText {
                                        anchors.fill: parent
                                        anchors.margins: rowDelegate.wide ? 10 : 4
                                        text: cell.entry?.text ?? ""
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        fontSizeMode: Text.Fit
                                        minimumPixelSize: 6
                                        font.pixelSize: rowDelegate.wide ? Appearance.font.pixelSize.large : Math.round(symbolList.cellSize * 0.42)
                                        font.family: cell.multiline ? Appearance.font.family.monospace : Appearance.font.family.main
                                        lineHeight: cell.multiline ? 1.0 : 1.1
                                        color: ClockStyle.colOnSurface
                                    }
                                }
                            }
                        }
                    }

                    TouchpadScrollHandler {
                        flickable: symbolList
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.filteredEntries.length === 0

                    ClockEmptyState {
                        anchors.centerIn: parent
                        symbol: "search_off"
                        shape: "Ghostish"
                        shapeSize: ClockStyle.emptyShapeSmall
                        title: Translation.tr("No symbols found")
                        subtitle: Translation.tr("Try another word, a code like U+00B0, or another category")
                    }
                }
            }
        }
    }
}
