pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.akebono

// Bar-style shelf module pill. The bar renders its pills as plain rounded
// rectangles (BarGroupTheme: Appearance.rounding.full — a capsule while the
// shell rounding is on, sharp edges when the user sets rounding to 0). The
// shelf used squircles here, whose swept curve reads differently sitting right
// next to the bar's groups; a Rectangle keeps the exact same silhouette.
//
// Group pills: the shelf host wraps each module in the same neighbor-aware
// logic the bar uses (BarGroupTheme). Adjacent modules square off the side
// facing their neighbour (verysmall) and keep a full capsule on the outside
// edge. The host injects groupStartRadius/groupEndRadius/groupBgColor (exactly
// how BarComponent injects groupBgColor/groupStartRadius/groupEndRadius into
// bar widgets that draw their own chips) and groupHovered for whole-module
// hover feedback.
Rectangle {
    id: root

    readonly property real pillRadius: Appearance.rounding.full
    property real startRadius: root.pillRadius
    property real endRadius: root.pillRadius

    property var groupStartRadius
    property var groupEndRadius
    property var groupBgColor
    property bool groupHovered: false

    readonly property real startRadiusResolved: root.groupStartRadius !== undefined ? root.groupStartRadius : root.startRadius
    readonly property real endRadiusResolved: root.groupEndRadius !== undefined ? root.groupEndRadius : root.endRadius
    topLeftRadius: root.startRadiusResolved
    bottomLeftRadius: root.startRadiusResolved
    topRightRadius: root.endRadiusResolved
    bottomRightRadius: root.endRadiusResolved

    property bool hovered: false
    property color colorNormal: AkebonoAppearance.shelfPillColor
    property color colorHover: AkebonoAppearance.shelfPillHoverColor

    readonly property color colorResolved: root.groupBgColor !== undefined ? root.groupBgColor : root.colorNormal
    color: (root.hovered || root.groupHovered) ? root.colorHover : root.colorResolved
    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
}