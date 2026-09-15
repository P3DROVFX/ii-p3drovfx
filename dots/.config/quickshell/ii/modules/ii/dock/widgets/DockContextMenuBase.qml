import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

// a base file for context menu that holds the common logic like functions and preadded things..

Loader {
    id: root

    property Item anchorItem: parent
    property bool isClosing: false
    property string headerText: ""
    property string headerSymbol: ""
    property Component headerIcon: null
    property bool showHeader: true
    property bool useDockSlideAnimation: false
    property bool pointerInsidePopup: false
    property bool symmetricContentMargins: false
    
    readonly property string dockPos: dock.dockEffectivePosition

    signal closed()

    function open() {
        if (active && !isClosing) return
        isClosing = false
        active = true
        if (root.item) root.item.startOpenAnimation()
    }

    function close() {
        if (!active || isClosing) return
        isClosing = true
        if (root.item) root.item.startCloseAnimation()
    }

    onActiveChanged: {
        if (!root.active) root.closed()
    }

    active: false
    visible: active

    sourceComponent: PopupWindow {
        id: popupWindow
        visible: true
        color: "transparent"

        property real dockMargin: -16
        property real shadowMargin: 20
        readonly property real slideDistance: Math.max(Appearance.sizes.elevationMargin * 3, Appearance.sizes.dockButtonSize * 0.35)
        readonly property real slideOffsetX: root.useDockSlideAnimation
            ? (root.dockPos === "left" ? -slideDistance : (root.dockPos === "right" ? slideDistance : 0))
            : 0
        readonly property real slideOffsetY: root.useDockSlideAnimation
            ? (root.dockPos === "top" ? -slideDistance : (root.dockPos === "bottom" ? slideDistance : 0))
            : 0
        property real slideX: slideOffsetX
        property real slideY: slideOffsetY

        function requestAnchorUpdate() {
            if (!root.active || root.isClosing || !root.anchorItem || !popupWindow.anchor.window)
                return
            anchorUpdateTimer.restart()
        }

        Timer {
            id: anchorUpdateTimer
            interval: 0
            repeat: false
            onTriggered: {
                if (root.active && !root.isClosing && root.anchorItem && popupWindow.anchor.window)
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
        }

        implicitWidth: menuContent.implicitWidth + popupWindow.shadowMargin * 2
        implicitHeight: menuContent.implicitHeight + popupWindow.shadowMargin * 2

        function startOpenAnimation() {
            if (root.useDockSlideAnimation) {
                menuContent.scale = 1.0
                menuContent.opacity = 0.0
                popupWindow.slideX = popupWindow.slideOffsetX
                popupWindow.slideY = popupWindow.slideOffsetY
                Qt.callLater(function () {
                    menuContent.opacity = 1.0
                    popupWindow.slideX = 0
                    popupWindow.slideY = 0
                })
                return
            }

            menuContent.scale = 1.0
            menuContent.opacity = 1.0
        }

        function startCloseAnimation() {
            if (root.useDockSlideAnimation) {
                menuContent.opacity = 0.0
                popupWindow.slideX = popupWindow.slideOffsetX
                popupWindow.slideY = popupWindow.slideOffsetY
                return
            }

            menuContent.scale = 0.8
            menuContent.opacity = 0.0
        }

        Behavior on slideX {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
        }

        Behavior on slideY {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
        }

        HyprlandFocusGrab {
            active: root.active && !root.isClosing
            windows: [popupWindow]
            onCleared: root.close()
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
            color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal

            implicitWidth: menuColumn.implicitWidth + (headerRow.Layout.leftMargin * 2) + (menuMargin * 2)
            implicitHeight: menuColumn.implicitHeight + (root.showHeader ? headerRow.Layout.topMargin : 0) + menuMargin * 2

            opacity: 0.0
            scale: 0.8
            transformOrigin: Item.Center

            transform: Translate {
                x: popupWindow.slideX
                y: popupWindow.slideY
            }

            Component.onCompleted: startOpenAnimation()

            HoverHandler {
                onHoveredChanged: root.pointerInsidePopup = hovered
            }

            Behavior on opacity {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            Behavior on scale {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            onOpacityChanged: {
                if (opacity === 0.0 && root.isClosing) {
                    root.active = false
                    root.isClosing = false
                }
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
                    Layout.fillWidth: true
                    sourceComponent: root.contentComponent
                }
            }
        }
    }

    property Component contentComponent: null
}
