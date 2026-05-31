import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

LazyLoader {
    id: root
    property Item hoverTarget
    default property Item contentItem
    property real popupBackgroundMargin: 0
    property int popupRadius: Appearance.rounding.large
    property bool animate: true
    property bool animateHeight: true
    property bool stickyHover: false

    property bool isClickedOpen: false
    property bool _popupHovered: false
    property bool _stickyActive: false
    property bool _targetHovered: hoverTarget ? hoverTarget.containsMouse : false

    active: Config.options.bar.tooltips.clickToShow ? isClickedOpen : (stickyHover ? _stickyActive : (hoverTarget && hoverTarget.containsMouse))

    // I have NO FUCKING IDEA why we cant use a normal timer here
    // Because if we do, we FUCKING cannot reference the timer from anywhere
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
            if (_targetHovered) {
                isClickedOpen = !isClickedOpen;
            }
        } else {
            _evaluateStickyState();
        }
    }

    onActiveChanged: {
        if (!active) {
            _popupHovered = false;
            _timers.grace.stop();
            isClickedOpen = false;
        }
    }

    component: PanelWindow {
        id: popupWindow
        color: "transparent"

        Component.onCompleted: {
            if (Config.options.bar.tooltips.clickToShow) {
                GlobalFocusGrab.addDismissable(popupWindow);
            }
        }
        Component.onDestruction: {
            if (Config.options.bar.tooltips.clickToShow) {
                GlobalFocusGrab.removeDismissable(popupWindow);
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                if (Config.options.bar.tooltips.clickToShow) {
                    root.isClickedOpen = false;
                }
            }
        }

        readonly property real screenWidth: popupWindow.screen?.width ?? 0
        readonly property real screenHeight: popupWindow.screen?.height ?? 0

        // Max usable popup height: screen minus bar + elevation margins + small padding
        readonly property real maxPopupHeight: {
            const barSize = Config.options.bar.vertical
                ? 0
                : Appearance.sizes.barHeight;
            const avail = screenHeight - barSize - Appearance.sizes.elevationMargin * 2 - 16;
            return Math.max(120, avail);
        }

        anchors.left: !Config.options.bar.vertical || (Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.right: Config.options.bar.vertical && Config.options.bar.bottom
        anchors.top: Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.bottom: !Config.options.bar.vertical && Config.options.bar.bottom

        implicitWidth: popupBackground.targetWidth + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin
        implicitHeight: popupBackground.height + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin

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
                var stableHeight = (heroHeight > 0 ? heroHeight : 200) + Appearance.sizes.elevationMargin * 2;
                var centeredY = targetPos.y + (root.hoverTarget.height - stableHeight) / 2;
                var minY = 0;
                var maxY = screenHeight - popupWindow.implicitHeight;
                return Math.max(minY, Math.min(maxY, centeredY));
            }

            right: Appearance.sizes.verticalBarWidth
            bottom: Appearance.sizes.barHeight
        }

        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay

        StyledRectangularShadow {
            target: popupBackground
        }

        property real animProgress: 0.0
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

        NumberAnimation on animProgress {
            id: openAnim
            from: 0
            to: 1
            running: true
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }

        Rectangle {
            id: popupBackground
            readonly property real margin: 10

            readonly property real targetWidth: (root.contentItem?.implicitWidth ?? 0) + margin * 2
            readonly property real targetHeight: (root.contentItem?.implicitHeight ?? 0) + margin * 2

            property bool isVertical: Config.options.bar.vertical
            property bool isBottom: Config.options.bar.bottom
            property int elevation: Appearance.sizes.elevationMargin

            // Debounced height — no auto-binding to targetHeight.
            // Batches rapid layout changes before triggering smooth animation.
            property real _commitHeight: 0
            // Delayed enable to avoid opening animation transition glitch
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
                enabled: popupBackground._heightReady && root.animateHeight
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
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
                const maxH = popupWindow.maxPopupHeight + margin * 2;
                let h;
                if (!root.animate || !root.contentItem || !heroItem || targetHeight <= heroHeight + margin * 2)
                    h = _commitHeight;
                else
                    h = (heroHeight + margin * 2) + (_commitHeight - (heroHeight + margin * 2)) * popupWindow.animProgress;
                return Math.min(h, maxH);
            }

            color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer
            radius: root.popupRadius

            Flickable {
                id: contentContainer
                anchors.fill: parent
                anchors.margins: popupBackground.margin
                clip: true

                contentWidth: width
                contentHeight: root.contentItem?.implicitHeight ?? height
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                // Disable interaction and lock scroll position during open animation
                // to prevent trembling and scrollbar flash
                interactive: popupWindow.animProgress >= 1.0
                contentY: interactive ? contentY : 0

                ScrollBar.vertical: ScrollBar {
                    id: popupScrollBar
                    // Only show after animation completes AND content actually overflows
                    policy: popupWindow.animProgress >= 1.0 && contentContainer.contentHeight > contentContainer.height
                        ? ScrollBar.AlwaysOn
                        : ScrollBar.AlwaysOff
                    minimumSize: 0.1
                }

                Component.onCompleted: {
                    if (root.contentItem) {
                        // Parent to Flickable's contentItem but anchor width to
                        // contentContainer itself (not contentItem) to avoid
                        // circular binding with popupBackground.targetWidth
                        root.contentItem.parent = contentContainer.contentItem;
                        root.contentItem.anchors.centerIn = undefined;
                        root.contentItem.anchors.top = contentContainer.contentItem.top;
                        root.contentItem.anchors.left = contentContainer.contentItem.left;
                        root.contentItem.width = Qt.binding(() => contentContainer.width);

                        for (let i = 0; i < root.contentItem.children.length; i++) {
                            let child = root.contentItem.children[i];

                            child.opacity = Qt.binding(() => {
                                if (!root.animate)
                                    return 1.0;
                                let normalizedDelay = child.y / popupBackground.targetHeight;
                                let progress = (popupWindow.animProgress - normalizedDelay) / (1.0 - normalizedDelay);
                                return Math.max(0, Math.min(1.0, progress));
                            });

                            child.scale = Qt.binding(() => {
                                if (!root.animate)
                                    return 1.0;
                                let normalizedDelay = child.y / popupBackground.targetHeight;
                                let progress = (popupWindow.animProgress - normalizedDelay) / (1.0 - normalizedDelay);
                                return 0.85 + (0.15 * Math.max(0, Math.min(1.0, progress)));
                            });
                        }
                    }
                }
            }

            HoverHandler {
                id: popupHoverHandler
                onHoveredChanged: {
                    root._popupHovered = hovered;
                    if (!Config.options.bar.tooltips.clickToShow) {
                        root._evaluateStickyState();
                    }
                }
            }

            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
    }
}
