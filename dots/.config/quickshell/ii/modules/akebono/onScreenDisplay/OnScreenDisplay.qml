import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import qs.modules.lunae
import qs.modules.lunae.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property string protectionMessage: ""
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
    property string currentIndicator: "volume"

    function triggerOsd() {
        GlobalStates.osdVolumeOpen = true;
        if (!(osdLoader.item?.keepOpen ?? false))
            osdTimeout.restart();
    }

    Timer {
        id: osdTimeout
        interval: Config.options.osd.timeout
        repeat: false
        running: false
        onTriggered: {
            if (osdLoader.item?.keepOpen) {
                osdTimeout.restart();
                return;
            }
            GlobalStates.osdVolumeOpen = false;
            root.protectionMessage = "";
        }
    }

    Connections {
        target: Brightness
        function onBrightnessChanged() {
            root.protectionMessage = "";
            root.currentIndicator = "brightness";
            root.triggerOsd();
        }
    }

    Connections {
        target: Hyprsunset
        function onGammaChangeAttempt() {
            root.protectionMessage = "";
            root.currentIndicator = "gamma";
            root.triggerOsd();
        }
    }

    Connections {
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            if (!Audio.ready)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
        function onMutedChanged() {
            if (!Audio.ready)
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

    Loader {
        id: osdLoader
        active: GlobalStates.osdVolumeOpen

        sourceComponent: PanelWindow {
            id: osdRoot
            color: "transparent"
            screen: root.focusedScreen

            readonly property bool topMode: (Config.options.akebono?.shelf.position ?? "bottom") === "top"
            readonly property real shelfClearance: (Config.options.akebono?.shelf.height ?? 54) + Appearance.sizes.hyprlandGapsOut + 14
            readonly property bool keepOpen: contentHover.hovered || primarySlider.pressed || (secondSliderLoader.item?.pressed ?? false)
            property real anim: 0

            WlrLayershell.namespace: "quickshell:onScreenDisplay"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            anchors {
                top: osdRoot.topMode
                bottom: !osdRoot.topMode
            }
            margins {
                top: osdRoot.shelfClearance
                bottom: osdRoot.shelfClearance
            }
            mask: Region {
                item: content
            }
            implicitWidth: content.implicitWidth + 2 * Appearance.sizes.elevationMargin
            implicitHeight: content.implicitHeight + 2 * Appearance.sizes.elevationMargin
            visible: osdLoader.active

            Component.onCompleted: anim = 1

            Behavior on anim {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }

            ColumnLayout {
                id: content
                anchors.centerIn: parent
                spacing: 10
                opacity: osdRoot.anim
                transform: Translate {
                    y: (1 - osdRoot.anim) * (osdRoot.topMode ? -16 : 16)
                }

                HoverHandler {
                    id: contentHover
                }

                Item {
                    visible: root.protectionMessage !== ""
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: protectionRow.implicitWidth + 28
                    implicitHeight: protectionRow.implicitHeight + 18

                    StyledRectangularShadow {
                        target: protectionBg
                    }
                    Squircle {
                        id: protectionBg
                        anchors.fill: parent
                        radius: 16
                        smoothing: AkebonoAppearance.squircleSmoothing
                        color: Appearance.m3colors.m3error
                    }
                    RowLayout {
                        id: protectionRow
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            text: "dangerous"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.m3colors.m3onError
                        }
                        StyledText {
                            color: Appearance.m3colors.m3onError
                            wrapMode: Text.Wrap
                            Layout.maximumWidth: 240
                            text: root.protectionMessage
                        }
                    }
                }

                Item {
                    id: osdPanel
                    Layout.alignment: Qt.AlignHCenter

                    readonly property bool showBoth: Config.options.akebono?.osd.showBoth ?? false
                    readonly property string gifSource: Config.options.akebono?.osd.gifSource ?? ""
                    readonly property bool hasGif: gifSource !== ""
                    readonly property real gifNudgeUp: Config.options.akebono?.osd.gifNudgeUp ?? 0
                    readonly property real gifNudgeRight: Config.options.akebono?.osd.gifNudgeRight ?? 0

                    readonly property real padding: 12
                    readonly property real sliderThickness: 30
                    readonly property real sliderWidth: 150
                    readonly property real gifSize: 72

                    readonly property real contentWidth: {
                        let w = (showBoth ? 2 : 1) * sliderWidth + padding * 2;
                        if (showBoth)
                            w += padding;
                        if (hasGif)
                            w += gifSize + padding;
                        return w;
                    }
                    readonly property real contentHeight: sliderThickness + padding * 2

                    property var brightnessMonitor: Brightness.getMonitorForScreen(root.focusedScreen)

                    readonly property bool isVolume: root.currentIndicator === "volume"
                    readonly property bool isGamma: root.currentIndicator === "gamma"
                    readonly property real volumeValue: Audio.sink?.audio.volume ?? 0
                    readonly property real brightnessValue: brightnessMonitor?.brightness ?? 0.5
                    readonly property real gammaValue: Hyprsunset.gamma / 100
                    readonly property string volumeIcon: (Audio.sink?.audio.muted || volumeValue === 0) ? "volume_off" : "volume_up"
                    readonly property string brightnessIcon: Hyprsunset?.temperatureActive ? "routine" : "light_mode"
                    readonly property string gammaIcon: "wb_twilight"

                    readonly property string primaryIcon: showBoth || isVolume ? volumeIcon : isGamma ? gammaIcon : brightnessIcon
                    readonly property real primaryValue: showBoth || isVolume ? volumeValue : isGamma ? gammaValue : brightnessValue

                    function setPrimaryValue(v: real) {
                        if (showBoth || isVolume)
                            Audio.sink.audio.volume = v;
                        else if (isGamma)
                            Hyprsunset.setGamma(v * 100);
                        else
                            brightnessMonitor?.setBrightness(v);
                    }

                    implicitWidth: contentWidth
                    implicitHeight: contentHeight

                    StyledRectangularShadow {
                        target: panelBg
                    }
                    Rectangle {
                        id: panelBg
                        anchors.fill: parent
                        radius: LunaeAppearance.rounding.panelLarge
                        color: Appearance.colors.colLayer0
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        width: osdPanel.contentWidth - osdPanel.padding * 2
                        height: osdPanel.contentHeight - osdPanel.padding * 2
                        spacing: osdPanel.padding

                        FilledSlider {
                            id: primarySlider
                            orientation: Qt.Horizontal
                            Layout.preferredWidth: osdPanel.sliderWidth
                            Layout.preferredHeight: osdPanel.sliderThickness
                            Layout.alignment: Qt.AlignVCenter
                            icon: osdPanel.primaryIcon
                            value: osdPanel.primaryValue
                            to: osdPanel.isVolume || osdPanel.showBoth ? Audio.hardMaxValue : 1
                            onMoved: osdPanel.setPrimaryValue(value)
                        }

                        Item {
                            visible: osdPanel.hasGif
                            Layout.preferredWidth: osdPanel.gifSize
                            Layout.preferredHeight: osdPanel.sliderThickness
                            Layout.alignment: Qt.AlignVCenter

                            AnimatedImage {
                                width: osdPanel.gifSize
                                height: osdPanel.gifSize
                                anchors.centerIn: parent
                                playing: osdPanel.visible
                                source: osdPanel.gifSource
                                asynchronous: true
                                fillMode: AnimatedImage.PreserveAspectFit
                                transform: Translate {
                                    x: osdPanel.gifNudgeRight
                                    y: -osdPanel.gifNudgeUp
                                }
                            }
                        }

                        Loader {
                            id: secondSliderLoader
                            active: osdPanel.showBoth
                            visible: active
                            Layout.preferredWidth: osdPanel.sliderWidth
                            Layout.preferredHeight: osdPanel.sliderThickness
                            Layout.alignment: Qt.AlignVCenter

                            sourceComponent: FilledSlider {
                                orientation: Qt.Horizontal
                                icon: osdPanel.brightnessIcon
                                value: osdPanel.brightnessValue
                                onMoved: osdPanel.brightnessMonitor?.setBrightness(value)
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
}
