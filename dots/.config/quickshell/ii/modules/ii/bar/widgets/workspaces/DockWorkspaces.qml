import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets

Item {
    id: root

    BarWidgetPalette {
        id: widgetPalette
        colorMode: Config.options.bar.workspaces.colorMode
    }

    Layout.fillHeight: !vertical
    Layout.fillWidth: vertical

    // ── Design tokens (matching DocktoPanel) ──────────────────────────────
    property real iconSize:     23
    property real btnSize:      28
    property real btnSpacing:   2
    property bool vertical:     false

    readonly property bool showAppIcons: Config.options.bar.workspaces.dockShowAppIcons
    readonly property bool useRandomShape: wsModel.useRandomShape

    WorkspaceBarModel {
        id: wsModel
        screen: root.QsWindow.window?.screen ?? null
        trackWindows: root.showAppIcons || Config.options.bar.workspaces.dockShowWindowDots
    }

    readonly property bool scratchpadOpen: wsModel.scratchpadOpen
    property real blur: root.scratchpadOpen ? 1 : 0
    readonly property int activeWsId: wsModel.activeId
    readonly property var noWindows: []

    function windowsOn(wsId) {
        return wsModel.windows[wsId] ?? root.noWindows;
    }

    // ── Active indicator computed position ───────────────────────────────
    readonly property int activeIndex: wsModel.activeIndex

    readonly property real flowX: root.vertical ? 0 : (pill.width - flow.implicitWidth) / 2
    readonly property real flowY: root.vertical ? (pill.height - flow.implicitHeight) / 2 : 0

    readonly property real indicatorPosX: root.vertical
        ? (pill.width - root.btnSize) / 2
        : root.flowX + root.activeIndex * (root.btnSize + root.btnSpacing)
    readonly property real indicatorPosY: root.vertical
        ? root.flowY + root.activeIndex * (root.btnSize + root.btnSpacing)
        : (pill.height - root.btnSize) / 2

    // ── Implicit size (DocktoPanel style) ─────────────────────────────────
    implicitWidth:  vertical ? root.btnSize : pill.implicitWidth
    implicitHeight: vertical ? pill.implicitHeight : root.btnSize

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    Behavior on blur {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // ── Blur + dim wrapper (dimmed/blurred as a whole when scratchpad is open) ──
    Item {
        id: contentContainer
        anchors.fill: parent
        z: 0
        opacity: root.scratchpadOpen ? 0.65 : 1
        layer.enabled: root.blur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            blur: root.blur
        }

        // ── Container pill (transparent, like DocktoPanel) ────────────────
        Rectangle {
            id: pill
            anchors.centerIn: parent
            color: "transparent"
            radius: Appearance.rounding.full

            implicitWidth:  flow.implicitWidth + (root.vertical ? 0 : 4)
            implicitHeight: flow.implicitHeight + (root.vertical ? 4 : 0)

            Behavior on implicitWidth {
                animation: Appearance.animation.barResize.numberAnimation.createObject(this)
            }
            Behavior on implicitHeight {
                animation: Appearance.animation.barResize.numberAnimation.createObject(this)
            }

            // ── Active workspace indicator ───────────────────────────────
            Loader {
                id: activeIndicatorLoader
                x: root.indicatorPosX
                y: root.indicatorPosY
                width: root.btnSize
                height: root.btnSize
                visible: Config.options.bar.workspaces.dockShowActiveIndicator && root.activeIndex >= 0
                active: Config.options.bar.workspaces.dockShowActiveIndicator && root.activeIndex >= 0

                Behavior on x {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on y {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                sourceComponent: (Config.options.bar.workspaces.useMaterialShapeForActiveIndicator || root.useRandomShape)
                    ? materialShapeComp : rectangleComp

                Component {
                    id: rectangleComp
                    Rectangle {
                        radius: Appearance.rounding.full
                        color: widgetPalette.colBackground
                        opacity: Config.options.bar.workspaces.activeIndicatorOpacity / 100
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }

                Component {
                    id: materialShapeComp
                    MaterialShape {
                        anchors.fill: parent
                        transformOrigin: Item.Center
                        shapeString: root.useRandomShape
                            ? wsModel.randomShape
                            : Config.options.bar.workspaces.activeIndicatorShape
                        color: widgetPalette.colBackground
                        opacity: Config.options.bar.workspaces.activeIndicatorOpacity / 100
                        rotation: root.useRandomShape ? wsModel.randomRotation : 0
                        Behavior on rotation {
                            RotationAnimation {
                                duration: 350
                                direction: RotationAnimation.Clockwise
                                easing.type: Easing.OutBack
                            }
                        }
                    }
                }
            }

            Flow {
                id: flow
                anchors.centerIn: parent
                flow:    root.vertical ? Flow.TopToBottom : Flow.LeftToRight
                spacing: root.btnSpacing

                Repeater {
                    id: repeater
                    model: wsModel.visibleIds

                    delegate: Item {
                        id: wsItem
                        required property int index
                        required property var modelData

                        readonly property int wsId: modelData
                        readonly property bool isActive: wsId === root.activeWsId
                        readonly property bool isOccupied: wsModel.occupied[wsId] === true
                        readonly property var wsWindows: root.windowsOn(wsId)
                        readonly property string icon: root.showAppIcons && wsWindows.length > 0 ? wsWindows[0].icon : ""

                        width:  root.btnSize
                        height: root.btnSize

                        // ── Hover effect (scale) ─────────────────────────────
                        readonly property real baseScale: Config.options.bar.workspaces.dockHoverEffect
                            ? (wsItem.isActive ? 1.0 : 0.9)
                            : 1.0

                        scale: wsItem.baseScale * (Config.options.bar.workspaces.dockHoverEffect && wsButton.hovered && !wsItem.isActive ? 1.08 : 1.0)
                        Behavior on scale {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }

                        // ── Scratchpad dimming ──────────────────────────────
                        opacity: root.scratchpadOpen && !wsItem.isActive ? 0.35 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 110 } }

                        RippleButton {
                            id: wsButton
                            anchors.fill: parent
                            buttonRadius: Appearance.rounding.small
                            hoverEnabled: true

                            onClicked: wsModel.focus(wsItem.wsId)

                            contentItem: Item {
                                anchors.centerIn: parent

                                // ── Icon wrapper (for shape mask) ──────────
                                Item {
                                    id: iconWrapper
                                    anchors.centerIn: parent
                                    width: root.iconSize
                                    height: root.iconSize

                                    // ── Workspace icon (first window) ──────
                                    IconImage {
                                        id: wsIcon
                                        anchors.centerIn: parent
                                        source: wsItem.icon
                                        implicitSize: root.iconSize
                                        visible: wsItem.icon !== ""

                                        // Force reload when the icon theme regenerates. Resolved on this
                                        // thread: the shared icon loader is not safe to read from Qt's
                                        // image thread while the theme is changing under it.
                                        asynchronous: false
                                        backer.cache: false
                                        backer.sourceSize: Qt.size(root.iconSize + TaskbarApps.iconThemeRevision,
                                                                   root.iconSize + TaskbarApps.iconThemeRevision)
                                    }

                                    // ── Monochrome tint (DocktoPanel pattern) ──
                                    Loader {
                                        active: Config.options.bar.workspaces.monochromeIcons && wsItem.icon !== ""
                                        anchors.fill: wsIcon
                                        sourceComponent: Item {
                                            Desaturate {
                                                id: desat
                                                visible: false
                                                anchors.fill: parent
                                                source: wsIcon
                                                desaturation: 0.8
                                            }
                                            ColorOverlay {
                                                anchors.fill: desat
                                                source: desat
                                                color: ColorUtils.transparentize(
                                                    widgetPalette.colBackground,
                                                    1.0 - (Config.options.appearance.iconTintPercentage ?? 0.6)
                                                )
                                            }
                                        }
                                    }

                                    // ── Shape mask for icons ───────────────
                                    layer.enabled: Config.options.appearance.icons.enableShapeMask && wsItem.icon !== ""
                                    layer.effect: OpacityMask {
                                        maskSource: MaterialShape {
                                            anchors.fill: parent
                                            shapeString: Config.options.appearance.icons.shapeMask
                                            visible: false
                                        }
                                    }
                                }

                                // ── Fallback dot for empty workspaces ────────
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: wsItem.icon === "" ? (wsItem.isActive ? 7 : 5) : 0
                                    height: width
                                    radius: width / 2
                                    color: {
                                        if (wsItem.isActive)
                                            return widgetPalette.colOnBackground;
                                        if (wsItem.isOccupied)
                                            return widgetPalette.colOnContainer;
                                        return ColorUtils.transparentize(widgetPalette.colOnContainer, 0.45);
                                    }
                                    visible: wsItem.icon === ""

                                    Behavior on width {
                                        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                                    }
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 150
                                        }
                                    }
                                }

                                // ── Window count dots ─────────────────────────
                                Flow {
                                    id: windowDotsFlow
                                    visible: Config.options.bar.workspaces.dockShowWindowDots
                                    flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
                                    spacing: 2
                                    anchors {
                                        left:   root.vertical ? iconWrapper.right    : undefined
                                        top:    root.vertical ? undefined            : iconWrapper.bottom
                                        leftMargin:  root.vertical ? 1  : 0
                                        topMargin:   root.vertical ? 0  : 1
                                        horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                                        verticalCenter:   root.vertical ? parent.verticalCenter : undefined
                                    }

                                    Repeater {
                                        model: wsItem.wsWindows.length

                                        delegate: Rectangle {
                                            required property int index
                                            radius: Appearance.rounding.full
                                            implicitWidth:  root.vertical
                                                ? 2
                                                : wsItem.wsWindows.length <= 3 ? 4 : 2
                                            implicitHeight: root.vertical
                                                ? (wsItem.wsWindows.length <= 3 ? 4 : 2)
                                                : 2
                                            color: wsItem.isActive
                                                ? widgetPalette.colBackground
                                                : widgetPalette.colContainer
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } // pill

        // Position helper (invisible, inside blur container)
        Item {
            id: positionHelper
            readonly property Item activeItem: root.activeIndex >= 0 ? repeater.itemAt(root.activeIndex) : null

            x: activeItem ? activeItem.x + flow.x + pill.x : 0
            y: activeItem ? activeItem.y + flow.y + pill.y : 0
            width: activeItem ? activeItem.width : root.btnSize
            height: activeItem ? activeItem.height : root.btnSize
            visible: false
        }

    } // contentContainer

    // Active workspace overlay (above blur, same position, kept sharp)
    Item {
        id: activeOverlay
        z: 10

        x: positionHelper.x
        y: positionHelper.y
        width: positionHelper.width
        height: positionHelper.height

        readonly property bool _show: root.scratchpadOpen && positionHelper.activeItem !== null
        readonly property var _activeWsWindows: root.windowsOn(root.activeWsId)
        readonly property string _activeIcon: root.showAppIcons && _activeWsWindows.length > 0 ? _activeWsWindows[0].icon : ""

        visible: _show
        opacity: _show ? 1.0 : 0.0
        scale: _show ? 1.1 : 1.0
        transformOrigin: Item.Center

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Item {
            id: overlayIconWrapper
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize

            IconImage {
                id: overlayIcon
                anchors.centerIn: parent
                source: activeOverlay._activeIcon
                implicitSize: root.iconSize
                visible: activeOverlay._activeIcon !== ""

                // Force reload when the icon theme regenerates. Resolved on this thread: the
                // shared icon loader is not safe to read from Qt's image thread while the
                // theme is changing under it.
                asynchronous: false
                backer.cache: false
                backer.sourceSize: Qt.size(root.iconSize + TaskbarApps.iconThemeRevision,
                                           root.iconSize + TaskbarApps.iconThemeRevision)

                layer.enabled: Config.options.appearance.icons.enableShapeMask
                layer.effect: OpacityMask {
                    maskSource: overlayIconMask
                }
            }

            MaterialShape {
                id: overlayIconMask
                anchors.fill: overlayIcon
                shapeString: Config.options.appearance.icons.shapeMask
                visible: false
            }

            Rectangle {
                anchors.centerIn: parent
                width: activeOverlay._activeIcon === "" ? 7 : 0
                height: width
                radius: width / 2
                color: widgetPalette.colBackground
                visible: activeOverlay._activeIcon === ""
            }
        }
    }

    // ── Root MouseArea for right-click, back, scroll (NOT left-click) ────
    // Left-click is handled per-slot by RippleButton above.
    MouseArea {
        anchors.fill: parent
        z: 4
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        acceptedButtons: Qt.RightButton | Qt.BackButton

        onPressed: event => {
            if (event.button === Qt.RightButton)
                GlobalStates.toggleOverview();
            else if (event.button === Qt.BackButton)
                wsModel.toggleScratchpad();
        }

        onWheel: wheel => {
            wheel.accepted = true;
            wsModel.scroll(wheel.angleDelta.y);
        }
    }
}
