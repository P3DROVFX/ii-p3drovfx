import QtQuick
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common

Item {
    id: gradientBlurRoot

    required property string wallpaperPath

    Loader {
        id: gradientBlurLoader
        active: Config.options.background.gradientBlur.enable && !GlobalStates.screenLocked
        anchors.fill: parent
        visible: active
        sourceComponent: Item {
            anchors.fill: parent

            Image {
                id: gradientBlurSource
                anchors.fill: parent
                source: gradientBlurRoot.wallpaperPath
                fillMode: Image.PreserveAspectCrop
                visible: false
            }

            // Light blur layer — full intensity at start, fading to 0
            Item {
                id: lightBlurWrapper
                anchors.fill: parent
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: lightBlurMask
                }

                FastBlur {
                    anchors.fill: parent
                    source: gradientBlurSource
                    radius: Math.round(Config.options.background.gradientBlur.radius * 0.32)
                    transparentBorder: true
                }
            }

            Item {
                id: lightBlurMask
                anchors.fill: parent
                visible: false

                Canvas {
                    id: lightCanvas
                    anchors.fill: parent
                    readonly property string dir: Config.options.background.gradientBlur.direction

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();

                        var gradient;
                        if (dir === "left-to-right") {
                            gradient = ctx.createLinearGradient(0, 0, width, 0);
                        } else if (dir === "right-to-left") {
                            gradient = ctx.createLinearGradient(width, 0, 0, 0);
                        } else if (dir === "bottom-to-top") {
                            gradient = ctx.createLinearGradient(0, height, 0, 0);
                        } else {
                            gradient = ctx.createLinearGradient(0, 0, 0, height);
                        }

                        gradient.addColorStop(0.0, "rgba(255, 255, 255, 1)");
                        gradient.addColorStop(0.5, "rgba(255, 255, 255, 0.5)");
                        gradient.addColorStop(1.0, "rgba(255, 255, 255, 0)");

                        ctx.fillStyle = gradient;
                        ctx.fillRect(0, 0, width, height);
                    }

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                }
            }

            // Heavy blur layer — 0 at start, full intensity at end
            Item {
                id: heavyBlurWrapper
                anchors.fill: parent
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: heavyBlurMask
                }

                FastBlur {
                    anchors.fill: parent
                    source: gradientBlurSource
                    radius: Math.round(Config.options.background.gradientBlur.radius * 0.64)
                    transparentBorder: true
                }
            }

            Item {
                id: heavyBlurMask
                anchors.fill: parent
                visible: false

                Canvas {
                    id: heavyCanvas
                    anchors.fill: parent
                    readonly property string dir: Config.options.background.gradientBlur.direction

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();

                        var gradient;
                        if (dir === "left-to-right") {
                            gradient = ctx.createLinearGradient(0, 0, width, 0);
                        } else if (dir === "right-to-left") {
                            gradient = ctx.createLinearGradient(width, 0, 0, 0);
                        } else if (dir === "bottom-to-top") {
                            gradient = ctx.createLinearGradient(0, height, 0, 0);
                        } else {
                            gradient = ctx.createLinearGradient(0, 0, 0, height);
                        }

                        gradient.addColorStop(0.0, "rgba(255, 255, 255, 0)");
                        gradient.addColorStop(0.5, "rgba(255, 255, 255, 0.5)");
                        gradient.addColorStop(1.0, "rgba(255, 255, 255, 1)");

                        ctx.fillStyle = gradient;
                        ctx.fillRect(0, 0, width, height);
                    }

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    Connections {
                        target: Config.options.background.gradientBlur
                        function onDirectionChanged() {
                            lightCanvas.requestPaint();
                            heavyCanvas.requestPaint();
                        }
                    }
                }
            }
        }
    }
}
