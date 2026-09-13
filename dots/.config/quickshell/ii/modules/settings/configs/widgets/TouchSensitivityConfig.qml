import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    readonly property var opts: (Config.options && Config.options.interactions && Config.options.interactions.touchGestures)
        ? Config.options.interactions.touchGestures
        : null

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Touch Sensitivity & Detection")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "tune"
            title: Translation.tr("Sensitivity & Detection")
            tooltip: Translation.tr("Detection thresholds, recognition distances, flick velocity and calibration.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ContentSubsection {
                    icon: "speed"
                    title: Translation.tr("Sensitivity Presets")
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: {
                            if (!root.opts) return "balanced";
                            var e = root.opts.edgeWidth;
                            var c = root.opts.cornerSize;
                            var m = root.opts.minDistance;
                            var cd = root.opts.commitDistance;
                            if (e === 18 && c === 72 && m === 44 && cd === 110) return "balanced";
                            if (e === 12 && c === 56 && m === 60 && cd === 145) return "strict";
                            if (e === 28 && c === 92 && m === 34 && cd === 86) return "relaxed";
                            return "custom";
                        }
                        options: [
                            { displayName: Translation.tr("Balanced"), icon: "balance", value: "balanced" },
                            { displayName: Translation.tr("Strict"), icon: "lock", value: "strict" },
                            { displayName: Translation.tr("Relaxed"), icon: "hotel", value: "relaxed" }
                        ]
                        onSelected: function(preset) {
                            if (!Config.ready || !root.opts) return;
                            if (preset === "balanced") {
                                root.opts.edgeWidth = 18;
                                root.opts.cornerSize = 72;
                                root.opts.minDistance = 44;
                                root.opts.commitDistance = 110;
                                root.opts.velocityThreshold = 650;
                                root.opts.directionTolerance = 35;
                                root.opts.cooldownMs = 250;
                            } else if (preset === "strict") {
                                root.opts.edgeWidth = 12;
                                root.opts.cornerSize = 56;
                                root.opts.minDistance = 60;
                                root.opts.commitDistance = 145;
                                root.opts.velocityThreshold = 850;
                                root.opts.directionTolerance = 25;
                                root.opts.cooldownMs = 350;
                            } else if (preset === "relaxed") {
                                root.opts.edgeWidth = 28;
                                root.opts.cornerSize = 92;
                                root.opts.minDistance = 34;
                                root.opts.commitDistance = 86;
                                root.opts.velocityThreshold = 480;
                                root.opts.directionTolerance = 45;
                                root.opts.cooldownMs = 200;
                            }
                        }
                    }
                }

                ConfigSlider {
                    buttonIcon: "border_left"
                    text: Translation.tr("Edge detection zone (px)")
                    usePercentTooltip: false
                    value: (root.opts && root.opts.edgeWidth) ? root.opts.edgeWidth : 24
                    from: 8
                    to: 64
                    stepSize: 1
                    onValueChanged: {
                        if (Config.ready && root.opts) {
                            root.opts.edgeWidth = Math.round(value);
                            if (isPressed) TouchGestureService.updateCalibration(Math.round(value));
                        }
                    }
                    onIsPressedChanged: {
                        if (isPressed) {
                            TouchGestureService.startCalibration("edgeWidth", Math.round(value));
                        } else {
                            TouchGestureService.stopCalibration();
                        }
                    }
                }

                ConfigSlider {
                    buttonIcon: "crop_square"
                    text: Translation.tr("Corner detection zone (px)")
                    usePercentTooltip: false
                    value: (root.opts && root.opts.cornerSize) ? root.opts.cornerSize : 72
                    from: 32
                    to: 160
                    stepSize: 2
                    onValueChanged: {
                        if (Config.ready && root.opts) {
                            root.opts.cornerSize = Math.round(value);
                            if (isPressed) TouchGestureService.updateCalibration(Math.round(value));
                        }
                    }
                    onIsPressedChanged: {
                        if (isPressed) {
                            TouchGestureService.startCalibration("cornerSize", Math.round(value));
                        } else {
                            TouchGestureService.stopCalibration();
                        }
                    }
                }

                ConfigSlider {
                    buttonIcon: "linear_scale"
                    text: Translation.tr("Minimum travel before recognition (px)")
                    usePercentTooltip: false
                    value: (root.opts && root.opts.minDistance) ? root.opts.minDistance : 44
                    from: 16
                    to: 80
                    stepSize: 2
                    onValueChanged: {
                        if (Config.ready && root.opts) {
                            root.opts.minDistance = Math.round(value);
                            if (isPressed) TouchGestureService.updateCalibration(Math.round(value));
                        }
                    }
                    onIsPressedChanged: {
                        if (isPressed) {
                            TouchGestureService.startCalibration("minDistance", Math.round(value));
                        } else {
                            TouchGestureService.stopCalibration();
                        }
                    }
                }

                ConfigSlider {
                    buttonIcon: "check"
                    text: Translation.tr("Commit activation distance (px)")
                    usePercentTooltip: false
                    value: (root.opts && root.opts.commitDistance) ? root.opts.commitDistance : 110
                    from: 60
                    to: 240
                    stepSize: 5
                    onValueChanged: {
                        if (Config.ready && root.opts) {
                            root.opts.commitDistance = Math.round(value);
                            if (isPressed) TouchGestureService.updateCalibration(Math.round(value));
                        }
                    }
                    onIsPressedChanged: {
                        if (isPressed) {
                            TouchGestureService.startCalibration("commitDistance", Math.round(value));
                        } else {
                            TouchGestureService.stopCalibration();
                        }
                    }
                }

                ConfigSlider {
                    buttonIcon: "bolt"
                    text: Translation.tr("Flick velocity threshold (px/s)")
                    usePercentTooltip: false
                    value: (root.opts && root.opts.velocityThreshold) ? root.opts.velocityThreshold : 650
                    from: 200
                    to: 1600
                    stepSize: 25
                    onValueChanged: {
                        if (Config.ready && root.opts) root.opts.velocityThreshold = Math.round(value);
                    }
                }

                ConfigSlider {
                    buttonIcon: "rotate_90_degrees_ccw"
                    text: Translation.tr("Direction angle tolerance (degrees)")
                    usePercentTooltip: false
                    value: (root.opts && root.opts.directionTolerance) ? root.opts.directionTolerance : 35
                    from: 15
                    to: 60
                    stepSize: 1
                    onValueChanged: {
                        if (Config.ready && root.opts) root.opts.directionTolerance = Math.round(value);
                    }
                }

                ConfigSlider {
                    buttonIcon: "timer"
                    text: Translation.tr("Gesture cooldown (ms)")
                    usePercentTooltip: false
                    value: (root.opts && root.opts.cooldownMs) ? root.opts.cooldownMs : 250
                    from: 100
                    to: 800
                    stepSize: 25
                    onValueChanged: {
                        if (Config.ready && root.opts) root.opts.cooldownMs = Math.round(value);
                    }
                }

                RippleButtonWithIcon {
                    buttonRadius: Appearance.rounding.small
                    materialIcon: "refresh"
                    mainText: Translation.tr("Reset sensitivity to defaults")
                    Layout.topMargin: 8
                    onClicked: {
                        if (Config.ready && root.opts) {
                            root.opts.edgeWidth = 18;
                            root.opts.cornerSize = 72;
                            root.opts.minDistance = 44;
                            root.opts.commitDistance = 110;
                            root.opts.velocityThreshold = 650;
                            root.opts.directionTolerance = 35;
                            root.opts.cooldownMs = 250;
                        }
                    }
                }
            }
        }
    }
}
