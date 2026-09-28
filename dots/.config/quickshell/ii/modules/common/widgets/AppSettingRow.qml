import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * One setting: an icon, what it is, what it does, and the control on the right;
 * `below` holds anything that needs the full width (fields, chips, buttons).
 * The outer corners of the first and last *visible* row in a section are large
 * and the joins small, so hiding a row keeps the group's shape.
 */
Rectangle {
    id: row

    property string symbol: ""
    property string title: ""
    property string description: ""
    property string help: ""
    property bool clickable: false
    default property alias control: controlHolder.data
    property alias below: belowHolder.data

    signal clicked()

    // Only rows count: a Repeater in the same column is a visible child too.
    readonly property bool isSettingRow: true
    readonly property var _siblings: parent ? Array.from(parent.visibleChildren).filter(child => child.isSettingRow === true) : []
    readonly property bool first: _siblings.length > 0 && _siblings[0] === row
    readonly property bool last: _siblings.length > 0 && _siblings[_siblings.length - 1] === row
    readonly property real _outer: Appearance.rounding.large
    readonly property real _inner: Appearance.rounding.verysmall

    Layout.fillWidth: true
    implicitHeight: Math.max(56, content.implicitHeight + 20)
    topLeftRadius: row.first ? row._outer : row._inner
    topRightRadius: row.first ? row._outer : row._inner
    bottomLeftRadius: row.last ? row._outer : row._inner
    bottomRightRadius: row.last ? row._outer : row._inner
    color: row.clickable && row.enabled && rowHover.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
    opacity: row.enabled ? 1 : 0.45

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // The cursor lives on the HoverHandler: a TapHandler's cursorShape only
    // shows while it is pressed, so the row read as inert under the pointer.
    HoverHandler {
        id: rowHover
        cursorShape: row.clickable && row.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        enabled: row.clickable
        onTapped: row.clicked()
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 16
        anchors.rightMargin: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            // A row that only carries `below` content (a notice, a button) drops its header.
            visible: row.symbol.length > 0 || row.title.length > 0 || controlHolder.children.length > 0
            spacing: 14

            MaterialSymbol {
                visible: row.symbol.length > 0
                text: row.symbol
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: row.title
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: row.description.length > 0
                    text: row.description
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            Item {
                visible: row.help.length > 0
                implicitWidth: 22
                implicitHeight: 22
                Layout.alignment: Qt.AlignVCenter

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "info"
                    iconSize: Appearance.font.pixelSize.normal
                    color: infoHover.hovered ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                HoverHandler {
                    id: infoHover
                }
                StyledToolTip {
                    text: row.help
                    extraVisibleCondition: infoHover.hovered
                }
            }

            RowLayout {
                id: controlHolder
                Layout.alignment: Qt.AlignVCenter
                spacing: 4
            }
        }

        ColumnLayout {
            id: belowHolder
            Layout.fillWidth: true
            visible: children.length > 0
            spacing: 8
        }
    }
}
