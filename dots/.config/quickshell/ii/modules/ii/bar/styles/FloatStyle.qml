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

        layer.enabled: !root.isIslandMode && Config.options.bar.dropShadow
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.28)
            shadowVerticalOffset: Config.options.bar.bottom ? -4 : 4
            shadowBlur: 1.0
        }
    }

    Rectangle {
        id: bottomShadowGradient
        visible: !root.isIslandMode && Config.options.bar.dropShadow && !Config.options.bar.autoHide.enable
        anchors {
            bottom: barBackground.bottom
            left: barBackground.left
            right: barBackground.right
        }
        height: 6
        radius: barBackground.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.12) }
        }
    }

    // ── Islands (barBackgroundStyle === 3) ────────────────────────────────────
    property color islandFillColor: Config.options.bar.expressiveColors
        ? root.activeTheme.barBackground
        : Appearance.colors.colLayer0

    Rectangle {
        id: leftIsland
        visible: root.isIslandMode && (Config.options.bar.layouts.left || []).length > 0
        anchors {
            left: leftSection.left; leftMargin: -6
            right: leftSection.right; rightMargin: -6
            top: barBackground.top; bottom: barBackground.bottom
        }
        color: root.islandFillColor
        radius: Appearance.rounding.full
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(leftIsland)
        }
    }

    Rectangle {
        id: middleIsland
        visible: root.isIslandMode && (root.leftList.length > 0 || root.centerList.length > 0 || root.rightList.length > 0)
        anchors {
            left: middleSection.left; leftMargin: -6
            right: middleSection.right; rightMargin: -6
            top: barBackground.top; bottom: barBackground.bottom
        }
        color: root.islandFillColor
        radius: Appearance.rounding.full
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(middleIsland)
        }
    }

    Rectangle {
        id: rightIsland
        visible: root.isIslandMode && (Config.options.bar.layouts.right || []).length > 0
        anchors {
            left: rightSection.left; leftMargin: -6
            right: rightSection.right; rightMargin: -6
            top: barBackground.top; bottom: barBackground.bottom
        }
        color: root.islandFillColor
        radius: Appearance.rounding.full
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
        width: middleLeft.width + centerCenter.width + middleRight.width + 8

        RowLayout {
            id: middleLeft
            anchors { top: parent.top; bottom: parent.bottom; right: centerCenter.left; rightMargin: 4 }
            Repeater {
                model: root.leftList
                delegate: BarComponent {
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
        onPressed: event => { if (event.button === Qt.LeftButton) GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen; }

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
        onPressed: event => { if (event.button === Qt.LeftButton) GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen; }

        ScrollHint {
            reveal: barRightSideMouseArea.hovered && Config.options.bar.enableVolumeScroll
            icon: "volume_up"
            tooltipText: Translation.tr("Scroll to change volume")
            side: "right"
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        }
    }
}
