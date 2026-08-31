pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The keyboard layouts in use, and the catalogue to add to them.
 *
 * Hyprland keeps the layouts in one comma-separated string and their variants in another, in the
 * same order, which is a shape you cannot edit one row at a time. So the page shows it as what it
 * means: a list you own at the top - reorder it, drop from it - and the catalogue underneath,
 * where picking appends rather than replaces. Both halves write the pair together, which is the
 * only way to leave it in a state that says what it means.
 *
 * The catalogue is flat on purpose: "French (AZERTY)" is a row, not a French row you then have to
 * open. The shortlist on top is the same one the Welcome flow offers, in the languages' own
 * names. Everything under it comes from the system's own XKB rules file.
 */
Item {
    id: root
    anchors.fill: parent

    signal goBack
    property bool showBackButton: false

    readonly property string rawLayout: String(HyprlandGui.displayValue("input:kb_layout", "us") ?? "")
    readonly property string rawVariant: String(HyprlandGui.displayValue("input:kb_variant", "") ?? "")

    /// [{ layout, variant }] in the order Hyprland has them. The first one is active at startup.
    readonly property var chosen: {
        const layouts = root.rawLayout.split(",").map(part => part.trim()).filter(part => part !== "");
        const variants = root.rawVariant.split(",").map(part => part.trim());
        return layouts.map((layout, index) => ({
            "layout": layout,
            "variant": variants[index] ?? ""
        }));
    }

    function has(layout: string, variant: string): bool {
        return root.chosen.some(entry => entry.layout === layout && entry.variant === variant);
    }

    function describe(layout: string, variant: string): string {
        if (!XkbCatalog.loaded) return layout;
        return variant === "" ? XkbCatalog.layoutName(layout) : XkbCatalog.variantName(layout, variant);
    }

    function code(layout: string, variant: string): string {
        return variant === "" ? layout : `${layout} ${variant}`;
    }

    function matches(row: var, query: string): bool {
        if (query === "") return true;
        return row.name.toLowerCase().indexOf(query) >= 0
            || row.layout.indexOf(query) >= 0
            || row.variant.indexOf(query) >= 0;
    }

    /// Write the whole list back, layouts and variants together.
    function write(entries: var) {
        const layouts = entries.map(entry => entry.layout);
        const variants = entries.map(entry => entry.variant);
        HyprlandGui.batch(() => {
            HyprlandGui.setKey("input:kb_layout", layouts.join(","));
            // An empty variant still has to be written when something else sets one, or the old
            // value survives; when nothing does, dropping the key is tidier than a row of commas.
            if (variants.every(variant => variant === "")
                    && HyprlandGui.resolve("input:kb_variant").inherited === null)
                HyprlandGui.resetKey("input:kb_variant");
            else
                HyprlandGui.setKey("input:kb_variant", variants.join(","));
        });
    }

    function add(layout: string, variant: string) {
        if (root.has(layout, variant)) return;
        root.write(root.chosen.concat([{ "layout": layout, "variant": variant }]));
    }

    /// Hyprland needs a layout, so the last one cannot be dropped - it is replaced instead.
    function removeAt(index: int) {
        if (root.chosen.length <= 1) return;
        root.write(root.chosen.filter((entry, at) => at !== index));
    }

    function moveBy(index: int, offset: int) {
        const target = index + offset;
        if (target < 0 || target >= root.chosen.length) return;
        const next = root.chosen.slice();
        const moved = next[index];
        next[index] = next[target];
        next[target] = moved;
        root.write(next);
    }

    readonly property var rows: {
        const query = searchField.text.trim().toLowerCase();
        let out = [{ "header": Translation.tr("Your layouts") }];
        for (let index = 0; index < root.chosen.length; index++) {
            const entry = root.chosen[index];
            out.push({
                "kind": "current",
                "index": index,
                "layout": entry.layout,
                "variant": entry.variant,
                "name": root.describe(entry.layout, entry.variant)
            });
        }
        // Something already in the list at the top has no business being offered again below it.
        const offered = row => root.matches(row, query) && !root.has(row.layout, row.variant);
        const common = XkbCatalog.commonLayouts
            .map(entry => ({ "layout": entry.code, "variant": "", "name": entry.label }))
            .filter(offered);
        const all = XkbCatalog.pickerRows().filter(offered);
        if (common.length > 0)
            out = out.concat([{ "header": Translation.tr("Common") }], common);
        if (all.length > 0)
            out = out.concat([{ "header": Translation.tr("All layouts") }], all);
        return out;
    }

    Component.onCompleted: {
        XkbCatalog.load();
        HyprlandGui.watch(["input:kb_layout", "input:kb_variant"]);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: Translation.tr("Keyboard layout")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.chosen.length > 1
                        ? Translation.tr("%1 layouts, the first one active at startup.").arg(root.chosen.length)
                        : Translation.tr("Pick one below, or add a second to switch between them.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        // Two layouts and no way to reach the second one is a setting that looks broken, so the
        // switch that reaches it lives here, next to the list that made it necessary.
        HyprXkbOptionSwitch {
            visible: root.chosen.length > 1
            option: "grp:alt_shift_toggle"
            buttonIcon: "language"
            alwaysExplain: true
            text: Translation.tr("Alt+Shift switches between layouts")
            textOn: Translation.tr("Alt+Shift moves to the next layout in the list.")
            textOff: Translation.tr("Alt+Shift does nothing special; layouts are switched from the bar or a shortcut.")
        }

        MaterialTextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: XkbCatalog.loaded
                ? Translation.tr("Search %1 layouts to add").arg(XkbCatalog.layouts.length)
                : Translation.tr("Reading the system's layout list…")
        }

        StyledListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2
            clip: true
            // Filtered per keystroke; replaying the entry animation on every letter reads as
            // a stutter, not an animation.
            animateAppearance: false
            model: root.rows

            delegate: Item {
                id: entryRow

                required property var modelData

                readonly property bool isHeader: modelData.header !== undefined
                readonly property bool isCurrent: modelData.kind === "current"
                /// The one Hyprland starts on, filled in rather than outlined so the order the
                /// list is in reads as an order and not a set.
                readonly property bool leading: entryRow.isCurrent && modelData.index === 0
                readonly property color rowColor: entryRow.leading ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colLayer1
                readonly property color onRowColor: entryRow.leading ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colOnLayer1

                width: list.width
                implicitHeight: entryRow.isHeader ? 34 : (entryRow.isCurrent ? 52 : 44)

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    visible: entryRow.isHeader
                    text: entryRow.isHeader ? entryRow.modelData.header : ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.bottomMargin: 2
                    visible: entryRow.isCurrent
                    radius: Appearance.rounding.normal
                    color: entryRow.rowColor

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 6
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: entryRow.isCurrent ? entryRow.modelData.name : ""
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: entryRow.onRowColor
                            }

                            StyledText {
                                text: entryRow.isCurrent
                                    ? (entryRow.leading
                                        ? Translation.tr("%1 · at startup").arg(root.code(entryRow.modelData.layout, entryRow.modelData.variant))
                                        : root.code(entryRow.modelData.layout, entryRow.modelData.variant))
                                    : ""
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.monospace
                                color: entryRow.onRowColor
                                opacity: 0.7
                            }
                        }

                        RowAction {
                            symbol: "keyboard_arrow_up"
                            tint: entryRow.onRowColor
                            tooltip: Translation.tr("Move up")
                            enabled: entryRow.isCurrent && entryRow.modelData.index > 0
                            onClicked: root.moveBy(entryRow.modelData.index, -1)
                        }

                        RowAction {
                            symbol: "keyboard_arrow_down"
                            tint: entryRow.onRowColor
                            tooltip: Translation.tr("Move down")
                            enabled: entryRow.isCurrent && entryRow.modelData.index < root.chosen.length - 1
                            onClicked: root.moveBy(entryRow.modelData.index, 1)
                        }

                        RowAction {
                            symbol: "close"
                            tint: entryRow.onRowColor
                            tooltip: root.chosen.length > 1 ? Translation.tr("Remove")
                                : Translation.tr("The last layout cannot be removed")
                            enabled: root.chosen.length > 1
                            onClicked: root.removeAt(entryRow.modelData.index)
                        }
                    }
                }

                RippleButton {
                    anchors.fill: parent
                    visible: !entryRow.isHeader && !entryRow.isCurrent
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: root.add(entryRow.modelData.layout, entryRow.modelData.variant)

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        MaterialSymbol {
                            text: "add"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: entryRow.isHeader || entryRow.isCurrent ? "" : entryRow.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            text: entryRow.isHeader || entryRow.isCurrent ? ""
                                : root.code(entryRow.modelData.layout, entryRow.modelData.variant)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            visible: XkbCatalog.loaded && root.rows.length === 1 + root.chosen.length
            text: Translation.tr("No layout matches \"%1\".").arg(searchField.text.trim())
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignHCenter
        }

        StyledText {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            visible: XkbCatalog.failed
            text: Translation.tr("Could not read %1, so only the shortlist is available.").arg(XkbCatalog.source)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
            wrapMode: Text.WordWrap
        }
    }

    /// A round icon button sized for a list row, dimmed rather than hidden when it does not
    /// apply - buttons that come and go move the two next to them every time the list changes.
    component RowAction: RippleButton {
        id: action

        required property string symbol
        required property color tint
        property string tooltip: ""

        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        opacity: action.enabled ? 1 : 0.35
        colBackground: ColorUtils.transparentize(action.tint, 1)
        colBackgroundHover: ColorUtils.transparentize(action.tint, 0.88)
        colRipple: ColorUtils.transparentize(action.tint, 0.75)

        MaterialSymbol {
            anchors.centerIn: parent
            text: action.symbol
            iconSize: Appearance.font.pixelSize.large
            color: action.tint
        }

        StyledToolTip {
            text: action.tooltip
        }
    }
}
