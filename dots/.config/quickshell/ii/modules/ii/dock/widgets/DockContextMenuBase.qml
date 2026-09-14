import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

// Shared popup lifetime and motion for menus, app groups and file stacks.

Loader {
    id: root

    property Item anchorItem: parent
    property bool isClosing: false
    property string headerText: ""
    property string headerSymbol: ""
    property Component headerIcon: null
    property bool showHeader: true
    property bool useDockSlideAnimation: true
    property bool pointerInsidePopup: false
    property bool symmetricContentMargins: false
    
    property string dockPos: root.anchorItem?.dockContent?.dockPos ?? (typeof dock !== "undefined" ? dock.dockEffectivePosition : "bottom")
    property real motionMargin: 0
    property color surfaceColor: Appearance.colors.colLayer0
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
        readonly property real slideDistance: Math.max(Appearance.sizes.elevationMargin * 3, Appearance.sizes.dockButtonSize * 0.35)
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
                const item = root.anchorItem
                if (!item) return
                const pos = root.dockPos
                const scale = item.scale ?? 1.0
                const mapped = item.mapToItem(null, item.width / 2, item.height / 2)
                const dm = popupWindow.dockMargin
                const itemHalfH = (item.height * scale) / 2
                const itemHalfW = (item.width * scale) / 2

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
            target: root.anchorItem
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

        StyledRectangularShadow {
            target: menuContent
            opacity: menuContent.opacity
            visible: menuContent.visible
        }

        Rectangle {
            id: menuContent
            property real menuMargin: 8
            anchors.centerIn: parent
            color: root.surfaceColor
            radius: Appearance.rounding.normal

            implicitWidth: menuColumn.implicitWidth + (headerRow.Layout.leftMargin * 2) + (menuMargin * 2)
            implicitHeight: menuColumn.implicitHeight + (root.showHeader ? headerRow.Layout.topMargin : 0) + menuMargin * 2

            Behavior on implicitHeight {
                enabled: root.popupProgress === 1 && !root.isClosing
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            opacity: root.popupProgress
            enabled: !root.isClosing
            transform: Translate {
                x: popupWindow.slideOffsetX * (1 - root.popupProgress)
                y: popupWindow.slideOffsetY * (1 - root.popupProgress)
            }
            // Allocate blur only during the transition, with a fixed kernel.
            // Changing blurMax per frame would keep rebuilding the shader.
            layer.enabled: root.popupProgress > 0 && root.popupProgress < 1
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 12
                blur: 1 - root.popupProgress
            }

            HoverHandler {
                onHoveredChanged: root.pointerInsidePopup = hovered
            }

            ColumnLayout {
                id: menuColumn
                anchors.fill: parent
                anchors.leftMargin: menuContent.menuMargin
                anchors.rightMargin: menuContent.menuMargin
                anchors.topMargin: root.symmetricContentMargins
                    ? menuContent.menuMargin
                    : menuContent.menuMargin / 2
                anchors.bottomMargin: menuContent.menuMargin
                spacing: 0

                Item {
                    id: headerRow
                    visible: root.showHeader
                    Layout.fillWidth: true
                    Layout.topMargin: menuContent.menuMargin
                    Layout.bottomMargin: menuContent.menuMargin
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2
                    implicitHeight: headerRowLayout.implicitHeight
                    implicitWidth: headerRowLayout.implicitWidth

                    RowLayout {
                        id: headerRowLayout
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Loader {
                            active: !!root.headerIcon || root.headerSymbol !== ""
                            sourceComponent: root.headerIcon ? root.headerIcon : symbolComp
                        }

                        Component {
                            id: symbolComp
                            MaterialSymbol {
                                text: root.headerSymbol
                                iconSize: 22
                                color: Appearance.colors.colOnLayer0
                            }
                        }

                        StyledText {
                            text: root.headerText
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer0
                            font.weight: Font.DemiBold
                            elide: Text.ElideMiddle
                            Layout.maximumWidth: 200
                        }
                    }
                }

                Rectangle {
                    visible: root.showHeader
                    Layout.fillWidth: true
                    Layout.bottomMargin: menuContent.menuMargin
                    implicitHeight: 1
                    color: Appearance.colors.colLayer0Border
                }

                // Placeholder for content
                Loader {
                    id: contentLoader
                    readonly property var _dockPopup: root
                    Layout.fillWidth: true
                    sourceComponent: root.contentComponent
                }
            }
        }
    }

    property Component contentComponent: null
}
