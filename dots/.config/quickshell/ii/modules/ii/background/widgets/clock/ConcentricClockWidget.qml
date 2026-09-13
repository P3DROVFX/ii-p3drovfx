import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import QtQuick.Shapes as Shapes
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock.minuteMarks
import "concentric"

AbstractBackgroundWidget {
    id: root

    configEntryName: "concentric_clock"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly" || (Config.options.lock.centerWidget === "concentric_clock")
    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property real contentScale: (Config.options.background.widgets.concentric_clock.widgetSize ?? 100) / 100.0
    implicitWidth: 240 * contentScale
    implicitHeight: 240 * contentScale

    // Config options with safe fallbacks
    readonly property string cfgDialStyle: Config.ready ? (Config.options.background.widgets.concentric_clock.dialStyle ?? "concentric") : "concentric"
    readonly property string cfgFrameStyle: Config.ready ? (Config.options.background.widgets.concentric_clock.frameStyle ?? "none") : "none"
    readonly property bool cfgBoldFont: Config.ready ? (Config.options.background.widgets.concentric_clock.boldFont ?? false) : false
    readonly property bool cfgUse24h: Config.ready ? (Config.options.background.widgets.concentric_clock.use24h ?? true) : true
    readonly property bool cfgShowHourText: Config.ready ? (Config.options.background.widgets.concentric_clock.showHourText ?? true) : true

    readonly property string cfgHourHandStyle: Config.ready ? (Config.options.background.widgets.concentric_clock.hourHandStyle ?? "hide") : "hide"
    readonly property string cfgMinuteHandStyle: Config.ready ? (Config.options.background.widgets.concentric_clock.minuteHandStyle ?? "hide") : "hide"
    readonly property string cfgSecondHandStyle: Config.ready ? (Config.options.background.widgets.concentric_clock.secondHandStyle ?? "hide") : "hide"
    readonly property bool cfgShowHourMarks: Config.ready ? (Config.options.background.widgets.concentric_clock.showHourMarks ?? false) : false

    readonly property string cfgMinuteStyle: Config.ready ? (Config.options.background.widgets.concentric_clock.minuteStyle ?? "pill_horizontal") : "pill_horizontal"
    readonly property bool cfgShowArc24h: Config.ready ? (Config.options.background.widgets.concentric_clock.showArc24h ?? false) : false
    readonly property bool cfgShowHourSubDial: Config.ready ? (Config.options.background.widgets.concentric_clock.showHourSubDial ?? false) : false
    readonly property bool cfgShowSunsetDial: Config.ready ? (Config.options.background.widgets.concentric_clock.showSunsetDial ?? false) : false
    readonly property string cfgBottomSubDialContent: Config.ready ? (Config.options.background.widgets.concentric_clock.bottomSubDialContent ?? "weather_temp") : "weather_temp"
    readonly property bool cfgShowMinuteDot: Config.ready ? (Config.options.background.widgets.concentric_clock.showMinuteDot ?? false) : false

    readonly property bool cfgQuoteEnable: Config.ready ? (Config.options.background.widgets.concentric_clock.quoteEnable ?? false) : false
    readonly property string cfgQuoteText: Config.ready ? (Config.options.background.widgets.concentric_clock.quoteText ?? "") : ""
    readonly property bool cfgUseBlackBg: Config.ready ? (Config.options.background.widgets.concentric_clock.useBlackBg ?? false) : false
    readonly property bool cfgEnableGlassReflection: Config.ready ? (Config.options.background.widgets.concentric_clock.enableGlassReflection ?? false) : false
    readonly property real cfgMinutePillLeftMargin: Config.ready ? (Config.options.background.widgets.concentric_clock.minutePillLeftMargin ?? 67) / 100.0 : 0.67
    readonly property real cfgSubdialMarginOffset: Config.ready ? (Config.options.background.widgets.concentric_clock.subdialMarginOffset ?? 5) / 100.0 : 0.05
    readonly property real cfgDialMarginOffset: Config.ready ? (Config.options.background.widgets.concentric_clock.dialMarginOffset ?? 3) / 100.0 : 0.03

    readonly property real cfgHourPixelSize: Config.ready ? (Config.options.background.widgets.concentric_clock.hourPixelSize ?? 30) : 30
    readonly property int cfgHourFontWeight: Config.ready ? (Config.options.background.widgets.concentric_clock.hourFontWeight ?? 600) : 600
    readonly property int cfgHourFontWidth: Config.ready ? (Config.options.background.widgets.concentric_clock.hourFontWidth ?? 85) : 85
    readonly property int cfgHourFontRound: Config.ready ? (Config.options.background.widgets.concentric_clock.hourFontRound ?? 100) : 100

    readonly property color clockBgColor: root.cfgUseBlackBg ? Appearance.m3colors.m3shadow : WidgetColorScheme.cardBgColor

    // Dynamic offset for sub-dials based on dialStyle to prevent overlapping numbers
    readonly property real dialInnerMargin: ((cfgDialStyle === "concentric" || cfgDialStyle === "inner_only" || cfgDialStyle === "full_dense") ? 0.08 : 0.02) + cfgSubdialMarginOffset

    property int clockSecond: DateTime.clock.seconds
    Timer {
        running: root.cfgSecondHandStyle !== "hide"
        repeat: true
        interval: 1000
        onTriggered: root.clockSecond = new Date().getSeconds()
    }

    StyledDropShadow {
        target: clockBgCircle
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Column {
        anchors.centerIn: parent
        spacing: 10

        // Main Clock Container
        Item {
            id: clockContainer
            width: root.implicitWidth
            height: root.implicitHeight

            // Background Circle (Card / Black) with CLIP: TRUE containing all dial elements
            Rectangle {
                id: clockBgCircle
                anchors.fill: parent
                radius: width / 2
                color: WidgetColorScheme.tintBackground(root.clockBgColor)
                clip: true

                // 1. Dial Canvas
                ConcentricDialCanvas {
                    anchors.fill: parent
                    dialStyle: root.cfgDialStyle
                    showMinuteDot: root.cfgShowMinuteDot
                    boldFont: root.cfgBoldFont
                    dialMarginOffset: root.cfgDialMarginOffset
                    hideMinutePillArea: root.cfgMinuteStyle !== "hide"
                }

                // Cookie Clock Big Hour Numbers overlay (Style 7: numbers)
                FadeLoader {
                    anchors.fill: parent
                    shown: root.cfgDialStyle === "numbers"
                    sourceComponent: BigHourNumbers {
                        color: WidgetColorScheme.textColorOnBg
                        numberSize: parent.width * 0.3
                        fontSize: Math.round(parent.width * 0.28)
                        margins: Math.round(parent.width * (0.05 - root.cfgDialMarginOffset))
                    }
                }

                // 2. Outer Frame Overlay
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.color: ColorUtils.applyAlpha(WidgetColorScheme.subtextColorOnBg, root.cfgFrameStyle === "ring_thick" ? 0.35 : 0.2)
                    border.width: root.cfgFrameStyle === "ring_thick" ? 4 : root.cfgFrameStyle === "ring_thin" ? 1.5 : 0
                    visible: root.cfgFrameStyle === "ring_thin" || root.cfgFrameStyle === "ring_thick"
                }

                // Dot Ring Frame Overlay
                Item {
                    anchors.fill: parent
                    visible: root.cfgFrameStyle === "dot_ring"
                    Repeater {
                        model: 60
                        Item {
                            anchors.fill: parent
                            rotation: index * 6
                            Rectangle {
                                width: index % 5 === 0 ? 3 : 1.5
                                height: width
                                radius: width / 2
                                color: ColorUtils.applyAlpha(WidgetColorScheme.subtextColorOnBg, index % 5 === 0 ? 0.6 : 0.3)
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 2
                            }
                        }
                    }
                }

                // 3. Arc 24h (Top)
                FadeLoader {
                    anchors.fill: parent
                    shown: root.cfgShowArc24h
                    sourceComponent: ConcentricArc24h {}
                }

                // 4. Hour Sub-Dial (Bottom-Left 7:30)
                FadeLoader {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: parent.width * (0.16 + root.dialInnerMargin)
                    anchors.bottomMargin: parent.height * (0.20 + root.dialInnerMargin)
                    shown: root.cfgShowHourSubDial
                    sourceComponent: ConcentricSubDial {
                        type: "hour"
                    }
                }

                // 5. Sunset Sub-Dial (Top-Center)
                FadeLoader {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    shown: root.cfgShowSunsetDial
                    sourceComponent: ConcentricSubDial {
                        type: "sunset"
                    }
                }

                // 6. Bottom Complication (Battery / Weather)
                FadeLoader {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: parent.height * (0.06 + root.dialInnerMargin)
                    shown: root.cfgBottomSubDialContent !== "none"
                    sourceComponent: ConcentricComplication {
                        type: root.cfgBottomSubDialContent
                    }
                }

                // 7. Large Hour Display (Centered in widget)
                FadeLoader {
                    anchors.centerIn: parent
                    shown: root.cfgShowHourText
                    sourceComponent: ConcentricHourDisplay {
                        baseWidth: clockContainer.width
                        use24h: root.cfgUse24h
                        boldFont: root.cfgBoldFont
                        customPixelSize: root.cfgHourPixelSize
                        customWeight: root.cfgHourFontWeight
                        customWidth: root.cfgHourFontWidth
                        customRound: root.cfgHourFontRound
                    }
                }

                // 8. Minute Pill (Positioned right at 3:00 / 15 minute tick, clipped by clockBgCircle)
                FadeLoader {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: parent.width * root.cfgMinutePillLeftMargin
                    shown: root.cfgMinuteStyle !== "hide"
                    sourceComponent: ConcentricMinutePill {
                        baseWidth: clockContainer.width
                        minuteStyle: root.cfgMinuteStyle
                        boldFont: root.cfgBoldFont
                    }
                }
            }

            // 9. Hour Marks (Center overlay)
            FadeLoader {
                id: hourMarksLoader
                anchors.centerIn: parent
                shown: root.cfgShowHourMarks
                sourceComponent: HourMarks {
                    implicitSize: parent.width * 0.55
                }
            }

            // 10. Minute Hand (Center overlay)
            FadeLoader {
                anchors.fill: parent
                z: 1
                shown: root.cfgMinuteHandStyle !== "hide"
                sourceComponent: MinuteHand {
                    anchors.fill: parent
                    clockMinute: DateTime.clock.minutes
                    style: root.cfgMinuteHandStyle
                    color: WidgetColorScheme.subtextColorOnBg
                }
            }

            // 11. Hour Hand (Center overlay)
            FadeLoader {
                anchors.fill: parent
                z: (item && item.style === "hollow") ? 0 : 2
                shown: root.cfgHourHandStyle !== "hide"
                sourceComponent: HourHand {
                    clockHour: DateTime.clock.hours % 12
                    clockMinute: DateTime.clock.minutes
                    style: root.cfgHourHandStyle
                    color: WidgetColorScheme.accentColor
                }
            }

            // 12. Second Hand (Center overlay)
            FadeLoader {
                z: (root.cfgSecondHandStyle === "line") ? 2 : 3
                shown: root.cfgSecondHandStyle !== "hide"
                anchors.fill: parent
                sourceComponent: SecondHand {
                    clockSecond: root.clockSecond
                    style: root.cfgSecondHandStyle
                    color: WidgetColorScheme.surfaceVariantColor
                }
            }

            // 13. Center Pivot Dot
            FadeLoader {
                z: 4
                anchors.centerIn: parent
                shown: root.cfgMinuteHandStyle !== "hide" || root.cfgHourHandStyle !== "hide" || root.cfgSecondHandStyle !== "hide"
                sourceComponent: Rectangle {
                    implicitWidth: 6
                    implicitHeight: 6
                    radius: 3
                    color: WidgetColorScheme.pillFillColor
                }
            }

            // 14. 3D Glass Dome Reflection Overlay
            Item {
                id: glassReflectionOverlay
                anchors.fill: parent
                z: 10
                enabled: false
                visible: root.cfgEnableGlassReflection

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Item {
                        width: glassReflectionOverlay.width
                        height: glassReflectionOverlay.height

                        Rectangle {
                            id: outerMaskBase
                            anchors.fill: parent
                            radius: width / 2
                            visible: false
                        }

                        FastBlur {
                            anchors.fill: parent
                            source: outerMaskBase
                            radius: 3
                        }
                    }
                }

                // Top-Right Crescent Reflection
                Item {
                    id: topReflectionContainer
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: FastBlur {
                        radius: 28
                    }

                    Shapes.Shape {
                        id: topMaskShape
                        anchors.fill: parent
                        visible: false

                        Shapes.ShapePath {
                            strokeColor: "transparent"
                            fillColor: "white"
                            startX: parent.width * 0.40
                            startY: parent.height * 0.04
                            PathArc {
                                x: topMaskShape.width * 0.96
                                y: topMaskShape.height * 0.60
                                radiusX: topMaskShape.width * 0.48
                                radiusY: topMaskShape.height * 0.48
                                useLargeArc: false
                            }
                            PathArc {
                                x: topMaskShape.width * 0.40
                                y: topMaskShape.height * 0.04
                                radiusX: topMaskShape.width * 0.35
                                radiusY: topMaskShape.height * 0.35
                                useLargeArc: false
                                direction: PathArc.Counterclockwise
                            }
                        }
                    }

                    LinearGradient {
                        anchors.fill: parent
                        start: Qt.point(width * 0.40, height * 0.04)
                        end: Qt.point(width * 0.96, height * 0.60)
                        cached: true
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: "transparent"
                            }
                            GradientStop {
                                position: 0.3
                                color: ColorUtils.applyAlpha("#FFFFFF", 0.42)
                            }
                            GradientStop {
                                position: 0.7
                                color: ColorUtils.applyAlpha("#FFFFFF", 0.42)
                            }
                            GradientStop {
                                position: 1.0
                                color: "transparent"
                            }
                        }
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: topMaskShape
                        }
                    }
                }

                // Bottom-Left Crescent Reflection
                Item {
                    id: bottomReflectionContainer
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: FastBlur {
                        radius: 28
                    }

                    Shapes.Shape {
                        id: bottomMaskShape
                        anchors.fill: parent
                        visible: false

                        Shapes.ShapePath {
                            strokeColor: "transparent"
                            fillColor: "white"
                            startX: parent.width * 0.60
                            startY: parent.height * 0.96
                            PathArc {
                                x: bottomMaskShape.width * 0.04
                                y: bottomMaskShape.height * 0.40
                                radiusX: bottomMaskShape.width * 0.48
                                radiusY: bottomMaskShape.height * 0.48
                                useLargeArc: false
                            }
                            PathArc {
                                x: bottomMaskShape.width * 0.60
                                y: bottomMaskShape.height * 0.96
                                radiusX: bottomMaskShape.width * 0.35
                                radiusY: bottomMaskShape.height * 0.35
                                useLargeArc: false
                                direction: PathArc.Counterclockwise
                            }
                        }
                    }

                    LinearGradient {
                        anchors.fill: parent
                        start: Qt.point(width * 0.60, height * 0.96)
                        end: Qt.point(width * 0.04, height * 0.40)
                        cached: true
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: "transparent"
                            }
                            GradientStop {
                                position: 0.3
                                color: ColorUtils.applyAlpha("#FFFFFF", 0.28)
                            }
                            GradientStop {
                                position: 0.7
                                color: ColorUtils.applyAlpha("#FFFFFF", 0.28)
                            }
                            GradientStop {
                                position: 1.0
                                color: "transparent"
                            }
                        }
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: bottomMaskShape
                        }
                    }
                }
            }
        }

        // Quote below widget
        FadeLoader {
            anchors.horizontalCenter: parent.horizontalCenter
            shown: root.cfgQuoteEnable && root.cfgQuoteText !== ""
            sourceComponent: CookieQuote {}
        }
    }
}
