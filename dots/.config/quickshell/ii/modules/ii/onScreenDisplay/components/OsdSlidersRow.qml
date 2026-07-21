import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.topLayer.osd
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

RowLayout {
    id: root

    property string currentIndicator: "volume"
    property real expandedProgress: 0.0
    property real sliderTrackWidth: 38
    property real sliderFillHeight: 180
    property real displayValue: 0.0
    property real maxLimit: 1.0
    property string currentIcon: "volume_up"
    property var rootOsd
    property var osdRoot

    property real osdRowSpacing: 8
    property real osdGroupSpacing: 28

    layoutDirection: Qt.RightToLeft
    spacing: osdRowSpacing * root.expandedProgress

    readonly property bool isDragging: mainVolumeSlider.pressed
        || (notificationSoundSlider.activeFocus && notificationSoundSlider.pressed)
        || (micSlider.activeFocus && micSlider.pressed)
        || (gammaSlider.activeFocus && gammaSlider.pressed)
        || (nightlightSlider.activeFocus && nightlightSlider.pressed)
        || (keyboardBacklightSlider.activeFocus && keyboardBacklightSlider.pressed)

    // (1) Main Slider - Fixo à direita, nunca sofre fade.
    // RightToLeft layout already places this as the rightmost item; no alignment
    // threshold (avoid the > 0.01 snap that previously jogged the slider).
    StyledVerticalSlider {
        id: mainVolumeSlider
        Layout.fillHeight: true
        Layout.preferredWidth: osdRoot ? osdRoot.osdButtonHeight : 56
        configuration: sliderTrackWidth

        from: 0
        to: (root.currentIndicator === "volume" || root.currentIndicator === "playerVolume") ? 1.0 : maxLimit
        value: displayValue
        rawValue: displayValue
        materialSymbol: currentIcon
        usePercentTooltip: false
        tooltipContent: {
            if (root.currentIndicator === "volume" || root.currentIndicator === "playerVolume")
                return Translation.tr("Volume");
            if (root.currentIndicator === "brightness")
                return Translation.tr("Brightness");
            if (root.currentIndicator === "keyboardBrightness")
                return Translation.tr("Keyboard backlight");
            if (root.currentIndicator === "gamma")
                return Translation.tr("Gamma");
            return "";
        }
        shape: {
            if (root.currentIndicator === "volume")
                return MaterialShape.Shape.Cookie7Sided;
            if (root.currentIndicator === "brightness")
                return MaterialShape.Shape.Burst;
            if (root.currentIndicator === "keyboardBrightness")
                return MaterialShape.Shape.Hexagon;
            return MaterialShape.Shape.Circle;
        }

        onMoved: {
            if (rootOsd) {
                rootOsd.updateIndicatorValue(value);
                rootOsd.triggerOsd();
            }
        }
    }

    // (2) Extras Sliders Container - Cresce à esquerda e aplica OpacityMask
    Item {
        id: extrasSliders
        Layout.fillHeight: true
        Layout.preferredWidth: osdRoot ? osdRoot.extrasExpandedWidth * expandedProgress : 0
        visible: expandedProgress > 0.001
        clip: true

        layer.enabled: root.currentIndicator !== "volume" && root.currentIndicator !== "brightness"
        layer.effect: OpacityMask {
            maskSource: extrasFadeMask
        }

        Canvas {
            id: extrasFadeMask
            anchors.fill: parent
            visible: false
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var grad = ctx.createLinearGradient(0, 0, width, 0);
                grad.addColorStop(0.0, Qt.rgba(1, 1, 1, 0.0));
                grad.addColorStop(0.15, Qt.rgba(1, 1, 1, 1.0));
                grad.addColorStop(1.0, Qt.rgba(1, 1, 1, 1.0));
                ctx.fillStyle = grad;
                ctx.fillRect(0, 0, width, height);
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }

        // RowLayout para os Sliders adicionais (RightToLeft)
        RowLayout {
            id: extrasLayout
            anchors.right: parent.right
            height: parent.height
            width: osdRoot ? osdRoot.extrasExpandedWidth : 0
            layoutDirection: Qt.RightToLeft
            spacing: osdRowSpacing

            // ================== VOLUME INDICATOR EXTRAS ==================
            RowLayout {
                layoutDirection: Qt.RightToLeft
                spacing: osdRowSpacing
                visible: root.currentIndicator === "volume"
                Layout.fillHeight: true

                // System Sounds Preview Volume
                StyledVerticalSlider {
                    id: notificationSoundSlider
                    Layout.fillHeight: true
                    Layout.preferredWidth: osdRoot ? osdRoot.osdButtonHeight : 56
                    configuration: sliderTrackWidth

                    from: 0
                    to: 100
                    value: Config.options.sounds.volume
                    rawValue: Config.options.sounds.volume / 100
                    materialSymbol: "notifications"
                    shape: MaterialShape.Shape.Circle
                    usePercentTooltip: false
                    tooltipContent: Translation.tr("System sounds")

                    onMoved: {
                        Config.options.sounds.volume = Math.round(value);
                        if (rootOsd) rootOsd.triggerOsd();
                    }
                }

                // Separador de Grupo (Playback Apps)
                Item {
                    Layout.preferredWidth: osdGroupSpacing - 2 * osdRowSpacing
                    visible: programPlaybackRepeater.count > 0
                }

                // App Playback Sliders
                Repeater {
                    id: programPlaybackRepeater
                    model: Audio.outputAppNodes

                    delegate: OsdProgramSlider {
                        required property var modelData
                        Layout.fillHeight: true
                        Layout.preferredWidth: osdRoot ? osdRoot.osdButtonHeight : 56
                        node: modelData
                    }
                }

                // Separador de Grupo (Microfone)
                Item {
                    Layout.preferredWidth: osdGroupSpacing - 2 * osdRowSpacing
                }

                // Microphone Volume Slider
                StyledVerticalSlider {
                    id: micSlider
                    Layout.fillHeight: true
                    Layout.preferredWidth: osdRoot ? osdRoot.osdButtonHeight : 56
                    configuration: sliderTrackWidth

                    from: 0
                    to: 100
                    usePercentTooltip: false
                    tooltipContent: Translation.tr("Microphone")
                    value: (Audio.source && Audio.source.audio) ? Math.round(Audio.source.audio.volume * 100) : 0
                    rawValue: (Audio.source && Audio.source.audio) ? Audio.source.audio.volume : 0
                    materialSymbol: (Audio.source && Audio.source.audio && Audio.source.audio.muted) ? "mic_off" : "mic"
                    shape: MaterialShape.Shape.Circle

                    onMoved: {
                        if (Audio.source && Audio.source.audio) {
                            Audio.source.audio.volume = value / 100;
                            if (Audio.source.audio.muted && value > 0) {
                                Audio.source.audio.muted = false;
                            }
                        }
                        if (rootOsd) rootOsd.triggerOsd();
                    }
                }
            }

            // ================== BRIGHTNESS INDICATOR EXTRAS ==================
            RowLayout {
                layoutDirection: Qt.RightToLeft
                spacing: osdRowSpacing
                visible: root.currentIndicator === "brightness"
                Layout.fillHeight: true

                // Gamma Slider (immediately next to Brightness)
                StyledVerticalSlider {
                    id: gammaSlider
                    Layout.fillHeight: true
                    Layout.preferredWidth: osdRoot ? osdRoot.osdButtonHeight : 56
                    configuration: sliderTrackWidth

                    from: Hyprsunset.gammaLowerLimit
                    to: 100
                    usePercentTooltip: false
                    tooltipContent: Translation.tr("Gamma")
                    value: Hyprsunset.gamma
                    rawValue: Hyprsunset.gamma / 100
                    materialSymbol: "wb_twilight"
                    shape: MaterialShape.Shape.Circle

                    onMoved: {
                        Hyprsunset.setGamma(Math.round(value));
                        if (rootOsd) rootOsd.triggerOsd();
                    }
                }

                // Separador de Grupo (Nightlight)
                Item {
                    Layout.preferredWidth: osdGroupSpacing - 2 * osdRowSpacing
                }

                // Nightlight temperature slider
                StyledVerticalSlider {
                    id: nightlightSlider
                    Layout.fillHeight: true
                    Layout.preferredWidth: osdRoot ? osdRoot.osdButtonHeight : 56
                    configuration: sliderTrackWidth

                    from: 1000
                    to: 6000
                    usePercentTooltip: false
                    tooltipContent: Translation.tr("Nightlight")
                    value: Config.options.light.night.colorTemperature
                    rawValue: Config.options.light.night.colorTemperature
                    materialSymbol: "wb_iridescent"
                    shape: MaterialShape.Shape.Circle

                    onMoved: {
                        Config.options.light.night.colorTemperature = Math.round(value);
                        if (Math.round(value) === 6000) {
                            Hyprsunset.disableTemperature();
                        } else {
                            Hyprsunset.enableTemperature();
                        }
                        if (rootOsd) rootOsd.triggerOsd();
                    }
                }

                // Separador de Grupo (Keyboard Backlight)
                Item {
                    Layout.preferredWidth: osdGroupSpacing - 2 * osdRowSpacing
                    visible: KeyboardBacklight.available
                }

                // Keyboard Backlight Slider
                StyledVerticalSlider {
                    id: keyboardBacklightSlider
                    Layout.fillHeight: true
                    Layout.preferredWidth: osdRoot ? osdRoot.osdButtonHeight : 56
                    configuration: sliderTrackWidth
                    visible: KeyboardBacklight.available

                    from: 0
                    to: 100
                    usePercentTooltip: false
                    tooltipContent: Translation.tr("Keyboard backlight")
                    value: KeyboardBacklight.percentage
                    rawValue: KeyboardBacklight.percentage / 100
                    materialSymbol: "keyboard"
                    shape: MaterialShape.Shape.Hexagon

                    onMoved: {
                        if (KeyboardBacklight.available && KeyboardBacklight.ready) {
                            const step = Math.round(value * KeyboardBacklight.maxValue / 100);
                            KeyboardBacklight.setValue(step);
                        }
                        if (rootOsd) rootOsd.triggerOsd();
                    }
                }
            }
        }
    }
}
