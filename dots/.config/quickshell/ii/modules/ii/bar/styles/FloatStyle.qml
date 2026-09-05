pragma ComponentBehavior: Bound
import qs.modules.ii.bar.shared
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// cornerStyle === 1 — margin + border + shadow + rounding
Item {
    id: root

    property bool showBarBackground
    property var  activeTheme
    property var  leftList
    property var  centerList
    property var  rightList

    property color actualColor: root.showBarBackground
        ? (Config.options.bar.expressiveColors
            ? root.activeTheme.barBackground
            : Appearance.colors.colLayer0)
        : "transparent"

    Behavior on actualColor {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(root)
    }

    readonly property bool isIslandMode: Config.options.bar.barBackgroundStyle === 3

    Rectangle {
        id: barBackground
        anchors {
            top: parent.top; bottom: parent.bottom
            left: parent.left; right: parent.right
            margins: Appearance.sizes.hyprlandGapsOut
        }

        color: root.isIslandMode ? "transparent" : root.actualColor

        radius: Appearance.rounding.full

        Behavior on radius { NumberAnimation { duration: 450; easing.type: Easing.OutExpo } }

        layer.enabled: !root.isIslandMode && Config.options.bar.dropShadow && !ShellModePolicy.barDropShadowBlocked
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.28)
            shadowVerticalOffset: BarPlacement.bottom ? -4 : 4
            shadowBlur: 1.0
        }
    }

    // ── Islands (barBackgroundStyle === 3) ────────────────────────────────────
    property color islandFillColor: Config.options.bar.expressiveColors
        ? root.activeTheme.barBackground
        : Appearance.colors.colLayer0

    // The islands pad themselves by exactly the inset the full-width bar uses
    // for its own content. That is not a coincidence to be written as a literal:
    // `barBackground` sits `hyprlandGapsOut` inside the bar and the sections sit
    // `hyprlandGapsOut` inside *that*, so an island anchored to a section and
    // grown by the same number lands its outer edge precisely where the
    // full-width pill's edge is, with the same gap to the last widget. A
    // hardcoded 6 put both one pixel out — the bar visibly changed its side
    // margins when you switched background style, which is the one thing
    // switching background style should not do.
    Rectangle {
        id: leftIsland
        visible: root.isIslandMode && (Config.options.bar.layouts.left || []).length > 0
        anchors {
            left: leftSection.left; leftMargin: -Appearance.sizes.hyprlandGapsOut
            right: leftSection.right; rightMargin: -Appearance.sizes.hyprlandGapsOut
            top: barBackground.top; bottom: barBackground.bottom
        }
        color: root.islandFillColor
        radius: Appearance.rounding.full

        layer.enabled: root.isIslandMode && Config.options.bar.dropShadow && !ShellModePolicy.barDropShadowBlocked
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.28)
            shadowVerticalOffset: BarPlacement.bottom ? -4 : 4
            shadowBlur: 1.0
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(leftIsland)
        }
    }

    Rectangle {
        id: middleIsland
        visible: root.isIslandMode && (root.leftList.length > 0 || root.centerList.length > 0 || root.rightList.length > 0)
        anchors {
            left: middleSection.left; leftMargin: -Appearance.sizes.hyprlandGapsOut
            right: middleSection.right; rightMargin: -Appearance.sizes.hyprlandGapsOut
            top: barBackground.top; bottom: barBackground.bottom
        }
        color: root.islandFillColor
        radius: Appearance.rounding.full

        layer.enabled: root.isIslandMode && Config.options.bar.dropShadow && !ShellModePolicy.barDropShadowBlocked
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.28)
            shadowVerticalOffset: BarPlacement.bottom ? -4 : 4
            shadowBlur: 1.0
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(middleIsland)
        }
    }

    Rectangle {
        id: rightIsland
        visible: root.isIslandMode && (Config.options.bar.layouts.right || []).length > 0
        anchors {
            left: rightSection.left; leftMargin: -Appearance.sizes.hyprlandGapsOut
            right: rightSection.right; rightMargin: -Appearance.sizes.hyprlandGapsOut
            top: barBackground.top; bottom: barBackground.bottom
        }
        color: root.islandFillColor
        radius: Appearance.rounding.full

        layer.enabled: root.isIslandMode && Config.options.bar.dropShadow && !ShellModePolicy.barDropShadowBlocked
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.28)
            shadowVerticalOffset: BarPlacement.bottom ? -4 : 4
            shadowBlur: 1.0
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(rightIsland)
        }
    }

    RowLayout {
        id: leftSection
        anchors {
            top: barBackground.top
            bottom: barBackground.bottom
            left: barBackground.left
            leftMargin: Appearance.sizes.hyprlandGapsOut
        }
        spacing: 4
        Repeater {
            id: leftRepeater
            model: Config.options.bar.layouts.left
            delegate: BarComponent {
                list: leftRepeater.model
                barSection: 0
            }
        }
    }

    Item {
        id: middleSection
        anchors { top: barBackground.top; bottom: barBackground.bottom; horizontalCenter: barBackground.horizontalCenter }
        // `centerCenter` is centred in here and the two side rows hang off it
        // with a 4px margin, so the box has to be symmetric around the centre:
        // whichever side is wider decides the slack, and both fit.
        //
        // The old form was `middleLeft + centerCenter + middleRight + 8`, which
        // charged for those two margins even when the rows they belong to were
        // empty. In `island` background style that is *always* — BarLayout
        // forces `centerIdx` to -1 there, so every centre widget lands in
        // `centerList` and the side rows are zero-wide. The island wraps this
        // box, so the phantom 4px on each side became visible padding inside
        // the pill; in every other background style the bar's own full-width
        // surface hid it, which is why the margins only looked wrong here.
        readonly property real sideSlack: Math.max(
            middleLeft.width > 0 ? middleLeft.width + 4 : 0,
            middleRight.width > 0 ? middleRight.width + 4 : 0)
        width: centerCenter.width + middleSection.sideSlack * 2

        RowLayout {
            id: middleLeft
            anchors { top: parent.top; bottom: parent.bottom; right: centerCenter.left; rightMargin: 4 }
            Repeater {
                model: root.leftList
                delegate: BarComponent {
                    growthEdge: "trailing"
                    list: Config.options.bar.layouts.center; barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                }
            }
        }
        RowLayout {
            id: centerCenter
            anchors.centerIn: parent
            Repeater {
                model: root.centerList
                delegate: BarComponent {
                    list: Config.options.bar.layouts.center; barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                }
            }
        }
        RowLayout {
            id: middleRight
            anchors { top: parent.top; bottom: parent.bottom; left: centerCenter.right; leftMargin: 4 }
            Repeater {
                model: root.rightList
                delegate: BarComponent {
                    growthEdge: "leading"
                    list: Config.options.bar.layouts.center; barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                }
            }
        }
    }

    RowLayout {
        id: rightSection
        anchors {
            top: barBackground.top
            bottom: barBackground.bottom
            right: barBackground.right
            rightMargin: Appearance.sizes.hyprlandGapsOut
        }
        spacing: 4
        Repeater {
            id: rightRepeater
            model: Config.options.bar.layouts.right
            delegate: BarComponent {
                list: rightRepeater.model
                barSection: 2
            }
        }
    }

    FocusedScrollMouseArea {
        id: barLeftSideMouseArea
        z: -1
        anchors { top: barBackground.top; bottom: barBackground.bottom; left: barBackground.left; right: middleSection.left }
        implicitHeight: Appearance.sizes.baseBarHeight
        onScrollDown: if (Config.options.bar.enableBrightnessScroll) Brightness.decreaseBrightness()
        onScrollUp:   if (Config.options.bar.enableBrightnessScroll) Brightness.increaseBrightness()
        onMovedAway:  GlobalStates.osdBrightnessOpen = false
        onPressed: event => { if (event.button === Qt.LeftButton) GlobalStates.toggleLeftSidebar(root.screen?.name); }

        ScrollHint {
            reveal: barLeftSideMouseArea.hovered && Config.options.bar.enableBrightnessScroll
            icon: Hyprsunset.gamma === 100 ? "light_mode" : "wb_twilight"
            tooltipText: Translation.tr("Scroll to change brightness")
            side: "left"
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        }
    }

    FocusedScrollMouseArea {
        id: barRightSideMouseArea
        z: -1
        anchors { top: barBackground.top; bottom: barBackground.bottom; left: middleSection.right; right: barBackground.right }
        implicitHeight: Appearance.sizes.baseBarHeight
        onScrollDown: if (Config.options.bar.enableVolumeScroll) Audio.decrementVolume()
        onScrollUp:   if (Config.options.bar.enableVolumeScroll) Audio.incrementVolume()
        onMovedAway:  GlobalStates.osdVolumeOpen = false
        onPressed: event => { if (event.button === Qt.LeftButton) GlobalStates.toggleRightSidebar(root.screen?.name); }

        ScrollHint {
            reveal: barRightSideMouseArea.hovered && Config.options.bar.enableVolumeScroll
            icon: "volume_up"
            tooltipText: Translation.tr("Scroll to change volume")
            side: "right"
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        }
    }
}
