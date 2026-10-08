pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "WorkspacesCatalog.js" as Catalog

/**
 * The numeral systems as type specimens: each card sets its first three numerals,
 * the middle one large, so the choice is made by how they read. The chosen card
 * takes the tertiary container.
 */
Flow {
    id: root

    property string currentValue: "normal"
    property var names: ({})

    readonly property real minCardWidth: 120
    readonly property int columns: Math.max(1, Math.min(Catalog.NUMERALS.length, Math.floor((width + root.spacing) / (root.minCardWidth + root.spacing))))
    readonly property real cardWidth: Math.floor((width - root.spacing * (root.columns - 1)) / root.columns)
    readonly property real cardHeight: 112
    readonly property real bigGlyph: 34
    readonly property real smallGlyph: 17
    readonly property int sample: 3

    property string tried: ""

    signal selected(string value)

    spacing: 8

    Repeater {
        model: Catalog.NUMERALS

        delegate: RippleButton {
            id: card
            required property var modelData
            readonly property bool chosen: root.currentValue === card.modelData.id
            readonly property color colContent: card.chosen ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnLayer1

            implicitWidth: root.cardWidth
            implicitHeight: root.cardHeight
            buttonRadius: card.chosen ? Appearance.rounding.verylarge : Appearance.rounding.large
            buttonRadiusPressed: Appearance.rounding.normal
            colBackground: card.chosen ? Appearance.colors.colTertiaryContainer : Appearance.colors.colLayer1
            colBackgroundHover: card.chosen ? Appearance.colors.colTertiaryContainerHover : Appearance.colors.colLayer1Hover
            colRipple: card.chosen ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colLayer1Active
            onClicked: root.selected(card.modelData.id)
            onHoveredChanged: {
                if (card.hovered)
                    root.tried = card.modelData.id;
                else if (root.tried === card.modelData.id)
                    root.tried = "";
            }

            contentItem: ColumnLayout {
                spacing: 4

                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: root.bigGlyph * 1.3
                    spacing: 6

                    Repeater {
                        model: root.sample
                        delegate: StyledText {
                            required property int index
                            readonly property bool lead: index === 1
                            anchors.verticalCenter: parent.verticalCenter
                            text: Catalog.label(card.modelData.map, index)
                            font.family: Appearance.font.family.title
                            font.pixelSize: lead && (card.hovered || card.chosen) ? root.bigGlyph : root.smallGlyph
                            font.weight: lead ? Font.Black : Font.DemiBold
                            color: card.colContent
                            opacity: lead ? 1 : 0.55
                            Behavior on font.pixelSize {
                                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                            }
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.names[card.modelData.id] ?? card.modelData.id
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: card.colContent
                }
            }
        }
    }
}
