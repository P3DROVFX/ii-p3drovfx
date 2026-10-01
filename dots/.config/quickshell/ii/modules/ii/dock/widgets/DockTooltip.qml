import QtQuick
import Quickshell
import Quickshell.Widgets
import qs
import qs.modules.common
import qs.modules.common.widgets

PopupWindow {
    id: rootToolTipPopup

    property Item parentItem: parent
    property string text: ""
    property bool showTooltip: false
    property int tooltipOffset: -12
    
    property string dockPosition: {
        const pos = Config.options?.dock?.position ?? "bottom"
        if (pos !== "auto") return pos
        return (Config.options?.bar?.bottom && !Config.options?.bar?.vertical) ? "top" : "bottom"
    }

    anchor.window: parentItem?.QsWindow?.window
    implicitWidth: tooltipRect.implicitWidth
    implicitHeight: tooltipRect.implicitHeight


    // mapToItem() walks the item's position in C++, which the QML binding
    // engine cannot observe: without these reads the anchor would be computed
    // once and then never follow the icon while the dock magnifies it.
    function trackedParentOffset() {
        if (!parentItem)
            return NaN
        return parentItem.x + parentItem.y + parentItem.width + parentItem.height + parentItem.scale
    }

    function anchorX() {
        if (!isFinite(rootToolTipPopup.trackedParentOffset()))
            return 0
        if (dockPosition === "left") {
            const mappedRight = parentItem.mapToItem(null, parentItem.width, 0)
            return mappedRight.x + 8
        }
        if (dockPosition === "right") {
            const mappedLeft = parentItem.mapToItem(null, 0, 0)
            return mappedLeft.x - rootToolTipPopup.width - 8
        }
        const mappedCenter = parentItem.mapToItem(null, parentItem.width / 2, 0)
        return mappedCenter.x - rootToolTipPopup.width / 2
    }

    function anchorY() {
        if (!isFinite(rootToolTipPopup.trackedParentOffset()))
            return 0
        if (dockPosition === "top") {
            const mappedBottom = parentItem.mapToItem(null, 0, parentItem.height)
            return mappedBottom.y + 8
        }
        if (dockPosition === "bottom") {
            const mappedTop = parentItem.mapToItem(null, 0, 0)
            return mappedTop.y - rootToolTipPopup.height - 8
        }
        const mappedCenter = parentItem.mapToItem(null, 0, parentItem.height / 2)
        return mappedCenter.y - rootToolTipPopup.height / 2
    }

    // A sweep across the dock flips `showTooltip` on every icon it crosses,
    // and each flip fades a native popup window in and out. The cost is not
    // one tooltip but N window animations per pass, competing with the
    // magnification on the same frames. A short dwell (70 ms) cuts that: a
    // fast pass flips nothing, a resting pointer waits out less than a blink.
    // Only the shown tooltip (and one still fading) pays mapToItem()/frame.
    property bool hoverDwellPassed: false
    onShowTooltipChanged: {
        if (showTooltip)
            dwellTimer.restart()
        else {
            dwellTimer.stop()
            hoverDwellPassed = false
        }
    }
    Timer {
        id: dwellTimer
        interval: 70
        onTriggered: rootToolTipPopup.hoverDwellPassed = true
    }
    readonly property bool tooltipShown: showTooltip && hoverDwellPassed
    readonly property bool anchoring: tooltipShown || visible

    anchor.rect.x: rootToolTipPopup.anchoring ? rootToolTipPopup.anchorX() : 0
    anchor.rect.y: rootToolTipPopup.anchoring ? rootToolTipPopup.anchorY() : 0

    visible: tooltipShown || tooltipRect.opacity > 0.01
    color: "transparent"

    Rectangle {
        id: tooltipRect
        implicitWidth: tooltipText.implicitWidth + 24
        implicitHeight: tooltipText.implicitHeight + 12
        opacity: rootToolTipPopup.tooltipShown ? 1.0 : 0.0
        scale: rootToolTipPopup.tooltipShown ? 1.0 : 0.8
        transformOrigin: {
            if (rootToolTipPopup.dockPosition === "top") return Item.Top
            if (rootToolTipPopup.dockPosition === "bottom") return Item.Bottom
            if (rootToolTipPopup.dockPosition === "left") return Item.Left
            if (rootToolTipPopup.dockPosition === "right") return Item.Right
            return Item.Bottom
        }

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(tooltipRect)
        }
        Behavior on scale {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(tooltipRect)
        }

        color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer
        radius: Appearance.rounding.small
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        StyledText {
            id: tooltipText
            anchors.centerIn: parent
            text: rootToolTipPopup.text
            color: Appearance.colors.colOnSurface
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }
}
