pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One choice as a row of cards, the Colors page's feature tiles made selectable: the
 * chosen card takes the primary container and its icon's shape morphs from a circle into
 * the card's own; the others stay on the row colour. All in one row, or one column when
 * a card would get narrower than `minCardWidth`.
 *
 *   options: [{ value, title, summary, icon, shape }]
 */
Item {
    id: root

    property var options: []
    property var currentValue: null
    property int minCardWidth: 190
    property int cardHeight: 132

    signal selected(var value)

    readonly property int gap: 8
    readonly property int count: Math.max(1, root.options.length)
    readonly property bool row: (root.width - root.gap * (root.count - 1)) / root.count >= root.minCardWidth
    readonly property int cardWidth: root.row ? Math.floor((root.width - root.gap * (root.count - 1)) / root.count) : root.width

    Layout.fillWidth: true
    implicitHeight: root.row ? root.cardHeight : root.count * root.cardHeight + (root.count - 1) * root.gap

    Repeater {
        model: root.options

        delegate: RippleButton {
            id: card

            required property var modelData
            required property int index
            readonly property bool chosen: root.currentValue === card.modelData.value
            readonly property color colContent: card.chosen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2

            x: root.row ? card.index * (root.cardWidth + root.gap) : 0
            y: root.row ? 0 : card.index * (root.cardHeight + root.gap)
            width: root.cardWidth
            height: root.cardHeight
            buttonRadius: Appearance.rounding.verylarge
            colBackground: card.chosen ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
            colBackgroundHover: card.chosen ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
            colBackgroundActive: card.chosen ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
            colRipple: card.chosen ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
            onClicked: root.selected(card.modelData.value)

            contentItem: Item {
                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: 18
                        topMargin: 16
                    }
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialShapeWrappedMaterialSymbol {
                            text: card.modelData.icon ?? ""
                            iconSize: 22
                            padding: 10
                            fill: card.chosen ? 1 : 0
                            shape: card.chosen ? (card.modelData.shape ?? MaterialShape.Shape.Cookie9Sided) : MaterialShape.Shape.Circle
                            color: card.chosen ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                            colSymbol: card.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignTop
                            text: card.chosen ? "check_circle" : "radio_button_unchecked"
                            fill: card.chosen ? 1 : 0
                            iconSize: 22
                            color: card.chosen ? Appearance.colors.colPrimary : card.colContent
                            opacity: card.chosen ? 1 : 0.5
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: card.modelData.title ?? ""
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: card.colContent
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        text: card.modelData.summary ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: card.colContent
                        opacity: 0.8
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
