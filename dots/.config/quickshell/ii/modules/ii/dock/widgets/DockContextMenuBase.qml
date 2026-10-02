import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
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
    readonly property real cardPadding: 8
    readonly property real plateHeight: 88
    readonly property real surfaceGap: 6
    readonly property real popupProgress: popupMotion.progress
    readonly property real motionX: dockPos === "left" ? -1 : (dockPos === "right" ? 1 : 0)
    readonly property real motionY: dockPos === "top" ? -1 : (dockPos === "bottom" ? 1 : 0)

    function contentProgress(index) { return popupMotion.phase(index); }

    DockMotion {
        id: popupMotion
        onSettled: value => {
            if (value === 0 && root.isClosing) {
                root.active = false;
                root.isClosing = false;
            }
        }
    }

    signal closed()

    function open() {
        if (active && !isClosing) return
        isClosing = false
        menuOpen = true
        active = true
        if (root.item) popupMotion.animateTo(1)
    }

    function close() {
        if (!active || isClosing) return
        isClosing = true
        popupMotion.animateTo(0)
    }

    onActiveChanged: {
        if (!root.active) {
            root.menuOpen = false
            popupMotion.reset(0)
            root.pointerInsidePopup = false
            root.closed()
        }
    }

    onLoaded: popupMotion.animateTo(root.isClosing ? 0 : 1)

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

                if (pos === "bottom") {
                    anchor.rect.x = mapped.x - popupWindow.implicitWidth / 2
                    anchor.rect.y = mapped.y - itemHalfH - popupWindow.implicitHeight - dm
                } else if (pos === "top") {
                    anchor.rect.x = mapped.x - popupWindow.implicitWidth / 2
                    anchor.rect.y = mapped.y + itemHalfH + dm
                } else if (pos === "left") {
                    anchor.rect.x = mapped.x + itemHalfW + dm
                    anchor.rect.y = mapped.y - popupWindow.implicitHeight / 2
                } else {
                    anchor.rect.x = mapped.x - itemHalfW - popupWindow.implicitWidth - dm
                    anchor.rect.y = mapped.y - popupWindow.implicitHeight / 2
                }
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

        implicitWidth: menuContent.implicitWidth + popupWindow.shadowMargin * 2
        implicitHeight: menuContent.implicitHeight + popupWindow.shadowMargin * 2

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
            anchors.centerIn: parent
            width: implicitWidth
            height: implicitHeight
            focus: true

            readonly property bool dataDriven: root.menuGroups !== null && root.contentComponent === null
            readonly property real cardContentWidth: dataDriven || root.showHeader
                ? root.menuWidth - root.cardPadding * 2
                : contentLoader.implicitWidth
            readonly property real cardContentHeight: dataDriven
                ? menuGroupsView.implicitHeight
                : contentLoader.implicitHeight

            implicitWidth: cardContentWidth + root.cardPadding * 2
            implicitHeight: (root.showHeader ? root.plateHeight + root.surfaceGap : 0) + card.implicitHeight

            // One clock for the pair: the grow runs the whole transition, the
            // fade is over in its first half so the rows are readable at once.
            opacity: Math.min(1, root.popupProgress * 2)
            scale: 0.85 + 0.15 * root.popupProgress
            transformOrigin: root.dockPos === "top" ? Item.Top
                : root.dockPos === "left" ? Item.Left
                : root.dockPos === "right" ? Item.Right
                : Item.Bottom
            enabled: !root.isClosing
            transform: Translate {
                x: popupWindow.slideOffsetX * (1 - root.popupProgress)
                y: popupWindow.slideOffsetY * (1 - root.popupProgress)
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
            }
            Rectangle {
                id: plate
                visible: root.showHeader
                width: parent.width
                height: root.plateHeight
                radius: root.cardRadius
                color: root.surfaceColor

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Rectangle {
                        implicitWidth: 64
                        implicitHeight: 64
                        radius: Math.max(Appearance.rounding.verysmall, root.cardRadius - 12)
                        color: Appearance.colors.colSurfaceContainerHigh

                        Loader {
                            anchors.centerIn: parent
                            width: 48
                            height: 48
                            active: root.showHeader && !!root.headerIcon
                            sourceComponent: root.headerIcon
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: root.showHeader && !root.headerIcon && root.headerSymbol !== ""
                            text: root.headerSymbol
                            iconSize: 32
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            Layout.fillWidth: true
                            text: root.headerText
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: root.headerSubtitle
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }

            // The card: the actions, or the custom content it hosts.
            StyledRectangularShadow {
                target: card
            }
            Rectangle {
                id: card
                y: root.showHeader ? root.plateHeight + root.surfaceGap : 0
                width: parent.width
                height: implicitHeight
                implicitHeight: menuContent.cardContentHeight + root.cardPadding * 2
                radius: root.cardRadius
                color: root.surfaceColor

                Behavior on implicitHeight {
                    enabled: root.popupProgress === 1 && !root.isClosing
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
                }

                DockMenuGroups {
                    id: menuGroupsView
                    visible: menuContent.dataDriven
                    x: root.cardPadding
                    y: root.cardPadding
                    width: menuContent.cardContentWidth
                    groups: menuContent.dataDriven ? root.menuGroups : []
                    hostRadius: root.cardRadius
                    hostPadding: root.cardPadding
                    onTriggered: actionId => root.actionTriggered(actionId)
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
