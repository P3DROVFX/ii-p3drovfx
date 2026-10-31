import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions

// The running-windows indicator, shared by the dock and the desktop icons so
// both follow the same dock.runningIndicator* options.
Item {
    id: indicatorContainer

    property var toplevels: []
    // Activation alone is not enough: Hyprland leaves it set on a window sent
    // to another workspace with a silent move. The dock passes its own index.
    property int focusedIndex: {
        const list = indicatorContainer.toplevels ?? [];
        for (let i = 0; i < list.length; i++) {
            if (list[i]?.activated && HyprlandData.toplevelOnScreen(list[i]))
                return i;
        }
        return -1;
    }
    // Which side of the parent the dots sit on: top, bottom, left or right.
    property string edge: "bottom"
    readonly property bool isVertical: edge === "left" || edge === "right"
    // Room along the icon's edge: a pill shortens to fit its row there before
    // it would ever overhang the slot.
    property real edgeExtent: 48
    // Configured sizes are for a 56 px dock; applied only with scaling on.
    property real scaleFactor: 1
    property real margin: 1

    // enableShapeMask used to hide this indicator with nothing drawing running
    // state in its place, so a running app and an idle one looked identical.
    // The parent fork shows it either way.
    visible: totalCount > 0

    readonly property int totalCount: toplevels ? toplevels.length : 0
    readonly property string indicatorStyle: Config.options?.dock?.runningIndicatorStyle ?? "dot"
    readonly property int maxVisible: Math.max(1, Config.options?.dock?.runningIndicatorMaxVisible ?? 5)
    readonly property int visibleCount: Math.min(totalCount, maxVisible)
    readonly property bool neutralColor: Config.options?.dock?.runningIndicatorNeutralColor ?? false

    readonly property real sizeScale: (Config.options?.dock?.runningIndicatorScaleWithDock ?? true) ? scaleFactor : 1
    readonly property real thickness: Math.max(2, Math.round((Config.options?.dock?.runningIndicatorThickness ?? 3) * sizeScale))
    // Never shorter than it is thick, so a pill can't stand on its side.
    readonly property real pillLength: Math.max(thickness, Math.round((Config.options?.dock?.runningIndicatorLength ?? 10) * sizeScale))

    readonly property real dotSpacing: Math.max(2, Math.round(thickness * 0.75))
    readonly property bool pillMode: indicatorStyle === "pill" && totalCount <= maxVisible
    // Length runs along the icon's edge: horizontal on a top/bottom edge,
    // vertical on a left/right one.
    readonly property real dotLength: {
        if (!pillMode || visibleCount < 1)
            return thickness;
        const fit = (edgeExtent - (visibleCount - 1) * dotSpacing) / visibleCount;
        return Math.max(thickness, Math.min(pillLength, Math.floor(fit)));
    }
    readonly property real baseDotW: isVertical ? thickness : dotLength
    readonly property real baseDotH: isVertical ? dotLength : thickness

    readonly property real pitchX: isVertical ? 0 : (baseDotW + dotSpacing)
    readonly property real pitchY: isVertical ? (baseDotH + dotSpacing) : 0

    // Past the slot count the row is a window onto the windows, centred on
    // the focused one, with the edge dots shrunk to say there are more.
    readonly property int windowStart: {
        if (totalCount <= maxVisible)
            return 0;
        const centeredStart = focusedIndex - Math.floor(maxVisible / 2);
        return Math.max(0, Math.min(totalCount - maxVisible, centeredStart));
    }
    readonly property bool hasHiddenStart: windowStart > 0
    readonly property bool hasHiddenEnd: (windowStart + visibleCount) < totalCount

    width: isVertical ? baseDotW : (visibleCount * baseDotW + Math.max(0, visibleCount - 1) * dotSpacing)
    height: isVertical ? (visibleCount * baseDotH + Math.max(0, visibleCount - 1) * dotSpacing) : baseDotH

    // Conditional anchors are evaluated one by one, so an orientation flip
    // overlaps opposite edges, over-constrains the group and permanently
    // removes the width/height bindings. AnchorChanges swaps the whole group
    // atomically.
    state: edge
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

    anchors.bottomMargin: margin
    anchors.topMargin: margin
    anchors.leftMargin: margin
    anchors.rightMargin: margin

    Repeater {
        model: indicatorContainer.visibleCount
        delegate: Rectangle {
            readonly property int absoluteIndex: indicatorContainer.windowStart + index
            readonly property bool isFocused: indicatorContainer.focusedIndex >= 0
                && absoluteIndex === indicatorContainer.focusedIndex
            readonly property bool isOverflowHint:
                (index === 0 && indicatorContainer.hasHiddenStart) ||
                (index === indicatorContainer.visibleCount - 1 && indicatorContainer.hasHiddenEnd)
            readonly property real shrinkFactor: (isOverflowHint && !isFocused) ? 0.72 : 1.0

            width: indicatorContainer.baseDotW * shrinkFactor
            height: indicatorContainer.baseDotH * shrinkFactor
            radius: Appearance.rounding.full

            x: index * indicatorContainer.pitchX + (indicatorContainer.baseDotW - width) / 2
            y: index * indicatorContainer.pitchY + (indicatorContainer.baseDotH - height) / 2

            color: !isFocused
                ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                : (indicatorContainer.neutralColor ? Appearance.colors.colOnLayer0 : Appearance.colors.colPrimary)
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
