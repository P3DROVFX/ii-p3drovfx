pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A page of the cheatsheet as a compact toggle row: the secondary container while it is on,
 * with the form-toggle vocabulary of the clock (icon shape swaps to tertiary and morphs
 * into the page's own, the switch takes the secondary accent). The whole card toggles.
 */
Rectangle {
    id: root

    readonly property real padding: 16
    readonly property real iconSize: 20
    readonly property real iconPadding: 10
    readonly property real rowHeight: 76
    readonly property real summaryOpacity: 0.8

    property string symbol: ""
    property var shapeOn: MaterialShape.Shape.Cookie9Sided
    property var shapeOff: MaterialShape.Shape.Circle
    property string title: ""
    property string summary: ""
    property bool checked: false

    signal toggled(bool value)

    readonly property bool engaged: rowHover.hovered
    readonly property color colContent: root.checked ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1

    implicitHeight: root.rowHeight
    radius: Appearance.rounding.large
    color: root.checked
        ? (root.engaged ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
        : (root.engaged ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: rowHover
    }
    // Under the content, so the switch keeps its own click. It owns the cursor: a
    // MouseArea without one would put the arrow back over the whole card.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: root.padding
            rightMargin: root.padding
        }
        spacing: 12

        MaterialShapeWrappedMaterialSymbol {
            text: root.symbol
            iconSize: root.iconSize
            padding: root.iconPadding
            fill: root.checked ? 1 : 0
            shape: root.checked ? root.shapeOn : root.shapeOff
            color: root.checked ? Appearance.colors.colTertiary : Appearance.colors.colSecondaryContainer
            colSymbol: root.checked ? Appearance.colors.colOnTertiary : Appearance.colors.colOnSecondaryContainer
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.normal
                color: root.colContent
                elide: Text.ElideRight
            }
            StyledText {
                id: summaryText
                Layout.fillWidth: true
                text: root.summary
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.colContent
                opacity: root.summaryOpacity
                elide: Text.ElideRight

                StyledToolTip {
                    extraVisibleCondition: summaryText.truncated && rowHover.hovered
                    text: root.summary
                }
            }
        }

        StyledSwitch {
            Layout.alignment: Qt.AlignVCenter
            sizeScale: 0.85
            checked: root.checked
            activeColor: Appearance.colors.colSecondary
            activeThumbColor: Appearance.colors.colOnSecondary
            onToggled: root.toggled(checked)
        }
    }
}
