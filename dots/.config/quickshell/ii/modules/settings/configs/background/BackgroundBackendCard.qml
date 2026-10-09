pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One of two ways to play a video wallpaper, as a card rather than a segment: the chosen one
 * takes the primary container and its shape morphs, and a pill states what the choice costs
 * or buys. The description always reserves `descriptionLines`, so a pair stays level.
 */
Rectangle {
    id: root

    readonly property real padding: 20
    readonly property real headerSpacing: 12
    readonly property real iconSize: 22
    readonly property real iconPadding: 11
    readonly property real blockGap: 12
    readonly property real descriptionOpacity: 0.8
    readonly property real pillHeight: 28
    readonly property real pillPadding: 10
    readonly property real pillTintAlpha: 0.12
    readonly property int descriptionLines: 4

    property string symbol: ""
    property var shapeChosen: MaterialShape.Shape.Cookie12Sided
    property var shapeIdle: MaterialShape.Shape.Circle
    property string title: ""
    property string description: ""
    property string pillSymbol: ""
    property string pillText: ""
    property bool chosen: false

    signal picked()

    readonly property bool engaged: cardHover.hovered
    readonly property color colContent: root.chosen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1

    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    color: root.chosen
        ? (root.engaged ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer)
        : (root.engaged ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: cardHover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: root.picked()
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: root.blockGap

        RowLayout {
            Layout.fillWidth: true
            spacing: root.headerSpacing

            MaterialShapeWrappedMaterialSymbol {
                text: root.chosen ? "check" : root.symbol
                iconSize: root.iconSize
                padding: root.iconPadding
                fill: root.chosen ? 1 : 0
                shape: root.chosen || root.engaged ? root.shapeChosen : root.shapeIdle
                color: root.chosen ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                colSymbol: root.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.larger
                color: root.colContent
                elide: Text.ElideRight
            }
        }

        StyledText {
            id: descriptionText
            Layout.fillWidth: true
            Layout.preferredHeight: descriptionMetrics.height * root.descriptionLines
            text: root.description
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.colContent
            opacity: root.descriptionOpacity
            wrapMode: Text.WordWrap
            maximumLineCount: root.descriptionLines
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop

            FontMetrics {
                id: descriptionMetrics
                font: descriptionText.font
            }
        }

        Rectangle {
            implicitHeight: root.pillHeight
            implicitWidth: pillRow.implicitWidth + root.pillPadding * 2
            radius: height / 2
            color: ColorUtils.applyAlpha(root.colContent, root.pillTintAlpha)

            RowLayout {
                id: pillRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    text: root.pillSymbol
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.colContent
                }
                StyledText {
                    text: root.pillText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: root.colContent
                }
            }
        }
    }
}
