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
import qs.modules.ii.dynamicIsland.core
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

    // ── Combined mode: the bar and the island share the centre ───────────────
    // With this bar style *and* the island drawn in the bar centre, the island is the
    // centred pill and the bar's job is to flank it. The two spacers around the (empty)
    // centre section each reserve half of the island's live width, so the island sits in
    // a gap of its own size and the widget groups are pushed outward as it grows.
    //
    // Deliberately not animated: the island is already animating its own width, and a
    // second animation here would chase a moving target - the same mistake that made
    // this pill lag behind the active window title (see the note above on content
    // resize vs mode resize).
    readonly property bool islandInBarCenter: IslandPolicy.centerInBar && BarInteraction.cornerStyle === 3
    readonly property real islandCenterGap: Appearance.sizes.hyprlandGapsOut
    // The side gaps close with the island when it hides, so a hidden island leaves no
    // hole: the two groups meet in the middle. Whole pixels; see IslandGeometry.
    readonly property real islandReservedWidth: root.islandInBarCenter
        ? Math.max(0, IslandGeometry.centerWidth + 2 * Math.round(root.islandCenterGap * IslandGeometry.reveal))
        : 0

    // The island window is centred on screen, so the reserved gap has to be centred too.
    // The pill itself is content-sized and its two groups are rarely the same width, so
    // centring the *pill* leaves the gap off to one side. Shifting the pill by the
    // difference puts the gap under the island and lets both groups keep hugging it,
    // which is why the cluster as a whole sits slightly off-centre.
    readonly property real islandCenterCorrection: {
        if (!root.islandInBarCenter)
            return 0;
        const inset = Math.max(0, (barBackground.width - islandSections.width) / 2);
        const gapCentreInPill = inset + leftSectionLayout.width + root.islandReservedWidth / 2;
        const correction = (barBackground.width / 2) - gapCentreInPill;
        // Whole pixels only. Centre anchors already snap the centred position to a
        // pixel (`alignWhenCentered`) and then add this offset, so a fractional offset
        // put the pill - and every widget in it - on a half pixel whenever the
        // groups' combined width changed parity: the whole bar flickered half a pixel
        // left and right while any widget animated its own width.
        return Math.round(correction);
    }
    readonly property var modeState: modeState

    readonly property var activeNotchCurve: {
        if (modeState._displayMode === "clock" || modeState._displayMode === "")
            return Appearance.animationCurves.emphasized;
        return Appearance.animationCurves.emphasizedDecel;
    }

    // ── Content resize vs mode resize ────────────────────────────────────────
    // Two different reasons for this pill to change size, and they need
    // opposite treatment:
    //
    //  • A mode change (notch collapse/expand, OSD, notification, search) moves
    //    the width to a fixed target. That one animates.
    //  • A widget growing or shrinking inside moves it to whatever the content
    //    now measures. That one must NOT animate: the widgets already animate
    //    their own size on Appearance.animation.barResize, and a second
    //    animation on the container chases a target that is itself moving —
    //    which is exactly what made the pill lag behind the active window title
    //    and the dock icons. Following the content directly keeps the two
    //    locked together for the whole travel.
    property bool modeResizing: false
    Timer {
        id: modeResizeWindow
        interval: Appearance.animation.elementResize.duration + 120
        repeat: false
        onTriggered: root.modeResizing = false
    }
    function beginModeResize() {
        root.modeResizing = true;
        modeResizeWindow.restart();
    }
    readonly property string _modeKey: modeState._displayMode + "|" + modeState.expanded
    on_ModeKeyChanged: root.beginModeResize()
    onIsSearchActiveHereChanged: root.beginModeResize()

    readonly property bool searchStable: modeState._displayMode === "search" && (searchWidgetLoader.item ? searchWidgetLoader.item.openStateStable : false)
    readonly property bool isSearchModeActive: (modeState._displayMode === "search") || searchWidgetLoader.visible || root.isSearchActiveHere

    readonly property real verticalTopOffset: BarPlacement.bottom ? Math.max(0, (barBackground.height + root.frameThickness) - parent.height) : 0
    readonly property real verticalBottomOffset: !BarPlacement.bottom ? Math.max(0, (barBackground.height + root.frameThickness) - parent.height) : 0

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
            top: !BarPlacement.bottom ? parent.top : undefined
            bottom: BarPlacement.bottom ? parent.bottom : undefined
            horizontalCenter: parent.horizontalCenter
            // An offset rather than a swapped anchor: the pill stays centre-anchored and
            // is simply nudged so its centre gap lands on the island.
            horizontalCenterOffset: root.islandCenterCorrection
            topMargin: !BarPlacement.bottom ? root.frameThickness : 0
            bottomMargin: BarPlacement.bottom ? root.frameThickness : 0
        }

        layer.enabled: Config.options.bar.dropShadow && !ShellModePolicy.barDropShadowBlocked
        layer.smooth: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.28)
            shadowVerticalOffset: BarPlacement.bottom ? -4 : 4
            shadowBlur: 1.0
        }

        height: {
            const isNotchActive = modeState.notchModeEnabled;
            const isExpanded = modeState.expanded;
            if (isNotchActive && !isExpanded) {
                if (modeState._displayMode === "")
                    return 0;
                if (modeState._displayMode === "osd") {
                    return Math.max(0, 72 - root.frameThickness);
                }
                if (modeState._displayMode === "notification") {
                    return Math.max(0, 80 - root.frameThickness);
                }
                if (modeState._displayMode === "search") {
                    const searchH = searchWidgetLoader.item ? Math.min(root.screen.height * 0.7, searchWidgetLoader.item.implicitHeight) : (GlobalStates.searchConnectActive ? 68 : 60);
                    return Math.max(0, searchH - root.frameThickness);
                }
            }
            return Math.max(0, parent.height - root.frameThickness);
        }

        Behavior on height {
            id: barHeightBehavior
            enabled: !root.searchStable && root.modeResizing
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

        readonly property real availableIslandHeight: Math.max(0, height)
        readonly property real islandRadius: Math.min(Appearance.rounding.screenRounding, Math.floor(availableIslandHeight / 2))
        property real baseRadius: islandRadius
        topLeftRadius: !BarPlacement.bottom ? 0 : baseRadius
        topRightRadius: !BarPlacement.bottom ? 0 : baseRadius
        bottomLeftRadius: BarPlacement.bottom ? 0 : baseRadius
        bottomRightRadius: BarPlacement.bottom ? 0 : baseRadius

        Behavior on width {
            // Never while the island sits in the centre. The pill's width is then a sum
            // with the island's *live* width in it, so any mode change (search opening
            // or closing is one) armed this OutBack animation toward a target that moved
            // every frame: it restarted each frame, overshot and stalled, the pill
            // lagged its own widgets and clipped the outermost ones, and the concave
            // corners anchored to it jittered. The island is the one animator; the pill
            // follows it exactly.
            enabled: !root.islandInBarCenter && !root.searchStable && root.modeResizing
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
            // The row is normally 22px wider than its content (the pill adds 32, this
            // takes 10 back), and Qt hands that slack to whichever cells can grow - which
            // moved the right half outward and made the island's right margin wider than
            // its left. In combined mode the row is exactly its content, so there is no
            // slack to distribute and both margins come out equal.
            width: root.islandInBarCenter ? implicitWidth : (parent.width - 10)
            height: parent.height
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
                // Layout.fillWidth defaults to true for a Layout inside a Layout, so
                // these sections used to absorb the row's leftover width and shift the
                // halves apart - the right margin came out 22px wider than the left. In
                // combined mode the gap belongs to the island, so nothing may stretch.
                Layout.fillWidth: !root.islandInBarCenter
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
                // In combined mode the gap belongs to the island, so it must not
                // stretch: `fillWidth` would hand it leftover space and the groups would
                // stop tracking the island. Half here, half in the mirrored spacer.
                Layout.fillWidth: !root.islandInBarCenter && (!modeState.notchModeEnabled || modeState.expanded)
                Layout.preferredWidth: {
                    if (root.islandInBarCenter)
                        return root.islandReservedWidth / 2;
                    return (!modeState.notchModeEnabled || modeState.expanded) ? barBackground.islandSectionSpacing : 0;
                }
                visible: Layout.preferredWidth > 0
                Behavior on Layout.preferredWidth {
                    // Content-driven, like the pill above: only a mode change is worth
                    // animating here, and in combined mode never - the island's own
                    // animation is the one to follow.
                    enabled: root.modeResizing && !root.islandInBarCenter
                    animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                }
            }
            RowLayout {
                id: centerSectionLayout
                spacing: (modeState.notchModeEnabled && !modeState.expanded) ? 0 : 4
                // Layout.fillWidth defaults to true for a Layout inside a Layout, so
                // these sections used to absorb the row's leftover width and shift the
                // halves apart - the right margin came out 22px wider than the left. In
                // combined mode the gap belongs to the island, so nothing may stretch.
                Layout.fillWidth: !root.islandInBarCenter
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
                // In combined mode the gap belongs to the island, so it must not
                // stretch: `fillWidth` would hand it leftover space and the groups would
                // stop tracking the island. Half here, half in the mirrored spacer.
                Layout.fillWidth: !root.islandInBarCenter && (!modeState.notchModeEnabled || modeState.expanded)
                Layout.preferredWidth: {
                    if (root.islandInBarCenter)
                        return root.islandReservedWidth / 2;
                    return (!modeState.notchModeEnabled || modeState.expanded) ? barBackground.islandSectionSpacing : 0;
                }
                visible: Layout.preferredWidth > 0
                Behavior on Layout.preferredWidth {
                    // Content-driven, like the pill above: only a mode change is worth
                    // animating here, and in combined mode never - the island's own
                    // animation is the one to follow.
                    enabled: root.modeResizing && !root.islandInBarCenter
                    animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                }
            }
            RowLayout {
                id: rightSectionLayout
                spacing: 4
                // Layout.fillWidth defaults to true for a Layout inside a Layout, so
                // these sections used to absorb the row's leftover width and shift the
                // halves apart - the right margin came out 22px wider than the left. In
                // combined mode the gap belongs to the island, so nothing may stretch.
                Layout.fillWidth: !root.islandInBarCenter
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
        anchors.topMargin: 0
        anchors.right: barBackground.left
        implicitSize: barBackground.islandRadius
        color: barBackground.color
        corner: RoundCorner.CornerEnum.TopRight
        visible: root.showBarBackground && !BarPlacement.bottom
        opacity: visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }
    }
    RoundCorner {
        anchors.top: barBackground.top
        anchors.topMargin: 0
        anchors.left: barBackground.right
        implicitSize: barBackground.islandRadius
        color: barBackground.color
        corner: RoundCorner.CornerEnum.TopLeft
        visible: root.showBarBackground && !BarPlacement.bottom
        opacity: visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }
    }
    RoundCorner {
        anchors.bottom: barBackground.bottom
        anchors.bottomMargin: 0
        anchors.right: barBackground.left
        implicitSize: barBackground.islandRadius
        color: barBackground.color
        corner: RoundCorner.CornerEnum.BottomRight
        visible: root.showBarBackground && BarPlacement.bottom
        opacity: visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }
    }
    RoundCorner {
        anchors.bottom: barBackground.bottom
        anchors.bottomMargin: 0
        anchors.left: barBackground.right
        implicitSize: barBackground.islandRadius
        color: barBackground.color
        corner: RoundCorner.CornerEnum.BottomLeft
        visible: root.showBarBackground && BarPlacement.bottom
        opacity: visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }
    }
}

