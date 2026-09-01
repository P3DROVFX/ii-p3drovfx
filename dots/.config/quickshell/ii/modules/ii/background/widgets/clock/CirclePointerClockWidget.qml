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

AbstractBackgroundWidget {
    id: root

    configEntryName: "circle_pointer_clock"

    visibleWhenLocked: root.lockBehavior === "keep"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "circle_pointer_clock")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property real contentScale: (Config.options.background.widgets.circle_pointer_clock.widgetSize ?? 100) / 100.0
    implicitWidth:  240 * contentScale
    implicitHeight: 240 * contentScale

    // ── Config options bound directly to Config ────────────────────────────────
    readonly property bool cfgUseBlackBg:
        Config.ready ? (Config.options.background.widgets.circle_pointer_clock.useBlackBg ?? true) : true
    readonly property bool cfgEnableGlassReflection:
        Config.ready ? (Config.options.background.widgets.circle_pointer_clock.enableGlassReflection ?? false) : false
    readonly property bool cfgShowDots:
        Config.ready ? (Config.options.background.widgets.circle_pointer_clock.showDots ?? true) : true
    readonly property bool cfgBoldFont:
        Config.ready ? (Config.options.background.widgets.circle_pointer_clock.boldFont ?? true) : true

    readonly property color colBg: cfgUseBlackBg ? Appearance.m3colors.m3shadow
                                                : WidgetColorScheme.cardBgColor

    // ── Shadow + Container ────────────────────────────────────────────────────
    StyledDropShadow {
        target: clockBgShape
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Item {
        id: clockContainer
        anchors.centerIn: parent
        width:  root.implicitWidth
        height: root.implicitHeight

        // 1. MaterialShape Circle Background
        MaterialShape {
            id: clockBgShape
            anchors.fill: parent
            shape: MaterialShape.Shape.Circle
            color: root.colBg
        }

        // 2. Dial & Pointer Canvas Overlay
        // Supersampled: this dial is a Canvas, so it rasterises at its own
        // item size. Without this it would be a stretched bitmap the moment
        // the widget is scaled up.
        Supersampled {
            anchors.fill: parent
            factor: root.renderScale
        
            CirclePointerClock {
                anchors.fill: parent
                useBlackBg:            root.cfgUseBlackBg
                enableGlassReflection: root.cfgEnableGlassReflection
                showDots:              root.cfgShowDots
                boldFont:              root.cfgBoldFont
            }
        }

        // ── 3D Glass Dome Reflection ──────────────────────────────────────────
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
                    MaterialShape {
                        anchors.fill: parent
                        shape: MaterialShape.Shape.Circle
                        color: "white"
                    }
                }
            }

            // Top-Right crescent reflection
            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: FastBlur { radius: 28 }

                Shapes.Shape {
                    id: topMaskShape
                    anchors.fill: parent
                    visible: false
                    Shapes.ShapePath {
                        strokeColor: "transparent"
                        fillColor:   "white"
                        startX: parent.width  * 0.40
                        startY: parent.height * 0.04
                        PathArc {
                            x: topMaskShape.width  * 0.96
                            y: topMaskShape.height * 0.60
                            radiusX: topMaskShape.width  * 0.48
                            radiusY: topMaskShape.height * 0.48
                            useLargeArc: false
                        }
                        PathArc {
                            x: topMaskShape.width  * 0.40
                            y: topMaskShape.height * 0.04
                            radiusX: topMaskShape.width  * 0.35
                            radiusY: topMaskShape.height * 0.35
                            useLargeArc: false
                            direction: PathArc.Counterclockwise
                        }
                    }
                }

                LinearGradient {
                    anchors.fill: parent
                    start: Qt.point(width * 0.40, height * 0.04)
                    end:   Qt.point(width * 0.96, height * 0.60)
                    cached: true
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.3; color: ColorUtils.applyAlpha("#FFFFFF", 0.42) }
                        GradientStop { position: 0.7; color: ColorUtils.applyAlpha("#FFFFFF", 0.42) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    layer.enabled: true
                    layer.effect: OpacityMask { maskSource: topMaskShape }
                }
            }

            // Bottom-Left crescent reflection
            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: FastBlur { radius: 28 }

                Shapes.Shape {
                    id: bottomMaskShape
                    anchors.fill: parent
                    visible: false
                    Shapes.ShapePath {
                        strokeColor: "transparent"
                        fillColor:   "white"
                        startX: parent.width  * 0.60
                        startY: parent.height * 0.96
                        PathArc {
                            x: bottomMaskShape.width  * 0.04
                            y: bottomMaskShape.height * 0.40
                            radiusX: bottomMaskShape.width  * 0.48
                            radiusY: bottomMaskShape.height * 0.48
                            useLargeArc: false
                        }
                        PathArc {
                            x: bottomMaskShape.width  * 0.60
                            y: bottomMaskShape.height * 0.96
                            radiusX: bottomMaskShape.width  * 0.35
                            radiusY: bottomMaskShape.height * 0.35
                            useLargeArc: false
                            direction: PathArc.Counterclockwise
                        }
                    }
                }

                LinearGradient {
                    anchors.fill: parent
                    start: Qt.point(width * 0.60, height * 0.96)
                    end:   Qt.point(width * 0.04, height * 0.40)
                    cached: true
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.3; color: ColorUtils.applyAlpha("#FFFFFF", 0.28) }
                        GradientStop { position: 0.7; color: ColorUtils.applyAlpha("#FFFFFF", 0.28) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    layer.enabled: true
                    layer.effect: OpacityMask { maskSource: bottomMaskShape }
                }
            }
        }
    }
}
