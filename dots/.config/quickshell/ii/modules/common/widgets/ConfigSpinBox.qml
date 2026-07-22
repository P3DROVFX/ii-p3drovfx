import qs.modules.common.widgets
import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property string text: ""
    property string icon
    property alias value: spinBoxWidget.value
    property alias stepSize: spinBoxWidget.stepSize
    property alias from: spinBoxWidget.from
    property alias to: spinBoxWidget.to

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + 32

    color: Appearance.colors.colLayer2

    HoverHandler {
        id: hoverHandler
    }
    property bool hovered: hoverHandler.hovered

    readonly property int itemIndex: {
        if (typeof index !== "undefined") return index;
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
        var p = parent;
        if (!p) return 1;
        if (typeof index !== "undefined" && p.children) {
            var cardCount = 0;
            for (var i = 0; i < p.children.length; ++i) {
                if (typeof p.children[i].isFirst !== "undefined" || typeof p.children[i].topLeftRadius !== "undefined") {
                    cardCount++;
                }
            }
            if (cardCount > 0) return cardCount;
        }
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

    property bool isFirst: (typeof index !== "undefined") ? (index === 0) : (itemIndex === 0)
    property bool isLast: (typeof index !== "undefined") ? (index === totalItems - 1) : (itemIndex === totalItems - 1)

    readonly property bool isPressed: spinBoxWidget.up.pressed || spinBoxWidget.down.pressed

    readonly property bool prevIsPressed: {
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

    readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(height / 2, Appearance.rounding.large)

    topLeftRadius: (isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    topRightRadius: (isPressed || prevIsPressed) ? rFull : (isHorizontalLayout ? (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall) : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall))
    bottomLeftRadius: (isPressed || nextIsPressed) ? rFull : (isHorizontalLayout ? (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall) : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall))
    bottomRightRadius: (isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)

    Behavior on topLeftRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }
    Behavior on topRightRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }
    Behavior on bottomLeftRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }
    Behavior on bottomRightRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }

    HighlightOverlay {
        id: highlightOverlay
        anchors.fill: parent
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        visible: opacity > 0
    }

    ScrollAnimate {}

    RowLayout {
        id: rowLayout
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Loader {
            active: root.icon && root.icon.length > 0
            visible: active
            Layout.alignment: Qt.AlignVCenter
            opacity: root.enabled ? 1 : 0.4

            sourceComponent: MaterialShapeWrappedMaterialSymbol {
                text: root.icon
                readonly property bool isActive: spinBoxWidget.activeFocus || spinBoxWidget.up.pressed || spinBoxWidget.down.pressed
                shape: isActive ? MaterialShape.Shape.Cookie6Sided : MaterialShape.Shape.Circle
                iconSize: 18
                padding: 6
                color: isActive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                colSymbol: isActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3

                Behavior on color {
                    ColorAnimation {
                        duration: 250
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on colSymbol {
                    ColorAnimation {
                        duration: 250
                        easing.type: Easing.OutQuart
                    }
                }
            }
        }

        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            color: Appearance.colors.colOnLayer2
            opacity: root.enabled ? 1 : 0.4
        }

        StyledSpinBox {
            id: spinBoxWidget
            Layout.fillWidth: false
        }
    }
}
