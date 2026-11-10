import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: rootBox
    property string title: ""
    property string text: ""
    property bool expanded: false
    default property alias content: contentContainer.data

    readonly property GroupPosition groupPosition: GroupPosition {
        item: rootBox
    }
    readonly property int itemIndex: groupPosition.index

    readonly property int totalItems: groupPosition.count

    property bool isFirst: itemIndex === 0
    property bool isLast: itemIndex === totalItems - 1

    readonly property bool isPressed: headerMouseArea.pressed

    readonly property bool prevIsPressed: groupPosition.previousPressed

    readonly property bool nextIsPressed: groupPosition.nextPressed

    readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(height / 2, Appearance.rounding.large)

    topLeftRadius: (isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    topRightRadius: (isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    bottomLeftRadius: (isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)
    bottomRightRadius: (isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)

    Behavior on topLeftRadius {
        enabled: rootBox.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on topRightRadius {
        enabled: rootBox.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on bottomLeftRadius {
        enabled: rootBox.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on bottomRightRadius {
        enabled: rootBox.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    color: Appearance.colors.colSecondaryContainer
    implicitWidth: mainColumn.implicitWidth
    implicitHeight: mainColumn.implicitHeight

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    ColumnLayout {
        id: mainColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        // Header Area
        Item {
            id: headerArea
            Layout.fillWidth: true
            Layout.preferredHeight: headerRow.implicitHeight + 24

            MouseArea {
                id: headerMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: rootBox.expanded = !rootBox.expanded
            }

            RowLayout {
                id: headerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 12
                spacing: 12

                MaterialShapeWrappedMaterialSymbol {
                    id: icon
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignTop
                    text: "info"
                    shape: MaterialShape.Shape.Cookie9Sided
                    iconSize: 18
                    padding: 6
                    color: Appearance.colors.colSecondary
                    colSymbol: Appearance.colors.colOnSecondary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnSecondaryContainer
                        font.bold: true
                        visible: rootBox.title !== ""
                        text: rootBox.title
                    }

                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnSecondaryContainer
                        wrapMode: Text.WordWrap
                        visible: rootBox.text !== ""
                        text: rootBox.text
                    }
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: rootBox.expanded ? "keyboard_arrow_up" : "keyboard_arrow_down"
                    iconSize: 24
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }

        // Expanded Content
        Item {
            id: contentWrapper
            Layout.fillWidth: true
            Layout.preferredHeight: rootBox.expanded ? contentContainer.implicitHeight + 12 : 0
            clip: true

            Behavior on Layout.preferredHeight {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            ColumnLayout {
                id: contentContainer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.bottomMargin: 12
                spacing: 6
            }
        }
    }
}
