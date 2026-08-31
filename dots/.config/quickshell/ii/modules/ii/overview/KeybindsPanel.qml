pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: -1
    property string selectedCategory: "all"

    readonly property bool supportsSectionToggle: true
    readonly property string normalizedQuery: root.searchQuery.trim().toLocaleLowerCase()

    readonly property var categories: {
        const revision = KeybindsService.revision;
        const list = [
            { id: "all", label: Translation.tr("All"), icon: "all_inclusive", pageId: "" },
            { id: "hyprland", label: Translation.tr("Hyprland"), icon: "desktop_windows", pageId: "" }
        ];
        for (const page of KeybindsService.pages ?? []) {
            list.push({
                id: "page_" + String(page.id ?? ""),
                label: String(page.name ?? Translation.tr("Shortcuts")),
                icon: String(page.icon ?? "keyboard"),
                pageId: String(page.id ?? ""),
                program: String(page.program ?? ""),
                programId: String(page.programId ?? ""),
                useProgramIcon: Boolean(page.useProgramIcon)
            });
        }
        return list;
    }

    readonly property var allBindings: root.collectAllBindings()

    readonly property var activeBindings: {
        if (root.selectedCategory === "all")
            return root.allBindings;
        if (root.selectedCategory === "hyprland")
            return root.allBindings.filter(binding => binding.source === "hyprland");
        return root.allBindings.filter(binding => binding.source === root.selectedCategory);
    }

    readonly property var filteredBindings: root.activeBindings.filter(binding => {
        const terms = root.normalizedQuery.split(/\s+/).filter(term => term.length > 0);
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
        return terms.length === 0 || terms.every(term => haystack.includes(term));
    })

    readonly property var rows: root.sectionRows(root.filteredBindings)
    readonly property string statusText: Translation.tr("%1 shortcuts").arg(String(root.filteredBindings.length))

    implicitWidth: 720
    implicitHeight: scaffold.implicitHeight

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

    function sectionRows(bindings) {
        const output = [];
        let previousHeader = "";
        for (const binding of bindings) {
            const header = root.selectedCategory === "all"
                ? (binding.sourceLabel + " · " + binding.section)
                : binding.section;
            if (header !== previousHeader) {
                output.push({ kind: "section", name: header });
                previousHeader = header;
            }
            output.push({ kind: "binding", binding });
        }
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

    function moveSelection(direction) {
        if (root.filteredBindings.length === 0)
            return false;
        let index = root.selectedIndex;
        do {
            index += direction;
        } while (index >= 0 && index < root.rows.length && !root.isBindingIndex(index));
        if (!root.isBindingIndex(index))
            return false;
        root.selectedIndex = index;
        keybindList.positionViewAtIndex(index, ListView.Contain);
        return true;
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
        const index = root.categories.findIndex(c => c.id === categoryId);
        if (index >= 0) {
            categoryTabsList.positionViewAtIndex(index, ListView.Contain);
        }
    }

    onRowsChanged: root.clampSelection()
    onSelectedCategoryChanged: root.clampSelection()
    Component.onCompleted: root.clampSelection()

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Keybinds")
        icon: "keyboard"
        accent: true
        statusText: root.statusText
        showStatus: true
        primaryHint: {
            const b = root.selectedBinding();
            if (b && b.canDispatch)
                return ({ label: Translation.tr("Run"), actionId: "activate", keys: ["↵"] });
            return ({ label: Translation.tr("Open page"), actionId: "activate", keys: ["↵"] });
        }
        hints: [
            { label: Translation.tr("Copy"), actionId: "copy", keys: ["Ctrl", "C"] },
            { label: Translation.tr("Category"), actionId: "section", keys: ["Tab"] },
            { label: Translation.tr("Cheat sheet"), actionId: "secondary", keys: ["Ctrl", "↵"] }
        ]

        ColumnLayout {
            width: parent.width
            height: parent.height
            spacing: Appearance.sizes.elevationMargin

            // ── Category Selector Tab Bar ──
            ListView {
                id: categoryTabsList
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                orientation: ListView.Horizontal
                spacing: 6
                clip: true
                model: root.categories

                delegate: RippleButton {
                    id: tabButton
                    required property var modelData
                    implicitHeight: 32
                    implicitWidth: tabContent.implicitWidth + 18
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
                    onClicked: root.setCategory(modelData.id)

                    RowLayout {
                        id: tabContent
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: String(tabButton.modelData.icon ?? "keyboard")
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.selectedCategory === tabButton.modelData.id
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colSubtext
                        }

                        StyledText {
                            text: String(tabButton.modelData.label ?? "")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: root.selectedCategory === tabButton.modelData.id ? Font.Bold : Font.Normal
                            color: root.selectedCategory === tabButton.modelData.id
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnSurface
                        }
                    }
                }
            }

            ListView {
                id: keybindList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: emptyState.implicitHeight
                clip: true
                spacing: Appearance.sizes.elevationMargin / 2
                model: root.rows
                visible: root.rows.length > 0

                delegate: Loader {
                    id: rowLoader
                    required property int index
                    required property var modelData
                    width: keybindList.width
                    sourceComponent: rowLoader.modelData.kind === "section" ? sectionRow : bindingRow

                    Component {
                        id: sectionRow

                        StyledText {
                            width: rowLoader.width
                            text: rowLoader.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                            topPadding: Appearance.sizes.elevationMargin / 2
                        }
                    }

                    Component {
                        id: bindingRow

                        RippleButton {
                            readonly property var binding: rowLoader.modelData.binding
                            implicitWidth: rowLoader.width
                            implicitHeight: bindingContent.implicitHeight + Appearance.sizes.elevationMargin * 2
                            buttonRadius: Appearance.rounding.normal
                            colBackground: root.selectedIndex === rowLoader.index
                                ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colSurfaceContainerHigh
                            colBackgroundHover: root.selectedIndex === rowLoader.index
                                ? Appearance.colors.colPrimaryContainerHover
                                : Appearance.colors.colSurfaceContainerHighestHover
                            colRipple: root.selectedIndex === rowLoader.index
                                ? Appearance.colors.colPrimaryContainerActive
                                : Appearance.colors.colSurfaceContainerHighestActive
                            onClicked: {
                                root.selectedIndex = rowLoader.index;
                                activate();
                            }

                            function activate(): bool {
                                return root.activateSelected();
                            }

                            RowLayout {
                                id: bindingContent
                                anchors.fill: parent
                                anchors.margins: Appearance.sizes.elevationMargin
                                spacing: Appearance.sizes.elevationMargin

                                MaterialSymbol {
                                    visible: Boolean(binding.itemIcon)
                                    text: String(binding.itemIcon ?? "")
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: root.selectedIndex === rowLoader.index
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colPrimary
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: binding.name
                                        elide: Text.ElideRight
                                        font.weight: Font.DemiBold
                                        color: root.selectedIndex === rowLoader.index
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colOnSurface
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            const parts = [];
                                            if (root.selectedCategory === "all")
                                                parts.push(binding.sourceLabel);
                                            parts.push(binding.section);
                                            if (binding.context)
                                                parts.push(binding.context);
                                            return parts.join(" · ");
                                        }
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: root.selectedIndex === rowLoader.index
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colSubtext
                                    }
                                }

                                KeyHint {
                                    keys: binding.keys
                                    surface: root.selectedIndex === rowLoader.index
                                        ? Appearance.colors.colPrimaryContainer
                                        : Appearance.colors.colSurfaceContainerHigh
                                    onSurface: root.selectedIndex === rowLoader.index
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colOnSurface
                                }

                                ConfiguredKeyHint {
                                    visible: root.selectedIndex === rowLoader.index && Config.options.search.appearance.showKeyHints
                                    actionId: "activate"
                                    fallbackKeys: ["↵"]
                                    surface: Appearance.colors.colPrimaryContainer
                                    onSurface: Appearance.colors.colOnPrimaryContainer
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                id: emptyState
                Layout.fillWidth: true
                visible: root.rows.length === 0
                text: Translation.tr("No shortcuts match \"%1\"").arg(root.normalizedQuery)
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }
}

