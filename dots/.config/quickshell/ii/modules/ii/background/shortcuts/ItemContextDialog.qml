pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.editMode
import qs.modules.ii.contextMenu

/**
 * A menu about one item (a desktop icon, today): a plate naming the item on
 * top, and under it the card of actions, with pages of its own.
 *
 * The card is the desktop menu's (DesktopMenuCard), so the two menus the
 * desktop can open are one kind of object: EditPanelRow rows, the same card,
 * the same enter/exit (ContextMenuMotion), pages that slide in from the
 * right with their own header (EditMenuPageHeader) - or, in the cascade
 * style, open on a second card beside this one. What stays its own is the
 * plate - the item's icon, name and path above the card.
 *
 * With a `menuId` the actions go through ContextMenus.arrange(): the user's
 * order, hidden entries, the compact icon bar and their own command
 * entries, which run here with the item's path as $II_CONTEXT_TARGET.
 *
 * closeRequested fires only after the exit motion; the host may then unload.
 */
FocusScope {
    id: root
    property string title: ""
    property string subtitle: ""
    property url iconSource: ""
    property point anchorPoint: Qt.point(0, 0)
    property var actions: []
    property string menuId: ""
    // What a custom entry acts on ($II_CONTEXT_TARGET).
    property string customTarget: ""
    property Component pageComponent: null
    // How deep `pageComponent` sits: 0 is the actions, a page off them is 1,
    // a page off that is 2. It decides which way a page change slides.
    property int pageDepth: root.pageComponent ? 1 : 0
    property bool closing: false
    signal actionTriggered(string actionId)
    signal closeRequested()
    signal backRequested()
    // The host's selection, when the menu speaks of a set: Ctrl+A on the
    // action page asks the host to select everything it owns.
    signal selectAllRequested()
    // The rows the arrow keys walk: { count, itemAt(i) }, published by the
    // action page on create/destroy.
    property var actionRows: null

    // A row that just did its job (a copy) answers in place: it fills,
    // its icon turns into a check and its label into `doneText`.
    // Kept beside `actions`, not in it - a new actions array would rebuild
    // every row and the fill would snap instead of easing in.
    property string doneId: ""
    property string doneText: ""
    function confirmAction(id: string, text: string): void {
        root.doneText = text;
        root.doneId = id;
    }

    readonly property bool dense: ContextMenus.compact
    readonly property bool cascade: ContextMenus.cascade
    readonly property int padding: root.dense ? ContextMenus.compactPadding : ContextMenus.comfortablePadding
    readonly property real cardRadius: Appearance.rounding.windowRounding
    readonly property real headerRowHeight: 40
    readonly property real headerBlock: root.dense ? root.headerRowHeight + 9 : 0

    // The actions in the arrangement's terms; without a menuId they are
    // drawn as given, one run.
    readonly property var arranged: {
        const live = root.actions.map(a => ({
            "id": a.id,
            "symbol": a.icon ?? "",
            "iconSource": a.iconSource ?? "",
            "title": a.text ?? "",
            "destructive": a.destructive === true,
            "enabled": a.enabled !== false,
            "submenu": a.submenu === true,
            "toggle": a.toggle === true,
            "checked": a.checked === true
        }));
        return root.menuId !== "" ? ContextMenus.arrange(root.menuId, live) : { "bar": [], "rows": live };
    }

    function trigger(entry: var, from: Item): void {
        if (entry.custom) {
            ContextMenus.runCustom(entry, root.customTarget);
            root.dismiss();
            return;
        }
        if (entry.submenu && from)
            root.anchorY = from.mapToItem(body, 0, 0).y;
        // Cascade: a second click on the row whose page is open beside the
        // menu folds it away.
        if (root.cascade && entry.submenu && root.pageComponent && root.openActionId === entry.id) {
            root.backRequested();
            return;
        }
        root.openActionId = entry.submenu ? entry.id : root.openActionId;
        root.actionTriggered(entry.id);
    }
    property string openActionId: ""
    onPageComponentChanged: {
        if (!root.pageComponent)
            root.openActionId = "";
        root._pageChanged();
    }

    function dismiss() {
        if (root.closing)
            return;
        root.closing = true;
    }
    // A workspace change closes every menu (ContextMenus.dismissAll).
    Connections {
        target: ContextMenus
        function onDismissAllRequested() { root.dismiss(); }
    }

    // ── Enter and exit ───────────────────────────────────────────────────────
    // The desktop menu's motion: plate and card grow out of the corner under
    // the pointer as one while fading in, and leave as one. No row cascade.
    ContextMenuMotion {
        id: motion
        closing: root.closing
        onExitFinished: root.closeRequested()
    }
    readonly property real reveal: motion.reveal
    readonly property bool _motion: !Appearance.reducedMotion

    // ── Pages ────────────────────────────────────────────────────────────────
    // The page on show lags the requested one by the out half of the slide:
    // the old page leaves toward where it came from, then the new one comes
    // in from the other side. Deeper slides left, shallower slides right.
    // Cascaded, the first page simply arrives on the card beside the menu
    // and the last one leaves with it; only a page off a page slides.
    property Component displayedPage: null
    property int displayedDepth: 0
    property int _slideDir: 1
    readonly property real pageSlide: root.dense ? 16 : 36
    property real pageOffset: 0
    property real pageOpacity: 1

    function _pageChanged(): void {
        if (root.closing)
            return;
        root._slideDir = root.pageDepth >= root.displayedDepth ? 1 : -1;
        const instant = !root._motion || root.reveal < 1
            || (root.cascade && (!root.pageComponent || !root.displayedPage));
        if (instant) {
            pageMotion.stop();
            root.pageOffset = 0;
            root.pageOpacity = 1;
            // Cascaded, the card beside the menu keeps its page while it
            // fades away.
            if (root.pageComponent || !root.cascade) {
                root.displayedPage = root.pageComponent;
                root.displayedDepth = root.pageDepth;
            }
            return;
        }
        pageMotion.restart();
    }
    SequentialAnimation {
        id: pageMotion
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "pageOffset"; to: -root._slideDir * root.pageSlide
                duration: root.dense ? Appearance.animation.popupExit.duration : Appearance.animation.elementMoveExit.duration
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
            NumberAnimation {
                target: root; property: "pageOpacity"; to: 0
                duration: root.dense ? Appearance.animation.popupExit.duration : Appearance.animation.elementMoveExit.duration
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
        }
        ScriptAction {
            script: {
                root.displayedPage = root.pageComponent;
                root.displayedDepth = root.pageDepth;
                root.pageOffset = root._slideDir * root.pageSlide;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "pageOffset"; to: 0
                duration: root.dense ? Appearance.animation.popupEnter.duration : Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
            NumberAnimation {
                target: root; property: "pageOpacity"; to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
    }

    // ── Keyboard ─────────────────────────────────────────────────────────────
    // Arrow navigation over the action rows. The scope holds focus, so every
    // key lands here first. From "no row yet", Down enters at the top and Up
    // at the bottom. Only the action page: a page's own fields keep their
    // keys (rename's caret, search's list). A focused row reads as hovered
    // and takes Enter/Space itself (EditPanelRow).
    function navRows(delta: int): bool {
        const rep = root.actionRows;
        if (!rep || root.pageComponent || root.closing || rep.count === 0)
            return false;
        let idx = -1;
        for (let i = 0; i < rep.count; ++i) {
            if (rep.itemAt(i)?.activeFocus) {
                idx = i;
                break;
            }
        }
        // |delta| >= 9999 is Home/End: an absolute jump, never a walk.
        if (Math.abs(delta) >= 9999)
            idx = delta > 0 ? rep.count - 1 : 0;
        else if (idx === -1)
            idx = delta > 0 ? 0 : rep.count - 1;
        else
            idx = Math.max(0, Math.min(rep.count - 1, idx + delta));
        rep.itemAt(idx)?.forceActiveFocus();
        return true;
    }
    focus: true
    Component.onDestruction: GlobalStates.desktopDialogCount = Math.max(0, GlobalStates.desktopDialogCount - 1)
    Component.onCompleted: {
        GlobalStates.desktopDialogCount += 1;
        // Opened straight onto a page (F2 → rename), that page's field
        // claims focus itself — grabbing it here, after the children have
        // completed, would steal it back.
        if (!root.pageComponent)
            root.forceActiveFocus();
        root.displayedPage = root.pageComponent;
        root.displayedDepth = root.pageDepth;
        motion.playEnter(true);
    }
    Keys.onEscapePressed: event => {
        event.accepted = true;
        if (root.pageComponent && !root.closing)
            root.backRequested();
        else
            root.dismiss();
    }
    Keys.onUpPressed: event => {
        if (root.navRows(-1))
            event.accepted = true;
    }
    Keys.onDownPressed: event => {
        if (root.navRows(1))
            event.accepted = true;
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)
            && !root.pageComponent) {
            // Only the action page: on the rename page the field owns Ctrl+A.
            event.accepted = true;
            root.selectAllRequested();
        } else if (event.key === Qt.Key_Home) {
            if (root.navRows(-9999))
                event.accepted = true;
        } else if (event.key === Qt.Key_End) {
            if (root.navRows(9999))
                event.accepted = true;
        }
    }

    PointerBoundsEscape {}

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.dismiss()
        onWheel: wheel => wheel.accepted = true
    }

    // ── Width ────────────────────────────────────────────────────────────────
    // Comfortable keeps its 300 px. Compact fits the rows and the bar; a
    // page's fields and lists want a little more, so a page opened inside
    // the card widens it, and the cascade card gets that width of its own.
    property real actionsNaturalWidth: 0
    readonly property real compactWidth: Math.max(ContextMenus.compactMinWidth,
        Math.min(ContextMenus.compactMaxWidth, Math.ceil(Math.max(root.actionsNaturalWidth,
            8 + 28 + 10 + headerMetrics.advanceWidth(root.title) + 8) + root.padding * 2)))
    FontMetrics {
        id: headerMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.smallie + 1
        font.weight: Font.Medium
    }
    readonly property real pageWidth: root.dense ? Math.max(root.compactWidth, ContextMenus.compactPageWidth) : 300
    readonly property real menuWidth: Math.max(0, Math.min(
        root.dense ? (!root.cascade && root.displayedPage ? root.pageWidth : root.compactWidth) : 300,
        root.width - 16))

    // Edit Mode shrinks the whole desktop; a menu that shrinks with it is
    // both hard to read and rasterized off its native grid. The host hands in
    // the factor to undo and the cards are laid out in SCREEN pixels:
    // anchorPoint arrives in surface coordinates and is converted here, the
    // clamp runs on the unscaled extent. 1 outside the mode.
    property real counterScale: 1
    // The room the card keeps from each screen edge, in surface pixels: the
    // host raises an edge to clear the bar or dock sitting on it.
    property var insets: ({ left: 8, top: 8, right: 8, bottom: 8 })
    // Where the row that opened a page sits, in `body`, for the cascade card.
    property real anchorY: 0
    // The user's menu size (ContextMenus.scale) on top of the Edit Mode undo:
    // body units times `zoom` are surface units.
    readonly property real zoom: root.counterScale * ContextMenus.scale

    Item {
        id: body
        x: Math.max(root.insets.left, Math.min(root.anchorPoint.x / root.counterScale, root.width - width * ContextMenus.scale - root.insets.right)) * root.counterScale
        y: Math.max(root.insets.top, Math.min(root.anchorPoint.y / root.counterScale, root.height - height * ContextMenus.scale - root.insets.bottom)) * root.counterScale
        width: root.menuWidth
        height: cards.implicitHeight
        opacity: motion.reveal
        scale: root.zoom * motion.scale
        transformOrigin: Item.TopLeft
        enabled: !root.closing
        Behavior on y {
            enabled: root.counterScale === 1
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        // In Edit Mode the counter-scaled card spills past the shrunk canvas;
        // every level down to here carries one (see PointerBoundsEscape).
        PointerBoundsEscape {}
        Behavior on width {
            enabled: !Appearance.reducedMotion && root.reveal >= 1 && !root.closing
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            id: cards
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: root.dense ? 4 : 6

            // The plate: what the menu is about. Compact draws it as the
            // card's first row instead (headerBlock).
            Item {
                Layout.fillWidth: true
                visible: !root.dense
                implicitHeight: 88

                StyledRectangularShadow {
                    target: plate
                }
                Rectangle {
                    id: plate
                    anchors.fill: parent
                    radius: root.cardRadius
                    color: Appearance.m3colors.m3surfaceContainer
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: root.dense ? 8 : 12
                        spacing: root.dense ? 10 : 12
                        Rectangle {
                            implicitWidth: root.dense ? 36 : 64
                            implicitHeight: implicitWidth
                            radius: Math.max(Appearance.rounding.verysmall, root.cardRadius - (root.dense ? 8 : 12))
                            color: Appearance.colors.colSurfaceContainerHigh
                            Image {
                                anchors.centerIn: parent
                                width: root.dense ? 28 : 48
                                height: width
                                sourceSize: Qt.size(48, 48)
                                source: root.iconSource
                                fillMode: Image.PreserveAspectFit
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: root.dense ? 1 : 4
                            StyledText {
                                Layout.fillWidth: true
                                text: root.title
                                font.pixelSize: root.dense ? Appearance.font.pixelSize.smallie + 1 : Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurface
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.subtitle
                                visible: text.length > 0
                                color: Appearance.colors.colSubtext
                                font.pixelSize: root.dense ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                }
            }

            // The card: the actions, or (inline) the page they opened.
            Item {
                Layout.fillWidth: true
                implicitHeight: card.implicitHeight

                StyledRectangularShadow {
                    target: card
                }
                Rectangle {
                    id: card
                    anchors.left: parent.left
                    anchors.right: parent.right
                    implicitHeight: Math.min(Math.max(64, root.height / root.zoom - 110),
                        root.headerBlock + pageLoader.implicitHeight + root.padding * 2)
                    radius: root.cardRadius
                    color: Appearance.m3colors.m3surfaceContainer
                    clip: true
                    Behavior on implicitHeight {
                        enabled: !Appearance.reducedMotion && root.reveal >= 1
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(card)
                    }
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

                    // Compact: the item as the card's first row - its icon at
                    // row size, the name over the path - and a hairline under
                    // it, so the menu is one card rather than two.
                    Item {
                        visible: root.headerBlock > 0
                        x: root.padding
                        y: root.padding
                        width: parent.width - root.padding * 2
                        height: root.headerBlock

                        RowLayout {
                            x: 8
                            width: parent.width - 16
                            height: root.headerRowHeight
                            spacing: 10

                            Image {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                sourceSize: Qt.size(56, 56)
                                source: root.iconSource
                                fillMode: Image.PreserveAspectFit
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.title
                                    font.pixelSize: Appearance.font.pixelSize.smallie + 1
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnSurface
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: root.subtitle
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideMiddle
                                }
                            }
                        }
                        Rectangle {
                            x: 8
                            y: root.headerRowHeight + 4
                            width: parent.width - 16
                            height: 1
                            color: Appearance.colors.colOutlineVariant
                            opacity: 0.6
                        }
                    }

                    ScrollView {
                        id: pageScroll
                        anchors.fill: parent
                        anchors.margins: root.padding
                        anchors.topMargin: root.padding + root.headerBlock
                        contentWidth: availableWidth
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        Loader {
                            id: pageLoader
                            width: pageScroll.availableWidth
                            readonly property bool inline: !root.cascade
                            opacity: pageLoader.inline ? root.pageOpacity : 1
                            transform: Translate { x: pageLoader.inline ? root.pageOffset : 0 }
                            sourceComponent: pageLoader.inline ? (root.displayedPage ?? actionPage) : actionPage
                            enabled: !root.closing && (!pageLoader.inline || !pageMotion.running)

                            TouchpadScrollHandler {
                                flickable: pageScroll.contentItem
                            }
                        }
                    }
                }
            }
        }

        // ── The cascade card ─────────────────────────────────────────────────
        // The page beside the menu, level with the row that opened it, on
        // whichever side of the menu has room, held inside the surface.
        property real sideProgress: root.cascade && root.pageComponent ? 1 : 0
        Behavior on sideProgress {
            enabled: !Appearance.reducedMotion && root.reveal >= 1
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(body)
        }
        Item {
            id: side
            readonly property real gap: ContextMenus.cascadeGap
            readonly property real surfaceWidth: root.width / root.zoom
            readonly property real bodyX: body.x / root.zoom
            readonly property bool flip: side.bodyX + body.width + side.gap + side.width + 8 > side.surfaceWidth
            visible: root.cascade && body.sideProgress > 0 && root.displayedPage !== null
            width: root.dense ? root.pageWidth : 300
            height: sideCard.implicitHeight
            x: side.flip ? -side.gap - side.width : body.width + side.gap
            y: {
                const top = (8 - body.y) / root.zoom;
                const bottom = (root.height - 8 - body.y) / root.zoom - side.height;
                return Math.max(top, Math.min(root.anchorY - root.padding, bottom));
            }
            opacity: body.sideProgress
            scale: 0.95 + 0.05 * body.sideProgress
            transformOrigin: side.flip ? Item.TopRight : Item.TopLeft

            StyledRectangularShadow {
                target: sideCard
            }
            Rectangle {
                id: sideCard
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: Math.min(Math.max(64, root.height / root.zoom - 16),
                    sideLoader.implicitHeight + root.padding * 2)
                radius: root.cardRadius
                color: Appearance.m3colors.m3surfaceContainer
                clip: true
                Behavior on implicitHeight {
                    enabled: !Appearance.reducedMotion && body.sideProgress >= 1
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(sideCard)
                }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

                ScrollView {
                    id: sideScroll
                    anchors.fill: parent
                    anchors.margins: root.padding
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    Loader {
                        id: sideLoader
                        width: sideScroll.availableWidth
                        active: root.cascade
                        opacity: root.pageOpacity
                        transform: Translate { x: root.pageOffset }
                        sourceComponent: root.displayedPage
                        enabled: !pageMotion.running && !root.closing && root.pageComponent !== null

                        TouchpadScrollHandler {
                            flickable: sideScroll.contentItem
                        }
                    }
                }
            }
        }
    }

    Component {
        id: actionPage
        ColumnLayout {
            spacing: root.dense ? 4 : 3
            Component.onCompleted: {
                root.actionRows = {
                    "list": actionList,
                    get count() { return actionList.focusRows().length; },
                    itemAt(i) { return actionList.focusRows()[i] ?? null; }
                };
            }
            Component.onDestruction: root.actionRows = null

            ContextMenuIconBar {
                id: actionBar
                Layout.fillWidth: true
                entries: root.arranged.bar
                hostPadding: root.padding
                onActivated: (entry, button) => root.trigger(entry, button)
            }
            ContextMenuList {
                id: actionList
                Layout.fillWidth: true
                rows: root.arranged.rows
                dense: root.dense
                // The comfortable menu has always been one run of pills.
                separators: root.dense
                hostRadius: root.cardRadius
                hostPadding: root.padding
                doneId: root.doneId
                doneText: root.doneText
                openId: root.cascade ? root.openActionId : ""
                onActivated: (entry, row) => root.trigger(entry, row)
                // Copied out rather than bound: an inline page unloads this
                // list, and the card keeps the width it measured.
                function publishWidth(): void {
                    root.actionsNaturalWidth = Math.max(actionList.implicitWidth, actionBar.implicitWidth);
                }
                onImplicitWidthChanged: actionList.publishWidth()
                Component.onCompleted: actionList.publishWidth()
            }
        }
    }
}
