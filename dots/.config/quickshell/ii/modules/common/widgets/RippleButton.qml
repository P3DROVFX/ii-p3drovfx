import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls

/**
 * A button with ripple effect similar to in Material Design.
 */
Button {
    id: root
    property bool toggled
    property string buttonText
    property bool pointingHandCursor: true
    property real buttonRadius: Appearance?.rounding?.small ?? 4
    property real buttonRadiusPressed: buttonRadius
    property real buttonEffectiveRadius: root.down ? root.buttonRadiusPressed : root.buttonRadius
    readonly property bool isPressed: root.down
    property int rippleDuration: 1200
    property bool rippleEnabled: true
    property var downAction
    property var releaseAction
    property var altAction
    property var middleClickAction

    property bool useDynamicRadius: false

    readonly property int itemIndex: {
        if (!useDynamicRadius) return 0;
        var p = parent;
        if (!p) return 0;
        var children = p.children;
        var selfIdx = -1;
        for (var i = 0; i < children.length; ++i) {
            if (children[i] === root) {
                selfIdx = i;
                break;
            }
        }
        if (selfIdx === -1) return 0;
        
        var startIdx = 0;
        for (var i = selfIdx - 1; i >= 0; --i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                startIdx = i + 1;
                break;
            }
        }
        
        var idx = 0;
        for (var i = startIdx; i < selfIdx; ++i) {
            if (children[i].visible && typeof children[i].topLeftRadius !== "undefined") {
                idx++;
            }
        }
        return idx;
    }

    readonly property int totalItems: {
        if (!useDynamicRadius) return 1;
        var p = parent;
        if (!p) return 1;
        var children = p.children;
        var selfIdx = -1;
        for (var i = 0; i < children.length; ++i) {
            if (children[i] === root) {
                selfIdx = i;
                break;
            }
        }
        if (selfIdx === -1) return 1;
        
        var startIdx = 0;
        for (var i = selfIdx - 1; i >= 0; --i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                startIdx = i + 1;
                break;
            }
        }
        
        var endIdx = children.length - 1;
        for (var i = selfIdx + 1; i < children.length; ++i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                endIdx = i - 1;
                break;
            }
        }
        
        var count = 0;
        for (var i = startIdx; i <= endIdx; ++i) {
            if (children[i].visible && typeof children[i].topLeftRadius !== "undefined") {
                count++;
            }
        }
        return count;
    }

    property bool isFirst: useDynamicRadius ? (itemIndex === 0) : false
    property bool isLast: useDynamicRadius ? (itemIndex === totalItems - 1) : false

    readonly property bool prevIsPressed: {
        if (!useDynamicRadius) return false;
        var p = parent;
        if (!p) return false;
        var children = p.children;
        var selfIdx = -1;
        for (var i = 0; i < children.length; ++i) {
            if (children[i] === root) {
                selfIdx = i;
                break;
            }
        }
        if (selfIdx <= 0) return false;
        
        var startIdx = 0;
        for (var i = selfIdx - 1; i >= 0; --i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                startIdx = i + 1;
                break;
            }
        }
        
        for (var i = selfIdx - 1; i >= startIdx; --i) {
            var child = children[i];
            if (child.visible && typeof child.topLeftRadius !== "undefined") {
                return child.isPressed === true || (child.down !== undefined && child.down === true);
            }
        }
        return false;
    }

    readonly property bool nextIsPressed: {
        if (!useDynamicRadius) return false;
        var p = parent;
        if (!p) return false;
        var children = p.children;
        var selfIdx = -1;
        for (var i = 0; i < children.length; ++i) {
            if (children[i] === root) {
                selfIdx = i;
                break;
            }
        }
        if (selfIdx === -1 || selfIdx >= children.length - 1) return false;
        
        var endIdx = children.length - 1;
        for (var i = selfIdx + 1; i < children.length; ++i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                endIdx = i - 1;
                break;
            }
        }
        
        for (var i = selfIdx + 1; i <= endIdx; ++i) {
            var child = children[i];
            if (child.visible && typeof child.topLeftRadius !== "undefined") {
                return child.isPressed === true || (child.down !== undefined && child.down === true);
            }
        }
        return false;
    }

    readonly property bool isHorizontalLayout: {
        var p = parent;
        if (!p) return false;
        var pStr = p.toString();
        return (pStr.indexOf("RowLayout") !== -1 || pStr.indexOf("Row") !== -1) && pStr.indexOf("Column") === -1;
    }

    readonly property real rFull: useDynamicRadius ? (Appearance?.rounding?.scale === 0 ? 0 : Math.min(height / 2, Appearance?.rounding?.large ?? 23)) : buttonEffectiveRadius

    property real topLeftRadius: useDynamicRadius ? ((isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance?.rounding?.large ?? 23 : Appearance?.rounding?.verysmall ?? 4)) : buttonEffectiveRadius
    property real topRightRadius: useDynamicRadius ? ((isPressed || prevIsPressed) ? rFull : (isHorizontalLayout ? (isLast ? Appearance?.rounding?.large ?? 23 : Appearance?.rounding?.verysmall ?? 4) : (isFirst ? Appearance?.rounding?.large ?? 23 : Appearance?.rounding?.verysmall ?? 4))) : buttonEffectiveRadius
    property real bottomLeftRadius: useDynamicRadius ? ((isPressed || nextIsPressed) ? rFull : (isHorizontalLayout ? (isFirst ? Appearance?.rounding?.large ?? 23 : Appearance?.rounding?.verysmall ?? 4) : (isLast ? Appearance?.rounding?.large ?? 23 : Appearance?.rounding?.verysmall ?? 4))) : buttonEffectiveRadius
    property real bottomRightRadius: useDynamicRadius ? ((isPressed || nextIsPressed) ? rFull : (isLast ? Appearance?.rounding?.large ?? 23 : Appearance?.rounding?.verysmall ?? 4)) : buttonEffectiveRadius

    Behavior on topLeftRadius { enabled: root.useDynamicRadius; animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }
    Behavior on topRightRadius { enabled: root.useDynamicRadius; animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }
    Behavior on bottomLeftRadius { enabled: root.useDynamicRadius; animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }
    Behavior on bottomRightRadius { enabled: root.useDynamicRadius; animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }

    property color colBackground: ColorUtils.transparentize(Appearance?.colors.colLayer1Hover, 1) || "transparent"
    property color colBackgroundHover: Appearance?.colors.colLayer1Hover ?? "#E5DFED"
    property color colBackgroundActive: Appearance?.colors.colLayer1Active ?? colBackgroundHover
    property color colBackgroundToggled: Appearance?.colors.colPrimary ?? "#65558F"
    property color colBackgroundToggledHover: Appearance?.colors.colPrimaryHover ?? "#77699C"
    property color colBackgroundToggledActive: Appearance?.colors.colPrimaryActive ?? colBackgroundToggledHover
    property color colRipple: Appearance?.colors.colLayer1Active ?? "#D6CEE2"
    property color colRippleToggled: Appearance?.colors.colPrimaryActive ?? "#D6CEE2"

    Behavior on buttonEffectiveRadius {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    opacity: root.enabled ? 1 : 0.4
    property color buttonColor: ColorUtils.transparentize(root.toggled ? (root.down ? colBackgroundToggledActive : (root.hovered ? colBackgroundToggledHover : colBackgroundToggled)) : (root.down ? colBackgroundActive : (root.hovered ? colBackgroundHover : colBackground)), root.enabled ? 0 : 0)
    property color rippleColor: root.toggled ? colRippleToggled : colRipple

    Behavior on opacity {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    scale: root.down ? 0.96 : (root.hovered ? 1.01 : 1.0)
    Behavior on scale {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutQuad
        }
    }

    function startRipple(x, y) {
        const stateY = buttonBackground.y;
        rippleAnim.x = x;
        rippleAnim.y = y - stateY;
        const dist = (ox, oy) => ox * ox + oy * oy;
        const stateEndY = stateY + buttonBackground.height;
        rippleAnim.radius = Math.sqrt(Math.max(dist(0, stateY), dist(0, stateEndY), dist(width, stateY), dist(width, stateEndY)));
        rippleFadeAnim.complete();
        rippleAnim.restart();
    }

    component RippleAnim: NumberAnimation {
        duration: rippleDuration
        easing.type: Appearance?.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance?.animationCurves.standardDecel
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: root.pointingHandCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: event => {
            if (event.button === Qt.RightButton) {
                if (root.altAction)
                    root.altAction(event);
                return;
            }
            if (event.button === Qt.MiddleButton) {
                if (root.middleClickAction)
                    root.middleClickAction();
                return;
            }
            root.down = true;
            if (root.downAction)
                root.downAction();
            if (!root.rippleEnabled)
                return;
            const { x, y } = event;
            startRipple(x, y);
        }
        onReleased: event => {
            root.down = false;
            if (event.button != Qt.LeftButton)
                return;
            if (root.releaseAction)
                root.releaseAction();
            root.click();
            if (!root.rippleEnabled)
                return;
            rippleFadeAnim.restart();
        }
        onCanceled: event => {
            root.down = false;
            if (!root.rippleEnabled)
                return;
            rippleFadeAnim.restart();
        }
    }

    RippleAnim {
        id: rippleFadeAnim
        duration: rippleDuration * 2
        target: ripple
        property: "opacity"
        to: 0
    }

    SequentialAnimation {
        id: rippleAnim
        property real x
        property real y
        property real radius
        PropertyAction { target: ripple; property: "x"; value: rippleAnim.x }
        PropertyAction { target: ripple; property: "y"; value: rippleAnim.y }
        PropertyAction { target: ripple; property: "opacity"; value: 1 }
        ParallelAnimation {
            RippleAnim {
                target: ripple
                properties: "implicitWidth,implicitHeight"
                from: 0
                to: rippleAnim.radius * 2
            }
        }
    }

    background: Rectangle {
        id: buttonBackground
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        implicitHeight: 30
        color: root.buttonColor
        Behavior on color {
            animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        layer.enabled: true
        layer.samples: 8
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: buttonBackground.width
                height: buttonBackground.height
                topLeftRadius: root.topLeftRadius
                topRightRadius: root.topRightRadius
                bottomLeftRadius: root.bottomLeftRadius
                bottomRightRadius: root.bottomRightRadius
                antialiasing: true
            }
        }
        Item {
            id: ripple
            width: ripple.implicitWidth
            height: ripple.implicitHeight
            opacity: 0
            visible: width > 0 && height > 0
            property real implicitWidth: 0
            property real implicitHeight: 0
            Behavior on opacity {
                animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
            }
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

    contentItem: StyledText {
        text: root.buttonText
    }
}
