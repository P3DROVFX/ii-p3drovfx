import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell

Rectangle {
    id: root
    property string text: ""
    property string value: ""
    property int targetPageIndex: -1
    property string targetSectionTitle: ""
    property string linkText: Translation.tr("Go there")
    property string materialIcon: "help"

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
    readonly property bool isPressed: false

    readonly property bool prevIsPressed: {
        var p = parent;
        if (!p)
            return false;
        for (var i = 0; i < p.children.length; ++i) {
            var child = p.children[i];
            if (child === root)
                return false;
            if (child.visible && typeof child.topLeftRadius !== "undefined") {
                var isImmediatePrev = true;
                for (var j = i + 1; j < p.children.length; ++j) {
                    var midChild = p.children[j];
                    if (midChild === root)
                        break;
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
        if (!p)
            return false;
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

    Behavior on topLeftRadius {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on topRightRadius {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on bottomLeftRadius {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on bottomRightRadius {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    color: mouseArea.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
    implicitWidth: mainRowLayout.implicitWidth + 32
    implicitHeight: mainRowLayout.implicitHeight + 32

    function navigateToTarget() {
        var win = root.QsWindow.window;
        if (win && win.currentPage !== undefined && root.targetPageIndex >= 0) {
            win.pendingSectionHighlight = root.targetSectionTitle;
            win.currentPage = root.targetPageIndex;
        }
    }

    RowLayout {
        id: mainRowLayout
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        MaterialShapeWrappedMaterialSymbol {
            id: icon
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignVCenter
            text: root.materialIcon
            shape: MaterialShape.Shape.Cookie9Sided
            iconSize: 22
            padding: 8
            color: Appearance.colors.colSecondary
            colSymbol: Appearance.colors.colOnSecondary
        }

        StyledText {
            id: mainText
            Layout.fillWidth: true
            text: root.text !== "" ? root.text : Translation.tr("Looking for %1?").arg(root.value)
            color: Appearance.colors.colOnSecondaryContainer
            wrapMode: Text.WordWrap
        }

        StyledText {
            id: linkLabel
            Layout.alignment: Qt.AlignVCenter
            text: root.linkText
            font.pixelSize: Appearance.font.pixelSize.small
            font.bold: true
            color: Appearance.colors.colPrimary
        }

        MaterialSymbol {
            id: arrowIcon
            Layout.alignment: Qt.AlignVCenter
            text: "arrow_forward"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colPrimary
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.navigateToTarget()
    }
}
