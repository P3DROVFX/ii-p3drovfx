import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.topLayer.osd
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import "components"
import "popups"

Scope {
    id: root
    property string protectionMessage: ""
    property var focusedScreen: Quickshell.screens.find(s => s.name === (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")) || Quickshell.screens[0] || null

    // Reactive count of Pipewire program playback nodes (output apps with audio)
    // Updated explicitly via Connections to guarantee reactivity for width bindings
    property int programPlaybackCount: Audio.outputAppNodes.length

    Connections {
        target: Audio
        ignoreUnknownSignals: true
        function onOutputAppNodesChanged() {
            root.programPlaybackCount = Audio.outputAppNodes.length;
        }
    }

    property bool isStartup: true
    Timer {
        running: true
        interval: 500
        onTriggered: root.isStartup = false
    }

    property string currentIndicator: "volume"
    property var indicators: [
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
        },
        {
            id: "keyboardBrightness",
            sourceUrl: "indicators/KeyboardBrightnessIndicator.qml"
        }
    ]

    property bool isClosing: false

    readonly property real currentValue: {
        if (currentIndicator === "volume") {
            if (Audio.sink && Audio.sink.audio)
                return Audio.sink.audio.muted ? 0 : Audio.sink.audio.volume;
            return 0;
        } else if (currentIndicator === "brightness") {
            let focusedScreen = Quickshell.screens.find(s => s.name === (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")) || Quickshell.screens[0] || null;
            let brightnessMonitor = Brightness.getMonitorForScreen(focusedScreen);
            return brightnessMonitor ? brightnessMonitor.brightness : 0.5;
        } else if (currentIndicator === "playerVolume") {
            return MprisController.activePlayer ? MprisController.activePlayer.volume : 0;
        } else if (currentIndicator === "gamma") {
            let from = Hyprsunset.gammaLowerLimit / 100;
            return (Hyprsunset.gamma / 100 - from) / (1.0 - from);
        } else if (currentIndicator === "keyboardBrightness") {
            return KeyboardBacklight.percentage / 100;
        }
        return 0.5;
    }

    readonly property string currentIcon: {
        if (currentIndicator === "volume") {
            const muted = (Audio.sink && Audio.sink.audio) ? Audio.sink.audio.muted : false;
            const vol = root.currentValue;
            if (muted)
                return "volume_off";
            if (vol <= 0.0)
                return "volume_mute";
            if (vol <= 0.33)
                return "volume_mute";
            if (vol <= 0.66)
                return "volume_down";
            return "volume_up";
        } else if (currentIndicator === "brightness") {
            if (Hyprsunset.temperatureActive)
                return "routine";
            const val = root.currentValue;
            if (val <= 0.33)
                return "brightness_low";
            if (val <= 0.66)
                return "brightness_medium";
            return "brightness_high";
        } else if (currentIndicator === "playerVolume") {
            return "music_note";
        } else if (currentIndicator === "gamma") {
            return "wb_twilight";
        } else if (currentIndicator === "keyboardBrightness") {
            return "keyboard";
        }
        return "volume_up";
    }

    function updateIndicatorValue(newValue) {
        if (currentIndicator === "volume") {
            if (Audio.sink && Audio.sink.audio) {
                Audio.sink.audio.volume = newValue;
                if (Audio.sink.audio.muted && newValue > 0) {
                    Audio.sink.audio.muted = false;
                }
            }
        } else if (currentIndicator === "brightness") {
            let focusedScreen = Quickshell.screens.find(s => s.name === (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")) || Quickshell.screens[0] || null;
            let brightnessMonitor = Brightness.getMonitorForScreen(focusedScreen);
            if (brightnessMonitor) {
                brightnessMonitor.setBrightness(newValue);
            }
        } else if (currentIndicator === "playerVolume") {
            if (MprisController.activePlayer) {
                MprisController.activePlayer.volume = newValue;
            }
        } else if (currentIndicator === "gamma") {
            let from = Hyprsunset.gammaLowerLimit / 100;
            let actualValue = newValue * (1.0 - from) + from;
            Hyprsunset.setGamma(Math.round(actualValue * 100));
        } else if (currentIndicator === "keyboardBrightness") {
            if (KeyboardBacklight.available && KeyboardBacklight.ready) {
                const step = Math.round(newValue * KeyboardBacklight.maxValue);
                KeyboardBacklight.setValue(step);
            }
        }
    }

    function triggerOsd() {
        if (Config.ready && Config.options.osd && !Config.options.osd.enable)
            return;
        // If the OSD was fully closed (not just closing), reset expansion state
        // so the next open always starts collapsed. This prevents stale state
        // from a previous session when the Loader reuses the same PanelWindow.
        if (!GlobalStates.osdVolumeOpen && osdLoader.item) {
            osdLoader.item.isExpanded = false;
            osdLoader.item.expandedProgress = 0.0;
        }
        GlobalStates.osdVolumeOpen = true;
        osdTimeout.restart();
    }

    Timer {
        id: osdTimeout
        interval: Config.options.osd.timeout
        repeat: false
        running: false
        onTriggered: {
            if (osdLoader.item && (osdLoader.item._mouseInside || (osdLoader.item.deviceOutputPopup && osdLoader.item.deviceOutputPopup.opened)))
                return;
            GlobalStates.osdVolumeOpen = false;
            root.protectionMessage = "";
        }
    }

    Timer {
        id: stateResetTimer
        interval: 150
        repeat: true
        running: true
        onTriggered: {
            // If the OSD Loader has a live item but the shell-level flags say it
            // should be fully closed, force-reset the expansion state. This catches
            // edge cases where the Loader keeps the PanelWindow alive across
            // rapid brightness-scroll re-triggers and the normal close-path
            // signals never fire.
            if (osdLoader.item && !GlobalStates.osdVolumeOpen && !root.isClosing) {
                osdLoader.item.isExpanded = false;
                osdLoader.item.expandedProgress = 0.0;
            }
        }
    }

    Connections {
        target: GlobalStates
        ignoreUnknownSignals: true
        function onOsdInteraction() {
            root.triggerOsd();
        }
    }

    Connections {
        target: Brightness
        function onBrightnessChanged() {
            if (GlobalStates.dashboardPanelOpen)
                return;
            root.protectionMessage = "";
            root.currentIndicator = "brightness";
            root.triggerOsd();
        }
    }

    Connections {
        target: Hyprsunset
        function onGammaChangeAttempt() {
            if (GlobalStates.dashboardPanelOpen)
                return;
            root.protectionMessage = "";
            root.currentIndicator = "gamma";
            root.triggerOsd();
        }
    }

    Connections {
        target: KeyboardBacklight
        function onCurrentValueChanged() {
            if (root.isStartup || GlobalStates.dashboardPanelOpen)
                return;
            if (!KeyboardBacklight.initialValueLoaded) {
                KeyboardBacklight.initialValueLoaded = true;
                return;
            }
            root.protectionMessage = "";
            root.currentIndicator = "keyboardBrightness";
            root.triggerOsd();
        }
    }

    Connections {
        target: Audio
        function onValueChanged() {
            if (!Audio.ready || root.isStartup || GlobalStates.blockVolumeOsdForBluetooth || GlobalStates.dashboardPanelOpen)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
        function onMutedChanged() {
            if (!Audio.ready || root.isStartup || GlobalStates.blockVolumeOsdForBluetooth || GlobalStates.dashboardPanelOpen)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }

    Connections {
        target: Audio
        function onSinkProtectionTriggered(reason) {
            root.protectionMessage = reason;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }

    Connections {
        target: MprisController.activePlayer ?? null
        function onVolumeChanged() {
            if (MprisController.canChangeVolume) {
                root.currentIndicator = "playerVolume";
                root.triggerOsd();
            }
        }
    }

    Connections {
        target: Config.ready ? Config.options.osd : null
        ignoreUnknownSignals: true
        function onEnableChanged() {
            if (!Config.options.osd.enable) {
                GlobalStates.osdVolumeOpen = false;
                root.isClosing = false;
            }
        }
    }

    Loader {
        id: osdLoader
        active: (GlobalStates.osdVolumeOpen || root.isClosing) && !GlobalStates.osdConnectActive && !(Config.ready && Config.options.bar.floatingNotch.enable)

        sourceComponent: PanelWindow {
            id: osdRoot
            color: "transparent"
            implicitWidth: 800

            property alias deviceOutputPopup: deviceOutputPopup

            // === SIZING TOKENS ===
            readonly property real osdBaseHeight: (Config.ready && Config.options.osd && Config.options.osd.height) ? Config.options.osd.height : 500
            readonly property real osdMargin: 12
            readonly property real osdItemSpacing: 10
            readonly property real osdRowSpacing: 8
            readonly property real osdGroupSpacing: 28
            readonly property real osdButtonHeight: 56
            readonly property real osdCollapseButtonHeight: osdButtonHeight
            readonly property real osdSliderTrackWidth: 38
            readonly property real osdSliderFillHeight: osdBaseHeight - 2 * osdMargin - 2 * osdButtonHeight - 3 * osdItemSpacing - osdCollapseButtonHeight

            readonly property real osdContractedWidth: 2 * osdMargin + osdButtonHeight
            readonly property real extrasExpandedWidth: {
                if (root.currentIndicator === "volume") {
                    var count = root.programPlaybackCount;
                    var slidersW = (2 + count) * osdButtonHeight;
                    if (count > 0) {
                        return slidersW + 2 * osdGroupSpacing + count * osdRowSpacing;
                    } else {
                        return slidersW + osdGroupSpacing + osdRowSpacing;
                    }
                } else if (root.currentIndicator === "brightness") {
                    var kbd = KeyboardBacklight.available ? 1 : 0;
                    var n = 2 + kbd; // 2 extra sliders (Gamma, Nightlight) + optional KeyboardBacklight
                    return n * osdButtonHeight + 2 * osdGroupSpacing + (n - 1) * osdRowSpacing;
                }
                return 0;
            }
            readonly property real osdExpandedWidth: osdContractedWidth + extrasExpandedWidth
            readonly property real osdExtrasMaxWidth: extrasExpandedWidth

            component OsdMorphToggle: RippleButton {
                id: morphToggle

                property bool isFirstInGroup: false
                property bool isLastInGroup: false
                property var _leftNeighbor: null
                property var _rightNeighbor: null
                property real baseWidth: 200

                // Check press state of neighbors
                readonly property bool prevIsPressed: _leftNeighbor ? (_leftNeighbor.isPressed || _leftNeighbor.down) : false
                readonly property bool nextIsPressed: _rightNeighbor ? (_rightNeighbor.isPressed || _rightNeighbor.down) : false

                // Width animation logic (matching GroupButton / sidebar dashboard behavior)
                // When pressed: expand width. When neighbor pressed: shrink width.
                Layout.preferredWidth: {
                    if (isPressed || down) {
                        return baseWidth + 16;
                    } else if (prevIsPressed || nextIsPressed) {
                        return Math.max(40, baseWidth - 16);
                    }
                    return baseWidth;
                }

                Behavior on Layout.preferredWidth {
                    animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                }

                // Radius logic (ii standard):
                // Full radius value = height / 2 (or full rounding token)
                readonly property real rFull: Appearance?.rounding?.scale === 0 ? 0 : height / 2
                readonly property real rSmall: Appearance?.rounding?.small ?? 8

                // Check toggled state of neighbors
                // Note: In RightToLeft layout, _leftNeighbor is physically to the RIGHT, and _rightNeighbor is physically to the LEFT.
                readonly property bool isSelfToggled: toggledState || toggled || (activated !== undefined && activated)
                readonly property bool prevIsToggled: _leftNeighbor ? (_leftNeighbor.isSelfToggled || _leftNeighbor.toggledState || _leftNeighbor.toggled || (_leftNeighbor.activated !== undefined && _leftNeighbor.activated)) : false
                readonly property bool nextIsToggled: _rightNeighbor ? (_rightNeighbor.isSelfToggled || _rightNeighbor.toggledState || _rightNeighbor.toggled || (_rightNeighbor.activated !== undefined && _rightNeighbor.activated)) : false

                // Physical Left side radius:
                readonly property real leftRadiusCalc: osdRoot.isLeftPosition
                    ? ((isFirstInGroup || isSelfToggled || prevIsToggled) ? rFull : rSmall)
                    : ((isLastInGroup || isSelfToggled || nextIsToggled) ? rFull : rSmall)

                // Physical Right side radius:
                readonly property real rightRadiusCalc: osdRoot.isLeftPosition
                    ? ((isLastInGroup || isSelfToggled || nextIsToggled) ? rFull : rSmall)
                    : ((isFirstInGroup || isSelfToggled || prevIsToggled) ? rFull : rSmall)

                topLeftRadius: leftRadiusCalc
                bottomLeftRadius: leftRadiusCalc
                topRightRadius: rightRadiusCalc
                bottomRightRadius: rightRadiusCalc

                Behavior on topLeftRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                Behavior on bottomLeftRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                Behavior on topRightRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                Behavior on bottomRightRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }

                Layout.fillWidth: true
            }

            Connections {
                target: root
                function onFocusedScreenChanged() {
                    osdRoot.screen = root.focusedScreen;
                }
            }

            readonly property bool isLeftPosition: (Config.ready && Config.options.osd && Config.options.osd.position === "left")

            WlrLayershell.namespace: "quickshell:onScreenDisplay"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: true
                bottom: true
                right: !osdRoot.isLeftPosition
                left: osdRoot.isLeftPosition
            }
            mask: Region {
                item: osdGroupWrapper
                Region {
                    item: musicCircleContainer
                }
            }

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            readonly property real maxLimit: (root.currentIndicator === "volume") ? ((Config.options.audio && Config.options.audio.protection && Config.options.audio.protection.enable) ? Config.options.audio.protection.maxAllowed / 100 : 1.5) : 1.0

            property bool isExpanded: false
            property real openedProgress: 0.0
            property real expandedProgress: 0.0

            Behavior on openedProgress {
                NumberAnimation {
                    duration: Math.round(300 * Appearance.animMultiplier)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }

            NumberAnimation {
                id: expandAnim
                target: osdRoot
                property: "expandedProgress"
                to: 1.0
                duration: 250
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                id: collapseAnim
                target: osdRoot
                property: "expandedProgress"
                to: 0.0
                duration: 250
                easing.type: Easing.OutCubic
            }

            onIsExpandedChanged: {
                if (osdRoot.isExpanded) {
                    collapseAnim.stop();
                    expandAnim.start();
                } else {
                    expandAnim.stop();
                    collapseAnim.start();
                }
                if (isExpanded)
                    root.triggerOsd();
            }

            Component.onCompleted: {
                root.isClosing = false;
                openedProgress = 1.0;
            }

            Component.onDestruction: {
                root.isClosing = false;
            }

            Connections {
                target: GlobalStates
                function onOsdVolumeOpenChanged() {
                    if (GlobalStates.osdVolumeOpen) {
                        osdRoot.openedProgress = 1.0;
                        root.isClosing = false;
                        // Ensure collapsed state at the start of every open session.
                        // The Loader may reuse the same PanelWindow across rapid
                        // brightness-scroll re-triggers, so we zero out expansion
                        // here before the user sees the OSD.
                        osdRoot.isExpanded = false;
                        osdRoot.expandedProgress = 0.0;
                    } else {
                        root.isClosing = true;
                        osdRoot.openedProgress = 0.0;
                    }
                }
            }

            onOpenedProgressChanged: {
                if (openedProgress === 0.0) {
                    root.isClosing = false;
                }
            }

            onVisibleChanged: {
                if (!visible) {
                    osdRoot.isExpanded = false;
                }
            }

            property bool isDragging: slidersRow.isDragging
            property real displayValue: root.currentValue

            Behavior on displayValue {
                id: displayValueBehavior
                enabled: !osdRoot.isDragging
                SmoothedAnimation {
                    velocity: 4.0
                }
            }

            property bool _mouseInside: false
            property bool _mouseEverInside: false

            function _updateOsdHover(hovered) {
                if (osdRoot._mouseInside === hovered)
                    return;
                osdRoot._mouseInside = hovered;
                if (hovered) {
                    osdRoot._mouseEverInside = true;
                    osdTimeout.stop();
                    osdHoverGraceTimer.stop();
                    if (!GlobalStates.osdVolumeOpen) {
                        GlobalStates.osdVolumeOpen = true;
                    }
                } else {
                    osdHoverGraceTimer.restart();
                }
            }

            Timer {
                id: osdHoverGraceTimer
                interval: 150
                repeat: false
                onTriggered: {
                    if (!osdRoot._mouseInside && !deviceOutputPopup.opened) {
                        root.triggerOsd();
                    }
                }
            }

            Connections {
                target: deviceOutputPopup
                function onOpenedChanged() {
                    if (!deviceOutputPopup.opened && !osdRoot._mouseInside) {
                        osdTimeout.restart();
                    }
                }
            }

            Item {
                id: windowWrapper
                anchors.fill: parent

                Item {
                    id: protectionMessageWrapper
                    anchors.left: osdRoot.isLeftPosition ? osdGroupWrapper.right : undefined
                    anchors.right: !osdRoot.isLeftPosition ? osdGroupWrapper.left : undefined
                    anchors.leftMargin: osdRoot.isLeftPosition ? 12 : undefined
                    anchors.rightMargin: !osdRoot.isLeftPosition ? -12 : undefined
                    anchors.verticalCenter: osdGroupWrapper.verticalCenter
                    implicitHeight: protectionMessageBackground.implicitHeight
                    implicitWidth: protectionMessageBackground.implicitWidth
                    opacity: root.protectionMessage !== "" ? 1 : 0
                    visible: opacity > 0

                    HoverHandler {
                        id: protectionHoverHandler
                        enabled: protectionMessageWrapper.visible
                        onHoveredChanged: osdRoot._updateOsdHover(hovered)
                    }

                    Rectangle {
                        id: protectionMessageBackground
                        anchors.centerIn: parent
                        color: Appearance.m3colors.m3error
                        property real padding: 10
                        implicitHeight: protectionMessageRowLayout.implicitHeight + padding * 2
                        implicitWidth: protectionMessageRowLayout.implicitWidth + padding * 2
                        radius: Appearance.rounding.normal
                        border.width: 0

                        RowLayout {
                            id: protectionMessageRowLayout
                            anchors.centerIn: parent
                            MaterialSymbol {
                                id: protectionMessageIcon
                                text: "dangerous"
                                iconSize: Appearance.font.pixelSize.hugeass
                                color: Appearance.m3colors.m3onError
                            }
                            StyledText {
                                id: protectionMessageTextWidget
                                horizontalAlignment: Text.AlignHCenter
                                color: Appearance.m3colors.m3onError
                                wrapMode: Text.Wrap
                                text: root.protectionMessage
                            }
                        }
                    }
                }

                Item {
                    id: osdGroupWrapper
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: osdRoot.isLeftPosition ? parent.left : undefined
                    anchors.right: !osdRoot.isLeftPosition ? parent.right : undefined
                    anchors.leftMargin: osdRoot.isLeftPosition ? (-width + width * osdRoot.openedProgress) : undefined
                    anchors.rightMargin: !osdRoot.isLeftPosition ? (-width + width * osdRoot.openedProgress) : undefined
                    width: osdContainer.width + 2 * osdMargin
                    height: osdBaseHeight + 2 * osdMargin + (osdGroupWrapper.hasExpandableIndicator ? osdContractedWidth + osdMargin : 0)
                    opacity: osdRoot.openedProgress

                    readonly property bool hasExpandableIndicator: root.currentIndicator === "volume" || root.currentIndicator === "playerVolume" || root.currentIndicator === "brightness" || root.currentIndicator === "gamma"
                    readonly property bool hasTopButton: hasExpandableIndicator || root.currentIndicator === "keyboardBrightness"

                    HoverHandler {
                        id: osdHoverHandler
                        onHoveredChanged: osdRoot._updateOsdHover(hovered)
                    }

                    // (C.2) Drop Shadow
                    StyledDropShadow {
                        id: osdShadow
                        target: osdContainer
                        radius: 24
                        samples: 49
                        color: Appearance.colors.colShadow
                        transparentBorder: true
                    }

                    Rectangle {
                        id: osdContainer
                        anchors.top: parent.top
                        anchors.topMargin: osdMargin
                        anchors.left: osdRoot.isLeftPosition ? parent.left : undefined
                        anchors.leftMargin: osdRoot.isLeftPosition ? osdMargin : undefined
                        anchors.right: !osdRoot.isLeftPosition ? parent.right : undefined
                        anchors.rightMargin: !osdRoot.isLeftPosition ? osdMargin : undefined

                        width: osdContractedWidth + (osdExpandedWidth - osdContractedWidth) * osdRoot.expandedProgress
                        height: osdBaseHeight

                        // Radius interpolated directly from expandedProgress — synchronised with the
                        // master animation. No separate Behavior (it would lag the width growth).
                        // Contracted (expandedProgress=0) -> width/2 (pill shape).
                        // Expanded   (expandedProgress=1) -> windowRounding.
                        radius: (Appearance.rounding.windowRounding - osdContractedWidth / 2) * osdRoot.expandedProgress + osdContractedWidth / 2

                        color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer
                        border.width: 0

                        ColumnLayout {
                            id: osdLayout
                            anchors.fill: parent
                            anchors.margins: osdMargin
                            spacing: osdItemSpacing

                            // (1) Volume Top Row Layout (headphones, disable system sounds, mute sound)
                            RowLayout {
                                id: volumeTopRow
                                visible: root.currentIndicator === "volume"
                                spacing: 4 * osdRoot.expandedProgress
                                Layout.fillWidth: true
                                Layout.preferredHeight: osdButtonHeight
                                Layout.fillHeight: false
                                layoutDirection: osdRoot.isLeftPosition ? Qt.LeftToRight : Qt.RightToLeft

                                RippleButton {
                                    id: muteSoundBtn
                                    Layout.preferredHeight: osdButtonHeight
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: osdButtonHeight + (200 - osdButtonHeight) * osdRoot.expandedProgress
                                    buttonRadius: toggledState ? Appearance.rounding.normal : osdButtonHeight / 2

                                    property bool toggledState: (Audio.sink && Audio.sink.audio) ? Audio.sink.audio.muted : false
                                    colBackground: toggledState ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                    colBackgroundHover: toggledState ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                                    colRipple: toggledState ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive

                                    readonly property color contentColor: toggledState ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

                                    contentItem: RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: osdRoot.expandedProgress > 0.01 ? 16 : 0
                                        anchors.rightMargin: osdRoot.expandedProgress > 0.01 ? 16 : 0
                                        spacing: (muteSoundBtnText.visible ? 8 : 0) * osdRoot.expandedProgress

                                        Item { Layout.fillWidth: true }
                                        MaterialSymbol {
                                             text: muteSoundBtn.toggledState ? "volume_off" : "volume_up"
                                             iconSize: 20
                                             color: muteSoundBtn.contentColor
                                             Layout.alignment: Qt.AlignVCenter | (osdRoot.expandedProgress > 0.01 ? Qt.AlignLeft : Qt.AlignHCenter)
                                             fill: muteSoundBtn.toggledState ? 1.0 : 0.0
                                         }

                                        StyledText {
                                            id: muteSoundBtnText
                                            text: muteSoundBtn.toggledState ? Translation.tr("Unmute sound") : Translation.tr("Mute sound")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: muteSoundBtn.contentColor
                                            visible: osdRoot.expandedProgress > 0.5
                                            opacity: (osdRoot.expandedProgress - 0.5) * 2
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                         Item { Layout.fillWidth: true }
                                    }

                                     onClicked: {
                                         if (Audio.sink && Audio.sink.audio) {
                                             Audio.sink.audio.muted = !Audio.sink.audio.muted;
                                         }
                                         root.triggerOsd();
                                     }

                                     StyledToolTip {
                                         id: muteSoundBtnToolTip
                                         text: muteSoundBtn.toggledState ? Translation.tr("Unmute sound") : Translation.tr("Mute sound")
                                         extraVisibleCondition: !muteSoundBtnText.visible || muteSoundBtnText.truncated
                                     }
                                }

                                Item {
                                    id: expandingTogglesContainerTop
                                    Layout.fillHeight: true
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: (200 + 4 + osdButtonHeight) * osdRoot.expandedProgress
                                    visible: osdRoot.expandedProgress > 0.001
                                    clip: true

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 4
                                        layoutDirection: osdRoot.isLeftPosition ? Qt.LeftToRight : Qt.RightToLeft

                                        OsdMorphToggle {
                                            id: disableSystemSoundsBtn
                                            isFirstInGroup: true
                                            isLastInGroup: false
                                            Layout.fillHeight: true
                                            Layout.fillWidth: true
                                            baseWidth: 200

                                            property bool toggledState: !Config.options.sounds.enable
                                            colBackground: toggledState ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                            colBackgroundHover: toggledState ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                                            colRipple: toggledState ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive

                                            readonly property color contentColor: toggledState ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

                                            contentItem: RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: disableSystemSoundsBtnText.visible ? 8 : 0

                                                Item { Layout.fillWidth: true }
                                                MaterialSymbol {
                                                    text: Config.options.sounds.enable ? "volume_up" : "volume_off"
                                                    iconSize: 20
                                                    color: disableSystemSoundsBtn.contentColor
                                                    Layout.alignment: Qt.AlignVCenter
                                                    fill: disableSystemSoundsBtn.toggledState ? 1.0 : 0.0
                                                }
                                                  StyledText {
                                                      id: disableSystemSoundsBtnText
                                                      text: Config.options.sounds.enable ? Translation.tr("Disable system sounds") : Translation.tr("Enable system sounds")
                                                      font.pixelSize: Appearance.font.pixelSize.small
                                                      color: disableSystemSoundsBtn.contentColor
                                                      elide: Text.ElideRight
                                                      wrapMode: Text.NoWrap
                                                      Layout.fillWidth: true
                                                      Layout.alignment: Qt.AlignVCenter
                                                      visible: parent.width > 60
                                                  }
                                                Item { Layout.fillWidth: true }
                                            }

                                            onClicked: {
                                                Config.options.sounds.enable = !Config.options.sounds.enable;
                                                root.triggerOsd();
                                            }

                                            StyledToolTip {
                                                id: disableSystemSoundsBtnToolTip
                                                text: Config.options.sounds.enable ? Translation.tr("Disable system sounds") : Translation.tr("Enable system sounds")
                                                extraVisibleCondition: !disableSystemSoundsBtnText.visible || disableSystemSoundsBtnText.truncated
                                            }

                                            Component.onCompleted: {
                                                _rightNeighbor = outputDevicesBtn;
                                            }
                                        }

                                        OsdMorphToggle {
                                            id: outputDevicesBtn
                                            isFirstInGroup: false
                                            isLastInGroup: true
                                            Layout.preferredHeight: osdButtonHeight
                                            Layout.fillWidth: false
                                            Layout.preferredWidth: osdButtonHeight
                                            baseWidth: osdButtonHeight

                                            property bool activated: deviceOutputPopup.opened
                                            colBackground: activated ? Appearance.colors.colTertiary : Appearance.colors.colTertiaryContainer
                                            colBackgroundHover: activated ? Appearance.colors.colTertiaryHover : Appearance.colors.colTertiaryContainerHover
                                            colRipple: activated ? Appearance.colors.colTertiaryActive : Appearance.colors.colTertiaryContainerActive

                                            contentItem: MaterialSymbol {
                                                text: "headphones"
                                                iconSize: 20
                                                color: outputDevicesBtn.activated ? Appearance.colors.colOnTertiary : Appearance.colors.colOnTertiaryContainer
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                fill: outputDevicesBtn.activated ? 1.0 : 0.0
                                            }

                                            onClicked: {
                                                deviceOutputPopup._clickActive = !deviceOutputPopup._clickActive;
                                                root.triggerOsd();
                                            }

                                            OsdDeviceOutputPopup {
                                                 id: deviceOutputPopup
                                                 hoverTarget: outputDevicesBtn
                                                 keyboardFocus: WlrKeyboardFocus.Click
                                                 forceClick: true
                                                 customPosition: true
                                                 anchorRight: true
                                                 anchorTop: true
                                                 customMarginRight: osdContainer.width + 6
                                                 customMarginTop: (osdRoot && osdContainer) ? (osdRoot.height - osdContainer.height) / 2 - 10 : 0
                                                 contentHeight: osdContainer.height - 20
                                             }

                                            StyledToolTip {
                                                text: Translation.tr("Output devices")
                                            }

                                            Component.onCompleted: {
                                                _leftNeighbor = disableSystemSoundsBtn;
                                            }
                                        }
                                    }
                                }
                            }

                            // (1c) Brightness Top Row Layout (dark mode, nightlight, auto nightlight)
                            RowLayout {
                                id: brightnessTopRow
                                visible: root.currentIndicator === "brightness"
                                spacing: 4 * osdRoot.expandedProgress
                                Layout.fillWidth: true
                                Layout.preferredHeight: osdButtonHeight
                                Layout.fillHeight: false
                                layoutDirection: osdRoot.isLeftPosition ? Qt.LeftToRight : Qt.RightToLeft

                                RippleButton {
                                    id: darkModeBtn
                                    Layout.preferredHeight: osdButtonHeight
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: osdButtonHeight + (200 - osdButtonHeight) * osdRoot.expandedProgress
                                    buttonRadius: toggledState ? Appearance.rounding.normal : osdButtonHeight / 2

                                    property bool toggledState: Appearance.m3colors.darkmode
                                    colBackground: toggledState ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                    colBackgroundHover: toggledState ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                                    colRipple: toggledState ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive

                                    readonly property color contentColor: toggledState ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

                                    contentItem: RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: osdRoot.expandedProgress > 0.01 ? 16 : 0
                                        anchors.rightMargin: osdRoot.expandedProgress > 0.01 ? 16 : 0
                                        spacing: (darkModeBtnText.visible ? 8 : 0) * osdRoot.expandedProgress

                                        Item { Layout.fillWidth: true }
                                        MaterialSymbol {
                                             text: darkModeBtn.toggledState ? "dark_mode" : "light_mode"
                                             iconSize: 20
                                             color: darkModeBtn.contentColor
                                             Layout.alignment: Qt.AlignVCenter | (osdRoot.expandedProgress > 0.01 ? Qt.AlignLeft : Qt.AlignHCenter)
                                             fill: darkModeBtn.toggledState ? 1.0 : 0.0
                                         }

                                        StyledText {
                                            id: darkModeBtnText
                                            text: darkModeBtn.toggledState ? Translation.tr("Dark mode") : Translation.tr("Light mode")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: darkModeBtn.contentColor
                                            visible: osdRoot.expandedProgress > 0.5
                                            opacity: (osdRoot.expandedProgress - 0.5) * 2
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item { Layout.fillWidth: true }
                                    }

                                    onClicked: {
                                        if (Appearance.m3colors.darkmode) {
                                            DarkModeService.disableDarkMode();
                                        } else {
                                            DarkModeService.enableDarkMode();
                                        }
                                        root.triggerOsd();
                                    }

                                    StyledToolTip {
                                        id: darkModeBtnToolTip
                                        text: darkModeBtn.toggledState ? Translation.tr("Dark mode") : Translation.tr("Light mode")
                                        extraVisibleCondition: !darkModeBtnText.visible || darkModeBtnText.truncated
                                    }
                                }

                                Item {
                                    id: expandingTogglesContainerTopBrightness
                                    Layout.fillHeight: true
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: (200 + 4 + osdButtonHeight) * osdRoot.expandedProgress
                                    visible: osdRoot.expandedProgress > 0.001
                                    clip: true

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 4
                                        layoutDirection: osdRoot.isLeftPosition ? Qt.LeftToRight : Qt.RightToLeft

                                        OsdMorphToggle {
                                            id: nightlightBtn
                                            isFirstInGroup: true
                                            isLastInGroup: false
                                            Layout.fillHeight: true
                                            Layout.fillWidth: true
                                            baseWidth: 200

                                            property bool toggledState: Hyprsunset.temperatureActive
                                            colBackground: toggledState ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                            colBackgroundHover: toggledState ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                                            colRipple: toggledState ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive

                                            readonly property color contentColor: toggledState ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

                                            contentItem: RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: nightlightBtnText.visible ? 8 : 0

                                                Item { Layout.fillWidth: true }
                                                MaterialSymbol {
                                                    text: "wb_twilight"
                                                    iconSize: 20
                                                    color: nightlightBtn.contentColor
                                                    Layout.alignment: Qt.AlignVCenter
                                                    fill: nightlightBtn.toggledState ? 1.0 : 0.0
                                                }
                                                  StyledText {
                                                      id: nightlightBtnText
                                                      text: nightlightBtn.toggledState ? Translation.tr("Disable nightlight") : Translation.tr("Enable nightlight")
                                                      font.pixelSize: Appearance.font.pixelSize.small
                                                      color: nightlightBtn.contentColor
                                                      elide: Text.ElideRight
                                                      wrapMode: Text.NoWrap
                                                      Layout.fillWidth: true
                                                      Layout.alignment: Qt.AlignVCenter
                                                      visible: parent.width > 60
                                                  }
                                                Item { Layout.fillWidth: true }
                                            }

                                            onClicked: {
                                                Hyprsunset.toggleTemperature();
                                                root.triggerOsd();
                                            }

                                            StyledToolTip {
                                                id: nightlightBtnToolTip
                                                text: nightlightBtn.toggledState ? Translation.tr("Disable nightlight") : Translation.tr("Enable nightlight")
                                                extraVisibleCondition: !nightlightBtnText.visible || nightlightBtnText.truncated
                                            }

                                            Component.onCompleted: {
                                                _rightNeighbor = autoNightlightBtn;
                                            }
                                        }

                                         OsdMorphToggle {
                                              id: autoNightlightBtn
                                              isFirstInGroup: false
                                              isLastInGroup: true
                                              Layout.preferredHeight: osdButtonHeight
                                              Layout.fillWidth: false
                                              Layout.preferredWidth: osdButtonHeight
                                              baseWidth: osdButtonHeight

                                             property bool toggledState: Config.options.light.night.automatic
                                             colBackground: toggledState ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                             colBackgroundHover: toggledState ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                                             colRipple: toggledState ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive

                                             readonly property color contentColor: toggledState ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

                                             contentItem: MaterialSymbol {
                                                 text: "schedule"
                                                 iconSize: 20
                                                 color: autoNightlightBtn.contentColor
                                                 horizontalAlignment: Text.AlignHCenter
                                                 verticalAlignment: Text.AlignVCenter
                                                 fill: autoNightlightBtn.toggledState ? 1.0 : 0.0
                                             }

                                             onClicked: {
                                                 Config.options.light.night.automatic = !Config.options.light.night.automatic;
                                                 root.triggerOsd();
                                             }

                                             StyledToolTip {
                                                 text: autoNightlightBtn.toggledState ? Translation.tr("Auto nightlight on") : Translation.tr("Auto nightlight off")
                                             }

                                             Component.onCompleted: {
                                                 _leftNeighbor = nightlightBtn;
                                             }
                                         }
                                    }
                                }
                            }

                            // (1b) Original Top button (for brightness/gamma/keyboard indicators)
                            OsdTopButton {
                                id: topButton
                                visible: root.currentIndicator !== "volume" && root.currentIndicator !== "brightness"
                                currentIndicator: root.currentIndicator
                                expandedProgress: osdRoot.expandedProgress
                                buttonHeight: osdButtonHeight

                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignRight
                                Layout.preferredHeight: buttonHeight
                                Layout.preferredWidth: osdButtonHeight + (parent.width - osdButtonHeight) * osdRoot.expandedProgress
                                onClicked: root.triggerOsd()
                            }

                            // (2) Section title "Output" (no longer used in redesigned volume mode)
                            OsdSectionLabel {
                                text: Translation.tr("Output")
                                visible: false
                                Layout.preferredHeight: 18 * osdRoot.expandedProgress
                                opacity: osdRoot.expandedProgress
                            }

                            // (3) Device output selector button (no longer used here in redesigned volume mode)
                            OsdDeviceOutputButton {
                                id: deviceOutputButton
                                visible: false
                                buttonHeight: osdButtonHeight
                                rootOsd: root

                                Layout.preferredHeight: osdButtonHeight * osdRoot.expandedProgress
                                opacity: osdRoot.expandedProgress
                            }

                            // (4) Section title "Sliders" or "Display"
                            OsdSectionLabel {
                                text: root.currentIndicator === "volume" ? Translation.tr("Sliders") : Translation.tr("Display")
                                visible: false
                                Layout.preferredHeight: 18 * osdRoot.expandedProgress
                                opacity: osdRoot.expandedProgress
                            }

                            // (5) Sliders Row - always visible
                            OsdSlidersRow {
                                id: slidersRow
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                currentIndicator: root.currentIndicator
                                expandedProgress: osdRoot.expandedProgress
                                sliderTrackWidth: osdSliderTrackWidth
                                displayValue: osdRoot.displayValue
                                maxLimit: osdRoot.maxLimit
                                currentIcon: root.currentIcon
                                rootOsd: root
                                osdRoot: osdRoot
                                osdRowSpacing: osdRowSpacing
                                osdGroupSpacing: osdGroupSpacing
                            }

                            // (6) Section title "Audio Options" or "Backlight & Nightlight"
                            OsdSectionLabel {
                                text: root.currentIndicator === "volume" ? Translation.tr("Audio Options") : Translation.tr("Backlight & Nightlight")
                                visible: false
                                Layout.preferredHeight: 18 * osdRoot.expandedProgress
                                opacity: osdRoot.expandedProgress
                            }

                            // (7) Volume Bottom Row Layout (Mute Mic, Easy Effects, Stereo/Mono, Collapse)
                            RowLayout {
                                id: volumeBottomRow
                                visible: root.currentIndicator === "volume"
                                spacing: 4 * osdRoot.expandedProgress
                                Layout.fillWidth: true
                                Layout.preferredHeight: osdButtonHeight
                                Layout.fillHeight: false
                                layoutDirection: osdRoot.isLeftPosition ? Qt.LeftToRight : Qt.RightToLeft

                                OsdCollapseButton {
                                    id: volumeCollapseButton
                                    isExpanded: osdRoot.isExpanded
                                    hasExpandableIndicator: osdGroupWrapper.hasExpandableIndicator
                                    buttonHeight: osdButtonHeight
                                    expandedProgress: osdRoot.expandedProgress
                                    buttonRadius: osdButtonHeight / 2
                                    showText: false

                                    Layout.fillWidth: false
                                    Layout.alignment: Qt.AlignRight
                                    Layout.preferredHeight: osdButtonHeight
                                    Layout.preferredWidth: osdButtonHeight
                                    onClicked: {
                                        osdRoot.isExpanded = !osdRoot.isExpanded;
                                        root.triggerOsd();
                                    }
                                }

                                Item {
                                    id: expandingTogglesContainer
                                    Layout.fillHeight: true
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: osdRoot.osdExtrasMaxWidth * osdRoot.expandedProgress
                                    visible: osdRoot.expandedProgress > 0.001
                                    clip: true

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 4
                                        layoutDirection: osdRoot.isLeftPosition ? Qt.LeftToRight : Qt.RightToLeft

                                        OsdMorphToggle {
                                            id: stereoMonoBtn
                                            isFirstInGroup: true
                                            isLastInGroup: false
                                            Layout.fillHeight: true
                                            Layout.fillWidth: true
                                            baseWidth: 200

                                            property bool toggledState: Config.options.sounds.monoAudio
                                            colBackground: toggledState ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                            colBackgroundHover: toggledState ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                                            colRipple: toggledState ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive

                                            readonly property color contentColor: toggledState ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

                                            contentItem: RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: stereoMonoBtnText.visible ? 8 : 0

                                                Item { Layout.fillWidth: true }
                                                MaterialSymbol {
                                                     text: Config.options.sounds.monoAudio ? "hearing_disabled" : "surround_sound"
                                                     iconSize: 20
                                                     color: stereoMonoBtn.contentColor
                                                     fill: stereoMonoBtn.toggledState ? 1.0 : 0.0
                                                 }
                                                   StyledText {
                                                       id: stereoMonoBtnText
                                                       text: Config.options.sounds.monoAudio ? Translation.tr("Mono") : Translation.tr("Stereo")
                                                       font.pixelSize: Appearance.font.pixelSize.small
                                                       color: stereoMonoBtn.contentColor
                                                       elide: Text.ElideRight
                                                       wrapMode: Text.NoWrap
                                                       Layout.fillWidth: true
                                                       visible: parent.width > 60
                                                   }
                                                Item { Layout.fillWidth: true }
                                            }

                                            onClicked: {
                                                MonoAudioService.toggle();
                                                root.triggerOsd();
                                            }

                                            StyledToolTip {
                                                id: stereoMonoBtnToolTip
                                                text: Config.options.sounds.monoAudio ? Translation.tr("Mono") : Translation.tr("Stereo")
                                                extraVisibleCondition: !stereoMonoBtnText.visible || stereoMonoBtnText.truncated
                                            }

                                            Component.onCompleted: {
                                                _rightNeighbor = easyEffectsBtn;
                                            }
                                        }

                                        OsdMorphToggle {
                                            id: easyEffectsBtn
                                            isFirstInGroup: false
                                            isLastInGroup: false
                                            Layout.fillHeight: true
                                            Layout.fillWidth: true
                                            baseWidth: 200

                                            property bool toggledState: EasyEffects.active
                                            colBackground: toggledState ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                            colBackgroundHover: toggledState ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                                            colRipple: toggledState ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive

                                            readonly property color contentColor: toggledState ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

                                            contentItem: RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: easyEffectsBtnText.visible ? 8 : 0

                                                Item { Layout.fillWidth: true }
                                                 MaterialSymbol {
                                                     text: "graphic_eq"
                                                     iconSize: 20
                                                     color: easyEffectsBtn.contentColor
                                                     fill: easyEffectsBtn.toggledState ? 1.0 : 0.0
                                                 }
                                                    StyledText {
                                                        id: easyEffectsBtnText
                                                        text: EasyEffects.active ? Translation.tr("EasyEffects On") : Translation.tr("EasyEffects Off")
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        color: easyEffectsBtn.contentColor
                                                        elide: Text.ElideRight
                                                        wrapMode: Text.NoWrap
                                                        Layout.fillWidth: true
                                                        visible: parent.width > 60
                                                    }
                                                Item { Layout.fillWidth: true }
                                            }

                                            onClicked: {
                                                EasyEffects.toggle();
                                                root.triggerOsd();
                                            }

                                            StyledToolTip {
                                                id: easyEffectsBtnToolTip
                                                text: EasyEffects.active ? Translation.tr("EasyEffects On") : Translation.tr("EasyEffects Off")
                                                extraVisibleCondition: !easyEffectsBtnText.visible || easyEffectsBtnText.truncated
                                            }

                                            Component.onCompleted: {
                                                _leftNeighbor = stereoMonoBtn;
                                                _rightNeighbor = muteMicBtn;
                                            }
                                        }

                                        OsdMorphToggle {
                                            id: muteMicBtn
                                            isFirstInGroup: false
                                            isLastInGroup: true
                                            Layout.fillHeight: true
                                            Layout.fillWidth: true
                                            baseWidth: 200

                                            property bool toggledState: (Audio.source && Audio.source.audio && Audio.source.audio.muted) ? true : false
                                            colBackground: toggledState ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                            colBackgroundHover: toggledState ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                                            colRipple: toggledState ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive

                                            readonly property color contentColor: toggledState ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

                                            contentItem: RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: muteMicBtnText.visible ? 8 : 0

                                                Item { Layout.fillWidth: true }
                                                MaterialSymbol {
                                                     text: (Audio.source && Audio.source.audio && Audio.source.audio.muted) ? "mic_off" : "mic"
                                                     iconSize: 20
                                                     color: muteMicBtn.contentColor
                                                     fill: muteMicBtn.toggledState ? 1.0 : 0.0
                                                 }
                                                    StyledText {
                                                        id: muteMicBtnText
                                                        text: (Audio.source && Audio.source.audio && Audio.source.audio.muted) ? Translation.tr("Unmute Mic") : Translation.tr("Mute Mic")
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        color: muteMicBtn.contentColor
                                                        elide: Text.ElideRight
                                                        wrapMode: Text.NoWrap
                                                        Layout.fillWidth: true
                                                        visible: parent.width > 60
                                                    }
                                                Item { Layout.fillWidth: true }
                                            }

                                            onClicked: {
                                                Audio.toggleMicMute();
                                                root.triggerOsd();
                                            }

                                            StyledToolTip {
                                                id: muteMicBtnToolTip
                                                text: (Audio.source && Audio.source.audio && Audio.source.audio.muted) ? Translation.tr("Unmute Mic") : Translation.tr("Mute Mic")
                                                extraVisibleCondition: !muteMicBtnText.visible || muteMicBtnText.truncated
                                            }

                                            Component.onCompleted: {
                                                _leftNeighbor = easyEffectsBtn;
                                            }
                                        }
                                    }
                                }
                            }

                            // (7c) Brightness Bottom Row Layout (keyboard backlight, gamma reset, collapse)
                            RowLayout {
                                id: brightnessBottomRow
                                visible: root.currentIndicator === "brightness"
                                spacing: 4 * osdRoot.expandedProgress
                                Layout.fillWidth: true
                                Layout.preferredHeight: osdButtonHeight
                                Layout.fillHeight: false
                                layoutDirection: osdRoot.isLeftPosition ? Qt.LeftToRight : Qt.RightToLeft

                                OsdCollapseButton {
                                    id: brightnessCollapseButton
                                    isExpanded: osdRoot.isExpanded
                                    hasExpandableIndicator: osdGroupWrapper.hasExpandableIndicator
                                    buttonHeight: osdButtonHeight
                                    expandedProgress: osdRoot.expandedProgress
                                    buttonRadius: osdButtonHeight / 2
                                    showText: false

                                    Layout.fillWidth: false
                                    Layout.alignment: Qt.AlignRight
                                    Layout.preferredHeight: osdButtonHeight
                                    Layout.preferredWidth: osdButtonHeight
                                    onClicked: {
                                        osdRoot.isExpanded = !osdRoot.isExpanded;
                                        root.triggerOsd();
                                    }
                                }

                                Item {
                                    id: expandingTogglesContainerBottomBrightness
                                    Layout.fillHeight: true
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: osdRoot.osdExtrasMaxWidth * osdRoot.expandedProgress
                                    visible: osdRoot.expandedProgress > 0.001
                                    clip: true

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 4
                                        layoutDirection: osdRoot.isLeftPosition ? Qt.LeftToRight : Qt.RightToLeft

                                        OsdMorphToggle {
                                            id: keyboardBacklightBtn
                                            isFirstInGroup: true
                                            isLastInGroup: false
                                            Layout.fillHeight: true
                                            Layout.fillWidth: true
                                            baseWidth: 200

                                            property bool toggledState: KeyboardBacklight.currentValue > 0
                                            colBackground: toggledState ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                            colBackgroundHover: toggledState ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                                            colRipple: toggledState ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive

                                            readonly property color contentColor: toggledState ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

                                            contentItem: RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: keyboardBacklightBtnText.visible ? 8 : 0

                                                Item { Layout.fillWidth: true }
                                                MaterialSymbol {
                                                     text: "keyboard"
                                                     iconSize: 20
                                                     color: keyboardBacklightBtn.contentColor
                                                     fill: keyboardBacklightBtn.toggledState ? 1.0 : 0.0
                                                 }
                                                   StyledText {
                                                       id: keyboardBacklightBtnText
                                                       text: KeyboardBacklight.currentValue > 0 ? Translation.tr("Kbd Backlight On") : Translation.tr("Kbd Backlight Off")
                                                       font.pixelSize: Appearance.font.pixelSize.small
                                                       color: keyboardBacklightBtn.contentColor
                                                       elide: Text.ElideRight
                                                       wrapMode: Text.NoWrap
                                                       Layout.fillWidth: true
                                                       visible: parent.width > 60
                                                   }
                                                Item { Layout.fillWidth: true }
                                            }

                                            onClicked: {
                                                if (KeyboardBacklight.available && KeyboardBacklight.ready) {
                                                    KeyboardBacklight.setValue(KeyboardBacklight.currentValue > 0 ? 0 : KeyboardBacklight.maxValue);
                                                }
                                                root.triggerOsd();
                                            }

                                            StyledToolTip {
                                                id: keyboardBacklightBtnToolTip
                                                text: KeyboardBacklight.currentValue > 0 ? Translation.tr("Kbd Backlight On") : Translation.tr("Kbd Backlight Off")
                                                extraVisibleCondition: !keyboardBacklightBtnText.visible || keyboardBacklightBtnText.truncated
                                            }

                                            Component.onCompleted: {
                                                _rightNeighbor = gammaResetBtn;
                                            }
                                        }

                                        OsdMorphToggle {
                                            id: gammaResetBtn
                                            isFirstInGroup: false
                                            isLastInGroup: true
                                            Layout.fillHeight: true
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: osdButtonHeight
                                            baseWidth: 200

                                            property bool toggledState: Hyprsunset.gamma !== 100
                                            colBackground: toggledState ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                            colBackgroundHover: toggledState ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                                            colRipple: toggledState ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive

                                            readonly property color contentColor: toggledState ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

                                            contentItem: RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: gammaResetBtnText.visible ? 8 : 0

                                                Item { Layout.fillWidth: true }
                                                 MaterialSymbol {
                                                     text: "wb_sunny"
                                                     iconSize: 20
                                                     color: gammaResetBtn.contentColor
                                                     fill: gammaResetBtn.toggledState ? 1.0 : 0.0
                                                 }
                                                   StyledText {
                                                       id: gammaResetBtnText
                                                       text: Hyprsunset.gamma !== 100 ? Translation.tr("Low Gamma") : Translation.tr("Normal Gamma")
                                                       font.pixelSize: Appearance.font.pixelSize.small
                                                       color: gammaResetBtn.contentColor
                                                       elide: Text.ElideRight
                                                       wrapMode: Text.NoWrap
                                                       Layout.fillWidth: true
                                                       visible: parent.width > 60
                                                   }
                                                Item { Layout.fillWidth: true }
                                            }

                                            onClicked: {
                                                if (Hyprsunset.gamma === 100) {
                                                    Hyprsunset.setGamma(Hyprsunset.gammaLowerLimit);
                                                } else {
                                                    Hyprsunset.setGamma(100);
                                                }
                                                root.triggerOsd();
                                            }

                                            StyledToolTip {
                                                id: gammaResetBtnToolTip
                                                text: Hyprsunset.gamma !== 100 ? Translation.tr("Low Gamma") : Translation.tr("Normal Gamma")
                                                extraVisibleCondition: !gammaResetBtnText.visible || gammaResetBtnText.truncated
                                            }

                                            Component.onCompleted: {
                                                _leftNeighbor = keyboardBacklightBtn;
                                            }
                                        }
                                    }
                                }
                            }

                            // (7b) Original Toggles Row (for brightness/gamma/keyboard indicators)
                            OsdToggleRow {
                                id: toggleRow
                                Layout.fillWidth: true
                                currentIndicator: root.currentIndicator
                                buttonHeight: osdButtonHeight
                                rootOsd: root

                                Layout.preferredHeight: (root.currentIndicator === "volume" ? (2 * osdButtonHeight + 8) : osdButtonHeight) * osdRoot.expandedProgress
                                opacity: osdRoot.expandedProgress
                                visible: root.currentIndicator !== "volume" && root.currentIndicator !== "brightness" && (root.currentIndicator === "volume" || root.currentIndicator === "brightness") && osdRoot.expandedProgress > 0.01
                            }

                            // (8) Original Collapse button at the bottom right
                            OsdCollapseButton {
                                id: collapseButton
                                isExpanded: osdRoot.isExpanded
                                hasExpandableIndicator: osdGroupWrapper.hasExpandableIndicator
                                buttonHeight: osdCollapseButtonHeight
                                expandedProgress: osdRoot.expandedProgress
                                buttonRadius: osdCollapseButtonHeight / 2

                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignRight
                                Layout.preferredHeight: osdCollapseButtonHeight
                                Layout.preferredWidth: osdCollapseButtonHeight + (parent.width - osdCollapseButtonHeight) * osdRoot.expandedProgress
                                visible: root.currentIndicator !== "volume" && root.currentIndicator !== "brightness"
                                    onClicked: {
                                        osdRoot.isExpanded = !osdRoot.isExpanded;
                                        root.triggerOsd();
                                    }
                            }
                        }
                    }

                    Rectangle {
                        id: musicCircleContainer
                        width: osdRoot ? osdRoot.osdContractedWidth : 80
                        height: osdRoot ? osdRoot.osdContractedWidth : 80
                        radius: width / 2
                        anchors.top: osdContainer.bottom
                        anchors.topMargin: osdMargin
                        anchors.horizontalCenter: osdContainer.horizontalCenter
                        visible: osdGroupWrapper.hasExpandableIndicator && opacity > 0.001
                        opacity: (root.currentIndicator === "volume" || root.currentIndicator === "gamma") && !osdRoot.isExpanded ? osdRoot.openedProgress : 0.0
                        scale: opacity

                        color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer

                        HoverHandler {
                            id: musicCircleContainerHoverHandler
                            onHoveredChanged: osdRoot._updateOsdHover(hovered)
                        }

                        RippleButton {
                            id: musicCircle
                            anchors.centerIn: parent
                            width: osdButtonHeight
                            height: osdButtonHeight
                            buttonRadius: width / 2
                            rippleEnabled: true

                            toggled: {
                                if (root.currentIndicator === "brightness" || root.currentIndicator === "gamma")
                                    return Hyprsunset.temperatureActive;
                                return SongRec.running;
                            }
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            colBackgroundToggled: Appearance.colors.colPrimary
                            colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                            colRipple: Appearance.colors.colSecondaryContainerActive
                            colRippleToggled: Appearance.colors.colPrimaryActive

                            readonly property color contentColor: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

                            contentItem: MaterialSymbol {
                                id: musicIcon
                                text: {
                                    if (root.currentIndicator === "brightness" || root.currentIndicator === "gamma")
                                        return "wb_twilight";
                                    return "music_note";
                                }
                                color: musicCircle.contentColor
                                iconSize: 24
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: {
                                if (root.currentIndicator === "brightness" || root.currentIndicator === "gamma") {
                                    Hyprsunset.toggleTemperature();
                                } else {
                                    SongRec.toggleRunning();
                                }
                                root.triggerOsd();
                            }

                            StyledToolTip {
                                text: {
                                    if (root.currentIndicator === "brightness" || root.currentIndicator === "gamma") {
                                        return Hyprsunset.temperatureActive ? Translation.tr("Disable nightlight") : Translation.tr("Enable nightlight");
                                    }
                                    return SongRec.running ? Translation.tr("Stop music recognition") : Translation.tr("Start music recognition");
                                }
                                extraVisibleCondition: musicCircle.hovered
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "osdVolume"

        function trigger() {
            root.triggerOsd();
        }

        function hide() {
            GlobalStates.osdVolumeOpen = false;
        }

        function toggle() {
            GlobalStates.osdVolumeOpen = !GlobalStates.osdVolumeOpen;
        }

        function expand() {
            if (osdLoader.item)
                osdLoader.item.isExpanded = true;
            root.triggerOsd();
        }

        function collapse() {
            if (osdLoader.item)
                osdLoader.item.isExpanded = false;
            root.triggerOsd();
        }
    }
    GlobalShortcut {
        name: "osdVolumeTrigger"
        description: "Triggers volume OSD on press"

        onPressed: {
            root.triggerOsd();
        }
    }
    GlobalShortcut {
        name: "osdVolumeHide"
        description: "Hides volume OSD on press"

        onPressed: {
            GlobalStates.osdVolumeOpen = false;
        }
    }

    onCurrentIndicatorChanged: GlobalStates.osdCurrentIndicator = currentIndicator
    onProtectionMessageChanged: GlobalStates.osdProtectionMessage = protectionMessage

    Component.onCompleted: {
        GlobalStates.osdCurrentIndicator = currentIndicator;
        GlobalStates.osdProtectionMessage = protectionMessage;
    }
}
