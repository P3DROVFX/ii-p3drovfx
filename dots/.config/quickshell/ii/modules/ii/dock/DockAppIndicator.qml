import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: indicatorContainer
    readonly property bool isAdaptiveMode: Config.options?.dock?.enableShapeMask ?? false

    visible: root.appIsRunning && !isAdaptiveMode

    readonly property int totalCount: root.appToplevel ? root.appToplevel.toplevels.length : 0
    readonly property int maxVisibleDots: 5
    readonly property int visibleCount: Math.min(totalCount, maxVisibleDots)
    readonly property int focusedIndex: root.focusedWindowIndex

    readonly property real countDotHeight: Math.max(3, Math.round(root.dockHeight * 0.06))
    readonly property real baseDotW: countDotHeight
    readonly property real baseDotH: countDotHeight

    readonly property real dotSpacing: 3
    readonly property real pitchX: root.isVertical ? 0 : (baseDotW + dotSpacing)
    readonly property real pitchY: root.isVertical ? (baseDotH + dotSpacing) : 0
    readonly property real indicatorMargin: Math.max(1, (root.dockContent?.dotMarginV ?? 1) * 0.35)

    readonly property int windowStart: {
        if (totalCount <= maxVisibleDots) return 0
        const centeredStart = focusedIndex - Math.floor(maxVisibleDots / 2)
        const maxStart = totalCount - maxVisibleDots
        return Math.max(0, Math.min(maxStart, centeredStart))
    }
    readonly property bool hasHiddenLeft: windowStart > 0
    readonly property bool hasHiddenRight: (windowStart + visibleCount) < totalCount

    width: root.isVertical ? baseDotW : (visibleCount * baseDotW + Math.max(0, visibleCount - 1) * dotSpacing)
    height: root.isVertical ? (visibleCount * baseDotH + Math.max(0, visibleCount - 1) * dotSpacing) : baseDotH

    // Keep indicators on the screen-edge side of the icon in every orientation.
    // Same class of bug as the dock tray: conditional anchors are evaluated
    // one by one, so an orientation flip overlaps opposite edges, over-
    // constrains the group and permanently removes the width/height bindings.
    // AnchorChanges swaps the whole group atomically.
    state: root.dockPos
    states: [
        State {
            name: "top"
            AnchorChanges { target: indicatorContainer; anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter }
        },
        State {
            name: "bottom"
            AnchorChanges { target: indicatorContainer; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter }
        },
        State {
            name: "left"
            AnchorChanges { target: indicatorContainer; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
        },
        State {
            name: "right"
            AnchorChanges { target: indicatorContainer; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
        }
    ]

    anchors.bottomMargin: indicatorMargin
    anchors.topMargin: indicatorMargin
    anchors.leftMargin: indicatorMargin
    anchors.rightMargin: indicatorMargin

    Repeater {
        model: indicatorContainer.visibleCount
        delegate: Rectangle {
            id: dotRect

            readonly property int absoluteIndex: indicatorContainer.windowStart + index
            readonly property bool isFocused: absoluteIndex === indicatorContainer.focusedIndex

            readonly property bool isOverflowHint:
                (index === 0 && indicatorContainer.hasHiddenLeft) ||
                (index === indicatorContainer.visibleCount - 1 && indicatorContainer.hasHiddenRight)

            readonly property real shrinkFactor: (isOverflowHint && !isFocused) ? 0.72 : 1.0

            width: indicatorContainer.baseDotW * shrinkFactor
            height: indicatorContainer.baseDotH * shrinkFactor

            radius: Appearance.rounding.full

            x: root.isVertical ? (indicatorContainer.baseDotW - width) / 2 : (index * indicatorContainer.pitchX + (indicatorContainer.baseDotW - width) / 2)
            y: root.isVertical ? (index * indicatorContainer.pitchY + (indicatorContainer.baseDotH - height) / 2) : (indicatorContainer.baseDotH - height) / 2

            color: (isFocused && indicatorContainer.focusedIndex >= 0) ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)

            opacity: (isOverflowHint && !isFocused) ? 0.55 : 1.0

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on width {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on height {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
        }
    }
}
