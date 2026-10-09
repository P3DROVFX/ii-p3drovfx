pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Whether a sidebar's panel stays cached in memory, said as one big word instead of an
 * icon-only switch: the word sets itself from light and wide to heavy and condensed as the
 * switch turns on (the variable-font axes follow `boldness`), the card takes the primary
 * container and the header's shape morphs. The header names the sidebar and the panel it
 * holds, so two cards in a row cannot be mistaken for each other.
 */
Rectangle {
    id: root

    readonly property real padding: 20
    readonly property real headerSpacing: 12
    readonly property real iconSize: 22
    readonly property real iconPadding: 11
    readonly property real wordSize: 48
    readonly property real wghtOff: 340
    readonly property real wghtOn: 800
    readonly property real wdthOff: 112
    readonly property real wdthOn: 70
    readonly property real subtitleOpacity: 0.8
    readonly property real summaryOpacity: 0.8

    property string symbol: ""
    property var shapeOn: MaterialShape.Shape.Cookie12Sided
    property var shapeOff: MaterialShape.Shape.Circle
    property string title: ""
    property string subtitle: ""
    property string wordOn: ""
    property string wordOff: ""
    property string summaryOn: ""
    property string summaryOff: ""
    property bool checked: false

    signal toggled(bool value)

    readonly property bool engaged: cardHover.hovered
    readonly property color colContent: root.checked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
    // The spatial curve overshoots; the axes must not.
    property real boldness: root.checked ? 1 : 0
    readonly property real weight: Math.max(0, Math.min(1, root.boldness))
    Behavior on boldness {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    color: root.checked
        ? (root.engaged ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer)
        : (root.engaged ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: cardHover
    }
    // Under the content, so the switch keeps its own click. It owns the cursor: a
    // MouseArea without one would put the arrow back over the whole card.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: root.headerSpacing

            MaterialShapeWrappedMaterialSymbol {
                text: root.symbol
                iconSize: root.iconSize
                padding: root.iconPadding
                fill: root.checked ? 1 : 0
                shape: root.checked ? root.shapeOn : root.shapeOff
                color: root.checked ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                colSymbol: root.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
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
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: root.colContent
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.subtitle
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.colContent
                    opacity: root.subtitleOpacity
                    elide: Text.ElideRight
                }
            }

            StyledSwitch {
                Layout.alignment: Qt.AlignVCenter
                sizeScale: 0.85
                checked: root.checked
                activeColor: Appearance.colors.colPrimary
                activeThumbColor: Appearance.colors.colOnPrimary
                inactiveColor: Appearance.colors.colSurfaceContainerHighest
                onToggled: root.toggled(checked)
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: root.headerSpacing
            text: root.checked ? root.wordOn : root.wordOff
            font.family: Appearance.font.family.main
            font.pixelSize: Math.round(root.wordSize)
            font.variableAxes: ({
                "wght": root.wghtOff + (root.wghtOn - root.wghtOff) * root.weight,
                "wdth": root.wdthOff + (root.wdthOn - root.wdthOff) * root.weight,
                "ROND": 100
            })
            color: root.colContent
            elide: Text.ElideRight
        }

        StyledText {
            id: summaryText
            Layout.fillWidth: true
            // Two lines are always reserved so cards in a row stay level.
            Layout.preferredHeight: summaryMetrics.height * 2
            text: root.checked ? root.summaryOn : root.summaryOff
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.colContent
            opacity: root.summaryOpacity
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop

            FontMetrics {
                id: summaryMetrics
                font: summaryText.font
            }
        }
    }
}
