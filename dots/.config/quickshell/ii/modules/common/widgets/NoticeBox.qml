import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property alias materialIcon: icon.text
    property alias text: noticeText.text
    default property alias boxData: buttonRow.data

    readonly property int itemIndex: {
        var p = parent;
        if (!p) return 0;
        var idx = 0;
        for (var i = 0; i < p.children.length; ++i) {
            if (p.children[i] === root) return idx;
            if (p.children[i].visible && typeof p.children[i].topLeftRadius !== "undefined") idx++;
        }
        return 0;
    }

    readonly property int totalItems: {
        var p = parent;
        if (!p) return 1;
        var count = 0;
        for (var i = 0; i < p.children.length; ++i) {
            if (p.children[i].visible && typeof p.children[i].topLeftRadius !== "undefined") count++;
        }
        return count;
    }

    property bool isFirst: itemIndex === 0
    property bool isLast: itemIndex === totalItems - 1

    readonly property bool isPressed: false

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

    topLeftRadius: (isPressed || prevIsPressed) ? Appearance.rounding.full : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    topRightRadius: (isPressed || prevIsPressed) ? Appearance.rounding.full : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    bottomLeftRadius: (isPressed || nextIsPressed) ? Appearance.rounding.full : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)
    bottomRightRadius: (isPressed || nextIsPressed) ? Appearance.rounding.full : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)

    Behavior on topLeftRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }
    Behavior on topRightRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }
    Behavior on bottomLeftRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }
    Behavior on bottomRightRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root) }

    color: Appearance.colors.colTertiaryContainer
    implicitWidth: mainRowLayout.implicitWidth + mainRowLayout.anchors.margins * 2
    implicitHeight: mainRowLayout.implicitHeight + mainRowLayout.anchors.margins * 2

    RowLayout {
        id: mainRowLayout
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        MaterialShapeWrappedMaterialSymbol {
            id: icon
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignTop
            text: "info"
            shape: MaterialShape.Shape.Slanted
            iconSize: 22
            padding: 8
            color: Appearance.colors.colTertiary
            colSymbol: Appearance.colors.colOnTertiary
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                id: noticeText
                Layout.fillWidth: true
                text: "Notice message"
                color: Appearance.colors.colOnTertiaryContainer
                wrapMode: Text.WordWrap
            }

            RowLayout {
                id: buttonRow
                visible: children.length > 0
                Layout.fillWidth: true 
            }
        }
    }
}
