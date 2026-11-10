import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.contextMenu
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray

PopupWindow {
    id: root
    required property QsMenuHandle trayItemMenuHandle
    // Prefer the item over its id: ids are not unique for Electron/Chrome tray icons.
    property SystemTrayItem trayItem: null
    property string trayItemId: ""
    readonly property var pinTarget: root.trayItem ?? root.trayItemId
    property real popupBackgroundMargin: 0

    signal menuClosed
    signal menuOpened(qsWindow: var) // Correct type is QsWindow, but QML does not like that

    color: "transparent"
    property real padding: Appearance.sizes.elevationMargin

    // The ii context menu style (ContextMenus): compact is the card every
    // other menu draws, with 32 px rows; comfortable is this menu as it was.
    // The tablet family keeps its own.
    readonly property bool dense: ContextMenus.compact && PanelFamily.isIi
    readonly property bool cascade: ContextMenus.cascade && PanelFamily.isIi
    readonly property real cardPadding: root.dense ? ContextMenus.compactPadding : 4
    readonly property real rowRadius: Math.max(Appearance.rounding.verysmall, Appearance.rounding.windowRounding - root.cardPadding)

    // The app's entries are one block the user can move or hide; Pin, the
    // separator and their own commands are arranged around it ("tray").
    readonly property var arranged: ContextMenus.arrange("tray", [
        {
            "id": "pin",
            "shown": root.trayItemId !== undefined && root.trayItemId.length > 0,
            "symbol": "push_pin",
            "title": TrayService.isPinned(root.pinTarget) ? Translation.tr("Unpin") : Translation.tr("Pin")
        },
        { "id": "appEntries" }
    ].filter(entry => entry.shown !== false))
    function triggerArranged(entry: var): void {
        if (entry.custom) {
            root.close();
            ContextMenus.runCustom(entry, root.trayItemId);
            return;
        }
        if (entry.id === "pin") {
            // Repinning moves the item between the bar and the overflow popup,
            // which destroys whatever this menu is anchored to. Close first,
            // then defer the toggle so the menu PopupWindow finishes tearing
            // down before its anchor host is removed from the bar/overflow.
            const target = root.pinTarget;
            root.close();
            Qt.callLater(() => TrayService.togglePin(target));
        }
    }

    // ContextMenus.scale, ii only like the style.
    readonly property real zoom: PanelFamily.isIi ? ContextMenus.scale : 1
    implicitHeight: ((stackView.currentItem ? stackView.currentItem.implicitHeight : 100) + popupBackground.padding * 2) * root.zoom + root.padding * 2
    implicitWidth: popupBackground.implicitWidth * root.zoom + root.padding * 2

    // Mapping before the dbusmenu layout lands sizes the popup for the Pin row only,
    // and Hyprland keeps that size after the entries grow it, cropping the menu.
    // TrayService keeps every layout loaded, so this opens at once; the wait (capped
    // by a short timeout) only covers an item whose layout has not arrived yet.
    property bool openPending: false

    QsMenuOpener {
        id: rootOpener
        menu: root.trayItemMenuHandle
    }

    function open() {
        if ((rootOpener.children?.values?.length ?? 0) > 0) {
            root.show();
            return;
        }
        root.openPending = true;
        openFallback.restart();
    }

    function show() {
        if (!root.openPending && root.visible)
            return;
        root.openPending = false;
        openFallback.stop();
        root.visible = true;
        motion.playEnter(true);
        root.menuOpened(root);
    }

    // A workspace change closes every menu (ContextMenus.dismissAll); the
    // tray lets go of its focus grab on menuClosed.
    Connections {
        target: ContextMenus
        function onDismissAllRequested() {
            if (root.visible || root.openPending)
                root.close();
        }
    }

    function close() {
        root.openPending = false;
        openFallback.stop();
        root.closeCascadesFrom(0);
        root.visible = false;
        while (stackView.depth > 1)
            stackView.pop();
        root.menuClosed();
    }

    // ── Cascade ──────────────────────────────────────────────────────────────
    // A submenu as a popup of its own beside the row that opened it, nested
    // as deep as the app's menu goes. The windows are published so the tray's
    // focus grab can hold them with the menu (SysTray).
    property var cascadeWindows: []
    function closeCascadesFrom(level: int): void {
        const keep = root.cascadeWindows.slice(0, level);
        const drop = root.cascadeWindows.slice(level);
        root.cascadeWindows = keep;
        for (const w of drop) {
            w.visible = false;
            w.destroy();
        }
    }
    function openCascade(handle: var, row: Item, level: int): void {
        root.closeCascadesFrom(level);
        const parentWindow = level === 0 ? root : root.cascadeWindows[level - 1];
        if (!parentWindow || !row)
            return;
        const pos = row.mapToItem(null, 0, 0);
        const w = cascadeComponent.createObject(root, { "handle": handle, "level": level + 1 });
        w.anchor.window = parentWindow;
        w.anchor.rect = Qt.rect(pos.x, pos.y - root.cardPadding, row.width, row.height);
        w.anchor.edges = Edges.Right | Edges.Top;
        w.anchor.gravity = Edges.Right | Edges.Bottom;
        w.anchor.adjustment = PopupAdjustment.FlipX | PopupAdjustment.SlideY;
        w.visible = true;
        root.cascadeWindows = root.cascadeWindows.concat([w]);
    }
    function openSubmenu(handle: var, row: Item, level: int): void {
        if (root.cascade) {
            root.openCascade(handle, row, level);
            return;
        }
        stackView.push(subMenuComponent.createObject(null, {
            "handle": handle,
            "mode": "stacked"
        }));
    }

    ContextMenuMotion {
        id: motion
        compact: root.dense
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.RightButton
        onPressed: event => {
            if ((event.button === Qt.BackButton || event.button === Qt.RightButton) && stackView.depth > 1)
                stackView.pop();
        }

        // The user's menu size: the card is laid out at its own size and
        // scaled from the corner, held to the bar edge it opens from.
        Item {
            id: scaler
            x: root.padding
            y: BarPlacement.vertical ? (parent.height - scaler.height * root.zoom) / 2
                : BarPlacement.bottom ? parent.height - root.padding - scaler.height * root.zoom
                : root.padding
            width: popupBackground.implicitWidth
            height: popupBackground.implicitHeight
            scale: root.zoom
            transformOrigin: Item.TopLeft

        StyledRectangularShadow {
            target: popupBackground
            opacity: popupBackground.opacity
        }

        Rectangle {
            id: popupBackground
            readonly property real padding: root.cardPadding
            anchors.fill: parent

            color: root.dense ? Appearance.m3colors.m3surfaceContainer : Appearance.colors.colLayer0
            radius: Appearance.rounding.windowRounding
            border.width: root.dense ? 0 : 1
            border.color: Appearance.colors.colLayer0Border
            clip: true

            // Compact grows out of the bar edge on the shared menu motion;
            // comfortable only fades, as it always has.
            opacity: root.dense ? motion.reveal : (shownOnce ? 1 : 0)
            property bool shownOnce: false
            Component.onCompleted: shownOnce = true
            scale: root.dense ? motion.scale : 1
            transformOrigin: BarPlacement.vertical ? (BarPlacement.bottom ? Item.Right : Item.Left)
                : BarPlacement.bottom ? Item.Bottom : Item.Top
            implicitWidth: root.dense
                ? Math.max(ContextMenus.compactMinWidth, Math.min(ContextMenus.compactMaxWidth, stackView.implicitWidth + popupBackground.padding * 2))
                : stackView.implicitWidth + popupBackground.padding * 2
            implicitHeight: stackView.implicitHeight + popupBackground.padding * 2

            Behavior on opacity {
                enabled: !root.dense
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on implicitWidth {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            StackView {
                id: stackView
                anchors {
                    fill: parent
                    margins: popupBackground.padding
                }
                pushEnter: NoAnim {}
                pushExit: NoAnim {}
                popEnter: NoAnim {}
                popExit: NoAnim {}

                implicitWidth: currentItem ? currentItem.implicitWidth : 180
                implicitHeight: currentItem ? currentItem.implicitHeight : 80

                initialItem: SubMenu {
                    handle: root.trayItemMenuHandle
                    mode: "root"
                }
            }
        }
        }
    }

    Connections {
        target: rootOpener.children
        function onValuesChanged() {
            // callLater: let the Repeater/ColumnLayout settle implicitHeight before mapping
            if (root.openPending && rootOpener.children.values.length > 0)
                Qt.callLater(root.show);
        }
    }

    Timer {
        id: openFallback
        interval: 400
        onTriggered: if (root.openPending) root.show()
    }

    component NoAnim: Transition {
        NumberAnimation {
            duration: 0
        }
    }

    // A row of the menu's own (Back, Pin, a custom command): the entries'
    // shape, with a Material symbol where an entry has the app's icon.
    component PlainRow: RippleButton {
        id: plainRow
        property string symbol: ""
        property string label: ""
        buttonRadius: root.rowRadius
        horizontalPadding: root.dense ? 10 : 12
        implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
        implicitHeight: root.dense ? 32 : 36
        Layout.fillWidth: true

        contentItem: RowLayout {
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                right: parent.right
                leftMargin: plainRow.horizontalPadding
                rightMargin: plainRow.horizontalPadding
            }
            spacing: 8
            MaterialSymbol {
                iconSize: 18
                text: plainRow.symbol
            }
            StyledText {
                Layout.fillWidth: true
                text: plainRow.label
                font.pixelSize: Appearance.font.pixelSize.smallie
                elide: Text.ElideRight
            }
        }
    }

    component Separator: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: root.dense ? 8 : 0
        Layout.rightMargin: root.dense ? 8 : 0
        implicitHeight: 1
        color: root.dense ? Appearance.colors.colOutlineVariant : Appearance.colors.colSubtext
        opacity: root.dense ? 0.6 : 1
        Layout.topMargin: 4
        Layout.bottomMargin: 4
    }

    // One level of the app's menu. "root" carries the arranged rows around
    // the app's entries, "stacked" a Back row over them (inline submenus),
    // "cascade" the entries alone (a side popup).
    component SubMenu: ColumnLayout {
        id: submenu
        required property QsMenuHandle handle
        property string mode: "root"
        property int level: 0
        property bool shown: false
        opacity: shown ? 1 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Component.onCompleted: shown = true
        StackView.onActivating: shown = true
        StackView.onDeactivating: shown = false
        StackView.onRemoved: destroy()

        QsMenuOpener {
            id: menuOpener
            menu: submenu.handle
        }

        spacing: 0

        // Cascade: resting on an entry with children opens it beside the
        // menu; resting on any other entry folds deeper levels away.
        Timer {
            id: hoverIntent
            interval: 220
            property var entry: null
            property Item row: null
            onTriggered: {
                if (!root.cascade || !hoverIntent.row)
                    return;
                if (hoverIntent.entry && hoverIntent.entry.hasChildren)
                    root.openCascade(hoverIntent.entry, hoverIntent.row, submenu.level);
                else
                    root.closeCascadesFrom(submenu.level);
            }
        }

        PlainRow {
            visible: submenu.mode === "stacked"
            symbol: "chevron_left"
            label: Translation.tr("Back")
            downAction: () => stackView.pop()
        }

        ContextMenuIconBar {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            visible: submenu.mode === "root" && root.arranged.bar.length > 0
            entries: submenu.mode === "root" ? root.arranged.bar : []
            hostPadding: root.cardPadding
            onActivated: (entry, button) => root.triggerArranged(entry)
        }

        Repeater {
            // Root: the arranged rows, the app's block among them. Other
            // levels: only the block.
            model: submenu.mode === "root" ? root.arranged.rows : [{ "id": "appEntries" }]
            delegate: ColumnLayout {
                id: slot
                required property var modelData
                Layout.fillWidth: true
                spacing: 0

                Separator {
                    visible: slot.modelData.separator === true
                }
                PlainRow {
                    visible: !slot.modelData.separator && slot.modelData.id !== "appEntries"
                    symbol: slot.modelData.symbol ?? ""
                    label: slot.modelData.title ?? ""
                    releaseAction: () => root.triggerArranged(slot.modelData)
                }

                Repeater {
                    id: menuEntriesRepeater
                    model: slot.modelData.id === "appEntries" ? menuOpener.children : null
                    property bool iconColumnNeeded: {
                        if (!menuOpener || !menuOpener.children || !menuOpener.children.values) return false;
                        let vals = menuOpener.children.values;
                        for (let i = 0; i < vals.length; i++) {
                            let entry = vals[i];
                            if (entry && entry.icon && entry.icon.length > 0)
                                return true;
                        }
                        return false;
                    }
                    property bool specialInteractionColumnNeeded: {
                        if (!menuOpener || !menuOpener.children || !menuOpener.children.values) return false;
                        let vals = menuOpener.children.values;
                        for (let i = 0; i < vals.length; i++) {
                            let entry = vals[i];
                            if (entry && entry.buttonType !== undefined && entry.buttonType !== QsMenuButtonType.None)
                                return true;
                        }
                        return false;
                    }
                    delegate: SysTrayMenuEntry {
                        id: entryRow
                        required property QsMenuEntry modelData
                        forceIconColumn: menuEntriesRepeater.iconColumnNeeded
                        forceSpecialInteractionColumn: menuEntriesRepeater.specialInteractionColumnNeeded
                        menuEntry: modelData
                        dense: root.dense
                        buttonRadius: root.rowRadius

                        onDismiss: root.close()
                        onOpenSubmenu: handle => root.openSubmenu(handle, entryRow, submenu.level)
                        onHoveredChanged: {
                            if (!root.cascade || !entryRow.hovered)
                                return;
                            hoverIntent.entry = entryRow.menuEntry;
                            hoverIntent.row = entryRow;
                            hoverIntent.restart();
                        }
                    }
                }
            }
        }
    }

    Component {
        id: subMenuComponent
        SubMenu {}
    }

    // A cascaded level: the card of the menu, beside the row it came from.
    Component {
        id: cascadeComponent
        PopupWindow {
            id: cascadeWindow
            property var handle: null
            property int level: 1
            color: "transparent"
            visible: false
            implicitWidth: cascadeCard.implicitWidth * root.zoom + root.padding * 2
            implicitHeight: cascadeCard.implicitHeight * root.zoom + root.padding * 2

            ContextMenuMotion {
                id: cascadeMotion
                compact: root.dense
                Component.onCompleted: cascadeMotion.playEnter(true)
            }

            StyledRectangularShadow {
                target: cascadeCard
                opacity: cascadeCard.opacity
            }
            Rectangle {
                id: cascadeCard
                x: root.padding
                y: root.padding
                width: implicitWidth
                height: implicitHeight
                color: root.dense ? Appearance.m3colors.m3surfaceContainer : Appearance.colors.colLayer0
                radius: Appearance.rounding.windowRounding
                border.width: root.dense ? 0 : 1
                border.color: Appearance.colors.colLayer0Border
                opacity: cascadeMotion.reveal
                scale: root.zoom * (0.95 + 0.05 * cascadeMotion.grow)
                transformOrigin: Item.TopLeft
                implicitWidth: root.dense
                    ? Math.max(ContextMenus.compactMinWidth, Math.min(ContextMenus.compactMaxWidth, cascadeLevel.implicitWidth + root.cardPadding * 2))
                    : cascadeLevel.implicitWidth + root.cardPadding * 2
                implicitHeight: cascadeLevel.implicitHeight + root.cardPadding * 2

                SubMenu {
                    id: cascadeLevel
                    x: root.cardPadding
                    y: root.cardPadding
                    width: parent.width - root.cardPadding * 2
                    handle: cascadeWindow.handle
                    mode: "cascade"
                    level: cascadeWindow.level
                }
            }
        }
    }
}
