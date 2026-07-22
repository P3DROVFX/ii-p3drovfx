import qs.modules.common.widgets
import qs.modules.common
import qs.services
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RippleButton {
    id: root
    property string buttonIcon
    property real iconSize: 18
    property Component extraComponent: null

    Layout.fillWidth: true
    implicitHeight: contentLayout.implicitHeight + 20
    font.pixelSize: Appearance.font.pixelSize.small
    useDynamicRadius: true

    onClicked: checked = !checked

    property color normalColor: Appearance.colors.colLayer2
    property color highlightColor: Appearance.colors.colSecondaryContainer

    colBackground: normalColor
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

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
        radius: root.buttonEffectiveRadius
        color: root.highlightColor
    }

    ScrollAnimate {}

    contentItem: Item {
        anchors.fill: parent

        RowLayout {
            id: contentLayout
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 12

            Loader {
                active: root.buttonIcon && root.buttonIcon.length > 0
                visible: active
                Layout.alignment: Qt.AlignVCenter
                opacity: root.enabled ? 1 : 0.4

                sourceComponent: MaterialShapeWrappedMaterialSymbol {
                    id: iconWidget
                    text: root.buttonIcon
                    shape: root.checked ? MaterialShape.Shape.Cookie4Sided : MaterialShape.Shape.Circle
                    iconSize: 18
                    padding: 6
                    fill: root.checked ? 1 : 0
                    color: root.checked ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                    colSymbol: root.checked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                }
            }

            StyledText {
                id: labelWidget
                Layout.fillWidth: true
                text: root.text
                font.pixelSize: root.font.pixelSize
                color: Appearance.colors.colOnLayer2
                opacity: root.enabled ? 1 : 0.4
                wrapMode: Text.WordWrap
            }

            Loader {
                active: root.extraComponent !== null
                visible: active
                sourceComponent: root.extraComponent
                Layout.alignment: Qt.AlignVCenter
            }

            StyledSwitch {
                id: switchWidget
                Layout.fillWidth: false
                checked: root.checked
                enabled: false
                isPressed: root.isPressed
                opacity: root.enabled ? 1.0 : 0.4
            }
        }
    }
}
