import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
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
    // Two scalars, as the desktop menu card (DesktopMenuCard) settled on:
    // `grow` carries the shape (scale + slide out of the dock edge) on the
    // expressive enter clock, `reveal` the opacity on the fast clock, so the
    // surface is readable at once instead of fading in across the whole grow.
    // Both are driven by explicit animations: the exit has to say when it is
    // DONE, and a re-open mid-exit turns around from wherever it is.
    property real grow: 0
    property real reveal: 0
    readonly property bool _motion: !Appearance.reducedMotion
    readonly property real popupProgress: root.grow
    readonly property real motionX: dockPos === "left" ? -1 : (dockPos === "right" ? 1 : 0)
    readonly property real motionY: dockPos === "top" ? -1 : (dockPos === "bottom" ? 1 : 0)

    // Per-item cascade for hosts that stagger their content (app groups).
    function contentProgress(index) {
        const delay = Math.min(7, Math.max(0, index)) * 0.035 + 0.08;
        return Math.max(0, Math.min(1, (root.grow - delay) / (1 - delay)));
    }

    ParallelAnimation {
        id: enterMotion
        NumberAnimation {
            target: root
            property: "grow"
            to: 1
            duration: root._motion ? Appearance.animation.elementMoveEnter.duration : 0
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "reveal"
            to: 1
            duration: root._motion ? Appearance.animation.elementMoveFast.duration : 0
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    // The exit leaves as ONE piece, short and accelerating: shape and opacity
    // on the same exit clock, so nothing inside outlives the card.
    ParallelAnimation {
        id: exitMotion
        NumberAnimation {
            target: root
            property: "grow"
            to: 0.5
            duration: root._motion ? Appearance.animation.elementMoveExit.duration : 0
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "reveal"
            to: 0
            duration: root._motion ? Appearance.animation.elementMoveExit.duration : 0
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        // One more frame before the unmap, so the surface's last committed
        // buffer is the transparent one. Unmapping on the frame the fade
        // reached zero left a half-faded buffer, and the compositor's own
        // unmap fade then showed it as a ghost: the card gone, its content
        // still floating.
        onFinished: unmapDelay.restart()
    }
    Timer {
        id: unmapDelay
        interval: 32
        onTriggered: {
            if (!root.isClosing)
                return;
            root.active = false;
            root.isClosing = false;
        }
    }

    function _playEnter(fromStart) {
        exitMotion.stop();
        unmapDelay.stop();
        if (fromStart) {
            root.grow = 0;
            root.reveal = 0;
        }
        enterMotion.restart();
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
        enterMotion.stop()
        exitMotion.restart()
    }

    onActiveChanged: {
        if (!root.active) {
            root.menuOpen = false
            enterMotion.stop()
            exitMotion.stop()
            unmapDelay.stop()
            root.grow = 0
            root.reveal = 0
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

        // The surface only ever grows while it is open. Following the card's
        // animated height resized the Wayland surface (and re-anchored it) on
        // every frame of a height change, which is what made a panel shake;
        // the content is pinned to the dock-side edge of this reserve and the
        // card animates inside it instead.
        property real reservedContentHeight: 0
        readonly property real targetContentHeight: menuContent.targetHeight
        onTargetContentHeightChanged: reservedContentHeight = Math.max(reservedContentHeight, targetContentHeight)
        Component.onCompleted: reservedContentHeight = targetContentHeight

        implicitWidth: menuContent.implicitWidth + popupWindow.shadowMargin * 2
        implicitHeight: Math.max(popupWindow.reservedContentHeight, menuContent.implicitHeight) + popupWindow.shadowMargin * 2

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
            x: (parent.width - width) / 2
            y: root.dockPos === "bottom" ? parent.height - popupWindow.shadowMargin - height
                : root.dockPos === "top" ? popupWindow.shadowMargin
                : (parent.height - height) / 2
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
            // Where the card is heading, not where its animation is.
            readonly property real targetHeight: (root.showHeader ? root.plateHeight + root.surfaceGap : 0)
                + menuContent.cardContentHeight + root.cardPadding * 2

            // One clock for the pair: the grow runs the whole transition, the
            // fade is over in its first half so the rows are readable at once.
            opacity: root.reveal
            scale: 0.85 + 0.15 * root.grow
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
                // Under Hyprland's popup blur threshold (ignore_alpha 0.19 on
                // quickshell.*): a darker shadow gets the wallpaper behind it
                // blurred, a light halo around a card over a bright wallpaper.
                color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.83)
            }
            Rectangle {
                id: card
                y: root.showHeader ? root.plateHeight + root.surfaceGap : 0
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
