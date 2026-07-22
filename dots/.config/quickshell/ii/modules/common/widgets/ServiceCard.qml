import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RippleButton {
    id: root

    property string cardIcon: ""
    property real cardHue: 210
    property string cardShape: "Circle"
    property string title: ""
    property string description: ""

    signal openCard()

    Layout.fillWidth: true
    implicitHeight: contentLayout.implicitHeight + 32
    font.pixelSize: Appearance.font.pixelSize.small
    useDynamicRadius: true
    buttonRadius: Appearance.rounding.large

    readonly property bool isHorizontalLayout: {
        var p = parent;
        if (!p) return false;
        var pStr = p.toString();
        return (pStr.indexOf("RowLayout") !== -1 || pStr.indexOf("Row") !== -1) && pStr.indexOf("Column") === -1;
    }

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
            if (children[i].visible && (typeof children[i].topLeftRadius === "undefined" && typeof children[i].isFirst === "undefined")) {
                startIdx = i + 1;
                break;
            }
        }
        
        var idx = 0;
        for (var i = startIdx; i < selfIdx; ++i) {
            if (children[i].visible && (typeof children[i].topLeftRadius !== "undefined" || typeof children[i].isFirst !== "undefined")) {
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
            if (children[i].visible && (typeof children[i].topLeftRadius === "undefined" && typeof children[i].isFirst === "undefined")) {
                startIdx = i + 1;
                break;
            }
        }
        
        var endIdx = children.length - 1;
        for (var i = selfIdx + 1; i < children.length; ++i) {
            if (children[i].visible && (typeof children[i].topLeftRadius === "undefined" && typeof children[i].isFirst === "undefined")) {
                endIdx = i - 1;
                break;
            }
        }
        
        var count = 0;
        for (var i = startIdx; i <= endIdx; ++i) {
            if (children[i].visible && (typeof children[i].topLeftRadius !== "undefined" || typeof children[i].isFirst !== "undefined")) {
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
            if (children[i].visible && (typeof children[i].topLeftRadius === "undefined" && typeof children[i].isFirst === "undefined")) {
                startIdx = i + 1;
                break;
            }
        }
        
        for (var i = selfIdx - 1; i >= startIdx; --i) {
            var child = children[i];
            if (child.visible && (typeof child.topLeftRadius !== "undefined" || typeof child.isFirst !== "undefined")) {
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
            if (children[i].visible && (typeof children[i].topLeftRadius === "undefined" && typeof children[i].isFirst === "undefined")) {
                endIdx = i - 1;
                break;
            }
        }
        
        for (var i = selfIdx + 1; i <= endIdx; ++i) {
            var child = children[i];
            if (child.visible && (typeof child.topLeftRadius !== "undefined" || typeof child.isFirst !== "undefined")) {
                return child.isPressed === true || (child.down !== undefined && child.down === true);
            }
        }
        return false;
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

    onClicked: root.openCard()

    property color normalColor: Appearance.colors.colLayer2

    colBackground: normalColor
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    readonly property color _tint: ColorUtils.categoryContainer(root.cardHue, Appearance.m3colors.m3primaryFixed, 0.5)
    readonly property color _onTint: ColorUtils.categoryOnColor(root._tint, root.cardHue)

    ScrollAnimate {}

    contentItem: Item {
        anchors.fill: parent

        RowLayout {
            id: contentLayout
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 14

            MaterialShape {
                Layout.alignment: Qt.AlignVCenter
                implicitSize: 44
                shapeString: root.cardShape
                color: root._tint

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.cardIcon
                    iconSize: 24
                    color: root._onTint
                    fill: 1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    text: root.title
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                StyledText {
                    text: root.description
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                    opacity: 0.6
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
    }
}
