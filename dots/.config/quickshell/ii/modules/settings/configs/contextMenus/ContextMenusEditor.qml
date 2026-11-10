pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.workspaces

/**
 * One menu's entries, in the order the menu draws them: drag to reorder, put an entry in
 * the compact icon bar, take it out (it waits under "Add back"), add a separator or a
 * command of your own. Every change is written at once (ContextMenus.setLayout) and the
 * stage above shows it.
 *
 * Built-in entries are never deleted, only hidden: a menu that gains an entry in a later
 * shell slots it in by its declared neighbour, and a hidden one stays hidden.
 */
WorkspacesPane {
    id: root

    property string menuId: "desktop"
    property Flickable flick: null

    readonly property var definition: ContextMenus.definition(root.menuId)
    readonly property var layout: ContextMenus.layoutFor(root.menuId)
    readonly property var customs: ContextMenus.customEntriesFor(root.menuId)
    readonly property var hiddenSet: new Set(root.layout.hidden)
    readonly property var barSet: new Set(root.layout.bar)
    readonly property var shown: root.layout.order.filter(id => !root.hiddenSet.has(id))
    readonly property var hiddenDeclared: (root.definition?.entries ?? [])
        .filter(e => root.hiddenSet.has(e.id))

    function declared(id: string): var {
        return (root.definition?.entries ?? []).find(e => e.id === id) ?? null;
    }
    // What a row needs: glyph, name, and the kind of entry in one line.
    function info(id: string): var {
        if (ContextMenus.isSeparator(id))
            return { "id": id, "separator": true, "userSeparator": root.declared(id) === null };
        const custom = root.customs.find(c => c.id === id);
        if (custom)
            return { "id": id, "custom": true, "symbol": custom.symbol || "terminal", "title": custom.title || custom.command, "kind": custom.command };
        const e = root.declared(id);
        if (!e)
            return { "id": id, "title": id, "kind": "" };
        return {
            "id": id,
            "symbol": e.symbol,
            "title": Translation.tr(e.title),
            "block": e.block === true,
            "header": e.header === true,
            // Kept in the list - its place still counts on the families it is for -
            // but named, so a row that never shows here is not a mystery.
            "onlyIn": e.families && e.families.indexOf(PanelFamily.current) < 0
                ? (e.families.length === 1 && e.families[0] === "tablet" ? Translation.tr("Tablet only")
                    : e.families.length === 1 && e.families[0] === "waffle" ? Translation.tr("Waffle only")
                    : Translation.tr("Other families only"))
                : "",
            "kind": e.header ? Translation.tr("Always on top of the menu")
                : e.block ? Translation.tr("Supplied by the app; moves and hides as one")
                : e.submenu ? Translation.tr("Opens a page")
                : Translation.tr("Built in")
        };
    }

    // ── Writing ──────────────────────────────────────────────────────────
    // `order` keeps the hidden entries after the shown ones, so taking one out and adding
    // it back puts it last, where it can be dragged from.
    function write(shownOrder: var, bar: var, hidden: var): void {
        const rest = root.layout.order.filter(id => hidden.indexOf(id) >= 0 && shownOrder.indexOf(id) < 0);
        ContextMenus.setLayout(root.menuId, { "order": shownOrder.concat(rest), "bar": bar, "hidden": hidden });
    }
    function moveTo(from: int, to: int): void {
        if (from === to)
            return;
        const next = root.shown.slice();
        next.splice(to, 0, next.splice(from, 1)[0]);
        root.write(next, root.layout.bar, root.layout.hidden);
    }
    function toggleBar(id: string): void {
        const bar = root.barSet.has(id) ? root.layout.bar.filter(x => x !== id) : root.layout.bar.concat([id]);
        root.write(root.shown, bar, root.layout.hidden);
    }
    function remove(id: string): void {
        const i = root.info(id);
        if (i.custom) {
            ContextMenus.removeCustom(id);
            return;
        }
        if (i.userSeparator) {
            root.write(root.shown.filter(x => x !== id), root.layout.bar, root.layout.hidden);
            return;
        }
        root.write(root.shown.filter(x => x !== id), root.layout.bar.filter(x => x !== id), root.layout.hidden.concat([id]));
    }
    function addBack(id: string): void {
        root.write(root.shown.concat([id]), root.layout.bar, root.layout.hidden.filter(x => x !== id));
    }
    function addSeparator(): void {
        root.write(root.shown.concat(["separator-" + Date.now().toString(36)]), root.layout.bar, root.layout.hidden);
    }

    // The custom command form: "" closed, "new", or the id being edited.
    property string editing: ""
    function openForm(id: string): void {
        const c = root.customs.find(x => x.id === id);
        symbolField.text = c ? (c.symbol ?? "") : "terminal";
        titleField.text = c ? (c.title ?? "") : "";
        commandField.text = c ? (c.command ?? "") : "";
        root.editing = id === "" ? "new" : id;
        titleField.forceActiveFocus();
    }
    function saveForm(): void {
        const symbol = symbolField.text.trim() || "terminal";
        const title = titleField.text.trim();
        const command = commandField.text.trim();
        if (command.length === 0)
            return;
        if (root.editing === "new")
            ContextMenus.addCustom(root.menuId, symbol, title, command);
        else
            ContextMenus.updateCustom(root.editing, symbol, title, command);
        root.editing = "";
    }
    onMenuIdChanged: root.editing = ""

    symbol: "format_list_bulleted"
    title: Translation.tr("Entries")
    subtitle: Translation.tr("%1 · %2 shown, %3 in the icon bar")
        .arg(Translation.tr(root.definition?.name ?? ""))
        .arg(root.shown.filter(id => !ContextMenus.isSeparator(id)).length)
        .arg(root.layout.bar.filter(id => !root.hiddenSet.has(id)).length)
    engaged: list.dragging || root.editing !== ""

    headerExtra: RippleButton {
        visible: ContextMenus.isCustomised(root.menuId) || root.customs.length > 0
        implicitHeight: 36
        implicitWidth: resetRow.implicitWidth + 28
        buttonRadius: height / 2
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        onClicked: ContextMenus.resetLayout(root.menuId)

        contentItem: Item {
            RowLayout {
                id: resetRow
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: "restart_alt"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    text: Translation.tr("Reset")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }
    }

    // ── The order ─────────────────────────────────────────────────────────
    DragOrderList {
        id: list
        Layout.fillWidth: true
        count: root.shown.length
        spacing: 4
        flick: root.flick
        onMoved: (from, to) => root.moveTo(from, to)

        delegate: ContextMenusEntryRow {
            id: entryRow
            Layout.fillWidth: true
            info: root.info(root.shown[entryRow.index] ?? "")
            inBar: root.barSet.has(root.shown[entryRow.index] ?? "")
            draggable: list.count > 1
            opacity: list.dragFrom === entryRow.index ? 0 : 1

            transform: Translate {
                y: list.shiftFor(entryRow.index)
                Behavior on y {
                    enabled: list.dragging
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            onDragStarted: y => {
                list.pointerY = entryRow.mapToItem(list, 0, y).y;
                list.beginDrag(entryRow.index, y);
            }
            onDragMoved: y => list.pointerMoved(entryRow, y)
            onDragEnded: list.endDrag()
            onBarToggled: root.toggleBar(entryRow.info.id)
            onEditRequested: root.openForm(entryRow.info.id)
            onRemoveRequested: root.remove(entryRow.info.id)
        }

        ghostDelegate: Item {
            implicitHeight: ghostRow.implicitHeight

            StyledRectangularShadow {
                target: ghostRow
            }
            ContextMenusEntryRow {
                id: ghostRow
                anchors {
                    left: parent.left
                    right: parent.right
                }
                index: list.dragFrom
                info: root.info(root.shown[list.dragFrom] ?? "")
                ghost: true
                enabled: false
            }
        }
    }

    // ── Adding ────────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            text: Translation.tr("Add")
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: Appearance.colors.colOnSurfaceVariant
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: root.hiddenDeclared
                delegate: ColorsChip {
                    required property var modelData
                    symbol: modelData.separator ? "horizontal_rule" : (modelData.symbol ?? "add")
                    label: modelData.separator ? Translation.tr("Separator") : Translation.tr(modelData.title)
                    onClicked: root.addBack(modelData.id)
                }
            }
            ColorsChip {
                symbol: "horizontal_rule"
                label: Translation.tr("New separator")
                onClicked: root.addSeparator()
            }
            ColorsChip {
                symbol: "terminal"
                label: Translation.tr("Custom command")
                chosen: root.editing === "new"
                onClicked: root.editing === "new" ? root.editing = "" : root.openForm("")
            }
        }

        // The command form: what the entry shows and what it runs.
        Rectangle {
            Layout.fillWidth: true
            visible: root.editing !== ""
            implicitHeight: form.implicitHeight + 32
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: form
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 16
                }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: width / 2
                        color: Appearance.colors.colTertiaryContainer
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: symbolField.text.trim() || "terminal"
                            iconSize: 22
                            color: Appearance.colors.colOnTertiaryContainer
                        }
                    }
                    MaterialTextField {
                        id: symbolField
                        Layout.preferredWidth: 170
                        placeholderText: Translation.tr("Icon (Material Symbol)")
                    }
                    MaterialTextField {
                        id: titleField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Name in the menu")
                    }
                }

                MaterialTextField {
                    id: commandField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Command (bash; $II_CONTEXT_TARGET is what was clicked)")
                    font.family: Appearance.font.family.monospace
                    onAccepted: root.saveForm()
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Runs when the entry is clicked, then the menu closes.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                    RippleButton {
                        implicitHeight: 36
                        implicitWidth: cancelLabel.implicitWidth + 32
                        buttonRadius: height / 2
                        colBackground: Appearance.colors.colLayer3
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        onClicked: root.editing = ""
                        contentItem: StyledText {
                            id: cancelLabel
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Cancel")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer3
                        }
                    }
                    RippleButton {
                        implicitHeight: 36
                        implicitWidth: saveLabel.implicitWidth + 32
                        buttonRadius: height / 2
                        enabled: commandField.text.trim().length > 0
                        opacity: enabled ? 1 : 0.5
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: root.saveForm()
                        contentItem: StyledText {
                            id: saveLabel
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: root.editing === "new" ? Translation.tr("Add") : Translation.tr("Save")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }
    }
}
