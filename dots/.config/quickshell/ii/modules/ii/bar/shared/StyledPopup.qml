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
        var barSpace = Config.options.bar.vertical ? 0 : Appearance.sizes.barHeight;
        var maxAllowedHeight = screenHeight - barSpace - Appearance.sizes.elevationMargin * 2 - 40;
        var naturalHeight = root.contentItem.implicitHeight + 20;
        if (naturalHeight > maxAllowedHeight) {
            return Math.max(0.6, maxAllowedHeight / naturalHeight);
        }
        return 1.0;
    }
    property real popupBackgroundMargin: 0
    property int popupRadius: Appearance.rounding.large
    property bool animate: true
    property bool animateHeight: true
    property bool stickyHover: false
    property int keyboardFocus: WlrKeyboardFocus.None
    
    // Expose active state to child elements so they can trigger animations,
    // exactly like WeatherPopup does for HourlyForecast.
    readonly property bool opened: _computedActive && !root._isClosing

    property bool _popupHovered: false
    property bool _stickyActive: false
    property bool _targetHovered: hoverTarget ? hoverTarget.containsMouse : false
    property bool _clickActive: false
    property bool _isClosing: false

    readonly property bool _computedActive: Config.options.bar.tooltips.clickToShow ? _clickActive : (stickyHover ? _stickyActive : (hoverTarget && hoverTarget.containsMouse))

    active: _computedActive || _isClosing

    on_ComputedActiveChanged: {
        if (!_computedActive) {
            _isClosing = true;
        } else {
            _isClosing = false;
        }
    }

    property QtObject _timers: QtObject {
        property Timer grace: Timer {
            interval: 100
            onTriggered: {
                root._popupHovered = false;
                root._stickyActive = false;
            }
        }
    }

    function _evaluateStickyState() {
        if (!stickyHover)
            return;

        if (_targetHovered || _popupHovered) {
            _stickyActive = true;
            _timers.grace.stop();
        } else if (_stickyActive && !_timers.grace.running) {
            _timers.grace.start();
        }
    }

    on_TargetHoveredChanged: {
        if (Config.options.bar.tooltips.clickToShow) {
            if (_targetHovered && !root._clickActive) {
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
            _timers.grace.stop();
        }
    }

    component: PanelWindow {
        id: popupWindow
        WlrLayershell.keyboardFocus: root.keyboardFocus
        color: "transparent"

        readonly property real screenWidth: popupWindow.screen?.width ?? 0
        readonly property real screenHeight: popupWindow.screen?.height ?? 0

        anchors.left: !Config.options.bar.vertical || (Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.right: Config.options.bar.vertical && Config.options.bar.bottom
        anchors.top: Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.bottom: !Config.options.bar.vertical && Config.options.bar.bottom

        implicitWidth: popupBackground.targetWidth + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin
        implicitHeight: popupBackground.targetHeight + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin

        mask: Region {
            item: popupBackground
        }

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        margins {
            left: {
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

            right: Appearance.sizes.verticalBarWidth
            bottom: Appearance.sizes.barHeight
        }

        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay

        HyprlandFocusGrab {
            id: dismissGrab
            windows: [popupWindow]
            active: false
            onCleared: () => {
                root._clickActive = false;
            }
        }

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
            if (!isBarVertical) return 0;
            return isBarBottom ? slideOffset : -slideOffset;
        }

        readonly property real slideY: {
            if (isBarVertical) return 0;
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
            PauseAnimation { duration: 50 }
            NumberAnimation {
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
            onTriggered: root._isClosing = false
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
            }
            function on_IsClosingChanged() {
                if (root._isClosing) {
                    openAnimSeq.stop();
                    closeAnim.from = popupWindow.animProgress;
                    closeAnim.start();
                } else {
                    closeAnim.stop();
                    destroyTimer.stop();
                    popupWindow.animProgress = 0.0;
                    openAnimSeq.start();
                }
            }
        }

        Component.onCompleted: {
            if (Config.options.bar.tooltips.clickToShow) {
                grabDelayTimer.start();
            }
            popupWindow.animProgress = 0.0;
            openAnimSeq.start();
        }

        Timer {
            id: grabDelayTimer
            interval: 250
            onTriggered: dismissGrab.active = true
        }

        Item {
            id: animContainer
            anchors.fill: parent
            opacity: popupWindow.animProgress

            transform: Translate {
                x: popupWindow.slideX * (1.0 - popupWindow.animProgress)
                y: popupWindow.slideY * (1.0 - popupWindow.animProgress)
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 128.0
                blur: (1.0 - popupWindow.animProgress) * 1.0
            }

            StyledRectangularShadow {
                target: popupBackground
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
                property bool _heightReady: false

                onTargetHeightChanged: {
                    _commitHeight = targetHeight;
                }

                Component.onCompleted: {
                    _commitHeight = targetHeight;
                    Qt.callLater(function () {
                        popupBackground._heightReady = true;
                    });
                }

                Behavior on _commitHeight {
                    enabled: popupBackground._heightReady
                    SmoothedAnimation {
                        duration: 200
                        easing: Easing.OutQuad
                    }
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
                    if (!root.animate || !root.contentItem || !heroItem || targetHeight <= heroHeight + margin * 2)
                        return _commitHeight;
                    return (heroHeight + margin * 2) + (_commitHeight - (heroHeight + margin * 2)) * popupWindow.animProgress;
                }

                color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer
                radius: root.popupRadius

                Item {
                    id: contentContainer
                    anchors.centerIn: parent
                    width: root.contentItem ? root.contentItem.implicitWidth : 0
                    height: root.contentItem ? root.contentItem.implicitHeight : 0

                    scale: root.layoutScale
                    transformOrigin: Item.Center
                    clip: false

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
                            if (!root || !root.contentItem) return;
                            
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
                            if (!root || !root.contentItem) return;
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
                                    } catch(e) {}
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

                border.width: 1
                border.color: Appearance.colors.colLayer0Border
            }
        }
    }
}
