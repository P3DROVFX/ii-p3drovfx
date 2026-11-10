import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.contextMenu
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

// Shared popup lifetime and motion for menus, app groups and file stacks.
//
// The look is the desktop menu's (DesktopMenuCard / ItemContextDialog): a
// plate naming what the menu is about, and under it a borderless card of
// EditPanelRow runs. Both surfaces grow out of the dock edge as one
// (0.85 -> 1) while they fade in, with no row cascade and no blur pass.

Loader {
    id: root

    property Item anchorItem: parent
    // Item whose on-screen bounds place the popup. Widgets that magnify an
    // inner icon rather than themselves point this at the icon.
    property Item geometryItem: anchorItem
    property bool isClosing: false
    property string headerText: ""
    property string headerSubtitle: ""
    property string headerSymbol: ""
    property Component headerIcon: null
    property bool showHeader: true
    property bool useDockSlideAnimation: true
    property bool pointerInsidePopup: false
    // Kept for callers written against the old card; every card is padded
    // evenly now.
    property bool symmetricContentMargins: false

    // A data-driven menu: arrays of action objects (see DockMenuGroups).
    // When set and no contentComponent is given, the rows are built here and
    // the card's height is known before the surface maps.
    property var menuGroups: null
    // True from the call to open() until the Loader lets go. Menus build their
    // rows on this rather than on `active`: the Loader reacts to `active`
    // before any binding on it does, so rows gated on it arrived after the
    // surface had already been sized and anchored without them.
    property bool menuOpen: false
    property real menuWidth: 288
    signal actionTriggered(string actionId)

    property string dockPos: root.anchorItem?.dockContent?.dockPos ?? (typeof dock !== "undefined" ? dock.dockEffectivePosition : "bottom")
    property real motionMargin: 0
    property color surfaceColor: Appearance.m3colors.m3surfaceContainer
    readonly property real cardRadius: Appearance.rounding.windowRounding
    readonly property real cardPadding: root.dense ? ContextMenus.compactPadding : 8
    readonly property real plateHeight: 88
    readonly property real surfaceGap: 6
    // Compact has no plate: what the menu is about is the card's own first
    // row (headerBlock: the row, then a hairline), so the menu is one object.
    readonly property bool plateShown: root.showHeader && !root.dense
    readonly property real plateBlock: root.plateShown ? root.plateHeight + root.surfaceGap : 0
    readonly property real headerRowHeight: 40
    readonly property real headerBlock: root.showHeader && root.dense ? root.headerRowHeight + 9 : 0
    FontMetrics {
        id: headerMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.smallie + 1
        font.weight: Font.Medium
    }
    // 8 + icon 28 + 10 + title + 8, as the header row lays out.
    readonly property real headerNaturalWidth: root.headerBlock > 0
        ? 8 + 28 + 10 + headerMetrics.advanceWidth(root.headerText) + 8 : 0
    // Compact: as wide as the rows and the bar need, within ContextMenus'
    // bounds. Arithmetic like the height, so the surface maps at its size.
    readonly property real barHeight: root.barEntries.length > 0
        ? ContextMenus.barLayout(root.barEntries.length, root.effectiveMenuWidth - root.cardPadding * 2).height + 4 : 0
    readonly property real barNaturalWidth: ContextMenus.barNaturalWidth(root.barEntries.length)
    readonly property real effectiveMenuWidth: !root.dense ? root.menuWidth
        : Math.max(ContextMenus.compactMinWidth, Math.min(ContextMenus.compactMaxWidth,
            Math.ceil(Math.max(root._groupsNaturalWidth, root.barNaturalWidth, root.headerNaturalWidth) + root.cardPadding * 2)))
    property real _groupsNaturalWidth: 0
    // The desktop menu's motion (ContextMenuMotion): `grow` carries the shape
    // (scale + slide out of the dock edge), `reveal` the opacity on a faster
    // clock, so the surface is readable at once instead of fading in across
    // the whole grow. The exit says when it is DONE, and a re-open mid-exit
    // turns around from wherever it is. Compact runs the shorter version.
    ContextMenuMotion {
        id: motion
        // Only the context menus follow the style; app groups and stacks
        // keep their motion.
        compact: root.dense
        closing: root.isClosing
        onExitFinished: {
            root.active = false;
            root.isClosing = false;
        }
    }
    readonly property real grow: motion.grow
    readonly property real reveal: motion.reveal
    readonly property real popupProgress: root.grow

    // ── Arranged entries ─────────────────────────────────────────────────────
    // A data-driven menu that names itself (`menuId`) goes through
    // ContextMenus.arrange: the user's order, hidden entries, the compact
    // icon bar and their own commands, which run with `customTarget` as
    // $II_CONTEXT_TARGET. Actions sharing a `block` id (an app's own desktop
    // actions) move and hide as one entry. Groups come back from the
    // arrangement's separators.
    property string menuId: ""
    property string customTarget: ""
    readonly property bool arrangeable: root.menuId !== "" && root.menuGroups !== null && root.contentComponent === null
    readonly property bool dense: root.arrangeable && ContextMenus.compact
    // The user's menu size; app groups and stacks keep theirs.
    readonly property real zoom: root.arrangeable ? ContextMenus.scale : 1
    function _flatten(groups) {
        const out = [];
        for (const group of groups ?? []) {
            for (const action of group ?? []) {
                if (!action || action.visible === false)
                    continue;
                if (action.block) {
                    const last = out[out.length - 1];
                    if (last && last.id === action.block && last.items)
                        last.items.push(action);
                    else
                        out.push({ "id": action.block, "items": [action] });
                } else {
                    out.push(action);
                }
            }
        }
        return out;
    }
    readonly property var arranged: root.arrangeable && root.menuOpen
        ? ContextMenus.arrange(root.menuId, root._flatten(root.menuGroups)) : null
    readonly property var shownGroups: root.arranged
        ? ContextMenus.groupsOf(root.arranged.rows).map(group => group.map(e => e.custom
            ? { "id": e.id, "text": e.title, "icon": e.symbol } : e))
        : root.menuGroups
    readonly property var barEntries: root.arranged
        ? root.arranged.bar.map(e => e.custom ? e : {
            "id": e.id, "symbol": e.icon ?? "", "title": e.text ?? "", "destructive": e.destructive === true })
        : []
    function _trigger(actionId: string): void {
        if (actionId.startsWith("custom-")) {
            const entry = ContextMenus.customEntriesFor(root.menuId).find(e => e.id === actionId);
            ContextMenus.runCustom(entry, root.customTarget);
            root.close();
            return;
        }
        root.actionTriggered(actionId);
    }
    readonly property real motionX: dockPos === "left" ? -1 : (dockPos === "right" ? 1 : 0)
    readonly property real motionY: dockPos === "top" ? -1 : (dockPos === "bottom" ? 1 : 0)

    // Per-item cascade for hosts that stagger their content (app groups).
    function contentProgress(index) {
        const delay = Math.min(7, Math.max(0, index)) * 0.035 + 0.08;
        return Math.max(0, Math.min(1, (root.grow - delay) / (1 - delay)));
    }

    function _playEnter(fromStart) {
        motion.playEnter(fromStart);
    }

    signal closed()

    function open() {
        if (active && !isClosing) return
        const reopening = active && isClosing
        isClosing = false
        menuOpen = true
        active = true
        if (reopening)
            root._playEnter(false)
        else if (root.item)
            root._playEnter(true)
    }

    function close() {
        if (!active || isClosing) return
        isClosing = true
    }
    // A workspace change closes every menu and its focus grab
    // (ContextMenus.dismissAll); app groups and stacks go with them.
    Connections {
        target: ContextMenus
        function onDismissAllRequested() { root.close(); }
    }

    onActiveChanged: {
        if (!root.active) {
            root.menuOpen = false
            motion.stop()
            root.pointerInsidePopup = false
            root.closed()
        }
    }

    onLoaded: root._playEnter(true)

    active: false
    visible: active

    sourceComponent: PopupWindow {
        id: popupWindow
        visible: true
        color: "transparent"

        property real dockMargin: -16
        property real shadowMargin: Math.max(20, root.motionMargin)
        readonly property real slideDistance: Appearance.sizes.elevationMargin * 2
        readonly property real slideOffsetX: root.useDockSlideAnimation
            ? (root.dockPos === "left" ? -slideDistance : (root.dockPos === "right" ? slideDistance : 0))
            : 0
        readonly property real slideOffsetY: root.useDockSlideAnimation
            ? (root.dockPos === "top" ? -slideDistance : (root.dockPos === "bottom" ? slideDistance : 0))
            : 0
        function requestAnchorUpdate() {
            if (!root.active || !root.anchorItem || !popupWindow.anchor.window)
                return
            anchorUpdateTimer.restart()
        }

        Timer {
            id: anchorUpdateTimer
            interval: 0
            repeat: false
            onTriggered: {
                if (root.active && root.anchorItem && popupWindow.anchor.window)
                    popupWindow.anchor.updateAnchor()
            }
        }

        anchor {
            adjustment: PopupAdjustment.None
            window: root.anchorItem ? root.anchorItem.QsWindow.window : null
            onAnchoring: {
                const item = root.geometryItem
                if (!item) return
                const pos = root.dockPos
                // Map the edges, not centre +/- scale, so magnification applied
                // by an ancestor is counted too.
                const topLeft = item.mapToItem(null, 0, 0)
                const bottomRight = item.mapToItem(null, item.width, item.height)
                const mapped = Qt.point((topLeft.x + bottomRight.x) / 2, (topLeft.y + bottomRight.y) / 2)
                const dm = popupWindow.dockMargin
                const itemHalfH = Math.abs(bottomRight.y - topLeft.y) / 2
                const itemHalfW = Math.abs(bottomRight.x - topLeft.x) / 2

                let x, y
                if (pos === "bottom") {
                    x = mapped.x - popupWindow.implicitWidth / 2
                    y = mapped.y - itemHalfH - popupWindow.implicitHeight - dm
                } else if (pos === "top") {
                    x = mapped.x - popupWindow.implicitWidth / 2
                    y = mapped.y + itemHalfH + dm
                } else if (pos === "left") {
                    x = mapped.x + itemHalfW + dm
                    y = mapped.y - popupWindow.implicitHeight / 2
                } else {
                    x = mapped.x - itemHalfW - popupWindow.implicitWidth - dm
                    y = mapped.y - popupWindow.implicitHeight / 2
                }

                // Centred on an item near either end of the dock, the card ran
                // past the screen edge (the adjustment is None, so nothing
                // slides it back). The dock window spans its whole main axis,
                // minus other exclusive zones, so its edges are the limits;
                // the shadow envelope may hang outside, the card may not. A
                // card longer than the screen keeps its start visible.
                const win = popupWindow.anchor.window
                if (win) {
                    const sm = popupWindow.shadowMargin
                    const edgeGap = Appearance.sizes.hyprlandGapsOut
                    if (pos === "left" || pos === "right")
                        y = Math.max(edgeGap - sm, Math.min(y, win.height - popupWindow.implicitHeight + sm - edgeGap))
                    else
                        x = Math.max(edgeGap - sm, Math.min(x, win.width - popupWindow.implicitWidth + sm - edgeGap))
                }

                // One write per axis: every change to the rect re-dirties the
                // anchor, so writing a provisional value and then the final
                // one re-ran this handler forever (a polish loop per open).
                anchor.rect.x = Math.round(x)
                anchor.rect.y = Math.round(y)
            }
        }

        // PopupAnchor does not follow an item after the initial placement.
        // Dock magnification changes both the item's scale and the panel's
        // position, so re-anchor the group popup while it remains open.
        Connections {
            target: root.geometryItem
            function onScaleChanged() { popupWindow.requestAnchorUpdate() }
            function onXChanged() { popupWindow.requestAnchorUpdate() }
            function onYChanged() { popupWindow.requestAnchorUpdate() }
            function onWidthChanged() { popupWindow.requestAnchorUpdate() }
            function onHeightChanged() { popupWindow.requestAnchorUpdate() }
        }

        Connections {
            target: root.anchorItem?.dockContent ?? null
            function onButtonHoveredChanged() { popupWindow.requestAnchorUpdate() }
            function onHoveredSlotChanged() { popupWindow.requestAnchorUpdate() }
            function onLastHoveredButtonChanged() { popupWindow.requestAnchorUpdate() }
            function onFlattenedItemsChanged() { popupWindow.requestAnchorUpdate() }
            function onLayoutVisualMainExtentChanged() { popupWindow.requestAnchorUpdate() }
        }

        // The surface only ever grows while it is open. Following the card's
        // animated height resized the Wayland surface (and re-anchored it) on
        // every frame of a height change, which is what made a panel shake;
        // the content is pinned to the dock-side edge of this reserve and the
        // card animates inside it instead.
        property real reservedContentHeight: 0
        readonly property real targetContentHeight: menuContent.targetHeight
        onTargetContentHeightChanged: reservedContentHeight = Math.max(reservedContentHeight, targetContentHeight)
        Component.onCompleted: reservedContentHeight = targetContentHeight

        implicitWidth: menuContent.implicitWidth * root.zoom + popupWindow.shadowMargin * 2
        implicitHeight: Math.max(popupWindow.reservedContentHeight, menuContent.implicitHeight) * root.zoom + popupWindow.shadowMargin * 2

        onImplicitWidthChanged: requestAnchorUpdate()
        onImplicitHeightChanged: requestAnchorUpdate()

        HyprlandFocusGrab {
            active: root.active && !root.isClosing
            windows: [popupWindow]
            onCleared: root.close()
        }

        // The extra transparent envelope lets a folder icon leave its surface
        // while grabbed. A normal click in that envelope still dismisses it.
        MouseArea {
            id: dismissArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: event => {
                const point = menuContent.mapFromItem(dismissArea, event.x, event.y);
                if (point.x >= 0 && point.x < menuContent.width && point.y >= 0 && point.y < menuContent.height)
                    event.accepted = false;
                else
                    root.close();
            }
        }

        Item {
            id: menuContent
            // Pinned to the edge that faces the dock, so a card that changes
            // height grows and shrinks away from the dock inside the reserve.
            // Zoomed about the dock-facing edge: a side dock pins that edge,
            // so the card grows away from the dock instead of past the surface.
            x: root.dockPos === "left" ? popupWindow.shadowMargin
                : root.dockPos === "right" ? parent.width - popupWindow.shadowMargin - width
                : (parent.width - width) / 2
            y: root.dockPos === "bottom" ? parent.height - popupWindow.shadowMargin - height
                : root.dockPos === "top" ? popupWindow.shadowMargin
                : (parent.height - height) / 2
            width: implicitWidth
            height: implicitHeight
            focus: true

            readonly property bool dataDriven: root.menuGroups !== null && root.contentComponent === null
            readonly property real cardContentWidth: dataDriven || root.showHeader
                ? root.effectiveMenuWidth - root.cardPadding * 2
                : contentLoader.implicitWidth
            readonly property real cardContentHeight: dataDriven
                ? root.headerBlock + root.barHeight + menuGroupsView.implicitHeight
                : contentLoader.implicitHeight

            implicitWidth: cardContentWidth + root.cardPadding * 2
            implicitHeight: root.plateBlock + card.implicitHeight
            // Where the card is heading, not where its animation is.
            readonly property real targetHeight: root.plateBlock
                + menuContent.cardContentHeight + root.cardPadding * 2

            // One clock for the pair: the grow runs the whole transition, the
            // fade is over in its first half so the rows are readable at once.
            opacity: root.reveal
            scale: motion.scale * root.zoom
            transformOrigin: root.dockPos === "top" ? Item.Top
                : root.dockPos === "left" ? Item.Left
                : root.dockPos === "right" ? Item.Right
                : Item.Bottom
            enabled: !root.isClosing
            transform: Translate {
                x: popupWindow.slideOffsetX * (1 - root.grow)
                y: popupWindow.slideOffsetY * (1 - root.grow)
            }

            Keys.onEscapePressed: event => {
                event.accepted = true;
                root.close();
            }

            HoverHandler {
                onHoveredChanged: root.pointerInsidePopup = hovered
            }

            // The plate: what the menu is about.
            StyledRectangularShadow {
                target: plate
                visible: plate.visible
                // Under Hyprland's popup blur threshold (ignore_alpha 0.19 on
                // quickshell.*): a darker shadow gets the wallpaper behind it
                // blurred, a light halo around a card over a bright wallpaper.
                color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.83)
            }
            Rectangle {
                id: plate
                visible: root.plateShown
                width: parent.width
                height: root.plateHeight
                radius: root.cardRadius
                color: root.surfaceColor

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.dense ? 8 : 12
                    spacing: root.dense ? 10 : 12

                    Rectangle {
                        implicitWidth: root.dense ? 36 : 64
                        implicitHeight: implicitWidth
                        radius: Math.max(Appearance.rounding.verysmall, root.cardRadius - (root.dense ? 8 : 12))
                        color: Appearance.colors.colSurfaceContainerHigh

                        Loader {
                            anchors.centerIn: parent
                            width: root.dense ? 28 : 48
                            height: width
                            active: root.showHeader && !!root.headerIcon
                            sourceComponent: root.headerIcon
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: root.showHeader && !root.headerIcon && root.headerSymbol !== ""
                            text: root.headerSymbol
                            iconSize: root.dense ? 20 : 32
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.dense ? 1 : 4

                        StyledText {
                            Layout.fillWidth: true
                            text: root.headerText
                            font.pixelSize: root.dense ? Appearance.font.pixelSize.smallie + 1 : Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: root.headerSubtitle
                            font.pixelSize: root.dense ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }

            // The card: the actions, or the custom content it hosts.
            StyledRectangularShadow {
                target: card
                // Under Hyprland's popup blur threshold (ignore_alpha 0.19 on
                // quickshell.*): a darker shadow gets the wallpaper behind it
                // blurred, a light halo around a card over a bright wallpaper.
                color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.83)
            }
            Rectangle {
                id: card
                y: root.plateBlock
                width: parent.width
                height: implicitHeight
                implicitHeight: menuContent.cardContentHeight + root.cardPadding * 2
                radius: root.cardRadius
                color: root.surfaceColor
                // While the height animates the content is already at its new
                // size; clip it to the card instead of letting it spill out.
                clip: heightAnimation.running

                Behavior on implicitHeight {
                    id: heightBehavior
                    enabled: root.popupProgress === 1 && !root.isClosing
                    NumberAnimation {
                        id: heightAnimation
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                // Compact: the plate's job as the card's first row - the
                // icon at row size, the name over its one-line state - with
                // a hairline under it like the separators between groups.
                Item {
                    visible: root.headerBlock > 0
                    x: root.cardPadding
                    y: root.cardPadding
                    width: menuContent.cardContentWidth
                    height: root.headerBlock

                    RowLayout {
                        x: 8
                        width: parent.width - 16
                        height: root.headerRowHeight
                        spacing: 10

                        Item {
                            implicitWidth: 28
                            implicitHeight: 28
                            Loader {
                                anchors.centerIn: parent
                                width: 24
                                height: 24
                                active: root.headerBlock > 0 && !!root.headerIcon
                                sourceComponent: root.headerIcon
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: !root.headerIcon && root.headerSymbol !== ""
                                text: root.headerSymbol
                                iconSize: 20
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: root.headerText
                                font.pixelSize: Appearance.font.pixelSize.smallie + 1
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurface
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: root.headerSubtitle
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

                ContextMenuIconBar {
                    visible: menuContent.dataDriven && root.barEntries.length > 0
                    x: root.cardPadding
                    y: root.cardPadding + root.headerBlock
                    width: menuContent.cardContentWidth
                    height: implicitHeight
                    entries: menuContent.dataDriven ? root.barEntries : []
                    hostPadding: root.cardPadding
                    onActivated: (entry, button) => root._trigger(String(entry.id ?? ""))
                }

                DockMenuGroups {
                    id: menuGroupsView
                    visible: menuContent.dataDriven
                    x: root.cardPadding
                    y: root.cardPadding + root.headerBlock + root.barHeight
                    width: menuContent.cardContentWidth
                    groups: menuContent.dataDriven ? root.shownGroups : []
                    dense: root.dense
                    hostRadius: root.cardRadius
                    hostPadding: root.cardPadding
                    onTriggered: actionId => root._trigger(actionId)
                    onNaturalWidthChanged: root._groupsNaturalWidth = naturalWidth
                    Component.onCompleted: root._groupsNaturalWidth = naturalWidth
                }

                Loader {
                    id: contentLoader
                    readonly property var _dockPopup: root
                    x: root.cardPadding
                    y: root.cardPadding
                    width: menuContent.cardContentWidth
                    active: root.contentComponent !== null
                    sourceComponent: root.contentComponent
                }
            }
        }
    }

    property Component contentComponent: null
}
