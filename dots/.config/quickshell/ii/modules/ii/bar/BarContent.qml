import qs.modules.ii.bar.weather
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

import Quickshell.Io

Item { // Bar content region
    id: root

    property var screen: root.QsWindow.window?.screen
    property int monitorIndex
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    property real useShortenedForm: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2 : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0
    readonly property int centerSideModuleWidth: (useShortenedForm == 2) ? Appearance.sizes.barCenterSideModuleWidthHellaShortened : (useShortenedForm == 1) ? Appearance.sizes.barCenterSideModuleWidthShortened : Appearance.sizes.barCenterSideModuleWidth

    property bool hasActiveWindows: false
    property bool showBarBackground: root.hasActiveWindows && Config.options.bar.barBackgroundStyle === 2 || Config.options.bar.barBackgroundStyle === 1
    readonly property bool isDynamicIsland: Config.options.bar.cornerStyle === 3

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

    ////// Definning places of center modules //////
    property var fullModel: Config.options.bar.layouts.center

    property var leftList: []
    property var centerList: []
    property var rightList: []

    onFullModelChanged: {
        const idx = fullModel.findIndex(item => item.centered);

        if (idx === -1) {
            leftList = [];
            centerList = fullModel;
            rightList = [];
            return;
        }

        leftList = fullModel.slice(0, idx);
        centerList = [fullModel[idx]];
        rightList = fullModel.slice(idx + 1);
    }

    // Background shadow
    Loader {
        active: root.showBarBackground && Config.options.bar.cornerStyle === 1 && Config.options.bar.floatStyleShadow
        anchors.fill: barBackground
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
        }
    }
    BarThemes {
        id: barThemes
    }
    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

    Rectangle {
        id: shadowSource
        z: -12
        anchors {
            left: parent.left
            right: parent.right
            top: !Config.options.bar.vertical && !Config.options.bar.bottom ? parent.top : undefined
            bottom: !Config.options.bar.vertical && Config.options.bar.bottom ? parent.bottom : undefined
            leftMargin: (Config.options.bar.vertical && !Config.options.bar.bottom) ? 0 : undefined
            rightMargin: (Config.options.bar.vertical && Config.options.bar.bottom) ? 0 : undefined
        }
        width: Config.options.bar.vertical ? 1 : parent.width
        height: Config.options.bar.vertical ? parent.height : 1
        visible: Config.options.bar.barBackgroundStyle === 0
        color: "transparent"
    }

    Rectangle {
        z: -11
        anchors.fill: parent
        visible: Config.options.bar.barBackgroundStyle === 0
        gradient: Gradient {
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

    // Background
    Rectangle {
        id: barBackground
        z: -10 // making sure its behind everything
        anchors {
            fill: root.isDynamicIsland ? undefined : parent
            centerIn: root.isDynamicIsland ? parent : undefined
            margins: Config.options.bar.cornerStyle === 1 ? (Appearance.sizes.hyprlandGapsOut) : 0 // idk why but +1 is needed
        }

        readonly property int islandSectionSpacing: 48 //spacing between the three modules
        width: root.isDynamicIsland ? (Math.max(islandSections.implicitWidth + 12, 200)) : parent.width
        height: parent.height

        color: root.showBarBackground ? (Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"
        property real baseRadius: root.isDynamicIsland ? height / 2 : (Config.options.bar.cornerStyle === 1 || Config.options.appearance.fakeScreenRounding === 4 ? Appearance.rounding.windowRounding : 0)
        topLeftRadius: (!Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius
        topRightRadius: (!Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius
        bottomLeftRadius: (Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius
        bottomRightRadius: (Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius
        border.width: (Config.options.bar.cornerStyle === 1) ? 1 : 0
        border.color: root.showBarBackground ? Appearance.colors.colLayer0Border : "transparent"

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Behavior on width {
            NumberAnimation {
                duration: 450
                easing.type: Easing.OutExpo
            }
        }
    }

    // Concave Corners (HUD Mode)
    RoundCorner {
        z: -5
        anchors.top: barBackground.top
        anchors.right: barBackground.left
        implicitSize: barBackground.baseRadius
        color: barBackground.color
        corner: RoundCorner.CornerEnum.TopRight
        visible: root.isDynamicIsland && root.showBarBackground && !Config.options.bar.bottom
        opacity: visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 250
            }
        }
    }
    RoundCorner {
        z: -5
        anchors.top: barBackground.top
        anchors.left: barBackground.right
        implicitSize: barBackground.baseRadius
        color: barBackground.color
        corner: RoundCorner.CornerEnum.TopLeft
        visible: root.isDynamicIsland && root.showBarBackground && !Config.options.bar.bottom
        opacity: visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 250
            }
        }
    }

    RoundCorner {
        z: -5
        anchors.bottom: barBackground.bottom
        anchors.right: barBackground.left
        implicitSize: barBackground.baseRadius
        color: barBackground.color
        corner: RoundCorner.CornerEnum.BottomRight
        visible: root.isDynamicIsland && root.showBarBackground && Config.options.bar.bottom
        opacity: visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 250
            }
        }
    }
    RoundCorner {
        z: -5
        anchors.bottom: barBackground.bottom
        anchors.left: barBackground.right
        implicitSize: barBackground.baseRadius
        color: barBackground.color
        corner: RoundCorner.CornerEnum.BottomLeft
        visible: root.isDynamicIsland && root.showBarBackground && Config.options.bar.bottom
        opacity: visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 250
            }
        }
    }

    FocusedScrollMouseArea { // Left side | scroll to change brightness
        id: barLeftSideMouseArea

        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: middleSection.left
        }
        implicitHeight: Appearance.sizes.baseBarHeight

        onScrollDown: Brightness.decreaseBrightness()
        onScrollUp: Brightness.increaseBrightness()
        onMovedAway: GlobalStates.osdBrightnessOpen = false
        onPressed: event => {
            if (event.button === Qt.LeftButton)
                GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }

        ScrollHint {
            reveal: barLeftSideMouseArea.hovered
            icon: Hyprsunset.gamma === 100 ? "light_mode" : "wb_twilight"
            tooltipText: Translation.tr("Scroll to change brightness")
            side: "left"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Item {
        id: leftStopper
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            leftMargin: 4
        }
        width: 1
    }

    RowLayout { // Combined Island section
        id: islandSections
        visible: root.isDynamicIsland
        anchors.centerIn: parent
        spacing: barBackground.islandSectionSpacing

        RowLayout { // Left
            spacing: 4
            Repeater {
                model: Config.options.bar.layouts.left
                delegate: BarComponent {
                    list: Config.options.bar.layouts.left
                    barSection: 0
                }
            }
        }

        RowLayout { // Center
            spacing: 4
            Repeater {
                model: root.leftList
                delegate: BarComponent {
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                }
            }
            Repeater {
                model: root.centerList
                delegate: BarComponent {
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                }
            }
            Repeater {
                model: root.rightList
                delegate: BarComponent {
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                }
            }
        }

        RowLayout { // Right
            spacing: 4
            Repeater {
                model: Config.options.bar.layouts.right
                delegate: BarComponent {
                    list: Config.options.bar.layouts.right
                    barSection: 2
                }
            }
        }
    }

    RowLayout { // Left section
        id: leftSection
        visible: !root.isDynamicIsland
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: leftStopper.right
        }
        spacing: 4

        Repeater {
            id: leftRepeater
            model: Config.options.bar.layouts.left
            delegate: BarComponent {
                list: Config.options.bar.layouts.left
                barSection: 0
            }
        }
    }

    RowLayout { // Middle section
        id: middleSection
        visible: !root.isDynamicIsland
        anchors {
            top: parent.top
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }
        spacing: 4

        RowLayout {
            Layout.fillHeight: true
            Repeater {
                id: middleLeftRepeater
                model: root.leftList
                delegate: BarComponent {
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id) // we have to recalculate the index because repeater.model has changed
                }
            }
        }

        RowLayout { //center
            id: centerCenter
            Layout.fillHeight: true
            Repeater {
                model: root.centerList
                delegate: BarComponent {
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                }
            }
        }

        RowLayout {
            Layout.fillHeight: true
            Repeater {
                id: middleRightRepeater
                model: root.rightList
                delegate: BarComponent {
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                }
            }
        }
    }

    RowLayout { // Right section
        id: rightSection
        visible: !root.isDynamicIsland
        anchors {
            top: parent.top
            bottom: parent.bottom
            right: rightStopper.left
            rightMargin: 4
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

    Item {
        id: rightStopper
        anchors {
            top: parent.top
            bottom: parent.bottom
            right: parent.right
        }
        width: 1
    }

    FocusedScrollMouseArea { // Right side | scroll to change volume
        id: barRightSideMouseArea

        z: -1
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: middleSection.right
            right: parent.right
        }
        implicitHeight: Appearance.sizes.baseBarHeight

        onScrollDown: Audio.decrementVolume()
        onScrollUp: Audio.incrementVolume()
        onMovedAway: GlobalStates.osdVolumeOpen = false
        onPressed: event => {
            if (event.button === Qt.LeftButton) {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }
        }

        ScrollHint {
            reveal: barRightSideMouseArea.hovered
            icon: "volume_up"
            tooltipText: Translation.tr("Scroll to change volume")
            side: "right"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
