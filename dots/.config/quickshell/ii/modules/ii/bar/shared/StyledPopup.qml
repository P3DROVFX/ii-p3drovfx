import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

LazyLoader {
    id: root
    property Item hoverTarget
    default property Item contentItem

    readonly property real popupOpenProgress: root.item ? root.item.popupOpenProgress : 0.0

    readonly property real screenWidth: root.item ? root.item.screenWidth : 0
    readonly property real screenHeight: root.item ? root.item.screenHeight : 0
    readonly property bool isScreenSmall: screenHeight > 0 && screenHeight < 800

    readonly property real layoutScale: {
        if (screenHeight <= 0 || !root.contentItem)
            return 1.0;
        var baseScale = Math.max(0.75, Math.min(1.5, screenHeight / 1080.0));
        var barSpace = Config.options.bar.vertical ? 0 : Appearance.sizes.barHeight;
        var maxAllowedHeight = screenHeight - barSpace - Appearance.sizes.elevationMargin * 2 - 40;
        var maxAllowedWidth = (screenWidth > 0 ? screenWidth : 1920) * 0.9;
        
        var userMultiplier = Config.options?.bar?.tooltips?.popupScaleMultiplier ?? 1.0;
        var scale = baseScale * userMultiplier;
        // Measure with the actual candidate scale. Using baseScale here made
        // the size guard ignore the user multiplier and allowed oversized popup
        // surfaces to exceed the monitor's safe bounds.
        var scaledHeight = (root.contentItem.implicitHeight + 20) * scale;
        var scaledWidth = (root.contentItem.implicitWidth + 20) * scale;
        if (scaledHeight > maxAllowedHeight) {
            scale = Math.min(scale, Math.max(0.5, maxAllowedHeight / (root.contentItem.implicitHeight + 20)));
        }
        if (scaledWidth > maxAllowedWidth) {
            scale = Math.min(scale, Math.max(0.5, maxAllowedWidth / (root.contentItem.implicitWidth + 20)));
        }
        return scale;
    }
    property real popupBackgroundMargin: 0
    property int popupRadius: Appearance.rounding.large
    property bool animate: true
    property bool animateHeight: true
    property bool stickyHover: false
    property int keyboardFocus: WlrKeyboardFocus.None

    property bool customPosition: false
    property bool anchorRight: false
    property bool anchorLeft: false
    property bool anchorTop: false
    property bool anchorBottom: false
    property int customMarginLeft: 0
    property int customMarginRight: 0
    property int customMarginTop: 0
    property int customMarginBottom: 0

    // Expose active state to child elements so they can trigger animations,
    // exactly like WeatherPopup does for HourlyForecast.
    readonly property bool opened: _computedActive && !root._isClosing

    property bool _popupHovered: false
    property bool _stickyActive: false
    property bool forceClick: false
    // Set false when the user of this popup runs its own focus grab. Hyprland honours only
    // one grab per client, so a second one silently clears the first.
    property bool selfDismiss: true
    property bool _targetHovered: hoverTarget ? (hoverTarget.containsMouse !== undefined ? hoverTarget.containsMouse : (hoverTarget.hovered !== undefined ? hoverTarget.hovered : false)) : false
    property bool _clickActive: false
    property bool _isClosing: false
    property bool _reopenPending: false

    readonly property bool _computedActive: Config.options.bar.tooltips.enablePopups && ((Config.options.bar.tooltips.clickToShow || forceClick) ? _clickActive : (stickyHover ? _stickyActive : (_targetHovered && _openDebounced)))

    property bool _openDebounced: false

    active: _computedActive || _isClosing

    on_ComputedActiveChanged: {
        if (!_computedActive) {
            _isClosing = true;
            _reopenPending = false;
        } else if (_isClosing) {
            // Do not reverse a close halfway through. Child popup animations may
            // still have queued callbacks from the previous entrance; wait for a
            // clean progress=0 reset and reopen the instance afterward.
            _reopenPending = true;
        } else {
            _isClosing = false;
        }
    }

    property QtObject _timers: QtObject {
        property Timer openDebounce: Timer {
            interval: 60
            repeat: false
            onTriggered: {
                if (root._targetHovered && !root._isClosing) {
                    root._openDebounced = true;
                }
            }
        }
        property Timer grace: Timer {
            interval: 100 + Math.max(0, (Config.options && Config.options.bar && Config.options.bar.tooltips && Config.options.bar.tooltips.closeDelay) ? Config.options.bar.tooltips.closeDelay : 0)
            onTriggered: {
                root._popupHovered = false;
                root._stickyActive = false;
            }
        }
    }

    // Dismiss the popup regardless of which mode opened it (click, sticky hover or plain hover).
    function close() {
        _clickActive = false;
        _stickyActive = false;
        _openDebounced = false;
        _popupHovered = false;
        _timers.openDebounce.stop();
        _timers.grace.stop();
    }

    function _evaluateStickyState() {
        if (!stickyHover)
            return;

        // Neither the popup body nor the source widget may reverse a close in
        // progress. The source widget can request a queued re-open separately.
        if (_isClosing) {
            if (_targetHovered)
                _reopenPending = true;
            return;
        }

        if (_targetHovered || _popupHovered) {
            _stickyActive = true;
            _timers.grace.stop();
        } else if (_stickyActive && !_timers.grace.running) {
            _timers.grace.start();
        }
    }

    function _queueReopenFromTarget() {
        if (!_isClosing)
            return;

        _timers.grace.stop();
        _reopenPending = true;
    }

    on_TargetHoveredChanged: {
        if (_targetHovered) {
            if (_isClosing)
                _queueReopenFromTarget();
            _timers.openDebounce.restart();
        } else {
            _timers.openDebounce.stop();
            _openDebounced = false;
            _reopenPending = false;
        }

        if (Config.options.bar.tooltips.clickToShow || forceClick) {
            if (_targetHovered && !root._clickActive && !root._isClosing) {
                root._clickActive = true;
            }
        } else {
            _evaluateStickyState();
        }
    }

    onActiveChanged: {
        if (!active) {
            _popupHovered = false;
            _isClosing = false;
            _openDebounced = false;
            _timers.openDebounce.stop();
            _timers.grace.stop();
        }
    }

    component: PanelWindow {
        id: popupWindow
        WlrLayershell.keyboardFocus: root.keyboardFocus
        color: "transparent"

        readonly property real screenWidth: popupWindow.screen?.width ?? 0
        readonly property real screenHeight: popupWindow.screen?.height ?? 0

        anchors.left: root.customPosition ? root.anchorLeft : (!Config.options.bar.vertical || (Config.options.bar.vertical && !Config.options.bar.bottom))
        anchors.right: root.customPosition ? root.anchorRight : (Config.options.bar.vertical && Config.options.bar.bottom)
        anchors.top: root.customPosition ? root.anchorTop : (Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom))
        anchors.bottom: root.customPosition ? root.anchorBottom : (!Config.options.bar.vertical && Config.options.bar.bottom)

        implicitWidth: popupBackground.targetWidth + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin
        implicitHeight: popupBackground._windowHeight + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin

        // The input region must not follow the open animation. popupBackground lives inside
        // animContainer, which carries a Translate transform, and a transform change does not
        // emit the geometry signals Region listens to — so the committed region can stay stuck
        // at the animation's starting offset and swallow clicks aimed at the popup's contents.
        Item {
            id: maskRect
            x: popupBackground.x
            y: popupBackground.y
            width: popupBackground.width
            height: popupBackground.height
        }

        mask: Region {
            item: maskRect
        }

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        margins {
            left: {
                if (root.customPosition) {
                    return root.customMarginLeft;
                }
                if (!Config.options.bar.vertical) {
                    if (!root.hoverTarget || !root.QsWindow)
                        return 0;
                    var targetPos = root.QsWindow.mapFromItem(root.hoverTarget, 0, 0);
                    var centeredX = targetPos.x + (root.hoverTarget.width - popupWindow.implicitWidth) / 2;
                    var minX = 0;
                    var maxX = screenWidth - popupWindow.implicitWidth;
                    return Math.max(minX, Math.min(maxX, centeredX));
                }
                return Appearance.sizes.verticalBarWidth;
            }

            top: {
                if (root.customPosition) {
                    return root.customMarginTop;
                }
                if (!Config.options.bar.vertical) {
                    return Appearance.sizes.barHeight;
                }
                if (!root.hoverTarget || !root.QsWindow)
                    return 0;
                var targetPos = root.QsWindow.mapFromItem(root.hoverTarget, 0, 0);
                var centeredY = targetPos.y + (root.hoverTarget.height - popupWindow.implicitHeight) / 2;
                var minY = 0;
                var maxY = screenHeight - popupWindow.implicitHeight;
                return Math.max(minY, Math.min(maxY, centeredY));
            }

            right: root.customPosition ? root.customMarginRight : Appearance.sizes.verticalBarWidth
            bottom: root.customPosition ? root.customMarginBottom : Appearance.sizes.barHeight
        }

        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay

        property bool _dismissGrabArmed: false

        HyprlandFocusGrab {
            id: dismissGrab
            windows: [popupWindow]
            active: root.selfDismiss && (Config.options.bar.tooltips.clickToShow || root.forceClick) && root._computedActive && popupWindow._dismissGrabArmed
            onCleared: () => {
                root._clickActive = false;
            }
        }

        // Other shell modules (sidebars, cheatsheet, usage stats) run a HyprlandFocusGrab
        // that routes ALL pointer input to their grabbed windows. With such a grab active,
        // hover and clicks aimed at this popup were silently denied. Joining the shared
        // grab as persistent lets the compositor deliver input here while a module is
        // open — the same mechanism BarWindow.qml already uses for the bar itself.
        // Click-to-show popups are excluded: they run their own dismissGrab above.
        readonly property bool joinsSharedGrab: !(root.selfDismiss
            && (Config.options.bar.tooltips.clickToShow || root.forceClick))

        function updateSharedGrabMembership() {
            if (popupWindow.joinsSharedGrab && root.active)
                GlobalFocusGrab.addPersistent(popupWindow);
            else
                GlobalFocusGrab.removePersistent(popupWindow);
        }

        Component.onDestruction: GlobalFocusGrab.removePersistent(popupWindow)

        property real animProgress: 0.0
        readonly property real popupOpenProgress: animProgress
        property var childDelays: []

        onAnimProgressChanged: updateChildrenAnimation()

        function updateChildrenAnimation() {
            // Keep children animation clean and empty since they will animate themselves
            // directly using the root.active property, matching HourlyForecast's pattern.
        }

        readonly property bool isBarVertical: Config.options.bar.vertical
        readonly property bool isBarBottom: Config.options.bar.bottom
        readonly property real slideOffset: 35

        readonly property real slideX: {
            if (!isBarVertical)
                return 0;
            return isBarBottom ? slideOffset : -slideOffset;
        }

        readonly property real slideY: {
            if (isBarVertical)
                return 0;
            return isBarBottom ? slideOffset : -slideOffset;
        }

        readonly property Item heroItem: {
            if (!root.contentItem)
                return null;
            for (let i = 0; i < root.contentItem.children.length; i++) {
                let child = root.contentItem.children[i];
                if (child.visible && child.width > 0)
                    return child;
            }
            return null;
        }
        readonly property real heroHeight: heroItem ? heroItem.implicitHeight : 0

        SequentialAnimation {
            id: openAnimSeq
            PauseAnimation {
                duration: 50
            }
            NumberAnimation {
                id: openProgressAnim
                target: popupWindow
                property: "animProgress"
                from: 0.0
                to: 1.0
                duration: 380
                easing.type: Easing.OutQuart
            }
        }

        NumberAnimation {
            id: closeAnim
            target: popupWindow
            property: "animProgress"
            from: 1.0
            to: 0.0
            duration: 260
            easing.type: Easing.InCubic
            onFinished: {
                popupWindow.animProgress = 0.0;
                destroyTimer.start();
            }
        }

        Timer {
            id: destroyTimer
            interval: 30
            onTriggered: {
                root._isClosing = false;
                if (root._reopenPending)
                    reopenAfterClose.start();
            }
        }

        Timer {
            id: reopenAfterClose
            interval: 1
            onTriggered: {
                if (!root._reopenPending)
                    return;

                root._reopenPending = false;
                if (root._targetHovered || Config.options.bar.tooltips.clickToShow || root.forceClick) {
                    if (Config.options.bar.tooltips.clickToShow || root.forceClick)
                        root._clickActive = true;
                    else if (root.stickyHover)
                        root._stickyActive = true;
                    else
                        root._openDebounced = true;
                }
            }
        }

        Connections {
            target: root
            function onActiveChanged() {
                if (root.active) {
                    popupWindow.animProgress = 0.0;
                    openAnimSeq.start();
                } else {
                    popupWindow.animProgress = 0.0;
                }
                popupWindow.updateSharedGrabMembership();
            }
            function on_IsClosingChanged() {
                if (root._isClosing) {
                    openAnimSeq.stop();
                    closeAnim.from = popupWindow.animProgress;
                    closeAnim.start();
                } else if (root._computedActive) {
                    closeAnim.stop();
                    destroyTimer.stop();
                    popupWindow.animProgress = 0.0;
                    openAnimSeq.start();
                }
            }
            function on_ComputedActiveChanged() {
                if (root._computedActive && root.selfDismiss) {
                    popupWindow._dismissGrabArmed = false;
                    dismissGrabArmTimer.restart();
                } else {
                    dismissGrabArmTimer.stop();
                    popupWindow._dismissGrabArmed = false;
                }
            }
        }

        Component.onCompleted: {
            if (root.selfDismiss && Config.options.bar.tooltips.clickToShow) {
                dismissGrabArmTimer.restart();
            }
            popupWindow.animProgress = 0.0;
            openAnimSeq.start();
            popupWindow.updateSharedGrabMembership();
        }

        Timer {
            id: dismissGrabArmTimer
            interval: 250
            onTriggered: popupWindow._dismissGrabArmed = true
        }

        Item {
            id: animContainer
            anchors.fill: parent
            opacity: popupWindow.animProgress

            transform: Translate {
                x: popupWindow.slideX * (1.0 - popupWindow.animProgress)
                y: popupWindow.slideY * (1.0 - popupWindow.animProgress)
            }

            // Keep the popup vector/text content on the scene graph. Do not put
            // it in an FBO: scaling an FBO pixelates text, Material Symbols,
            // and thin shapes on monitors with fractional scale.
            StyledRectangularShadow {
                target: popupBackground
                visible: !Config.options.appearance.transparency.popups
            }

            Rectangle {
                id: popupBackground
                readonly property real margin: 10

                readonly property real targetWidth: ((root.contentItem?.implicitWidth ?? 0) + margin * 2) * root.layoutScale
                readonly property real targetHeight: ((root.contentItem?.implicitHeight ?? 0) + margin * 2) * root.layoutScale

                property bool isVertical: Config.options.bar.vertical
                property bool isBottom: Config.options.bar.bottom
                property int elevation: Appearance.sizes.elevationMargin

                property real _commitHeight: 0
                property real _windowHeight: 0
                property bool _heightReady: false

                onTargetHeightChanged: {
                    _commitHeight = targetHeight;
                    _windowHeight = targetHeight;
                }

                Component.onCompleted: {
                    _commitHeight = targetHeight;
                    _windowHeight = targetHeight;
                    Qt.callLater(function () {
                        popupBackground._heightReady = true;
                    });
                }

                Behavior on _commitHeight {
                    enabled: popupBackground._heightReady && root.animate && root.animateHeight
                        && root.opened && popupWindow.animProgress >= 1.0
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Behavior on _windowHeight {
                    enabled: popupBackground._heightReady && root.animate && root.animateHeight
                        && root.opened && popupWindow.animProgress >= 1.0
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                anchors {
                    top: (!isVertical && !isBottom) ? parent.top : undefined
                    bottom: (!isVertical && isBottom) ? parent.bottom : undefined
                    left: (isVertical && !isBottom) ? parent.left : undefined
                    right: (isVertical && isBottom) ? parent.right : undefined

                    topMargin: top ? elevation : undefined
                    bottomMargin: bottom ? elevation : undefined
                    leftMargin: left ? elevation : undefined
                    rightMargin: right ? elevation : undefined

                    verticalCenter: isVertical ? parent.verticalCenter : undefined
                    horizontalCenter: !isVertical ? parent.horizontalCenter : undefined
                }

                width: targetWidth
                height: {
                    if (!root.animateHeight)
                        return targetHeight;
                    if (!root.animate || !root.contentItem || !heroItem || targetHeight <= heroHeight + margin * 2)
                        return _commitHeight;
                    return (heroHeight + margin * 2) + (_commitHeight - (heroHeight + margin * 2)) * popupWindow.animProgress;
                }

                color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer
                radius: root.popupRadius
                // During close the surface shrinks before the content tree is destroyed.
                // Clip that subtree to the same animated bounds so cards cannot spill out.
                clip: root._isClosing

                Item {
                    id: contentContainer
                    anchors.centerIn: parent
                    width: root.contentItem ? root.contentItem.implicitWidth : 0
                    height: root.contentItem ? root.contentItem.implicitHeight : 0

                    // Keep the content exit synchronized with the surface close. Scale
                    // by the currently available surface height so the cards follow the
                    // same contraction instead of remaining at their full size.
                    readonly property real closeScale: root._isClosing
                        ? Math.max(0.0, Math.min(1.0, popupBackground.height / Math.max(1.0, height)))
                        : 1.0
                    readonly property real closeOriginX: {
                        if (root.customPosition) {
                            if (root.anchorLeft)
                                return 0;
                            if (root.anchorRight)
                                return width;
                        }
                        if (popupBackground.isVertical)
                            return popupBackground.isBottom ? width : 0;
                        return width / 2;
                    }
                    readonly property real closeOriginY: {
                        if (root.customPosition) {
                            if (root.anchorTop)
                                return 0;
                            if (root.anchorBottom)
                                return height;
                        }
                        if (popupBackground.isVertical)
                            return height / 2;
                        return popupBackground.isBottom ? height : 0;
                    }

                    // Keep the layout scale centered; only the close transform should
                    // travel toward the bar, so opening geometry remains unchanged.
                    scale: root.layoutScale
                    opacity: root._isClosing ? closeScale : 1.0
                    transformOrigin: Item.Center
                    transform: Scale {
                        origin.x: contentContainer.closeOriginX
                        origin.y: contentContainer.closeOriginY
                        xScale: contentContainer.closeScale
                        yScale: contentContainer.closeScale
                    }
                    clip: false

                    // contentItem is owned by root, which is a LazyLoader (not an Item), so it
                    // outlives this window. Detach it before the window's item tree is torn down,
                    // otherwise it keeps a dangling visual parent and anchors into freed items.
                    Component.onDestruction: {
                        if (!root || !root.contentItem)
                            return;
                        root.contentItem.anchors.fill = undefined;
                        root.contentItem.parent = null;
                    }

                    Component.onCompleted: {
                        if (root.contentItem) {
                            root.contentItem.parent = contentContainer;
                            root.contentItem.anchors.centerIn = undefined;
                            root.contentItem.anchors.top = undefined;
                            root.contentItem.anchors.bottom = undefined;
                            root.contentItem.anchors.left = undefined;
                            root.contentItem.anchors.right = undefined;
                            root.contentItem.anchors.fill = contentContainer;

                            function recalculateDelays() {
                                if (!root || !root.contentItem)
                                    return;

                                let targetItem = root.contentItem;
                                if (root.contentItem.children.length === 1) {
                                    let firstChild = root.contentItem.children[0];
                                    let name = firstChild.toString();
                                    if (name.includes("Layout") || firstChild.hasOwnProperty("spacing")) {
                                        targetItem = firstChild;
                                    }
                                }

                                let visibleChildren = [];
                                for (let i = 0; i < targetItem.children.length; i++) {
                                    let child = targetItem.children[i];
                                    if (child && child.hasOwnProperty("visible") && child.visible) {
                                        visibleChildren.push(child);
                                    }
                                }

                                let delays = [];
                                let total = visibleChildren.length;
                                for (let i = 0; i < targetItem.children.length; i++) {
                                    let child = targetItem.children[i];
                                    let visIdx = visibleChildren.indexOf(child);
                                    if (visIdx !== -1) {
                                        delays.push(visIdx / Math.max(1, total));
                                    } else {
                                        delays.push(0);
                                    }
                                }
                                popupWindow.childDelays = delays;
                                popupWindow.updateChildrenAnimation();
                            }

                            recalculateDelays();

                            // Listen to hierarchy changes to connect and recalculate delays properly
                            function setupConnections() {
                                if (!root || !root.contentItem)
                                    return;
                                let targetItem = root.contentItem;
                                if (root.contentItem.children.length === 1) {
                                    let firstChild = root.contentItem.children[0];
                                    let name = firstChild.toString();
                                    if (name.includes("Layout") || firstChild.hasOwnProperty("spacing")) {
                                        targetItem = firstChild;
                                    }
                                }

                                for (let i = 0; i < targetItem.children.length; i++) {
                                    let child = targetItem.children[i];
                                    if (child && child.hasOwnProperty("visibleChanged")) {
                                        try {
                                            child.visibleChanged.disconnect(recalculateDelays);
                                        } catch (e) {}
                                        child.visibleChanged.connect(recalculateDelays);
                                    }
                                }
                                recalculateDelays();
                            }

                            setupConnections();

                            if (root.contentItem.hasOwnProperty("childrenChanged")) {
                                root.contentItem.childrenChanged.connect(setupConnections);
                            }

                            let targetItem = root.contentItem;
                            if (root.contentItem.children.length === 1) {
                                let firstChild = root.contentItem.children[0];
                                let name = firstChild.toString();
                                if (name.includes("Layout") || firstChild.hasOwnProperty("spacing")) {
                                    targetItem = firstChild;
                                }
                            }
                            if (targetItem !== root.contentItem && targetItem.hasOwnProperty("childrenChanged")) {
                                targetItem.childrenChanged.connect(setupConnections);
                            }
                        }
                    }
                }

                HoverHandler {
                    id: popupHoverHandler
                    onHoveredChanged: {
                        root._popupHovered = hovered;
                        root._evaluateStickyState();
                    }
                }

                border.width: Config.options.appearance.transparency.popups ? 0 : 1
                border.color: Appearance.colors.colLayer0Border
            }
        }
    }
}
