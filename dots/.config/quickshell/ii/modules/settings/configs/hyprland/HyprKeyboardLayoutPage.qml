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

    /**
     * The row Hyprland is on right now, or -1.
     *
     * The one at the top is the one it starts on, which stops being the one in use the moment
     * anything switches away from it - so a list that only says "at startup" answers the wrong
     * question for the rest of the session.
     *
     * Hyprland names the active layout by its description rather than its code, and that
     * description is the one the catalogue prints on the row, so the two are matched on it. No
     * match means no claim: a wrong pill is worse than none.
     */
    readonly property int activeIndex: {
        const active = HyprlandXkb.currentLayoutName;
        if (active === "" || root.chosen.length <= 1) return -1;
        return root.chosen.findIndex(entry => root.describe(entry.layout, entry.variant) === active);
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

    /// A dropped row is taken out of the list and put back where it landed, so everything between
    /// the two positions closes up behind it - which is what the drag showed happening.
    function moveTo(from: int, to: int) {
        if (from === to) return;
        const next = root.chosen.slice();
        next.splice(to, 0, next.splice(from, 1)[0]);
        root.write(next);
    }

    /// The catalogue underneath, headers included. The layouts in use are their own list above
    /// this one: they are dragged rather than scrolled through, which a ListView cannot do.
    readonly property var rows: {
        const query = searchField.text.trim().toLowerCase();
        let out = [];
        // Something already in the list above has no business being offered again below it.
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

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Your layouts")
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: Appearance.colors.colSubtext
        }

        /**
         * The order is the setting, so it is set by putting the rows in order.
         *
         * A pair of arrows per row said the same thing, but a row moved by pressing a button
         * lands somewhere the eye has to go and find afterwards. Dragging shows the list it will
         * be while it is still being decided.
         */
        DragOrderList {
            id: chosenList

            Layout.fillWidth: true
            count: root.chosen.length
            spacing: 4
            onMoved: (from, to) => root.moveTo(from, to)

            delegate: LayoutRow {
                id: chosenRow

                Layout.fillWidth: true
                draggable: chosenList.count > 1
                // The row keeps its slot while the copy under the pointer stands in for it.
                opacity: chosenList.dragFrom === chosenRow.index ? 0 : 1

                transform: Translate {
                    y: chosenList.shiftFor(chosenRow.index)

                    Behavior on y {
                        enabled: chosenList.dragging
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                onDragStarted: y => {
                    chosenList.pointerY = chosenRow.mapToItem(chosenList, 0, y).y;
                    chosenList.beginDrag(chosenRow.index, y);
                }
                onDragMoved: y => chosenList.pointerMoved(chosenRow, y)
                onDragEnded: chosenList.endDrag()
            }

            ghostDelegate: Item {
                implicitHeight: ghostRow.implicitHeight

                StyledRectangularShadow {
                    target: ghostRow
                }

                LayoutRow {
                    id: ghostRow
                    anchors {
                        left: parent.left
                        right: parent.right
                    }
                    index: chosenList.dragFrom
                    ghost: true
                    enabled: false
                    scale: 1.01
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

                width: list.width
                implicitHeight: entryRow.isHeader ? 34 : 44

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

                RippleButton {
                    anchors.fill: parent
                    visible: !entryRow.isHeader
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
                            text: entryRow.isHeader ? "" : entryRow.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            text: entryRow.isHeader ? ""
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
            visible: XkbCatalog.loaded && root.rows.length === 0
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

    /**
     * One layout in use.
     *
     * Every row is drawn the same. The first one used to be a filled accent bar, which next to a
     * plain row read as two lists rather than one ordered list, and on its own read as a
     * selection nobody had made. What is special about it is one fact, so it says the fact.
     */
    component LayoutRow: RippleButton {
        id: layoutEntry

        required property int index
        property bool draggable: true
        /// The copy under the pointer: it shows the handle held down and no button to press.
        property bool ghost: false

        signal dragStarted(real y)
        signal dragMoved(real y)
        signal dragEnded

        readonly property var entry: root.chosen[layoutEntry.index] ?? ({
            "layout": "",
            "variant": ""
        })

        implicitHeight: 54
        // Not the grouped-list radius: that one reads its neighbours to round the ends of a run
        // and square the joins inside it, which on a list with gaps between the rows squares off
        // corners that have nothing next to them - and it re-rounds them again as rows are
        // pressed and dragged past each other. Every row here is its own card, always.
        buttonRadius: Appearance.rounding.normal
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        // Nothing happens when the row itself is clicked - the handle and the button on it are
        // what respond - so it does not offer the hand a button would.
        pointingHandCursor: false

        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            MouseArea {
                id: handle

                visible: layoutEntry.draggable
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 22
                implicitHeight: 40
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                // Without this the page's own flick takes the drag away as soon as it moves.
                preventStealing: true

                onPressed: mouse => layoutEntry.dragStarted(handle.mapToItem(layoutEntry, mouse.x, mouse.y).y)
                onPositionChanged: mouse => {
                    if (handle.pressed)
                        layoutEntry.dragMoved(handle.mapToItem(layoutEntry, mouse.x, mouse.y).y);
                }
                onReleased: layoutEntry.dragEnded()
                onCanceled: layoutEntry.dragEnded()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "drag_indicator"
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                    opacity: layoutEntry.hovered || handle.containsMouse || layoutEntry.ghost ? 1 : 0.35

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.describe(layoutEntry.entry.layout, layoutEntry.entry.variant)
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    text: root.code(layoutEntry.entry.layout, layoutEntry.entry.variant)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colSubtext
                }
            }

            // Both only matter when there is more than one row for them to pick out, and the two
            // are often the same row - which is worth seeing as much as the moment they differ.
            RowPill {
                visible: layoutEntry.index === root.activeIndex
                label: Translation.tr("in use")
                fill: Appearance.colors.colSecondaryContainer
                ink: Appearance.colors.colOnSecondaryContainer
            }

            RowPill {
                visible: layoutEntry.index === 0 && root.chosen.length > 1
                label: Translation.tr("at startup")
                fill: Appearance.colors.colPrimaryContainer
                ink: Appearance.colors.colOnPrimaryContainer
            }

            RowAction {
                symbol: "close"
                tint: Appearance.colors.colOnLayer2
                hoverTint: Appearance.colors.colError
                visible: !layoutEntry.ghost
                tooltip: root.chosen.length > 1 ? Translation.tr("Remove")
                    : Translation.tr("The last layout cannot be removed")
                enabled: root.chosen.length > 1
                onClicked: root.removeAt(layoutEntry.index)
            }
        }
    }

    /// A word on a row saying what is true of it, rather than a colour whose meaning the reader
    /// has to work out from the other rows.
    component RowPill: Rectangle {
        id: pill

        required property string label
        required property color fill
        required property color ink

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: pillLabel.implicitWidth + 20
        implicitHeight: 24
        radius: Appearance.rounding.full
        color: pill.fill

        StyledText {
            id: pillLabel
            anchors.centerIn: parent
            text: pill.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: pill.ink
        }
    }

    /// A round icon button sized for a list row, dimmed rather than hidden when it does not
    /// apply - buttons that come and go move the two next to them every time the list changes.
    component RowAction: RippleButton {
        id: action

        required property string symbol
        required property color tint
        /// What it turns under the pointer. Removing something says so in red before the click,
        /// not after it.
        property color hoverTint: action.tint
        property string tooltip: ""

        readonly property color liveTint: action.hovered ? action.hoverTint : action.tint

        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        opacity: action.enabled ? 1 : 0.35
        colBackground: ColorUtils.transparentize(action.tint, 1)
        colBackgroundHover: ColorUtils.transparentize(action.hoverTint, 0.88)
        colRipple: ColorUtils.transparentize(action.hoverTint, 0.75)

        MaterialSymbol {
            anchors.centerIn: parent
            text: action.symbol
            iconSize: Appearance.font.pixelSize.large
            color: action.liveTint

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledToolTip {
            text: action.tooltip
        }
    }
}
