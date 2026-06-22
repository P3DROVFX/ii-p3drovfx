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
    buttonRadius: Appearance.rounding.large

    readonly property int itemIndex: {
        var p = parent;
        if (!p)
            return 0;
        var idx = 0;
        for (var i = 0; i < p.children.length; ++i) {
            if (p.children[i] === root)
                return idx;
            if (p.children[i].visible && typeof p.children[i].topLeftRadius !== "undefined")
                idx++;
        }
        return 0;
    }

    readonly property int totalItems: {
        var p = parent;
        if (!p)
            return 1;
        var count = 0;
        for (var i = 0; i < p.children.length; ++i) {
            if (p.children[i].visible && typeof p.children[i].topLeftRadius !== "undefined")
                count++;
        }
        return count;
    }

    property bool isFirst: itemIndex === 0
    property bool isLast: itemIndex === totalItems - 1

    readonly property bool prevIsPressed: {
        var p = parent;
        if (!p) return false;
        for (var i = 0; i < p.children.length; ++i) {
            var child = p.children[i];
            if (child === root) return false;
            if (child.visible && typeof child.topLeftRadius !== "undefined") {
                var isImmediatePrev = true;
                for (var j = i + 1; j < p.children.length; ++j) {
                    var midChild = p.children[j];
                    if (midChild === root) break;
                    if (midChild.visible && typeof midChild.topLeftRadius !== "undefined") {
                        isImmediatePrev = false;
                        break;
                    }
                }
                if (isImmediatePrev) {
                    return child.isPressed === true || (child.down !== undefined && child.down === true);
                }
            }
        }
        return false;
    }

    readonly property bool nextIsPressed: {
        var p = parent;
        if (!p) return false;
        var foundSelf = false;
        for (var i = 0; i < p.children.length; ++i) {
            var child = p.children[i];
            if (child === root) {
                foundSelf = true;
                continue;
            }
            if (foundSelf && child.visible && typeof child.topLeftRadius !== "undefined") {
                return child.isPressed === true || (child.down !== undefined && child.down === true);
            }
        }
        return false;
    }

    readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(height / 2, Appearance.rounding.large)

    topLeftRadius: (isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    topRightRadius: (isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    bottomLeftRadius: (isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)
    bottomRightRadius: (isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)

    Behavior on topLeftRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }
    Behavior on topRightRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }
    Behavior on bottomLeftRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }
    Behavior on bottomRightRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }

    onClicked: root.openCard()

    property color normalColor: Appearance.colors.colLayer2Base

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
