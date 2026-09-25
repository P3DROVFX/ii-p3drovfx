import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * One setting: an icon, what it is, what it does, and the control on the right. Rows in
 * a section share one surface split by small gaps; the outer corners stay large.
 */
Rectangle {
    id: root

    property string symbol: ""
    property string title: ""
    property string description: ""
    property bool first: false
    property bool last: false
    property bool clickable: false
    default property alias control: controlHolder.data

    signal clicked()

    Layout.fillWidth: true
    implicitHeight: Math.max(ClockStyle.topBarHeight, rowLayout.implicitHeight + ClockStyle.gapLarge * 2)
    color: rowMouse.containsMouse && root.clickable ? ClockStyle.colSurfaceHover : ClockStyle.colSurfaceHigh
    topLeftRadius: root.first ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2
    topRightRadius: root.first ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2
    bottomLeftRadius: root.last ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2
    bottomRightRadius: root.last ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: root.clickable
        enabled: root.clickable
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }

    RowLayout {
        id: rowLayout
        anchors {
            fill: parent
            leftMargin: ClockStyle.cardPadding
            rightMargin: ClockStyle.gapLarge
        }
        spacing: ClockStyle.gapLarge

        MaterialSymbol {
            visible: root.symbol.length > 0
            text: root.symbol
            iconSize: ClockStyle.iconNormal
            color: ClockStyle.colOnSurfaceVariant
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.title
                wrapMode: Text.WordWrap
                font.pixelSize: ClockStyle.textNormal + 1
                color: ClockStyle.colOnSurface
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.description.length > 0
                text: root.description
                wrapMode: Text.WordWrap
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }

        RowLayout {
            id: controlHolder
            Layout.alignment: Qt.AlignVCenter
            spacing: ClockStyle.gapSmall
        }
    }
}
