pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

Item {
    id: root
    // Every motion in the overview and its panels answers to one switch:
    // Settings -> Overview -> Animation style -> None.
    readonly property bool animationsDisabled: Config.options.overview.animationStyle === "none"
    property string searchQuery: ""

    readonly property int gridColumns: 8
    readonly property int maxItems: 120
    readonly property real inspectorWidth: 284

    implicitWidth: Config.options.search.appearance.panelWidth
    implicitHeight: scaffold.implicitHeight

    property int focusedControlIndex: 0
    property var allIcons: []
    property var filteredIcons: []
    property var iconMap: ({})
    property bool dataLoaded: false

    /// The icon the inspector describes: the focused one, else the best match.
    readonly property var inspectedIcon: root.focusedControlIndex >= 0 && root.focusedControlIndex < root.filteredIcons.length
        ? root.filteredIcons[root.focusedControlIndex]
        : (root.filteredIcons.length > 0 ? root.filteredIcons[0] : null)

    readonly property int cellWidth: Math.floor((gridFlickable.width - (root.gridSpacing * (root.gridColumns - 1))) / root.gridColumns)
    readonly property int cellSize: root.cellWidth
    readonly property int cellHeight: root.cellSize
    readonly property int gridSpacing: 6

    function loadData() {
        symbolsFileView.reload();
    }

    function filterIcons() {
        if (!dataLoaded || allIcons.length === 0) {
            filteredIcons = [];
            iconMap = ({});
            updateSlots();
            return;
        }

        const query = root.searchQuery.trim().toLowerCase();
        if (query.length === 0) {
            filteredIcons = allIcons.slice(0, maxItems);

            const map = {};
            for (let i = 0; i < filteredIcons.length; i++) {
                map[filteredIcons[i].n] = filteredIcons[i];
            }
            iconMap = map;
            updateSlots();
            return;
        }

        const queryTerms = query.split(/\s+/).filter(t => t.length > 0);
        const scored = [];

        for (let i = 0; i < allIcons.length; i++) {
            const icon = allIcons[i];
            const name = icon.n.toLowerCase();
            const tags = icon.t;
            const categories = icon.c;

            let score = 0;
            let allTermsMatch = true;

            for (let t = 0; t < queryTerms.length; t++) {
                const term = queryTerms[t];
                let termMatched = false;

                if (name === term) {
                    score += 100;
                    termMatched = true;
                } else if (name.startsWith(term)) {
                    score += 50;
                    termMatched = true;
                } else if (name.includes(term)) {
                    score += 25;
                    termMatched = true;
                }

                if (!termMatched) {
                    for (let j = 0; j < tags.length; j++) {
                        const tag = tags[j].toLowerCase();
                        if (tag === term) {
                            score += 30;
                            termMatched = true;
                            break;
                        } else if (tag.startsWith(term)) {
                            score += 15;
                            termMatched = true;
                            break;
                        } else if (tag.includes(term)) {
                            score += 8;
                            termMatched = true;
                            break;
                        }
                    }
                }

                if (!termMatched) {
                    for (let j = 0; j < categories.length; j++) {
                        const cat = categories[j].toLowerCase();
                        if (cat.includes(term)) {
                            score += 5;
                            termMatched = true;
                            break;
                        }
                    }
                }

                if (!termMatched) {
                    allTermsMatch = false;
                    break;
                }
            }

            if (allTermsMatch && score > 0) {
                score += (icon.p || 0) / 10000;
                scored.push({ icon: icon, score: score });
            }
        }

        scored.sort((a, b) => b.score - a.score);
        filteredIcons = scored.slice(0, maxItems).map(s => s.icon);

        const map = {};
        for (let i = 0; i < filteredIcons.length; i++) {
            map[filteredIcons[i].n] = filteredIcons[i];
        }
        iconMap = map;

        updateSlots();
    }

    function navigateUp() {
        if (filteredIcons.length === 0) return;
        const cols = root.gridColumns;
        if (focusedControlIndex < 0) {
            focusedControlIndex = 0;
        } else if (focusedControlIndex >= cols) {
            focusedControlIndex -= cols;
        } else {
            focusedControlIndex = -1;
            root.requestFocusSearchInput();
        }
        ensureVisible();
    }

    function navigateDown() {
        if (filteredIcons.length === 0) return;
        const cols = root.gridColumns;
        if (focusedControlIndex < 0) {
            focusedControlIndex = 0;
        } else {
            const next = focusedControlIndex + cols;
            if (next < filteredIcons.length) {
                focusedControlIndex = next;
            }
        }
        ensureVisible();
    }

    function navigateLeft() {
        if (filteredIcons.length === 0) return;
        if (focusedControlIndex < 0) {
            focusedControlIndex = 0;
        } else if (focusedControlIndex > 0) {
            focusedControlIndex--;
        } else {
            focusedControlIndex = -1;
            root.requestFocusSearchInput();
        }
        ensureVisible();
    }

    function navigateRight() {
        if (filteredIcons.length === 0) return;
        if (focusedControlIndex < 0) {
            focusedControlIndex = 0;
        } else if (focusedControlIndex < filteredIcons.length - 1) {
            focusedControlIndex++;
        }
        ensureVisible();
    }

    function activateSelected() {
        if (focusedControlIndex >= 0 && focusedControlIndex < filteredIcons.length) {
            copyIconName(filteredIcons[focusedControlIndex].n);
        } else if (filteredIcons.length > 0) {
            copyIconName(filteredIcons[0].n);
        }
        GlobalStates.closeSearchSurfaces();
    }

    function focusInput() {
        focusedControlIndex = -1;
        root.requestFocusSearchInput();
    }

    // This is a flat panel — there is no sub-level to back out of. Without
    // this, Backspace on an empty query falls through to
    // SearchWidget.exitActivePanel() and kicks the user back to plain Search,
    // so clearing the query to retype something silently exits the panel.
    function ensureVisible() {
        if (focusedControlIndex < 0) return;
        const cols = root.gridColumns;
        const row = Math.floor(focusedControlIndex / cols);
        const itemTop = row * (root.cellHeight + root.gridSpacing);
        const itemBottom = itemTop + root.cellSize;
        const viewTop = gridFlickable.contentY;
        const viewBottom = viewTop + gridFlickable.height;

        if (itemTop < viewTop) {
            gridFlickable.contentY = Math.max(0, itemTop - 8);
        } else if (itemBottom > viewBottom) {
            gridFlickable.contentY = itemBottom - gridFlickable.height + 8;
        }
    }

    function copyIconName(name) {
        Quickshell.clipboardText = name;
        copyFeedbackIcon = name;
        copyFeedbackTimer.restart();
    }

    function copyIconSvg(iconData) {
        if (!iconData) return;
        const cp = iconData.cp;
        const hex = cp.toString(16).toUpperCase();
        const name = iconData.n;
        const svg = `<svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 -960 960 960" width="24"><text x="480" y="0" font-family="Material Symbols Rounded" font-size="960" text-anchor="middle" dominant-baseline="central" fill="black">&#x${hex};</text></svg>`;
        Quickshell.clipboardText = svg;
        copyFeedbackIcon = name;
        copyFeedbackTimer.restart();
    }

    function copyFocusedIconSvg() {
        if (focusedControlIndex >= 0 && focusedControlIndex < filteredIcons.length) {
            copyIconSvg(filteredIcons[focusedControlIndex]);
        } else if (filteredIcons.length > 0) {
            copyIconSvg(filteredIcons[0]);
        }
        GlobalStates.closeSearchSurfaces();
    }

    // Panel shortcuts dispatched by SearchBar: Ctrl+S copies the SVG, Ctrl+C the name.
    function saveSelected(): bool {
        root.copyFocusedIconSvg();
        return true;
    }

    function copySelected(): bool {
        if (!root.inspectedIcon)
            return false;
        root.copyIconName(root.inspectedIcon.n);
        return true;
    }

    function codepointLabel(icon) {
        return icon ? "U+" + Number(icon.cp).toString(16).toUpperCase().padStart(4, "0") : "";
    }

    function updateSlots() {
        const newUids = [];
        for (let i = 0; i < filteredIcons.length; i++) {
            newUids.push(filteredIcons[i].n);
        }

        const slots = [];
        for (let i = 0; i < iconRepeater.count; i++) {
            slots.push(iconRepeater.itemAt(i));
        }

        const oldUids = [];
        for (let i = 0; i < slots.length; i++) {
            oldUids.push(slots[i] ? slots[i].uniqueId : "");
        }

        for (let i = 0; i < slots.length; i++) {
            if (slots[i]) {
                slots[i].uniqueId = "";
                slots[i].hasData = false;
                slots[i].currentPosition = -1;
            }
        }

        const slotToNewPos = {};
        const usedNewPositions = new Set();

        for (let slotIdx = 0; slotIdx < slots.length; slotIdx++) {
            const oldUid = oldUids[slotIdx];
            if (!oldUid) continue;
            const newPos = newUids.indexOf(oldUid);
            if (newPos >= 0) {
                slotToNewPos[slotIdx] = newPos;
                usedNewPositions.add(newPos);
            }
        }

        for (let newPos = 0; newPos < newUids.length; newPos++) {
            if (usedNewPositions.has(newPos)) continue;
            for (let slotIdx = 0; slotIdx < slots.length; slotIdx++) {
                if (!(slotIdx in slotToNewPos)) {
                    slotToNewPos[slotIdx] = newPos;
                    usedNewPositions.add(newPos);
                    break;
                }
            }
        }

        for (let slotIdx = 0; slotIdx < slots.length; slotIdx++) {
            const slot = slots[slotIdx];
            if (!slot) continue;
            const newPos = slotToNewPos[slotIdx];
            if (newPos === undefined) continue;
            const uid = newUids[newPos];
            slot.uniqueId = uid;
            slot.hasData = true;
            slot.currentPosition = newPos;
        }

        updatePositions();
    }

    function updatePositions() {
        const cols = root.gridColumns;
        const ch = root.cellHeight;
        const spacing = root.gridSpacing;
        let visibleCount = 0;
        for (let i = 0; i < iconRepeater.count; i++) {
            const slot = iconRepeater.itemAt(i);
            if (!slot) continue;
            if (slot.hasData && slot.currentPosition >= 0) {
                visibleCount++;
            }
        }
        const totalRows = Math.ceil(visibleCount / cols);
        const totalHeight = totalRows > 0 ? totalRows * ch + (totalRows - 1) * spacing : 0;
        contentContainer.height = Math.max(0, totalHeight);
    }

    property string copyFeedbackIcon: ""

    signal requestFocusSearchInput()
    signal requestSetSearchQuery(string query)

    onSearchQueryChanged: {
        root.filterIcons();
        focusedControlIndex = -1;
    }

    Timer {
        id: copyFeedbackTimer
        interval: 1500
        repeat: false
    }

    FileView {
        id: symbolsFileView
        path: Directories.assetsPath + "/data/material_symbols.json"
        onLoadedChanged: {
            if (loaded) {
                try {
                    const content = text();
                    allIcons = JSON.parse(content);
                    dataLoaded = true;
                    root.filterIcons();
                } catch (e) {
                    console.warn("[MaterialSymbolsPanel] Failed to parse data:", e);
                }
            }
        }
    }

    Component.onCompleted: {
        root.loadData();
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        primaryHint: ({ label: Translation.tr("Copy name"), actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("Copy SVG"), actionId: "save", keys: ["Ctrl", "S"] },
            { label: Translation.tr("Navigate"), keys: ["↑", "↓", "←", "→"] }
        ]

        RowLayout {
            anchors.fill: parent
            spacing: ClockStyle.paneGap

            // ── Contact sheet: glyphs only, the inspector carries the names ──
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Flickable {
                    id: gridFlickable
                    anchors.fill: parent
                    clip: true
                    contentHeight: contentContainer.height
                    contentWidth: width
                    maximumFlickVelocity: 3500
                    boundsBehavior: Flickable.DragOverBounds
                    pixelAligned: true

                    // Smooths the keyboard selection's scroll into view
                    Behavior on contentY {
                        enabled: !root.animationsDisabled
                        NumberAnimation {
                            alwaysRunToEnd: true
                            duration: Appearance.animation.scroll.duration
                            easing.type: Appearance.animation.scroll.type
                            easing.bezierCurve: Appearance.animation.scroll.bezierCurve
                        }
                    }

                    TouchpadScrollHandler {
                        flickable: gridFlickable
                    }

                    Item {
                        id: contentContainer
                        width: gridFlickable.width
                        height: 0

                        Repeater {
                            id: iconRepeater
                            model: root.maxItems

                            delegate: Item {
                                id: delegateItem
                                required property int index

                                property string uniqueId: ""
                                property int currentPosition: -1
                                property var iconData: root.iconMap[uniqueId] || null
                                property bool hasData: iconData !== null

                                readonly property bool isFocused: root.focusedControlIndex >= 0
                                    && root.focusedControlIndex === delegateItem.currentPosition && delegateItem.hasData
                                // Before any keyboard focus, the best match is what Enter copies.
                                readonly property bool isInspected: delegateItem.hasData && root.inspectedIcon !== null
                                    && root.inspectedIcon.n === delegateItem.uniqueId

                                readonly property int targetCol: currentPosition >= 0 ? currentPosition % root.gridColumns : 0
                                readonly property int targetRow: currentPosition >= 0 ? Math.floor(currentPosition / root.gridColumns) : 0
                                x: targetCol * (root.cellWidth + root.gridSpacing)
                                y: targetRow * (root.cellHeight + root.gridSpacing)
                                width: root.cellWidth
                                height: hasData ? root.cellHeight : 0
                                opacity: hasData ? 1.0 : 0.0
                                visible: hasData || opacity > 0.01

                                Behavior on x {
                                    enabled: !root.animationsDisabled
                                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                                }
                                Behavior on y {
                                    enabled: !root.animationsDisabled
                                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                                }
                                Behavior on opacity {
                                    enabled: !root.animationsDisabled
                                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                                }

                                RippleButton {
                                    anchors.fill: parent
                                    enabled: delegateItem.hasData
                                    toggled: delegateItem.isInspected
                                    buttonRadius: delegateItem.isInspected ? Appearance.rounding.large : Appearance.rounding.small
                                    colBackground: ClockStyle.colSurface
                                    colBackgroundHover: ClockStyle.colSurfaceHover
                                    colBackgroundActive: ClockStyle.colSurfaceActive
                                    colBackgroundToggled: delegateItem.isFocused ? ClockStyle.colPrimary : ClockStyle.colPrimaryContainer
                                    colBackgroundToggledHover: delegateItem.isFocused ? ClockStyle.colPrimaryHover : ClockStyle.colPrimaryContainerHover
                                    colBackgroundToggledActive: delegateItem.isFocused ? ClockStyle.colPrimaryActive : ClockStyle.colPrimaryContainerActive
                                    colRipple: ClockStyle.colSurfaceActive
                                    colRippleToggled: ClockStyle.colPrimaryActive
                                    onClicked: root.focusedControlIndex = delegateItem.currentPosition
                                    onDoubleClicked: {
                                        root.copyIconName(delegateItem.iconData.n);
                                        GlobalStates.closeSearchSurfaces();
                                    }

                                    // The inspected glyph fills in: the FILL axis is the state.
                                    // A name newer than the installed font falls back to its
                                    // letters, much wider than a glyph; it is shown as missing.
                                    MaterialSymbol {
                                        id: tileGlyph
                                        readonly property bool missing: implicitWidth > iconSize * 1.25
                                        anchors.centerIn: parent
                                        visible: !tileGlyph.missing
                                        text: delegateItem.iconData ? delegateItem.iconData.n : ""
                                        iconSize: Math.round(root.cellSize * 0.42)
                                        fill: delegateItem.isInspected ? 1 : 0
                                        color: delegateItem.isFocused ? ClockStyle.colOnPrimary
                                            : delegateItem.isInspected ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: tileGlyph.missing
                                        text: "indeterminate_question_box"
                                        iconSize: Math.round(root.cellSize * 0.32)
                                        color: tileGlyph.color
                                        opacity: 0.4
                                    }
                                }
                            }
                        }
                    }
                }

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: !root.dataLoaded
                    implicitWidth: 56
                    implicitHeight: 56
                }

                ClockEmptyState {
                    anchors.centerIn: parent
                    visible: root.filteredIcons.length === 0 && root.dataLoaded
                    symbol: "search_off"
                    shape: "PixelCircle"
                    shapeSize: ClockStyle.emptyShapeSmall
                    title: Translation.tr("No symbols found")
                    subtitle: Translation.tr("Search by name, tag or category")
                }
            }

            // ── Inspector: the glyph in both styles, its name and codepoint in mono ──
            Rectangle {
                id: inspector
                readonly property var icon: root.inspectedIcon
                // A name newer than the installed font spells out instead of drawing a glyph.
                readonly property bool missing: nameMetrics.advanceWidth > 56 * 1.25
                readonly property bool copiedThis: copyFeedbackTimer.running && inspector.icon !== null
                    && root.copyFeedbackIcon === inspector.icon.n

                TextMetrics {
                    id: nameMetrics
                    font.family: Appearance.font.family.iconMaterial
                    font.pixelSize: 56
                    text: inspector.icon ? inspector.icon.n : ""
                }

                Layout.preferredWidth: root.inspectorWidth
                Layout.fillWidth: false
                Layout.fillHeight: true
                radius: ClockStyle.radiusCard
                color: ClockStyle.colSurfaceHigh

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gap
                    spacing: ClockStyle.gapSmall

                    // Filled on the tertiary, outlined on the surface.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: 118
                        spacing: ClockStyle.gapTiny

                        Repeater {
                            model: [1, 0]

                            delegate: Rectangle {
                                id: preview
                                required property int modelData
                                readonly property bool filled: preview.modelData === 1
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                topLeftRadius: preview.filled ? Appearance.rounding.verylarge - 8 : Appearance.rounding.verysmall
                                bottomLeftRadius: preview.filled ? Appearance.rounding.verylarge - 8 : Appearance.rounding.verysmall
                                topRightRadius: preview.filled ? Appearance.rounding.verysmall : Appearance.rounding.verylarge - 8
                                bottomRightRadius: preview.filled ? Appearance.rounding.verysmall : Appearance.rounding.verylarge - 8
                                color: preview.filled ? ClockStyle.colTertiary : ClockStyle.colSurfaceHighest

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: inspector.icon && !inspector.missing ? inspector.icon.n
                                        : (inspector.icon ? "indeterminate_question_box" : "category")
                                    iconSize: 56
                                    fill: preview.filled ? 1 : 0
                                    color: preview.filled ? ClockStyle.colOnTertiary : ClockStyle.colOnSurface
                                }

                                StyledText {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 10
                                    text: preview.filled ? Translation.tr("Filled") : Translation.tr("Outlined")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                    color: preview.filled ? ClockStyle.colOnTertiary : ClockStyle.colOnSurfaceVariant
                                    opacity: 0.8
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        Layout.leftMargin: 4
                        text: inspector.icon ? inspector.icon.n : Translation.tr("Nothing selected")
                        elide: Text.ElideRight
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                        color: ClockStyle.colOnSurface
                    }

                    // Caption over value, in mono: the reference sheet look.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        spacing: ClockStyle.gapLarge

                        Repeater {
                            model: [
                                { caption: Translation.tr("Codepoint"), value: root.codepointLabel(inspector.icon) },
                                { caption: Translation.tr("Category"), value: inspector.missing ? Translation.tr("Newer than your font") : (inspector.icon ? String(inspector.icon.c?.[0] ?? "—") : "—") }
                            ]

                            delegate: ColumnLayout {
                                id: fact
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                spacing: 1

                                StyledText {
                                    text: fact.modelData.caption
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                    color: ClockStyle.colOnSurfaceVariant
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: fact.modelData.value
                                    elide: Text.ElideRight
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: ClockStyle.colOnSurface
                                }
                            }
                        }
                    }

                    // A handful of tags, each one a search away.
                    Flow {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 2
                        spacing: ClockStyle.gapTiny
                        clip: true

                        Repeater {
                            model: inspector.icon ? Array.from(inspector.icon.t ?? []).filter(tag => tag !== inspector.icon.n).slice(0, 8) : []

                            delegate: RippleButton {
                                id: tagChip
                                required property string modelData
                                implicitWidth: tagLabel.implicitWidth + 20
                                implicitHeight: 26
                                buttonRadius: Appearance.rounding.full
                                colBackground: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.06)
                                colBackgroundHover: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.12)
                                colRipple: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.18)
                                onClicked: root.requestSetSearchQuery(tagChip.modelData)

                                StyledText {
                                    id: tagLabel
                                    anchors.centerIn: parent
                                    text: tagChip.modelData
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: ClockStyle.colOnSurfaceVariant
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        ClockSheetAction {
                            Layout.fillWidth: true
                            primary: true
                            enabled: inspector.icon !== null
                            symbol: inspector.copiedThis ? "check" : "content_copy"
                            label: inspector.copiedThis ? Translation.tr("Copied") : Translation.tr("Copy name")
                            onClicked: root.copySelected()
                        }

                        ClockSheetAction {
                            Layout.fillWidth: false
                            Layout.preferredWidth: 84
                            enabled: inspector.icon !== null
                            label: "SVG"
                            onClicked: root.copyFocusedIconSvg()
                        }
                    }
                }
            }
        }
    }
}
