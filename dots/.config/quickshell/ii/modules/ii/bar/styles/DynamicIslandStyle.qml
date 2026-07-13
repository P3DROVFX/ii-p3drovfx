pragma ComponentBehavior: Bound
import qs.modules.ii.bar.shared
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.overview
import "island"
import Qt5Compat.GraphicalEffects

Item {
    id: root
    focus: modeState._displayMode === "search"

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            GlobalStates.overviewOpen = false;
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (searchWidgetLoader.item) {
                searchWidgetLoader.item.focusFirstItem();
                event.accepted = true;
            }
            return;
        }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            if (searchWidgetLoader.item) {
                searchWidgetLoader.item.focusSearchInput();
                event.accepted = true;
            }
            return;
        }
    }

    // Required from BarContent
    property var screen
    property bool showBarBackground
    property bool isSearchActiveHere
    property real expectedSearchWidth
    property real frameThickness
    property var leftList
    property var centerList
    property var rightList
    property var activeTheme

    // Expose pill width back to BarContent
    readonly property real pillWidth: barBackground.width
    readonly property var modeState: modeState

    readonly property var activeNotchCurve: {
        if (modeState._displayMode === "clock" || modeState._displayMode === "")
            return Appearance.animationCurves.emphasized;
        return Appearance.animationCurves.emphasizedDecel;
    }

    readonly property bool searchStable: modeState._displayMode === "search" && (searchWidgetLoader.item ? searchWidgetLoader.item.openStateStable : false)
    readonly property bool isSearchModeActive: (modeState._displayMode === "search") || searchWidgetLoader.visible || root.isSearchActiveHere

    readonly property real verticalTopOffset: Config.options.bar.bottom ? Math.max(0, barBackground.height - parent.height) : 0
    readonly property real verticalBottomOffset: !Config.options.bar.bottom ? Math.max(0, barBackground.height - parent.height) : 0

    IslandModeController {
        id: modeController
        screen: root.screen
    }

    IslandModeState {
        id: modeState
        mode: modeController.resolvedMode
        hoverActive: islandHoverHandler.hovered
    }

    // Determine the actual background color of the bar reactively
    property color actualColor: root.showBarBackground ? (Config.options.bar.expressiveColors ? root.activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"

    Behavior on actualColor {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(root)
    }

    // ── Main Bar Background Pill ─────────────────────────────────────────────
    Rectangle {
        id: barBackground
        clip: true
        antialiasing: true
        color: root.actualColor

        anchors {
            top: !Config.options.bar.bottom ? parent.top : undefined
            bottom: Config.options.bar.bottom ? parent.bottom : undefined
            horizontalCenter: parent.horizontalCenter
        }

        layer.enabled: Config.options.bar.dropShadow
        layer.smooth: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.28)
            shadowVerticalOffset: Config.options.bar.bottom ? -4 : 4
            shadowBlur: 1.0
        }

        height: {
            const isNotchActive = modeState.notchModeEnabled;
            const isExpanded = modeState.expanded;
            if (isNotchActive && !isExpanded) {
                if (modeState._displayMode === "")
                    return 0;
                if (modeState._displayMode === "osd") {
                    return 72;
                }
                if (modeState._displayMode === "notification") {
                    return 80;
                }
                if (modeState._displayMode === "search") {
                    return searchWidgetLoader.item ? Math.min(root.screen.height * 0.7, searchWidgetLoader.item.implicitHeight) : (GlobalStates.searchConnectActive ? 68 : 60);
                }
            }
            return parent.height;
        }

        Behavior on height {
            id: barHeightBehavior
            enabled: !root.searchStable
            NumberAnimation {
                duration: {
                    if (modeState.notchModeEnabled) {
                        if (modeState.expanded && modeState._modeStable) {
                            return Appearance.animation.elementResize.duration;
                        }
                        return Config.options.bar.dynamicIsland.notchMode.expandAnimDuration;
                    }
                    return Appearance.animation.elementResize.duration;
                }
                easing.type: root.isSearchModeActive ? Easing.BezierSpline : Easing.OutCubic
                easing.bezierCurve: root.isSearchModeActive ? root.activeNotchCurve : []
            }
        }

        HoverHandler {
            id: islandHoverHandler
        }

        readonly property int islandSectionSpacing: {
            const screenWidth = root.screen ? root.screen.width : 1920;
            const frameThick = root.frameThickness;
            const maxAllowedWidth = screenWidth - 2 * frameThick - 64;
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
            const isNotchActive = modeState.notchModeEnabled;
            const isExpanded = modeState.expanded;
            if (isNotchActive && !isExpanded) {
                if (modeState._displayMode === "")
                    return 0;
                if (modeState._displayMode === "osd") {
                    return 380;
                }
                if (modeState._displayMode === "notification") {
                    return 450;
                }
                if (modeState._displayMode === "search") {
                    return searchWidgetLoader.item ? searchWidgetLoader.item.implicitWidth : (Config.options.search.baseWidth + (GlobalStates.searchConnectActive ? 48 : 0));
                }
            }
            const minW = (isNotchActive && !isExpanded) ? 80 : 200;
            const baseWidth = Math.max(islandSections.implicitWidth + 32, minW);
            if (GlobalStates.connectModeActive && root.isSearchActiveHere && !modeState.notchModeEnabled) {
                const requiredWidth = root.expectedSearchWidth + 100;
                return Math.max(baseWidth, requiredWidth);
            }
            return baseWidth;
        }

        property real baseRadius: Math.min(height / 2, Appearance.rounding.windowRounding + 12)
        topLeftRadius: !Config.options.bar.bottom ? 0 : baseRadius
        topRightRadius: !Config.options.bar.bottom ? 0 : baseRadius
        bottomLeftRadius: Config.options.bar.bottom ? 0 : baseRadius
        bottomRightRadius: Config.options.bar.bottom ? 0 : baseRadius

        Behavior on width {
            enabled: !root.searchStable
            NumberAnimation {
                duration: {
                    if (modeState.notchModeEnabled) {
                        return Config.options.bar.dynamicIsland.notchMode.expandAnimDuration;
                    }
                    const multiplier = Appearance.animMultiplier ?? 1.0;
                    return Math.round((root.isSearchActiveHere ? 450 : 280) * multiplier);
                }
                easing.type: root.isSearchModeActive ? Easing.BezierSpline : (modeState.notchModeEnabled ? Easing.OutCubic : Easing.OutBack)
                easing.bezierCurve: root.isSearchModeActive ? root.activeNotchCurve : []
            }
        }

        // ── Island layout (placed directly inside background to handle hover natively) ─
        RowLayout {
            id: islandSections
            width: parent.width - 10
            height: root.height
            anchors.centerIn: parent
            spacing: 0
            opacity: (!modeState.notchModeEnabled || (modeState.expanded && modeState._displayMode !== "search") || (modeState._displayMode !== "" && modeState._displayMode !== "osd" && modeState._displayMode !== "notification" && modeState._displayMode !== "search")) ? 1.0 : 0.0
            visible: opacity > 0.01
            Behavior on opacity {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutCubic
                }
            }

            layer.enabled: modeState.notchModeEnabled && !modeState.expanded
            layer.smooth: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: islandSections.width
                    height: islandSections.height
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop {
                            position: 0.0
                            color: "transparent"
                        }
                        GradientStop {
                            position: 0.25
                            color: "black"
                        }
                        GradientStop {
                            position: 0.75
                            color: "black"
                        }
                        GradientStop {
                            position: 1.0
                            color: "transparent"
                        }
                    }
                }
            }

            RowLayout {
                id: leftSectionLayout
                spacing: 4
                opacity: (!modeState.notchModeEnabled || modeState.expanded || (modeState._displayMode === "workspaces" && Config.options.bar.layouts.left.some(e => e.id === "workspaces"))) ? 1.0 : 0.0
                visible: opacity > 0.01
                Behavior on opacity {
                    SequentialAnimation {
                        PauseAnimation {
                            duration: (modeState.notchModeEnabled && modeState.expanded) ? Config.options.bar.dynamicIsland.notchMode.fadeDelay : 0
                        }
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }
                }
                Repeater {
                    id: leftRepeater
                    model: Config.options.bar.layouts.left
                    delegate: BarComponent {
                        list: leftRepeater.model
                        barSection: 0
                        modeState: root.modeState
                    }
                }
            }
            Item {
                Layout.fillWidth: !modeState.notchModeEnabled || modeState.expanded
                Layout.preferredWidth: (!modeState.notchModeEnabled || modeState.expanded) ? barBackground.islandSectionSpacing : 0
                visible: Layout.preferredWidth > 0
                Behavior on Layout.preferredWidth {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.OutCubic
                    }
                }
            }
            RowLayout {
                id: centerSectionLayout
                spacing: (modeState.notchModeEnabled && !modeState.expanded) ? 0 : 4
                Repeater {
                    model: root.leftList
                    delegate: BarComponent {
                        list: Config.options.bar.layouts.center
                        barSection: 1
                        originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                        modeState: root.modeState
                    }
                }
                Repeater {
                    model: root.centerList
                    delegate: BarComponent {
                        list: Config.options.bar.layouts.center
                        barSection: 1
                        originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                        modeState: root.modeState
                    }
                }
                Repeater {
                    model: root.rightList
                    delegate: BarComponent {
                        list: Config.options.bar.layouts.center
                        barSection: 1
                        originalIndex: Config.options.bar.layouts.center.findIndex(e => e.id === modelData.id)
                        modeState: root.modeState
                    }
                }
            }
            Item {
                Layout.fillWidth: !modeState.notchModeEnabled || modeState.expanded
                Layout.preferredWidth: (!modeState.notchModeEnabled || modeState.expanded) ? barBackground.islandSectionSpacing : 0
                visible: Layout.preferredWidth > 0
                Behavior on Layout.preferredWidth {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.OutCubic
                    }
                }
            }
            RowLayout {
                id: rightSectionLayout
                spacing: 4
                opacity: (!modeState.notchModeEnabled || modeState.expanded || (modeState._displayMode === "workspaces" && Config.options.bar.layouts.right.some(e => e.id === "workspaces"))) ? 1.0 : 0.0
                visible: opacity > 0.01
                Behavior on opacity {
                    SequentialAnimation {
                        PauseAnimation {
                            duration: (modeState.notchModeEnabled && modeState.expanded) ? Config.options.bar.dynamicIsland.notchMode.fadeDelay : 0
                        }
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }
                }
                Repeater {
                    id: rightRepeater
                    model: Config.options.bar.layouts.right
                    delegate: BarComponent {
                        list: rightRepeater.model
                        barSection: 2
                        modeState: root.modeState
                    }
                }
            }
        }

        // OSD Container
        Loader {
            id: osdLoader
            anchors.fill: parent
            active: modeState.notchModeEnabled && (modeState._displayMode === "osd" || opacity > 0.01)
            visible: opacity > 0.01
            opacity: modeState.notchModeEnabled && modeState._displayMode === "osd" ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
            sourceComponent: Component {
                Item {
                    id: osdItem
                    anchors.fill: parent
                    Loader {
                        id: osdIndicatorLoader
                        anchors.fill: parent
                        source: {
                            const item = [
                                {
                                    id: "volume",
                                    sourceUrl: "indicators/VolumeIndicator.qml"
                                },
                                {
                                    id: "brightness",
                                    sourceUrl: "indicators/BrightnessIndicator.qml"
                                },
                                {
                                    id: "playerVolume",
                                    sourceUrl: "indicators/PlayerVolumeIndicator.qml"
                                },
                                {
                                    id: "gamma",
                                    sourceUrl: "indicators/GammaIndicator.qml"
                                }
                            ].find(i => i.id === GlobalStates.osdCurrentIndicator);
                            if (!item)
                                return "";
                            return Quickshell.shellPath("modules/ii/topLayer/osd/" + item.sourceUrl);
                        }
                    }
                }
            }
        }

        // Notification Container
        RowLayout {
            id: notificationLayout
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 12
            opacity: modeState.notchModeEnabled && modeState._displayMode === "notification" ? 1.0 : 0.0
            visible: opacity > 0.01
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            readonly property var latestNotif: Notifications.popupList.length > 0 ? Notifications.popupList[Notifications.popupList.length - 1] : null

            NotificationAppIcon {
                id: notifIcon
                Layout.alignment: Qt.AlignVCenter
                appIcon: notificationLayout.latestNotif ? notificationLayout.latestNotif.appIcon : ""
                summary: notificationLayout.latestNotif ? notificationLayout.latestNotif.summary : ""
                urgency: (notificationLayout.latestNotif && notificationLayout.latestNotif.notification) ? notificationLayout.latestNotif.notification.urgency : 1
                image: notificationLayout.latestNotif ? notificationLayout.latestNotif.image : ""
                implicitSize: 32
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumHeight: implicitHeight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.bold: true
                    text: notificationLayout.latestNotif ? notificationLayout.latestNotif.summary : ""
                    maximumLineCount: 1
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumHeight: implicitHeight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: notificationLayout.latestNotif ? notificationLayout.latestNotif.body : ""
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                }
            }

            MaterialSymbol {
                text: "close"
                iconSize: 18
                color: Appearance.colors.colOnSurfaceVariant
                Layout.alignment: Qt.AlignVCenter
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (notificationLayout.latestNotif) {
                            Notifications.discardNotification(notificationLayout.latestNotif.notificationId);
                        }
                    }
                }
            }
        }

        // Search Container
        Loader {
            id: searchWidgetLoader
            anchors.fill: parent
            active: modeState.notchModeEnabled
            visible: opacity > 0.01
            focus: visible && modeState._displayMode === "search"
            opacity: modeState.notchModeEnabled && modeState._displayMode === "search" ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutCubic
                }
            }
            onVisibleChanged: {
                if (visible && item) {
                    if (GlobalStates.activeSearchQuery) {
                        item.setSearchingText(GlobalStates.activeSearchQuery);
                        GlobalStates.activeSearchQuery = "";
                    } else {
                        item.cancelSearch();
                    }
                    Qt.callLater(() => item.focusSearchInput());
                }
            }
            Connections {
                target: GlobalStates
                ignoreUnknownSignals: true
                function onActiveSearchQueryChanged() {
                    if (GlobalStates.activeSearchQuery && searchWidgetLoader.item && searchWidgetLoader.visible) {
                        searchWidgetLoader.item.setSearchingText(GlobalStates.activeSearchQuery);
                        GlobalStates.activeSearchQuery = "";
                    }
                }
            }
            sourceComponent: Component {
                SearchWidget {
                    id: searchWidget
                    inNotchMode: true
                    Component.onCompleted: {
                        if (GlobalStates.activeSearchQuery) {
                            searchWidget.setSearchingText(GlobalStates.activeSearchQuery);
                            GlobalStates.activeSearchQuery = "";
                        } else {
                            searchWidget.cancelSearch();
                        }
                        if (searchWidgetLoader.visible) {
                            Qt.callLater(() => searchWidget.focusSearchInput());
                        }
                    }
                }
            }
        }
    }

    // ── Concave Corners ──────────────────────────────────────────────────────
    // We anchor the RoundCorner Items to the sides of the bar with 0 margin
    // to prevent any 1px overlap, which would be visible as a double-blended
    // line when transparency is enabled.
    RoundCorner {
        anchors.top: barBackground.top
        anchors.right: barBackground.left
        anchors.rightMargin: 0
        extendHorizontal: false
        extendVertical: false
        implicitSize: barBackground.baseRadius
        color: barBackground.color
        corner: RoundCorner.CornerEnum.TopRight
        visible: root.showBarBackground && !Config.options.bar.bottom
        opacity: visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }
        anchors.topMargin: root.frameThickness
    }
    RoundCorner {
        anchors.top: barBackground.top
        anchors.left: barBackground.right
        anchors.leftMargin: 0
        extendHorizontal: false
        extendVertical: false
        implicitSize: barBackground.baseRadius
        color: barBackground.color
        corner: RoundCorner.CornerEnum.TopLeft
        visible: root.showBarBackground && !Config.options.bar.bottom
        opacity: visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }
        anchors.topMargin: root.frameThickness
    }
    RoundCorner {
        anchors.bottom: barBackground.bottom
        anchors.right: barBackground.left
        anchors.rightMargin: 0
        extendHorizontal: false
        extendVertical: false
        implicitSize: barBackground.baseRadius
        color: barBackground.color
        corner: RoundCorner.CornerEnum.BottomRight
        visible: root.showBarBackground && Config.options.bar.bottom
        opacity: visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }
        anchors.bottomMargin: root.frameThickness
    }
    RoundCorner {
        anchors.bottom: barBackground.bottom
        anchors.left: barBackground.right
        anchors.leftMargin: 0
        extendHorizontal: false
        extendVertical: false
        implicitSize: barBackground.baseRadius
        color: barBackground.color
        corner: RoundCorner.CornerEnum.BottomLeft
        visible: root.showBarBackground && Config.options.bar.bottom
        opacity: visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }
        anchors.bottomMargin: root.frameThickness
    }
}
