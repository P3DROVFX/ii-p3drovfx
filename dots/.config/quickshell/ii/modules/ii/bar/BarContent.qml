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
    readonly property bool isSearchActiveHere: GlobalStates.overviewOpen && (root.screen ? GlobalStates.activeSearchMonitor === root.screen.name : false)
    readonly property bool isSearchClipboardMode: LauncherSearch.query.startsWith(Config.options.search.prefix.clipboard)
    readonly property bool isSearchBluetoothMode: LauncherSearch.query.startsWith(Config.options.search.prefix.bluetooth)
    readonly property bool isSearchTranslatorMode: LauncherSearch.query.startsWith(Config.options.search.prefix.translator)
    readonly property bool isSearchMediaDownloaderMode: Config.options.mediaDownloader.enabled && LauncherSearch.query.startsWith(Config.options.search.prefix.mediaDownloader)
    readonly property bool isSearchSpecialMode: isSearchClipboardMode || isSearchBluetoothMode || isSearchTranslatorMode || isSearchMediaDownloaderMode

    readonly property real expectedSearchWidth: {
        if (isSearchSpecialMode) {
            return (Config.options.search.clipboard.panelWidth ?? 860) + 48;
        } else {
            return Config.options.search.baseWidth + 48;
        }
    }
    readonly property real frameThickness: Config.options.appearance.fakeScreenRounding === 3 ? Config.options.appearance.wrappedFrameThickness : 0
    readonly property real islandWidth: isDynamicIsland ? barBackground.width : 0

    Connections {
        enabled: Config.options.bar.barBackgroundStyle === 2
        target: HyprlandData
        function onWindowListChanged() {
            const monitorName = root.screen ? root.screen.name : "";
            const monitor = monitorName ? HyprlandData.monitors.find(m => m.name === monitorName) : null;
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
        anchors.fill: backgroundGroup
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
            shadowOffset: Qt.vector2d(0.0, Config.options.bar.bottom ? 1.0 : -1.0)
        }
    }
    BarThemes {
        id: barThemes
    }
    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

    // === Transparent bar background: simple color gradient (no blur) ===
    // Uses a semi-transparent solid color that fades from a subtle tint at the
    // screen edge to fully transparent at the content edge.
    Rectangle {
        id: transparentGradientLayer
        z: -11
        anchors.fill: parent
        visible: Config.options.bar.barBackgroundStyle === 0
        readonly property bool barAtTop: !Config.options.bar.bottom
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop {
                position: transparentGradientLayer.barAtTop ? 0.0 : 1.0
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.30)
            }
            GradientStop {
                position: transparentGradientLayer.barAtTop ? 1.0 : 0.0
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
                top: parent.top
                bottom: parent.bottom
                left: root.isDynamicIsland ? undefined : parent.left
                right: root.isDynamicIsland ? undefined : parent.right
                horizontalCenter: root.isDynamicIsland ? parent.horizontalCenter : undefined
                margins: Config.options.bar.cornerStyle === 1 ? (Appearance.sizes.hyprlandGapsOut) : 0
            }

            readonly property int islandSectionSpacing: {
                const screenWidth = root.screen ? root.screen.width : 1920;
                const frameThick = root.frameThickness;
                const maxAllowedWidth = screenWidth - 2 * frameThick - 64; // 32px padding on each side
                
                const leftW = leftSectionLayout.implicitWidth;
                const centerW = centerSectionLayout.implicitWidth;
                const rightW = rightSectionLayout.implicitWidth;
                
                const remaining = maxAllowedWidth - 32 - leftW - centerW - rightW;
                
                if (Config.options.bar.dynamicIslandLoadBalance) {
                    return Math.min(100, Math.max(16, Math.floor(remaining / 2)));
                } else {
                    const preferred = Config.options.bar.dynamicIslandSpacingHorizontal ?? 48;
                    const maxSpacing = Math.max(16, Math.floor(remaining / 2));
                    return Math.min(preferred, maxSpacing);
                }
            }
            width: {
                if (!root.isDynamicIsland)
                    return parent.width;
                const baseWidth = Math.max(islandSections.implicitWidth + 32, 200);
                if (GlobalStates.connectModeActive && root.isSearchActiveHere) {
                    const requiredWidth = root.expectedSearchWidth + 100;
                    return Math.max(baseWidth, requiredWidth);
                }
                return baseWidth;
            }

            color: Qt.rgba(backgroundGroup.actualColor.r, backgroundGroup.actualColor.g, backgroundGroup.actualColor.b, 1.0)
            property real baseRadius: root.isDynamicIsland ? height / 2 : (Config.options.bar.cornerStyle === 1 || Config.options.appearance.fakeScreenRounding === 4 ? Appearance.rounding.windowRounding : 0)
            radius: baseRadius
            topLeftRadius: (!Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius
            topRightRadius: (!Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius
            bottomLeftRadius: (Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius
            bottomRightRadius: (Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius
            border.width: (Config.options.bar.cornerStyle === 1) ? 1 : 0
            border.color: root.showBarBackground ? Appearance.colors.colLayer0Border : "transparent"

            Behavior on width {
                NumberAnimation {
                    duration: {
                        if (root.isDynamicIsland) {
                            const multiplier = Appearance.animMultiplier ?? 1.0;
                            return Math.round((root.isSearchActiveHere ? 450 : 280) * multiplier);
                        }
                        return 450;
                    }
                    easing.type: root.isDynamicIsland ? Easing.OutBack : Easing.OutExpo
                }
            }

            Behavior on baseRadius {
                NumberAnimation {
                    duration: 450
                    easing.type: root.isDynamicIsland ? Easing.OutBack : Easing.OutExpo
                }
            }
        }

        // Concave Corners (HUD Mode)
        RoundCorner {
            anchors.top: barBackground.top
            anchors.right: barBackground.left
            implicitSize: barBackground.baseRadius
            extendHorizontal: true
            color: barBackground.color
            corner: RoundCorner.CornerEnum.TopRight
            visible: root.isDynamicIsland && root.showBarBackground && !Config.options.bar.bottom
            opacity: visible ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 250
                }
            }
            anchors.topMargin: root.frameThickness
        }
        RoundCorner {
            anchors.top: barBackground.top
            anchors.left: barBackground.right
            implicitSize: barBackground.baseRadius
            extendHorizontal: true
            color: barBackground.color
            corner: RoundCorner.CornerEnum.TopLeft
            visible: root.isDynamicIsland && root.showBarBackground && !Config.options.bar.bottom
            opacity: visible ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 250
                }
            }
            anchors.topMargin: root.frameThickness
        }

        RoundCorner {
            anchors.bottom: barBackground.bottom
            anchors.right: barBackground.left
            implicitSize: barBackground.baseRadius
            extendHorizontal: true
            color: barBackground.color
            corner: RoundCorner.CornerEnum.BottomRight
            visible: root.isDynamicIsland && root.showBarBackground && Config.options.bar.bottom
            opacity: visible ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 250
                }
            }
            anchors.bottomMargin: root.frameThickness
        }
        RoundCorner {
            anchors.bottom: barBackground.bottom
            anchors.left: barBackground.right
            implicitSize: barBackground.baseRadius
            extendHorizontal: true
            color: barBackground.color
            corner: RoundCorner.CornerEnum.BottomLeft
            visible: root.isDynamicIsland && root.showBarBackground && Config.options.bar.bottom
            opacity: visible ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 250
                }
            }
            anchors.bottomMargin: root.frameThickness
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

        onScrollDown: if (Config.options.bar.enableBrightnessScroll)
            Brightness.decreaseBrightness()
        onScrollUp: if (Config.options.bar.enableBrightnessScroll)
            Brightness.increaseBrightness()
        onMovedAway: GlobalStates.osdBrightnessOpen = false
        onPressed: event => {
            if (event.button === Qt.LeftButton)
                GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }

        ScrollHint {
            reveal: barLeftSideMouseArea.hovered && Config.options.bar.enableBrightnessScroll
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
            top: backgroundGroup.top
            bottom: backgroundGroup.bottom
            left: backgroundGroup.left
            leftMargin: 4
        }
        width: 1
    }

    RowLayout { // Combined Island section
        id: islandSections
        visible: root.isDynamicIsland
        width: root.isDynamicIsland ? barBackground.width - 32 : implicitWidth
        anchors {
            top: backgroundGroup.top
            bottom: backgroundGroup.bottom
            horizontalCenter: backgroundGroup.horizontalCenter
        }
        spacing: 0

        RowLayout { // Left
            id: leftSectionLayout
            spacing: 4
            Repeater {
                model: Config.options.bar.layouts.left
                delegate: BarComponent {
                    list: Config.options.bar.layouts.left
                    barSection: 0
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredWidth: barBackground.islandSectionSpacing
        }

        RowLayout { // Center
            id: centerSectionLayout
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

        Item {
            Layout.fillWidth: true
            Layout.preferredWidth: barBackground.islandSectionSpacing
        }

        RowLayout { // Right
            id: rightSectionLayout
            spacing: 8
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
            top: backgroundGroup.top
            bottom: backgroundGroup.bottom
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

    Item { // Middle section
        id: middleSection
        visible: !root.isDynamicIsland
        anchors {
            top: backgroundGroup.top
            bottom: backgroundGroup.bottom
            horizontalCenter: backgroundGroup.horizontalCenter
        }
        width: Math.max(middleLeft.width, middleRight.width) * 2 + centerCenter.width + 8

        RowLayout {
            id: middleLeft
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: centerCenter.left
                rightMargin: 4
            }
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
            anchors.centerIn: parent
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
            id: middleRight
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: centerCenter.right
                leftMargin: 4
            }
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
            top: backgroundGroup.top
            bottom: backgroundGroup.bottom
            right: rightStopper.left
            rightMargin: 4
        }
        spacing: 8

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
            top: backgroundGroup.top
            bottom: backgroundGroup.bottom
            right: backgroundGroup.right
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

        onScrollDown: if (Config.options.bar.enableVolumeScroll)
            Audio.decrementVolume()
        onScrollUp: if (Config.options.bar.enableVolumeScroll)
            Audio.incrementVolume()
        onMovedAway: GlobalStates.osdVolumeOpen = false
        onPressed: event => {
            if (event.button === Qt.LeftButton) {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }
        }

        ScrollHint {
            reveal: barRightSideMouseArea.hovered && Config.options.bar.enableVolumeScroll
            icon: "volume_up"
            tooltipText: Translation.tr("Scroll to change volume")
            side: "right"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
