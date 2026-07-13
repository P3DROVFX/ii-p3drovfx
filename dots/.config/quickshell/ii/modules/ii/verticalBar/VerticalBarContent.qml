import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar as Bar
import qs.modules.ii.bar.shared

Item { // Bar content region
    id: root

    property var screen: root.QsWindow.window?.screen
    property int monitorIndex
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    property bool hasActiveWindows: false
    property bool showBarBackground: root.hasActiveWindows && Config.options.bar.barBackgroundStyle === 2 || Config.options.bar.barBackgroundStyle === 1 || Config.options.bar.barBackgroundStyle === 3

    Connections {
        enabled: Config.options.bar.barBackgroundStyle === 2 || Config.options.bar.barBackgroundStyle === 3
        target: HyprlandData
        function onWindowListChanged() {
            const monitorName = root.screen ? root.screen.name : "";
            const monitor = monitorName ? HyprlandData.monitors.find(m => m.name === monitorName) : null;
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
    // Use a single stable empty array reference so the binding tracker
    // doesn't see a "new" array on every re-evaluation when Config.options
    // transiently reloads. A fresh `[]` literal each frame creates a
    // chain reaction through leftList/centerList/rightList, which the
    // QML binding tracker reports as a binding loop.
    readonly property var _emptyLayout: ([])
    readonly property var fullModel: Config.options.bar.layouts.center || root._emptyLayout
    readonly property int centerIdx: fullModel.findIndex(item => item.centered)
    readonly property var leftList: centerIdx === -1 ? root._emptyLayout : fullModel.slice(0, centerIdx)
    readonly property var centerList: centerIdx === -1 ? fullModel.slice() : [fullModel[centerIdx]]
    readonly property var rightList: centerIdx === -1 ? root._emptyLayout : fullModel.slice(centerIdx + 1)


    BarThemes {
        id: barThemes
    }
    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

    readonly property bool isIslandMode: Config.options.bar.barBackgroundStyle === 3
    readonly property bool isDynamicIsland: Config.options.bar.cornerStyle === 3
    readonly property bool isHugIslandMode: root.isIslandMode && Config.options.bar.cornerStyle === 0
    readonly property string barEdge: Config.options.bar.bottom ? "right" : "left"
    readonly property real frameThickness: Config.options.appearance.fakeScreenRounding === 3 ? Config.options.appearance.wrappedFrameThickness : 0

    property color islandFillColor: Config.options.bar.expressiveColors
        ? root.activeTheme.barBackground
        : Appearance.colors.colLayer0



    // Background
    Rectangle {
        id: barBackground
        z: -10
        anchors {
            fill: root.isDynamicIsland ? undefined : parent
            centerIn: root.isDynamicIsland ? parent : undefined
            margins: (Config.options.bar.cornerStyle === 1) ? Appearance.sizes.hyprlandGapsOut : 0
        }

        property color actualColor: root.showBarBackground ? (Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"
        Behavior on actualColor {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(barBackground)
        }

        opacity: 1.0

        readonly property int islandSectionSpacing: {
            const screenHeight = root.screen ? root.screen.height : 1080;
            const frameThick = root.frameThickness;
            const maxAllowedHeight = screenHeight - 2 * frameThick - 64; // 32px padding on top/bottom
            
            const topH = topSectionLayout.implicitHeight;
            const centerH = centerSectionLayout.implicitHeight;
            const bottomH = bottomSectionLayout.implicitHeight;
            
            const remaining = maxAllowedHeight - 24 - topH - centerH - bottomH;
            
            if (Config.options.bar.dynamicIslandLoadBalance) {
                return Math.min(60, Math.max(8, Math.floor(remaining / 2)));
            } else {
                const preferred = Config.options.bar.dynamicIslandSpacingVertical ?? 16;
                const maxSpacing = Math.max(8, Math.floor(remaining / 2));
                return Math.min(preferred, maxSpacing);
            }
        }

        width: parent.width
        height: root.isDynamicIsland ? (Math.max(islandSections.implicitHeight + 24, 200)) : parent.height

        color: root.isIslandMode ? "transparent" : barBackground.actualColor
        property real baseRadius: root.isDynamicIsland ? width / 2 : (Config.options.bar.cornerStyle === 1 || Config.options.appearance.fakeScreenRounding === 4 ? Appearance.rounding.full : 0)

        // In vertical mode (Left/Right), the edges touching the screen are left/right.
        // For Left bar (bottom: false): left edges are 0.
        // For Right bar (bottom: true): right edges are 0.
        topLeftRadius: (!Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius
        bottomLeftRadius: (!Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius
        topRightRadius: (Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius
        bottomRightRadius: (Config.options.bar.bottom && (root.isDynamicIsland || Config.options.appearance.fakeScreenRounding === 4)) ? 0 : baseRadius

        border.width: 0
        border.color: "transparent"

        Behavior on height {
            enabled: !root.isDynamicIsland
            NumberAnimation {
                duration: 450
                easing.type: Easing.OutExpo
            }
        }

        layer.enabled: !root.isIslandMode && Config.options.bar.dropShadow
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.28)
            shadowHorizontalOffset: Config.options.bar.bottom ? -4 : 4
            shadowVerticalOffset: 0
            shadowBlur: 1.0
        }
    }

    // Concave Corners (HUD Mode)
    RoundCorner {
        anchors.bottom: barBackground.top
        anchors.left: Config.options.bar.bottom ? undefined : barBackground.left
        anchors.right: Config.options.bar.bottom ? barBackground.right : undefined
        implicitSize: barBackground.baseRadius
        extendHorizontal: false
        extendVertical: false
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
        extendHorizontal: false
        extendVertical: false
        color: barBackground.color
        corner: Config.options.bar.bottom ? RoundCorner.CornerEnum.TopRight : RoundCorner.CornerEnum.TopLeft
        visible: root.isDynamicIsland && root.showBarBackground
        anchors.leftMargin: (!Config.options.bar.bottom) ? root.frameThickness : 0
        anchors.rightMargin: Config.options.bar.bottom ? root.frameThickness : 0
    }

    // ── Islands (barBackgroundStyle === 3) ────────────────────────────────────
    // Pill islands for Float/Rect styles.
    Rectangle {
        id: topIsland
        z: -9
        visible: root.isIslandMode && !root.isHugIslandMode && (Config.options.bar.layouts.left || []).length > 0
        anchors {
            left: parent.left; leftMargin: 4
            right: parent.right; rightMargin: 4
            top: topSection.top; topMargin: -6
            bottom: topSection.bottom; bottomMargin: -6
        }
        color: root.islandFillColor
        radius: Appearance.rounding.full
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(topIsland)
        }
    }

    Rectangle {
        id: middleIsland
        z: -9
        visible: root.isIslandMode && !root.isHugIslandMode && (root.leftList.length > 0 || root.centerList.length > 0 || root.rightList.length > 0)
        anchors {
            left: parent.left; leftMargin: 4
            right: parent.right; rightMargin: 4
            top: middleSection.top; topMargin: -6
            bottom: middleSection.bottom; bottomMargin: -6
        }
        color: root.islandFillColor
        radius: Appearance.rounding.full
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(middleIsland)
        }
    }

    Rectangle {
        id: bottomIsland
        z: -9
        visible: root.isIslandMode && !root.isHugIslandMode && (Config.options.bar.layouts.right || []).length > 0
        anchors {
            left: parent.left; leftMargin: 4
            right: parent.right; rightMargin: 4
            top: bottomSection.top; topMargin: -6
            bottom: bottomSection.bottom; bottomMargin: -6
        }
        color: root.islandFillColor
        radius: Appearance.rounding.full
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(bottomIsland)
        }
    }

    // Hug-style islands: connected to the screen edge with concave transitions.
    HugIslandGroup {
        id: topHugIsland
        z: -9
        visible: root.isHugIslandMode && (Config.options.bar.layouts.left || []).length > 0
        edge: root.barEdge
        role: "first"
        fillColor: barBackground.actualColor
        anchors {
            top: parent.top
            bottom: topSection.bottom; bottomMargin: -6
            left: parent.left
            right: parent.right
        }
    }

    HugIslandGroup {
        id: middleHugIsland
        z: -9
        visible: root.isHugIslandMode && (root.leftList.length > 0 || root.centerList.length > 0 || root.rightList.length > 0)
        edge: root.barEdge
        role: "middle"
        fillColor: barBackground.actualColor
        anchors {
            top: middleSection.top; topMargin: -6
            bottom: middleSection.bottom; bottomMargin: -6
            left: parent.left
            right: parent.right
        }
    }

    HugIslandGroup {
        id: bottomHugIsland
        z: -9
        visible: root.isHugIslandMode && (Config.options.bar.layouts.right || []).length > 0
        edge: root.barEdge
        role: "last"
        fillColor: barBackground.actualColor
        anchors {
            top: bottomSection.top; topMargin: -6
            bottom: parent.bottom
            left: parent.left
            right: parent.right
        }
    }

    ColumnLayout { // Combined Island section
        id: islandSections
        visible: root.isDynamicIsland
        anchors.centerIn: parent
        spacing: 0

        ColumnLayout { // Top items
            id: topSectionLayout
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

        Item {
            Layout.fillHeight: true
            Layout.preferredHeight: barBackground.islandSectionSpacing
        }

        ColumnLayout { // Center items
            id: centerSectionLayout
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

        Item {
            Layout.fillHeight: true
            Layout.preferredHeight: barBackground.islandSectionSpacing
        }

        ColumnLayout { // Bottom items
            id: bottomSectionLayout
            spacing: 4
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
        width: Appearance.sizes.verticalBarWindowWidth

        onScrollDown: if (Config.options.bar.enableBrightnessScroll) Brightness.decreaseBrightness()
        onScrollUp: if (Config.options.bar.enableBrightnessScroll) Brightness.increaseBrightness()
        onMovedAway: GlobalStates.osdBrightnessOpen = false
        onPressed: event => {
            if (event.button === Qt.LeftButton)
                GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    ColumnLayout { // Top section
        id: topSection
        visible: !root.isDynamicIsland
        anchors {
            top: barBackground.top
            topMargin: (Config.options.bar.cornerStyle === 1) ? Appearance.sizes.hyprlandGapsOut : Math.ceil(Appearance.rounding.screenRounding / 2.5)
            horizontalCenter: barBackground.horizontalCenter
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
        readonly property real middleChildrenHeight: {
            const ch = centerCenter.implicitHeight;
            const lh = middleLeftColumn.implicitHeight;
            const rh = middleRightColumn.implicitHeight;
            let total = ch;
            if (lh > 0) total += lh + 4;
            if (rh > 0) total += rh + 4;
            return Math.max(1, total);
        }
        height: middleChildrenHeight

        ColumnLayout {
            id: middleLeftColumn
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
            id: middleRightColumn
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
            horizontalCenter: barBackground.horizontalCenter
            bottom: barBackground.bottom
            bottomMargin: (Config.options.bar.cornerStyle === 1) ? Appearance.sizes.hyprlandGapsOut : Math.ceil(Appearance.rounding.screenRounding / 2.5)
        }
        spacing: 4

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
