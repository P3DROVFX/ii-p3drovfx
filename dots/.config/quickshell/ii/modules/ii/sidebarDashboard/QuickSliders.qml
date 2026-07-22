import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.UPower

Rectangle {
    id: root

    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)

    implicitWidth: contentItem.implicitWidth + root.horizontalPadding * 2
    implicitHeight: contentItem.implicitHeight + root.verticalPadding * 2
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    property real verticalPadding: 4
    property real horizontalPadding: 12

    property bool showBrightness: Config.options.sidebar.quickSliders.showBrightness
    property bool showVolume: Config.options.sidebar.quickSliders.showVolume
    property bool showGamma: Config.options.sidebar.quickSliders.showGamma
    property bool showMic: Config.options.sidebar.quickSliders.showMic

    property bool isVertical: Config.options.sidebar.quickSliders.vertical

    property int entranceTrigger: -1

    GridLayout {
        id: contentItem
        anchors {
            fill: parent
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
        }

        rowSpacing: 4
        columnSpacing: 8
        columns: root.isVertical ? 1 : activeCount
        rows: root.isVertical ? activeCount : 1

        readonly property int activeCount: {
            let count = 0;
            if (showBrightness)
                count++;
            if (showVolume)
                count++;
            if (showMic)
                count++;
            if (showGamma)
                count++;
            return count;
        }

        Repeater {
            id: repeater
            model: [
                {
                    show: showBrightness,
                    icon: "brightness_6",
                    getVal: () => root.brightnessMonitor?.brightness ?? 0,
                    setVal: v => root.brightnessMonitor?.setBrightness(v)
                },
                {
                    show: showVolume,
                    icon: "volume_up",
                    getVal: () => (Audio.sink && Audio.sink.audio) ? Audio.sink.audio.volume : 0,
                    setVal: v => {
                        if (Audio.sink && Audio.sink.audio) {
                            Audio.sink.audio.volume = v;
                        }
                    }
                },
                {
                    show: showMic,
                    icon: "mic",
                    getVal: () => (Audio.source && Audio.source.audio) ? Audio.source.audio.volume : 0,
                    setVal: v => {
                        if (Audio.source && Audio.source.audio) {
                            Audio.source.audio.volume = v;
                        }
                    }
                },
                {
                    show: showGamma,
                    icon: "light_mode",
                    secondaryIcon: "wb_twilight",
                    getVal: () => Hyprsunset.gamma === 100 ? 0.3 + (root.brightnessMonitor?.brightness ?? 0) * 0.7 : (Hyprsunset.gamma - Hyprsunset.gammaLowerLimit) / (100 - Hyprsunset.gammaLowerLimit) * 0.3,
                    setVal: v => {
                        if (v >= 0.3) {
                            // 0.3 - 1.0 brightness
                            root.brightnessMonitor?.setBrightness((v - 0.3) / 0.7);
                            if (Hyprsunset.gamma !== 100) {
                                Hyprsunset.setGamma(100);
                            }
                        } else {
                            // 0 - 0.3 gamma
                            if (root.brightnessMonitor && root.brightnessMonitor.brightness !== 0) {
                                root.brightnessMonitor.setBrightness(0);
                            }
                            Hyprsunset.setGamma((v / 0.3 * (100 - Hyprsunset.gammaLowerLimit) + Hyprsunset.gammaLowerLimit));
                        }
                    }
                }
            ]

            QuickSlider {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                visible: modelData.show
                materialSymbol: {
                    if (modelData.icon === "volume_up") {
                        const muted = (Audio.sink && Audio.sink.audio) ? Audio.sink.audio.muted : false;
                        const vol = value;
                        if (muted) return "volume_off";
                        if (vol <= 0.0) return "volume_mute";
                        if (vol <= 0.33) return "volume_mute";
                        if (vol <= 0.66) return "volume_down";
                        return "volume_up";
                    }
                    if (modelData.icon === "brightness_6") {
                        const vol = value;
                        if (vol <= 0.33) return "brightness_low";
                        if (vol <= 0.66) return "brightness_medium";
                        return "brightness_high";
                    }
                    return modelData.icon;
                }
                secondaryMaterialSymbol: modelData?.secondaryIcon ?? ""
                targetValue: modelData.getVal()
                sliderIndex: index
                parentEntranceTrigger: root.entranceTrigger
                onMoved: modelData.setVal(value)
            }
        }
    }

    component QuickSlider: StyledSlider {
        id: quickSlider
        required property string materialSymbol
        property string secondaryMaterialSymbol
        property real targetValue: 0
        property int sliderIndex: 0
        property int parentEntranceTrigger: -1
        property real currentSliderValue: 0

        value: currentSliderValue

        function animateProgress() {
            quickSlider.valueAnimationDuration = 0;
            currentSliderValue = 0;
            sliderDelayTimer.restart();
        }

        Timer {
            id: sliderDelayTimer
            interval: 180 + sliderIndex * 70
            repeat: false
            onTriggered: {
                quickSlider.valueAnimationDuration = 650;
                currentSliderValue = targetValue;
            }
        }

        onParentEntranceTriggerChanged: animateProgress()
        Component.onCompleted: animateProgress()
        configuration: StyledSlider.Configuration.M
        stopIndicatorValues: []
        dividerValues: secondaryMaterialSymbol.length > 0 ? [secondaryIcon.iconLocation] : []

        MaterialShapeWrappedMaterialSymbol {
            id: icon
            property bool nearFull: quickSlider.value >= 0.82
            anchors {
                verticalCenter: quickSlider.verticalCenter
                right: nearFull ? quickSlider.handle.right : quickSlider.right
                rightMargin: nearFull ? 10 : 4
            }
            iconSize: 16
            padding: 4
            shape: MaterialShape.Shape.Cookie7Sided
            text: quickSlider.materialSymbol

            rotation: quickSlider.value * 360

            Behavior on rotation {
                NumberAnimation {
                    duration: 350
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.5
                }
            }

            color: {
                if (quickSlider.value > 1.0) {
                    return Appearance.colors.colErrorContainer;
                }
                return nearFull ? "transparent" : Appearance.colors.colSecondaryContainer;
            }

            colSymbol: {
                if (quickSlider.value > 1.0) {
                    return Appearance.m3colors.m3onErrorContainer;
                }
                return nearFull ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer;
            }

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on colSymbol {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on anchors.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        MaterialSymbol {
            id: secondaryIcon
            visible: secondaryMaterialSymbol.length > 0
            property real iconLocation: 0.3
            property bool nearIcon: iconLocation - quickSlider.value <= 0.1 && iconLocation - quickSlider.value > (quickSlider.handleWidth + 8 - 14) / quickSlider.effectiveDraggingWidth
            anchors {
                verticalCenter: quickSlider.verticalCenter
                right: nearIcon ? quickSlider.handle.right : quickSlider.right
                rightMargin: nearIcon ? 14 : (1 - iconLocation) * quickSlider.effectiveDraggingWidth + quickSlider.rightPadding + 8
            }
            iconSize: 20
            color: quickSlider.value >= iconLocation - 0.1 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            text: secondaryMaterialSymbol

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
