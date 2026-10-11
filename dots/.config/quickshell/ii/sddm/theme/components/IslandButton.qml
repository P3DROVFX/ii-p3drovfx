import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

/**
 * The shell's ToolbarButton (a RippleButton with a full radius): colour states
 * for hover, press and toggled, a radial ripple from the press point clipped to
 * the pill, and the 0.92 press scale.
 */
Button {
    id: root

    property bool toggled: false
    property color colBackground: Theme.transparentize(Theme.colLayer1Hover, 1)
    property color colBackgroundHover: Theme.colLayer1Hover
    property color colBackgroundActive: Theme.colLayer1Active
    property color colBackgroundToggled: Theme.m3primary
    property color colBackgroundToggledHover: Theme.colPrimaryHover
    property color colBackgroundToggledActive: Theme.colPrimaryActive
    property color colRipple: Theme.colLayer1Active
    property color colRippleToggled: Theme.colPrimaryActive
    property bool pointingHandCursor: true
    property real buttonRadius: Theme.roundingFull

    Layout.fillHeight: true
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    padding: 0
    implicitHeight: 30
    opacity: root.enabled ? 1 : 0.4
    scale: root.down ? 0.92 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    readonly property color buttonColor: root.toggled
        ? (root.down ? colBackgroundToggledActive : (root.hovered ? colBackgroundToggledHover : colBackgroundToggled))
        : (root.down ? colBackgroundActive : (root.hovered ? colBackgroundHover : colBackground))
    readonly property color rippleColor: root.toggled ? colRippleToggled : colRipple

    HoverHandler {
        enabled: root.enabled && root.pointingHandCursor
        cursorShape: Qt.PointingHandCursor
    }

    onPressed: {
        const x = root.pressX;
        const y = root.pressY;
        const dist = (ox, oy) => (x - ox) * (x - ox) + (y - oy) * (y - oy);
        rippleAnim.cx = x;
        rippleAnim.cy = y;
        rippleAnim.radius = Math.sqrt(Math.max(dist(0, 0), dist(0, height), dist(width, 0), dist(width, height)));
        rippleFade.stop();
        rippleAnim.restart();
    }
    onReleased: rippleFade.restart()
    onCanceled: rippleFade.restart()

    NumberAnimation {
        id: rippleFade
        target: ripple
        property: "opacity"
        to: 0
        duration: 2400
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.standardDecel
    }

    SequentialAnimation {
        id: rippleAnim
        property real cx
        property real cy
        property real radius
        PropertyAction { target: ripple; property: "x"; value: rippleAnim.cx }
        PropertyAction { target: ripple; property: "y"; value: rippleAnim.cy }
        PropertyAction { target: ripple; property: "opacity"; value: 1 }
        NumberAnimation {
            target: ripple
            property: "size"
            from: 0
            to: rippleAnim.radius * 2
            duration: 1200
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.standardDecel
        }
    }

    background: Rectangle {
        id: buttonBackground
        implicitHeight: 30
        radius: Math.min(root.buttonRadius, height / 2, width / 2)
        color: root.buttonColor
        antialiasing: true
        Behavior on color {
            ColorAnimation {
                duration: Theme.ms(200)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveEffects
            }
        }
        layer.enabled: ripple.rippling
        layer.samples: 8
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: buttonBackground.width
                height: buttonBackground.height
                radius: buttonBackground.radius
                antialiasing: true
            }
        }
        Item {
            id: ripple
            width: size
            height: size
            property real size: 0
            opacity: 0
            visible: rippling
            readonly property bool rippling: opacity > 0 && width > 0
            RadialGradient {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.rippleColor }
                    GradientStop { position: 0.3; color: root.rippleColor }
                    GradientStop { position: 0.5; color: Qt.rgba(root.rippleColor.r, root.rippleColor.g, root.rippleColor.b, 0) }
                }
            }
            transform: Translate {
                x: -ripple.width / 2
                y: -ripple.height / 2
            }
        }
    }
}
