pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One choice out of a few that each need a sentence, drawn as a grouped list: the rows share
 * a shape (large outer corners, small joins) and the chosen row becomes a pill that presses
 * a notch into the group, its neighbours rounding towards it. A row's shape morphs when it
 * is chosen. `options`: [{ value, name, description, icon, shape, enabled }].
 */
ColumnLayout {
    id: root

    readonly property real rowPadding: 14
    readonly property real rowSpacing: 2
    readonly property real iconSize: 20
    readonly property real iconPadding: 10
    readonly property real contentSpacing: 14
    readonly property real descriptionOpacity: 0.8
    readonly property real disabledOpacity: 0.45
    readonly property real outer: Appearance.rounding.large
    readonly property real inner: Appearance.rounding.verysmall

    property var options: []
    property var currentValue: null

    signal selected(var value)

    spacing: root.rowSpacing

    Repeater {
        model: root.options

        delegate: Rectangle {
            id: row

            required property var modelData
            required property int index
            readonly property bool chosen: root.currentValue === row.modelData.value
            readonly property bool usable: row.modelData.enabled !== false
            readonly property bool hovered: rowHover.hovered && row.usable
            readonly property bool previousChosen: row.index > 0 && root.currentValue === root.options[row.index - 1].value
            readonly property bool nextChosen: row.index < root.options.length - 1 && root.currentValue === root.options[row.index + 1].value
            readonly property bool roundTop: row.index === 0 || row.chosen || row.previousChosen
            readonly property bool roundBottom: row.index === root.options.length - 1 || row.chosen || row.nextChosen
            readonly property color colContent: row.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2

            Layout.fillWidth: true
            implicitHeight: rowLayout.implicitHeight + root.rowPadding * 2
            opacity: row.usable ? 1 : root.disabledOpacity
            topLeftRadius: row.roundTop ? root.outer : root.inner
            topRightRadius: row.roundTop ? root.outer : root.inner
            bottomLeftRadius: row.roundBottom ? root.outer : root.inner
            bottomRightRadius: row.roundBottom ? root.outer : root.inner
            color: row.chosen
                ? (row.hovered ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                : (row.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on topLeftRadius {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on topRightRadius {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on bottomLeftRadius {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on bottomRightRadius {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            HoverHandler {
                id: rowHover
                cursorShape: row.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
            TapHandler {
                enabled: row.usable
                onTapped: root.selected(row.modelData.value)
            }

            RowLayout {
                id: rowLayout
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: root.rowPadding + 2
                    rightMargin: root.rowPadding + 2
                }
                spacing: root.contentSpacing

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: row.chosen ? "check" : row.modelData.icon
                    iconSize: root.iconSize
                    padding: root.iconPadding
                    fill: row.chosen ? 1 : 0
                    shape: row.chosen ? row.modelData.shape : MaterialShape.Shape.Circle
                    color: row.chosen ? Appearance.colors.colSecondary : Appearance.colors.colLayer3
                    colSymbol: row.chosen ? Appearance.colors.colOnSecondary : Appearance.colors.colOnLayer2
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: row.colContent
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.description
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: row.colContent
                        opacity: root.descriptionOpacity
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
