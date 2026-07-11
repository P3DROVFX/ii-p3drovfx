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

// cornerStyle === 0 
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
    readonly property string barEdge: Config.options.bar.bottom ? "bottom" : "top"

    Rectangle {
        id: barBackground
        anchors.fill: parent
        color: root.isIslandMode ? "transparent" : root.actualColor
        radius: 0

        layer.enabled: !root.isIslandMode && Config.options.bar.dropShadow
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.28)
            shadowVerticalOffset: Config.options.bar.bottom ? -4 : 4
            shadowBlur: 1.0
        }
    }

    // ── Hug-style islands (barBackgroundStyle === 3) ─────────────────────────
    HugIslandGroup {
        id: leftIsland
        z: -9
        visible: root.isIslandMode && (Config.options.bar.layouts.left || []).length > 0
        edge: root.barEdge
        role: "first"
        fillColor: root.actualColor
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: leftSection.right; rightMargin: -6
        }
    }

    HugIslandGroup {
        id: middleIsland
        z: -9
        visible: root.isIslandMode && (root.leftList.length > 0 || root.centerList.length > 0 || root.rightList.length > 0)
        edge: root.barEdge
        role: "middle"
        fillColor: root.actualColor
        anchors {
            top: middleSection.top
            bottom: middleSection.bottom
            left: middleSection.left; leftMargin: -6
            right: middleSection.right; rightMargin: -6
        }
    }

    HugIslandGroup {
        id: rightIsland
        z: -9
        visible: root.isIslandMode && (Config.options.bar.layouts.right || []).length > 0
        edge: root.barEdge
        role: "last"
        fillColor: root.actualColor
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: rightSection.left; leftMargin: -6
            right: parent.right
        }
    }

    Item {
        id: leftStopper
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left; leftMargin: 4 }
        width: 1
    }
    Item {
        id: rightStopper
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: 1
    }

    RowLayout {
        id: leftSection
        anchors { top: parent.top; bottom: parent.bottom; left: leftStopper.right }
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
        anchors { top: parent.top; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
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
        anchors { top: parent.top; bottom: parent.bottom; right: rightStopper.left; rightMargin: 4 }
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
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left; right: middleSection.left }
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
        anchors { top: parent.top; bottom: parent.bottom; left: middleSection.right; right: parent.right }
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
