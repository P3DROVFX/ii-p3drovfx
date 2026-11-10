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
    property string targetPageId: ""
    // Deprecated — use targetPageId
    property int targetPageIndex: -1
    property string targetSectionTitle: ""
    property string linkText: Translation.tr("Go there")
    property string materialIcon: "help"

    readonly property GroupPosition groupPosition: GroupPosition {
        item: root
    }
    readonly property int itemIndex: groupPosition.index

    readonly property int totalItems: groupPosition.count

    property bool isFirst: itemIndex === 0
    property bool isLast: itemIndex === totalItems - 1
    readonly property bool isPressed: mouseArea.pressed

    readonly property bool prevIsPressed: groupPosition.previousPressed

    readonly property bool nextIsPressed: groupPosition.nextPressed

    readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(height / 2, Appearance.rounding.large)

    topLeftRadius: (isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    topRightRadius: (isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    bottomLeftRadius: (isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)
    bottomRightRadius: (isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)

    Behavior on topLeftRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on topRightRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on bottomLeftRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on bottomRightRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    color: mouseArea.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
    implicitWidth: mainRowLayout.implicitWidth + 32
    implicitHeight: mainRowLayout.implicitHeight + 32

    function navigateToTarget() {
        var win = root.QsWindow.window;
        if (!win || win.currentPage === undefined)
            return;
        // Prefer the stable page id; targetPageIndex is deprecated
        var idx = (root.targetPageId !== "" && win.pageIndexById !== undefined) ? win.pageIndexById(root.targetPageId) : root.targetPageIndex;
        if (idx >= 0) {
            win.pendingSectionHighlight = root.targetSectionTitle;
            win.currentPage = idx;
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
