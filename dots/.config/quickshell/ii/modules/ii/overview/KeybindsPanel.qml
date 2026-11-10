pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Keybinds panel of the overview Search.
 *
 * Material 3 Expressive layout: a source rail on the left (a tertiary count tile whose
 * shape morphs with the source, then the sources as pills carrying their match count)
 * and a grouped list on the right. Shortcuts are drawn as physical keycaps; the selected
 * row grows to show what the shortcut runs plus its actions, and its caps play the chord
 * once. The empty state spells the query in keycaps.
 */
Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: -1
    property string selectedCategory: "all"

    readonly property bool supportsSectionToggle: true
    readonly property string normalizedQuery: root.searchQuery.trim().toLocaleLowerCase()
    readonly property bool hasQuery: root.normalizedQuery.length > 0
    readonly property bool reducedMotion: ClockStyle.reducedMotion

    readonly property int railWidth: 212
    readonly property int rowHeight: 56
    readonly property int detailHeight: 50
    readonly property var pageShapes: ["Sunny", "Cookie9Sided", "SoftBurst", "Flower", "Cookie12Sided", "Clover8Leaf", "Puffy", "Gem"]

    readonly property var categories: {
        const revision = KeybindsService.revision;
        const list = [
            { id: "all", label: Translation.tr("All"), icon: "all_inclusive", pageId: "", shape: "Clover4Leaf", programIcon: "" },
            { id: "hyprland", label: Translation.tr("Hyprland"), icon: "desktop_windows", pageId: "", shape: "Cookie7Sided", programIcon: "" }
        ];
        let pageIndex = 0;
        for (const page of KeybindsService.pages ?? []) {
            list.push({
                id: "page_" + String(page.id ?? ""),
                label: String(page.name ?? Translation.tr("Shortcuts")),
                icon: String(page.icon ?? "keyboard"),
                pageId: String(page.id ?? ""),
                shape: root.pageShapes[pageIndex % root.pageShapes.length],
                programIcon: Boolean(page.useProgramIcon) ? root.programIcon(page.program, page.programId) : ""
            });
            pageIndex++;
        }
        return list;
    }
    readonly property var selectedCategoryData: root.categories.find(c => c.id === root.selectedCategory) ?? root.categories[0]

    readonly property var allBindings: root.collectAllBindings()

    // Query first, source second: the rail counts what the query matched in every source.
    readonly property var matchedBindings: {
        const terms = root.normalizedQuery.split(/\s+/).filter(term => term.length > 0);
        if (terms.length === 0)
            return root.allBindings;
        return root.allBindings.filter(binding => {
            const haystack = [
                binding.section,
                binding.sourceLabel,
                binding.name,
                binding.rawKeys,
                binding.keys.join(" "),
                binding.context ?? "",
                binding.notes ?? "",
                binding.dispatcher ?? "",
                binding.params ?? ""
            ].join(" ").toLocaleLowerCase();
            return terms.every(term => haystack.includes(term));
        });
    }
    readonly property var categoryCounts: {
        const counts = { all: root.matchedBindings.length, hyprland: 0 };
        for (const binding of root.matchedBindings)
            counts[binding.source] = (counts[binding.source] ?? 0) + 1;
        return counts;
    }
    readonly property var filteredBindings: root.selectedCategory === "all"
        ? root.matchedBindings
        : root.matchedBindings.filter(binding => binding.source === root.selectedCategory)

    readonly property var rows: root.sectionRows(root.filteredBindings)
    readonly property string statusText: Translation.tr("%1 shortcuts").arg(String(root.filteredBindings.length))

    implicitWidth: Config.options.search.appearance.panelWidth
    implicitHeight: scaffold.implicitHeight

    function programIcon(program, programId): string {
        const wanted = String(program ?? "").trim();
        const wantedId = String(programId ?? "").trim();
        if (!wanted && !wantedId)
            return "";
        const normalized = wanted.toLowerCase();
        const normalizedId = wantedId.toLowerCase();
        const usable = icon => icon && icon !== "image-missing" && icon !== "application-x-executable" && AppSearch.iconExists(icon);
        for (const app of AppSearch.list ?? []) {
            const appId = String(app?.id ?? "").trim().toLowerCase();
            if ((normalizedId && appId === normalizedId)
                    || (normalized && String(app?.name ?? "").trim().toLowerCase() === normalized)
                    || (normalized && appId === normalized)) {
                const icon = String(app?.icon ?? "").trim();
                if (usable(icon))
                    return icon;
                break;
            }
        }
        const guessed = AppSearch.guessIcon(wantedId || wanted);
        return usable(guessed) ? guessed : "";
    }

    function parseKeyList(rawKeys) {
        if (!rawKeys) return [];
        if (Array.isArray(rawKeys)) return rawKeys;
        const str = String(rawKeys).trim();
        if (str.includes("+")) {
            return str.split("+").map(p => p.trim()).filter(Boolean);
        }
        if (str.includes(" ")) {
            return str.split(/\s+/).map(p => p.trim()).filter(Boolean);
        }
        return [str];
    }

    function collectHyprlandBindings() {
        const output = [];

        function walk(nodes, source, parentSection) {
            for (const node of Array.from(nodes ?? [])) {
                const section = String(node?.name ?? parentSection ?? "").trim() || Translation.tr("Keybinds");
                for (const binding of Array.from(node?.keybinds ?? [])) {
                    const keys = Array.from(binding?.mods ?? []).map(part => String(part))
                        .concat([String(binding?.key ?? "")]).filter(part => part.length > 0);
                    const name = String(binding?.comment ?? "").trim()
                        || `${String(binding?.dispatcher ?? "").trim()} ${String(binding?.params ?? "").trim()}`.trim();
                    if (keys.length === 0 || name.length === 0)
                        continue;
                    output.push({
                        section: section,
                        source: "hyprland",
                        sourceLabel: Translation.tr("Hyprland"),
                        icon: "desktop_windows",
                        pageId: "",
                        keys: keys,
                        rawKeys: keys.join("+"),
                        name: name,
                        context: "",
                        notes: "",
                        dispatcher: String(binding?.dispatcher ?? "").trim(),
                        params: String(binding?.params ?? "").trim(),
                        canDispatch: true
                    });
                }
                walk(node?.children, source, section);
            }
        }

        if (Config.options.search.modules.keybinds.includeDefaultBinds)
            walk(HyprlandKeybinds.defaultKeybinds?.children, "default", "");
        if (Config.options.search.modules.keybinds.includeUserBinds)
            walk(HyprlandKeybinds.userKeybinds?.children, "user", "");
        return output;
    }

    function collectCustomBindings() {
        const output = [];
        const revision = KeybindsService.revision;
        for (const page of KeybindsService.pages ?? []) {
            const pageName = String(page.name ?? Translation.tr("Shortcuts"));
            const pageIcon = String(page.icon ?? "keyboard");
            const pageId = String(page.id ?? "");
            for (const item of page.keybinds ?? []) {
                const rawKeys = String(item.keys ?? "").trim();
                if (!rawKeys) continue;
                const section = String(item.category ?? "").trim() || pageName;
                const name = String(item.description ?? "").trim() || rawKeys;
                const keys = root.parseKeyList(rawKeys);
                output.push({
                    section: section,
                    source: "page_" + pageId,
                    sourceLabel: pageName,
                    icon: pageIcon,
                    pageId: pageId,
                    keys: keys.length > 0 ? keys : [rawKeys],
                    rawKeys: rawKeys,
                    name: name,
                    context: String(item.context ?? "").trim(),
                    notes: String(item.notes ?? "").trim(),
                    itemIcon: String(item.icon ?? "").trim(),
                    dispatcher: "",
                    params: "",
                    canDispatch: false
                });
            }
        }
        return output;
    }

    function collectAllBindings() {
        return root.collectHyprlandBindings().concat(root.collectCustomBindings());
    }

    // Consecutive bindings of one source + section form a group: a caption row, then
    // rows that know whether they open or close it (outer corners round, joins stay tight).
    function sectionRows(bindings) {
        const output = [];
        let previousKey = "";
        let header = null;
        for (const binding of bindings) {
            const key = binding.source + "\u0000" + binding.section;
            if (key !== previousKey) {
                if (output.length > 0)
                    output[output.length - 1].last = true;
                header = {
                    kind: "section",
                    name: binding.section,
                    sourceLabel: binding.sourceLabel,
                    sourceIcon: binding.icon,
                    count: 0
                };
                output.push(header);
                previousKey = key;
                output.push({ kind: "binding", binding, first: true, last: false });
            } else {
                output.push({ kind: "binding", binding, first: false, last: false });
            }
            header.count++;
        }
        if (output.length > 0)
            output[output.length - 1].last = true;
        return output;
    }

    function isBindingIndex(index) {
        return index >= 0 && index < root.rows.length && root.rows[index].kind === "binding";
    }

    function clampSelection() {
        if (root.filteredBindings.length === 0) {
            root.selectedIndex = -1;
            return;
        }
        if (!root.isBindingIndex(root.selectedIndex))
            root.selectedIndex = root.rows.findIndex(row => row.kind === "binding");
    }

    function select(index) {
        if (!root.isBindingIndex(index))
            return false;
        root.selectedIndex = index;
        keybindList.positionViewAtIndex(index, ListView.Contain);
        settleScroll.restart();
        return true;
    }

    function moveSelection(direction) {
        if (root.filteredBindings.length === 0)
            return false;
        let index = root.selectedIndex;
        do {
            index += direction;
        } while (index >= 0 && index < root.rows.length && !root.isBindingIndex(index));
        return root.select(index);
    }

    function sectionJump(direction): bool {
        let index = root.selectedIndex;
        // Back to the start of the current group first, then group by group.
        if (direction < 0 && root.isBindingIndex(index) && !root.rows[index].first)
        {
            while (index > 0 && !(root.isBindingIndex(index) && root.rows[index].first))
                index--;
            return root.select(index);
        }
        do {
            index += direction;
        } while (index >= 0 && index < root.rows.length && !(root.isBindingIndex(index) && root.rows[index].first));
        return root.select(index);
    }

    function selectedBinding() {
        return root.isBindingIndex(root.selectedIndex) ? root.rows[root.selectedIndex].binding : null;
    }

    function focusInput(): bool {
        return false;
    }

    function navigateUp(): bool {
        return root.moveSelection(-1);
    }

    function navigateDown(): bool {
        return root.moveSelection(1);
    }

    function sectionPrevious(): bool {
        return root.sectionJump(-1);
    }

    function sectionNext(): bool {
        return root.sectionJump(1);
    }

    function activateSelected(): bool {
        const binding = root.selectedBinding();
        if (!binding)
            return false;
        if (binding.canDispatch) {
            return HyprlandKeybinds.dispatchBinding(binding);
        }
        Quickshell.clipboardText = binding.rawKeys || binding.keys.join("+");
        GlobalStates.openCheatsheet("keybinds");
        if (binding.pageId) {
            KeybindsService.selectPage(binding.pageId);
        }
        return true;
    }

    function copySelected(): bool {
        const binding = root.selectedBinding();
        if (!binding)
            return false;
        Quickshell.clipboardText = binding.rawKeys || binding.keys.join("+");
        return true;
    }

    function openSelectedInCheatsheet(): bool {
        const binding = root.selectedBinding();
        if (!binding)
            return false;
        GlobalStates.openCheatsheet("keybinds");
        if (binding.pageId) {
            KeybindsService.selectPage(binding.pageId);
        }
        return true;
    }

    function openCheatsheet() {
        GlobalStates.openCheatsheet("keybinds");
        if (root.selectedCategoryData.pageId)
            KeybindsService.selectPage(root.selectedCategoryData.pageId);
    }

    function toggleSection(): bool {
        return root.cycleCategory(1);
    }

    function cycleSection(): bool {
        return root.cycleCategory(1);
    }

    function cycleCategory(direction = 1): bool {
        if (root.categories.length === 0)
            return false;
        let currentIndex = root.categories.findIndex(c => c.id === root.selectedCategory);
        if (currentIndex < 0)
            currentIndex = 0;
        let nextIndex = (currentIndex + direction + root.categories.length) % root.categories.length;
        root.setCategory(root.categories[nextIndex].id);
        return true;
    }

    function setCategory(categoryId: string) {
        root.selectedCategory = categoryId;
        root.selectedIndex = -1;
        root.clampSelection();
        keybindList.positionViewAtBeginning();
        const index = root.categories.findIndex(c => c.id === categoryId);
        if (index >= 0) {
            categoryList.positionViewAtIndex(index, ListView.Contain);
        }
    }

    onRowsChanged: root.clampSelection()
    onSelectedCategoryChanged: root.clampSelection()
    Component.onCompleted: root.clampSelection()

    // The selected row grows after the list has already scrolled to it; once it has
    // settled, glide it fully into view instead of jumping.
    Timer {
        id: settleScroll
        interval: ClockStyle.motionDefault.duration + 16
        onTriggered: {
            const row = keybindList.itemAtIndex(root.selectedIndex);
            if (!row)
                return;
            const top = row.y;
            const bottom = row.y + row.height;
            let target = keybindList.contentY;
            if (bottom > keybindList.contentY + keybindList.height)
                target = bottom - keybindList.height;
            if (top < target)
                target = top;
            if (target === keybindList.contentY)
                return;
            if (root.reducedMotion) {
                keybindList.contentY = target;
                return;
            }
            scrollGlide.to = target;
            scrollGlide.restart();
        }
    }

    NumberAnimation {
        id: scrollGlide
        target: keybindList
        property: "contentY"
        duration: ClockStyle.motionFast.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
    }

    // ── A chord drawn as physical keycaps ───────────────────────────────────────
    // Each cap is a face sitting on a darker lip. Modifiers are tonal; the key that
    // finishes the chord carries the accent. play() presses the caps one after the
    // other, once, the way the chord is typed.
    component Keycaps: Row {
        id: caps

        property var keys: []
        property bool active: false
        property bool large: false
        property color colRow: ClockStyle.colSurfaceHigh
        property color colContent: ClockStyle.colOnSurface
        property color colAccent: ClockStyle.colSecondaryContainer
        property color colOnAccent: ClockStyle.colOnSecondaryContainer
        property int maxKeys: 12

        readonly property int capHeight: caps.large ? 54 : 30
        readonly property int lip: caps.large ? 5 : 3
        readonly property real capRadius: Math.min(caps.large ? Appearance.rounding.normal : Appearance.rounding.small * 0.75, caps.capHeight * 0.3)
        readonly property var macSymbols: ({ "Ctrl": "󰘴", "Alt": "󰘵", "Shift": "󰘶" })
        readonly property var tokens: Array.from(caps.keys ?? []).slice(0, caps.maxKeys).map(key => caps.token(key))

        spacing: caps.large ? 8 : 4

        function token(raw): var {
            const clean = String(raw ?? "").trim();
            const lower = clean.toLowerCase();
            const mac = Config.options.cheatsheet.useMacSymbol;
            const modifier = (text, symbol) => ({
                text: mac && symbol ? symbol : text,
                nerd: mac && Boolean(symbol),
                modifier: true
            });
            if (lower.startsWith("super") || lower === "mod4" || lower === "$mainmod" || lower === "win") {
                const superKey = String(Config.options.cheatsheet.superKey ?? "");
                return { text: superKey || "Super", nerd: superKey.length > 0, modifier: true };
            }
            if (lower === "ctrl" || lower.startsWith("control"))
                return modifier("Ctrl", caps.macSymbols.Ctrl);
            if (lower === "alt" || lower.startsWith("alt_") || lower === "mod1")
                return modifier("Alt", caps.macSymbols.Alt);
            if (lower === "shift" || lower.startsWith("shift_"))
                return modifier("Shift", caps.macSymbols.Shift);
            const named = {
                "mouse:272": "LMB", "mouse:273": "RMB", "mouse:274": "MMB",
                "mouse:275": "Back", "mouse:276": "Fwd",
                "mouse_up": "Scroll ↓", "mouse_down": "Scroll ↑",
                "return": "Enter", "escape": "Esc", "space": "Space", "tab": "Tab",
                "backspace": "⌫", "delete": "Del", "print": "PrtSc",
                "slash": "/", "backslash": "\\", "comma": ",", "period": ".",
                "minus": "−", "equal": "=", "plus": "+", "hash": "#", "grave": "`",
                "left": "←", "right": "→", "up": "↑", "down": "↓",
                "page_up": "PgUp", "page_down": "PgDn"
            };
            if (Object.prototype.hasOwnProperty.call(named, lower))
                return { text: named[lower], nerd: false, modifier: false };
            if (/^xf86/i.test(clean))
                return { text: clean.slice(4).replace(/([a-z])([A-Z])/g, "$1 $2"), nerd: false, modifier: false };
            return { text: clean.length === 1 ? clean.toUpperCase() : clean.replace(/_/g, " "), nerd: false, modifier: false };
        }

        function play() {
            if (Appearance.reducedMotion)
                return;
            for (let i = 0; i < capRepeater.count; i++)
                capRepeater.itemAt(i)?.press(i);
        }

        Repeater {
            id: capRepeater
            model: caps.tokens

            delegate: Item {
                id: cap

                required property var modelData
                required property int index
                readonly property bool accent: !cap.modelData.modifier
                readonly property color colFace: cap.accent
                    ? caps.colAccent
                    : ColorUtils.mix(caps.colContent, caps.colRow, caps.active ? 0.16 : 0.1)
                readonly property color colLabel: cap.accent ? caps.colOnAccent : caps.colContent
                property real pressed: 0

                implicitHeight: caps.capHeight
                implicitWidth: Math.max(caps.capHeight - caps.lip, label.implicitWidth + (caps.large ? 26 : 16))

                function press(order) {
                    pressDelay.duration = order * Math.round(ClockStyle.motionFast.duration * 0.28);
                    pressAnimation.restart();
                }

                SequentialAnimation {
                    id: pressAnimation
                    PauseAnimation {
                        id: pressDelay
                    }
                    NumberAnimation {
                        target: cap
                        property: "pressed"
                        to: 1
                        duration: Math.round(ClockStyle.motionFast.duration * 0.3)
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: cap
                        property: "pressed"
                        to: 0
                        duration: ClockStyle.motionSpatial.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                    }
                }

                // Lip: the side of the key, seen below the face.
                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: caps.lip
                    radius: caps.capRadius
                    color: ColorUtils.mix(cap.colFace, Appearance.m3colors.m3shadow, 0.68)
                    Behavior on color {
                        enabled: !Appearance.reducedMotion
                        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                    }
                }

                Rectangle {
                    width: parent.width
                    height: parent.height - caps.lip
                    y: caps.lip * cap.pressed
                    radius: caps.capRadius
                    color: cap.colFace
                    Behavior on color {
                        enabled: !Appearance.reducedMotion
                        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                    }

                    StyledText {
                        id: label
                        anchors.centerIn: parent
                        text: cap.modelData.text
                        font.family: cap.modelData.nerd ? Appearance.font.family.iconNerd : ClockStyle.fontMain
                        font.variableAxes: cap.modelData.nerd ? ({}) : (cap.accent
                            ? ({ "wght": 780, "wdth": 88, "ROND": 100 })
                            : ({ "wght": 620, "wdth": 76, "ROND": 100 }))
                        font.pixelSize: caps.large ? 26 : (cap.accent ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.smaller)
                        color: cap.colLabel
                    }
                }
            }
        }
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Keybinds")
        icon: "keyboard"
        accent: true
        statusText: root.statusText
        primaryHint: {
            const b = root.selectedBinding();
            if (b && b.canDispatch)
                return ({ label: Translation.tr("Run"), actionId: "activate", keys: ["↵"] });
            return ({ label: Translation.tr("Open page"), actionId: "activate", keys: ["↵"] });
        }
        hints: [
            { label: Translation.tr("Copy"), actionId: "copy", keys: ["Ctrl", "C"] },
            { label: Translation.tr("Source"), actionId: "section", keys: ["Tab"] },
            { label: Translation.tr("Cheat sheet"), actionId: "secondary", keys: ["Ctrl", "↵"] }
        ]

        RowLayout {
            width: parent.width
            height: parent.height
            spacing: ClockStyle.paneGap

            // ── Source rail ──────────────────────────────────────────────────
            Rectangle {
                id: rail
                Layout.preferredWidth: root.railWidth
                Layout.fillHeight: true
                radius: ClockStyle.radiusCard
                color: ClockStyle.colSurface

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gapSmall
                    spacing: ClockStyle.gapSmall

                    // The one number: how many shortcuts the query leaves in this source.
                    Rectangle {
                        id: countTile
                        Layout.fillWidth: true
                        implicitHeight: 128
                        radius: ClockStyle.radiusCard - ClockStyle.gapSmall
                        color: ClockStyle.colTertiaryContainer

                        MaterialShape {
                            id: sourceShape
                            x: ClockStyle.gap
                            y: ClockStyle.gap
                            implicitSize: 40
                            shapeString: root.selectedCategoryData.shape
                            color: ClockStyle.colOnTertiaryContainer

                            Loader {
                                anchors.centerIn: parent
                                active: root.selectedCategoryData.programIcon.length > 0
                                visible: active
                                sourceComponent: IconImage {
                                    implicitSize: 22
                                    source: Quickshell.iconPath(root.selectedCategoryData.programIcon, "image-missing")
                                }
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: root.selectedCategoryData.programIcon.length === 0
                                text: root.selectedCategoryData.icon
                                iconSize: Appearance.font.pixelSize.larger
                                fill: 1
                                color: ClockStyle.colTertiaryContainer
                            }
                        }

                        StyledText {
                            anchors.left: sourceShape.right
                            anchors.leftMargin: ClockStyle.gapSmall + 2
                            anchors.right: parent.right
                            anchors.rightMargin: ClockStyle.gap
                            anchors.verticalCenter: sourceShape.verticalCenter
                            text: root.selectedCategoryData.label
                            elide: Text.ElideRight
                            font.family: ClockStyle.fontTitle
                            font.variableAxes: ClockStyle.axesTitle
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: ClockStyle.colOnTertiaryContainer
                        }

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: ClockStyle.gap + 2
                            anchors.rightMargin: ClockStyle.gap
                            anchors.bottomMargin: 6
                            spacing: ClockStyle.gapSmall

                            StyledText {
                                text: String(root.filteredBindings.length)
                                font.family: ClockStyle.fontMain
                                font.variableAxes: ClockStyle.axesDigitsBold
                                font.pixelSize: 60
                                color: ClockStyle.colOnTertiaryContainer
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignBottom
                                Layout.bottomMargin: 12
                                spacing: -2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.hasQuery ? Translation.tr("matches") : Translation.tr("shortcuts")
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                    color: ClockStyle.colOnTertiaryContainer
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: root.hasQuery
                                    text: Translation.tr("of %1").arg(String(root.allBindings.length))
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: ClockStyle.colOnTertiaryContainer
                                    opacity: 0.72
                                }
                            }
                        }
                    }

                    ListView {
                        id: categoryList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.categories

                        delegate: RippleButton {
                            id: sourceButton
                            required property var modelData
                            readonly property bool selected: root.selectedCategory === modelData.id
                            readonly property int count: root.categoryCounts[modelData.id] ?? 0
                            readonly property color colContent: selected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface

                            width: categoryList.width
                            implicitHeight: 42
                            buttonRadius: Appearance.rounding.full
                            buttonRadiusPressed: Appearance.rounding.small
                            toggled: selected
                            colBackground: ColorUtils.transparentize(ClockStyle.colSurfaceHover, 1)
                            colBackgroundHover: ClockStyle.colSurfaceHover
                            colBackgroundActive: ClockStyle.colSurfaceActive
                            colBackgroundToggled: ClockStyle.colSecondaryContainer
                            colBackgroundToggledHover: ClockStyle.colSecondaryContainerHover
                            colBackgroundToggledActive: ClockStyle.colSecondaryContainerActive
                            colRipple: ClockStyle.colSurfaceActive
                            colRippleToggled: ClockStyle.colSecondaryContainerActive
                            // A source the query left empty steps back without disappearing.
                            opacity: sourceButton.count > 0 || sourceButton.selected ? 1 : 0.45
                            onClicked: root.setCategory(modelData.id)

                            Behavior on opacity {
                                enabled: !root.reducedMotion
                                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                            }

                            contentItem: Item {
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 10

                                    Item {
                                        implicitWidth: 20
                                        implicitHeight: 20

                                        Loader {
                                            anchors.fill: parent
                                            active: sourceButton.modelData.programIcon.length > 0
                                            visible: active
                                            sourceComponent: IconImage {
                                                source: Quickshell.iconPath(sourceButton.modelData.programIcon, "image-missing")
                                            }
                                        }

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            visible: sourceButton.modelData.programIcon.length === 0
                                            text: sourceButton.modelData.icon
                                            iconSize: Appearance.font.pixelSize.larger
                                            fill: sourceButton.selected ? 1 : 0
                                            color: sourceButton.colContent
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: sourceButton.modelData.label
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: sourceButton.selected ? Font.Bold : Font.Medium
                                        color: sourceButton.colContent
                                    }

                                    StyledText {
                                        text: String(sourceButton.count)
                                        font.family: ClockStyle.fontMain
                                        font.variableAxes: ClockStyle.axesDigits
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: sourceButton.colContent
                                        opacity: 0.8
                                    }
                                }
                            }
                        }

                        TouchpadScrollHandler {
                            flickable: categoryList
                        }
                    }

                    RippleButton {
                        id: cheatsheetButton
                        Layout.fillWidth: true
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.full
                        buttonRadiusPressed: Appearance.rounding.small
                        colBackground: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.06)
                        colBackgroundHover: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.12)
                        colBackgroundActive: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.18)
                        colRipple: colBackgroundActive
                        onClicked: root.openCheatsheet()

                        contentItem: Item {
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: ClockStyle.gapSmall

                                MaterialSymbol {
                                    text: "edit_note"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: ClockStyle.colOnSurface
                                }

                                StyledText {
                                    text: Translation.tr("Edit in Cheatsheet")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: ClockStyle.colOnSurface
                                }
                            }
                        }
                    }
                }
            }

            // ── Shortcuts ────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: keybindList
                    anchors.fill: parent
                    clip: true
                    spacing: 2
                    cacheBuffer: height
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.rows
                    visible: root.rows.length > 0

                    delegate: Loader {
                        id: rowLoader
                        required property int index
                        required property var modelData
                        width: keybindList.width
                        height: item?.implicitHeight ?? 0
                        sourceComponent: rowLoader.modelData.kind === "section" ? sectionRow : bindingRow

                        Component {
                            id: sectionRow

                            // Group caption in the rounded title face; the source as a quiet
                            // trailing caption only where several sources share the list.
                            Item {
                                implicitHeight: rowLoader.index === 0 ? 30 : 42

                                RowLayout {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 12
                                    anchors.bottomMargin: 6
                                    spacing: ClockStyle.gapSmall

                                    StyledText {
                                        Layout.maximumWidth: Math.round(rowLoader.width * 0.62)
                                        text: rowLoader.modelData.name
                                        elide: Text.ElideRight
                                        font.family: ClockStyle.fontTitle
                                        font.variableAxes: ClockStyle.axesTitle
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: ClockStyle.colPrimary
                                    }

                                    StyledText {
                                        visible: root.selectedCategory === "all"
                                        text: rowLoader.modelData.sourceLabel.toUpperCase()
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.2
                                        color: ClockStyle.colSubtext
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    StyledText {
                                        text: String(rowLoader.modelData.count)
                                        font.family: ClockStyle.fontMain
                                        font.variableAxes: ClockStyle.axesDigits
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: ClockStyle.colSubtext
                                    }
                                }
                            }
                        }

                        Component {
                            id: bindingRow

                            RippleButton {
                                id: bindingButton

                                readonly property var binding: rowLoader.modelData.binding
                                readonly property bool selected: root.selectedIndex === rowLoader.index
                                readonly property bool aboveSelected: root.selectedIndex === rowLoader.index + 1
                                readonly property bool belowSelected: root.selectedIndex === rowLoader.index - 1
                                readonly property real pill: Math.min(root.rowHeight / 2, Appearance.rounding.large)
                                readonly property real join: Appearance.rounding.verysmall
                                readonly property color colContent: selected ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface
                                readonly property color colRow: selected ? ClockStyle.colPrimaryContainer : ClockStyle.colSurfaceHigh
                                readonly property string detailText: binding.canDispatch
                                    ? `${binding.dispatcher} ${binding.params}`.trim()
                                    : (binding.notes || Translation.tr("From “%1”").arg(binding.sourceLabel))
                                readonly property string subline: binding.context || (binding.canDispatch ? "" : binding.notes)
                                property real reveal: selected ? 1 : 0

                                implicitWidth: rowLoader.width
                                implicitHeight: root.rowHeight + Math.round(root.detailHeight * Math.max(0, bindingButton.reveal))
                                clip: true
                                topLeftRadius: selected ? Appearance.rounding.large
                                    : (belowSelected ? pill : (rowLoader.modelData.first ? Appearance.rounding.large : join))
                                topRightRadius: topLeftRadius
                                bottomLeftRadius: selected ? Appearance.rounding.large
                                    : (aboveSelected ? pill : (rowLoader.modelData.last ? Appearance.rounding.large : join))
                                bottomRightRadius: bottomLeftRadius
                                toggled: selected
                                colBackground: ClockStyle.colSurfaceHigh
                                colBackgroundHover: ClockStyle.colSurfaceHover
                                colBackgroundActive: ClockStyle.colSurfaceActive
                                colBackgroundToggled: ClockStyle.colPrimaryContainer
                                colBackgroundToggledHover: ClockStyle.colPrimaryContainerHover
                                colBackgroundToggledActive: ClockStyle.colPrimaryContainerActive
                                colRipple: ClockStyle.colSurfaceActive
                                colRippleToggled: ClockStyle.colPrimaryContainerActive

                                // The first click selects (and opens the row); the second runs it.
                                onClicked: {
                                    if (bindingButton.selected)
                                        root.activateSelected();
                                    else
                                        root.select(rowLoader.index);
                                }
                                onSelectedChanged: {
                                    if (bindingButton.selected)
                                        keycaps.play();
                                }
                                Component.onCompleted: {
                                    if (bindingButton.selected)
                                        keycaps.play();
                                }

                                function activate(): bool {
                                    return root.activateSelected();
                                }

                                Behavior on reveal {
                                    enabled: !root.reducedMotion
                                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                                }

                                RowLayout {
                                    id: headline
                                    x: 18
                                    width: parent.width - 18 - 12
                                    height: root.rowHeight
                                    spacing: ClockStyle.gap

                                    MaterialSymbol {
                                        visible: Boolean(bindingButton.binding.itemIcon)
                                        text: String(bindingButton.binding.itemIcon ?? "")
                                        iconSize: Appearance.font.pixelSize.larger
                                        fill: bindingButton.selected ? 1 : 0
                                        color: bindingButton.selected ? ClockStyle.colPrimary : ClockStyle.colOnSurfaceVariant
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: bindingButton.binding.name
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: bindingButton.selected ? Font.Bold : Font.DemiBold
                                            color: bindingButton.colContent
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: bindingButton.subline.length > 0
                                            text: bindingButton.subline
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: bindingButton.colContent
                                            opacity: 0.72
                                        }
                                    }

                                    Keycaps {
                                        id: keycaps
                                        Layout.alignment: Qt.AlignVCenter
                                        keys: bindingButton.binding.keys
                                        active: bindingButton.selected
                                        colRow: bindingButton.colRow
                                        colContent: bindingButton.colContent
                                        colAccent: bindingButton.selected ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer
                                        colOnAccent: bindingButton.selected ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
                                    }
                                }

                                // What the shortcut does, and what can be done with it. Built
                                // only while the row is open.
                                Loader {
                                    x: 12
                                    y: root.rowHeight - 4
                                    width: parent.width - 24
                                    height: root.detailHeight - 8
                                    active: bindingButton.reveal > 0.01
                                    opacity: Math.max(0, Math.min(1, bindingButton.reveal * 1.4 - 0.4))

                                    sourceComponent: RowLayout {
                                        spacing: ClockStyle.gapSmall

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 80
                                            Layout.preferredWidth: detailRow.implicitWidth + 24
                                            Layout.maximumWidth: detailRow.implicitWidth + 24
                                            implicitHeight: 34
                                            radius: Appearance.rounding.small
                                            color: ColorUtils.mix(ClockStyle.colOnPrimaryContainer, ClockStyle.colPrimaryContainer, 0.08)

                                            RowLayout {
                                                id: detailRow
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 12
                                                spacing: 6

                                                MaterialSymbol {
                                                    text: bindingButton.binding.canDispatch ? "terminal" : "sticky_note_2"
                                                    iconSize: Appearance.font.pixelSize.normal
                                                    color: ClockStyle.colOnPrimaryContainer
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: bindingButton.detailText
                                                    elide: Text.ElideRight
                                                    font.family: bindingButton.binding.canDispatch ? Appearance.font.family.monospace : ClockStyle.fontMain
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    color: ClockStyle.colOnPrimaryContainer
                                                }
                                            }
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 0
                                        }

                                        ClockCardAction {
                                            symbol: "content_copy"
                                            tip: Translation.tr("Copy keys")
                                            colContent: ClockStyle.colOnPrimaryContainer
                                            onClicked: root.copySelected()
                                        }

                                        ClockCardAction {
                                            symbol: "menu_book"
                                            tip: Translation.tr("Show in Cheatsheet")
                                            colContent: ClockStyle.colOnPrimaryContainer
                                            onClicked: root.openSelectedInCheatsheet()
                                        }

                                        RippleButton {
                                            id: runButton
                                            implicitHeight: 34
                                            implicitWidth: runRow.implicitWidth + 28
                                            buttonRadius: Appearance.rounding.full
                                            buttonRadiusPressed: Appearance.rounding.small
                                            colBackground: ClockStyle.colPrimary
                                            colBackgroundHover: ClockStyle.colPrimaryHover
                                            colBackgroundActive: ClockStyle.colPrimaryActive
                                            colRipple: ClockStyle.colPrimaryActive
                                            onClicked: root.activateSelected()

                                            contentItem: Item {
                                                RowLayout {
                                                    id: runRow
                                                    anchors.centerIn: parent
                                                    spacing: 6

                                                    MaterialSymbol {
                                                        text: bindingButton.binding.canDispatch ? "play_arrow" : "arrow_outward"
                                                        iconSize: Appearance.font.pixelSize.larger
                                                        fill: 1
                                                        color: ClockStyle.colOnPrimary
                                                    }

                                                    StyledText {
                                                        text: bindingButton.binding.canDispatch ? Translation.tr("Run") : Translation.tr("Open page")
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        font.weight: Font.Bold
                                                        color: ClockStyle.colOnPrimary
                                                    }

                                                    ConfiguredKeyHint {
                                                        visible: Config.options.search.appearance.showKeyHints
                                                        actionId: "activate"
                                                        fallbackKeys: ["↵"]
                                                        surface: ClockStyle.colPrimary
                                                        onSurface: ClockStyle.colOnPrimary
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    TouchpadScrollHandler {
                        flickable: keybindList
                    }
                }

                // ── Empty: the query, spelled in keycaps ──────────────────────
                Rectangle {
                    id: emptyPane
                    anchors.fill: parent
                    visible: root.rows.length === 0
                    radius: ClockStyle.radiusCard
                    color: ClockStyle.colSurfaceHigh

                    readonly property int elsewhere: root.categoryCounts.all ?? 0
                    readonly property var letters: root.hasQuery
                        ? Array.from(root.searchQuery.trim().replace(/\s+/g, "")).slice(0, 9)
                        : ["Super", "?"]

                    onVisibleChanged: if (visible) emptyPlay.restart()

                    Timer {
                        id: emptyPlay
                        interval: 260
                        onTriggered: emptyCaps.play()
                    }

                    Connections {
                        target: root
                        function onSearchQueryChanged() {
                            if (emptyPane.visible)
                                emptyPlay.restart();
                        }
                    }

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: ClockStyle.pagePaddingWide + 8
                        anchors.rightMargin: ClockStyle.pagePaddingWide + 8
                        spacing: ClockStyle.gapLarge

                        Keycaps {
                            id: emptyCaps
                            large: true
                            keys: emptyPane.letters
                            colRow: emptyPane.color
                            colContent: ClockStyle.colOnSurface
                            colAccent: ClockStyle.colTertiaryContainer
                            colOnAccent: ClockStyle.colOnTertiaryContainer
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapSmall

                            StyledText {
                                Layout.fillWidth: true
                                text: root.hasQuery
                                    ? Translation.tr("Nothing is bound to that")
                                    : Translation.tr("No shortcuts here yet")
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                lineHeight: 0.9
                                font.family: ClockStyle.fontMain
                                font.variableAxes: ({ "wght": 800, "wdth": 62, "ROND": 0 })
                                font.pixelSize: 40
                                color: ClockStyle.colOnSurface
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: !root.hasQuery
                                    ? Translation.tr("Add a page of shortcuts in the Cheatsheet and it shows up here.")
                                    : (emptyPane.elsewhere > 0 && root.selectedCategory !== "all"
                                        ? Translation.tr("%1 matches in other sources.").arg(String(emptyPane.elsewhere))
                                        : Translation.tr("Search by what a shortcut does — close, workspace, screenshot."))
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: ClockStyle.colOnSurfaceVariant
                            }
                        }

                        RowLayout {
                            spacing: ClockStyle.gapSmall

                            RippleButton {
                                visible: root.hasQuery && emptyPane.elsewhere > 0 && root.selectedCategory !== "all"
                                implicitHeight: 44
                                implicitWidth: allRow.implicitWidth + 32
                                buttonRadius: Appearance.rounding.full
                                buttonRadiusPressed: Appearance.rounding.small
                                colBackground: ClockStyle.colPrimary
                                colBackgroundHover: ClockStyle.colPrimaryHover
                                colBackgroundActive: ClockStyle.colPrimaryActive
                                colRipple: ClockStyle.colPrimaryActive
                                onClicked: root.setCategory("all")

                                contentItem: Item {
                                    RowLayout {
                                        id: allRow
                                        anchors.centerIn: parent
                                        spacing: ClockStyle.gapSmall

                                        MaterialSymbol {
                                            text: "all_inclusive"
                                            iconSize: Appearance.font.pixelSize.larger
                                            color: ClockStyle.colOnPrimary
                                        }

                                        StyledText {
                                            text: Translation.tr("Search all sources")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Bold
                                            color: ClockStyle.colOnPrimary
                                        }
                                    }
                                }
                            }

                            RippleButton {
                                implicitHeight: 44
                                implicitWidth: addRow.implicitWidth + 32
                                buttonRadius: Appearance.rounding.full
                                buttonRadiusPressed: Appearance.rounding.small
                                colBackground: ClockStyle.colSecondaryContainer
                                colBackgroundHover: ClockStyle.colSecondaryContainerHover
                                colBackgroundActive: ClockStyle.colSecondaryContainerActive
                                colRipple: ClockStyle.colSecondaryContainerActive
                                onClicked: root.openCheatsheet()

                                contentItem: Item {
                                    RowLayout {
                                        id: addRow
                                        anchors.centerIn: parent
                                        spacing: ClockStyle.gapSmall

                                        MaterialSymbol {
                                            text: "add"
                                            iconSize: Appearance.font.pixelSize.larger
                                            color: ClockStyle.colOnSecondaryContainer
                                        }

                                        StyledText {
                                            text: Translation.tr("Add in Cheatsheet")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Bold
                                            color: ClockStyle.colOnSecondaryContainer
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
