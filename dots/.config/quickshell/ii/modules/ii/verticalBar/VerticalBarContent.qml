import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar as Bar

Item { // Bar content region
    id: root

    property var screen: root.QsWindow.window?.screen
    property int monitorIndex
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    property bool hasActiveWindows: false
    property bool showBarBackground: root.hasActiveWindows && Config.options.bar.barBackgroundStyle === 2 || Config.options.bar.barBackgroundStyle === 1

    Connections {
        enabled: Config.options.bar.barBackgroundStyle === 2
        target: HyprlandData
        function onWindowListChanged() {
            const monitor = HyprlandData.monitors.find(m => m.id === monitorIndex);
            const wsId = monitor?.activeWorkspace?.id;

            const hasWindow = wsId ? HyprlandData.windowList.some(w => w.workspace.id === wsId && !w.floating) : false;

            root.hasActiveWindows = hasWindow;
        }
    }

    component HorizontalBarSeparator: Rectangle {
        Layout.leftMargin: Appearance.sizes.baseBarHeight / 3
        Layout.rightMargin: Appearance.sizes.baseBarHeight / 3
        Layout.fillWidth: true
        implicitHeight: 1
        color: Appearance.colors.colOutlineVariant
    }

    ////// Definning places of center modules //////
    property var fullModel: Config.options?.bar?.layouts?.center

    property int centerIdx: (fullModel || []).findIndex(item => item.centered)

    property var leftList: centerIdx === -1 ? [] : fullModel.slice(0, centerIdx)
    property var centerList: centerIdx === -1 ? fullModel : [fullModel[centerIdx]]
    property var rightList: centerIdx === -1 ? [] : fullModel.slice(centerIdx + 1)

    // Background shadow
    Loader {
        active: root.showBarBackground && Config.options.bar.cornerStyle === 1 && Config.options.bar.floatStyleShadow
        anchors.fill: barBackground
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
        }
    }
    Bar.BarThemes {
        id: barThemes
    }
    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

    readonly property bool isDynamicIsland: Config.options.bar.cornerStyle === 3
    readonly property real frameThickness: Config.options.appearance.fakeScreenRounding === 3 ? Config.options.appearance.wrappedFrameThickness : 0

    Rectangle {
        z: -11
        anchors.fill: parent
        visible: Config.options.bar.barBackgroundStyle === 0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: Config.options.bar.bottom ? 1.0 : 0.0
                color: Qt.rgba(0, 0, 0, 0.6)
            }
            GradientStop {
                position: Config.options.bar.bottom ? 0.6 : 0.4
                color: Qt.rgba(0, 0, 0, 0.2)
            }
            GradientStop {
                position: Config.options.bar.bottom ? 0.0 : 1.0
                color: "transparent"
            }
        }
    }

    Item {
        id: backgroundGroup
        z: -10
        anchors.fill: parent

        property color actualColor: root.showBarBackground ? (Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"
        Behavior on actualColor {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(backgroundGroup)
        }

        opacity: actualColor.a
        layer.enabled: actualColor.a > 0.0 && actualColor.a < 1.0

        // Background
        Rectangle {
            id: barBackground
            anchors {
                fill: root.isDynamicIsland ? undefined : parent
                centerIn: root.isDynamicIsland ? parent : undefined
            }

            width: parent.width
            height: root.isDynamicIsland ? (Math.max(islandSections.implicitHeight + 24, 200)) : parent.height

            color: Qt.rgba(backgroundGroup.actualColor.r, backgroundGroup.actualColor.g, backgroundGroup.actualColor.b, 1.0)
            property real baseRadius: root.isDynamicIsland ? width / 2 : (Config.options.bar.cornerStyle === 1 || Config.options.appearance.fakeScreenRounding === 4 ? Appearance.rounding.windowRounding : 0)

            // In vertical mode (Left/Right), the edges touching the screen are left/right.
            // For Left bar (bottom: false): left edges are 0.
            // For Right bar (bottom: true): right edges are 0.
            topLeftRadius: (!Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius
            bottomLeftRadius: (!Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius
            topRightRadius: (Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius
            bottomRightRadius: (Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius

            border.width: (Config.options.bar.cornerStyle === 1) ? 1 : 0
            border.color: root.showBarBackground ? Appearance.colors.colLayer0Border : "transparent"

            Behavior on height {
                enabled: !root.isDynamicIsland
                NumberAnimation {
                    duration: 450
                    easing.type: Easing.OutExpo
                }
            }
        }

        // Concave Corners (HUD Mode)
        RoundCorner {
            anchors.bottom: barBackground.top
            anchors.left: Config.options.bar.bottom ? undefined : barBackground.left
            anchors.right: Config.options.bar.bottom ? barBackground.right : undefined
            implicitSize: barBackground.baseRadius
            extendVertical: true
            color: barBackground.color
            corner: Config.options.bar.bottom ? RoundCorner.CornerEnum.BottomRight : RoundCorner.CornerEnum.BottomLeft
            visible: root.isDynamicIsland && root.showBarBackground
            anchors.leftMargin: (!Config.options.bar.bottom) ? root.frameThickness : 0
            anchors.rightMargin: Config.options.bar.bottom ? root.frameThickness : 0
        }
        RoundCorner {
            anchors.top: barBackground.bottom
            anchors.left: Config.options.bar.bottom ? undefined : barBackground.left
            anchors.right: Config.options.bar.bottom ? barBackground.right : undefined
            implicitSize: barBackground.baseRadius
            extendVertical: true
            color: barBackground.color
            corner: Config.options.bar.bottom ? RoundCorner.CornerEnum.TopRight : RoundCorner.CornerEnum.TopLeft
            visible: root.isDynamicIsland && root.showBarBackground
            anchors.leftMargin: (!Config.options.bar.bottom) ? root.frameThickness : 0
            anchors.rightMargin: Config.options.bar.bottom ? root.frameThickness : 0
        }
    }

    ColumnLayout { // Combined Island section
        id: islandSections
        visible: root.isDynamicIsland
        anchors.centerIn: parent
        spacing: 16

        ColumnLayout { // Top items
            spacing: 4
            Repeater {
                model: Config.options.bar.layouts.left
                delegate: Bar.BarComponent {
                    vertical: true
                    list: Config.options.bar.layouts.left
                    barSection: 0
                }
            }
        }

        ColumnLayout { // Center items
            spacing: 4
            Repeater {
                model: root.leftList
                delegate: Bar.BarComponent {
                    vertical: true
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                }
            }
            Repeater {
                model: root.centerList
                delegate: Bar.BarComponent {
                    vertical: true
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                }
            }
            Repeater {
                model: root.rightList
                delegate: Bar.BarComponent {
                    vertical: true
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                }
            }
        }

        ColumnLayout { // Bottom items
            spacing: 8
            Repeater {
                model: Config.options.bar.layouts.right
                delegate: Bar.BarComponent {
                    vertical: true
                    list: Config.options.bar.layouts.right
                    barSection: 2
                }
            }
        }
    }

    FocusedScrollMouseArea { // Top section | scroll to change brightness
        id: barTopSectionMouseArea
        visible: !root.isDynamicIsland
        anchors {
            top: parent.top
            bottom: middleSection.top
            left: parent.left
            right: parent.right
        }
        implicitWidth: Appearance.sizes.baseVerticalBarWidth
        height: (root.height - middleSection.height) / 2
        width: Appearance.sizes.verticalBarWidth

        onScrollDown: if (Config.options.bar.enableBrightnessScroll) Brightness.decreaseBrightness()
        onScrollUp: if (Config.options.bar.enableBrightnessScroll) Brightness.increaseBrightness()
        onMovedAway: GlobalStates.osdBrightnessOpen = false
        onPressed: event => {
            if (event.button === Qt.LeftButton)
                GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    Item {
        id: topStopper
        visible: !root.isDynamicIsland
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: Math.ceil(Appearance.rounding.screenRounding / 2.5)
        }
        height: 1
    }

    ColumnLayout { // Top section
        id: topSection
        visible: !root.isDynamicIsland
        anchors {
            top: topStopper.bottom
            horizontalCenter: parent.horizontalCenter
        }
        spacing: 4

        Repeater {
            id: leftRepeater
            model: Config.options.bar.layouts.left
            delegate: Bar.BarComponent {
                vertical: true
                list: leftRepeater.model
                barSection: 0
            }
        }
    }

    Item {
        id: middleSection
        visible: !root.isDynamicIsland
        anchors {
            horizontalCenter: parent.horizontalCenter
            verticalCenter: parent.verticalCenter
        }

        ColumnLayout {
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: centerCenter.top
                bottomMargin: 4
            }
            Repeater {
                id: middleLeftRepeater
                model: root.leftList
                delegate: Bar.BarComponent {
                    vertical: true
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id) // we have to recalculate the index because repeater.model has changed
                }
            }
        }

        ColumnLayout { //center
            id: centerCenter
            anchors {
                horizontalCenter: parent.horizontalCenter
                verticalCenter: parent.verticalCenter
            }
            Repeater {
                model: root.centerList
                delegate: Bar.BarComponent {
                    vertical: true
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                }
            }
        }

        ColumnLayout {
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: centerCenter.bottom
                topMargin: 4
            }
            Repeater {
                id: middleRightRepeater
                model: root.rightList
                delegate: Bar.BarComponent {
                    vertical: true
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                }
            }
        }
    }

    ColumnLayout { // Bottom section
        id: bottomSection
        visible: !root.isDynamicIsland
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: bottomStopper.top
        }
        spacing: 8

        Repeater {
            id: rightRepeater
            model: Config.options.bar.layouts.right
            delegate: Bar.BarComponent {
                vertical: true
                list: rightRepeater.model
                barSection: 2
            }
        }
    }

    Item {
        id: bottomStopper
        visible: !root.isDynamicIsland
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            bottomMargin: Math.ceil(Appearance.rounding.screenRounding / 2.5)
        }
        height: 1
    }

    FocusedScrollMouseArea { // Bottom section | scroll to change volume
        id: barBottomSectionMouseArea
        visible: !root.isDynamicIsland

        z: -1
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            top: middleSection.bottom
        }
        implicitWidth: Appearance.sizes.baseVerticalBarWidth

        onScrollDown: if (Config.options.bar.enableVolumeScroll) Audio.decrementVolume()
        onScrollUp: if (Config.options.bar.enableVolumeScroll) Audio.incrementVolume()
        onMovedAway: GlobalStates.osdVolumeOpen = false
        onPressed: event => {
            if (event.button === Qt.LeftButton) {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }
        }
    }
}
