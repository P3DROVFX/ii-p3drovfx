pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "WorkspaceNumerals.js" as Numerals
import "WorkspacesGrid.js" as GridMath

/**
 * The glyphs a workspace is numbered with. Pure type: each card sets the same five
 * sample ids (1 to 5) in its own numerals, and the chosen one grows heavier.
 */
WorkspacesPane {
    id: root

    readonly property int gap: 10
    readonly property real minCell: 132
    readonly property real cardHeight: 96
    readonly property real cardPadding: 14
    readonly property real sampleSize: Appearance.font.pixelSize.large
    readonly property var axesIdle: ({ "wght": 640, "wdth": 100, "ROND": 100 })
    readonly property var axesChosen: ({ "wght": 820, "wdth": 90, "ROND": 100 })

    property string hoveredId: ""

    readonly property var systems: [
        { "id": "normal", "label": Translation.tr("Normal") },
        { "id": "han", "label": Translation.tr("Han chars") },
        { "id": "roman", "label": Translation.tr("Roman") },
        { "id": "greek", "label": Translation.tr("Greek") },
        { "id": "rods", "label": Translation.tr("Counting rods") }
    ]
    readonly property string currentId: Numerals.idFor(Config.options.bar.workspaces.numberMap)
    readonly property var currentEntry: root.systems.find(entry => entry.id === root.currentId) ?? null
    readonly property var hoveredEntry: root.systems.find(entry => entry.id === root.hoveredId) ?? null

    symbol: "pin"
    title: Translation.tr("Numerals")
    engaged: root.hoveredId.length > 0
    subtitle: root.hoveredEntry ? root.hoveredEntry.label
        : root.currentEntry ? root.currentEntry.label : Translation.tr("Custom")

    Item {
        id: grid
        Layout.fillWidth: true
        implicitHeight: GridMath.rowCount(root.systems.length, grid.cols) * (root.cardHeight + root.gap) - root.gap

        readonly property int cols: GridMath.columns(root.systems.length, grid.width, root.gap, root.minCell)

        Flow {
            width: parent.width
            spacing: root.gap

            Repeater {
                model: root.systems
                delegate: RippleButton {
                    id: card

                    required property var modelData
                    required property int index
                    readonly property bool chosen: root.currentId === card.modelData.id
                    // 0 → 1 as the card is chosen; weight and width follow it.
                    property real boldness: card.chosen ? 1 : 0
                    Behavior on boldness {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    readonly property color colContent: card.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2

                    width: GridMath.cellWidth(card.index, root.systems.length, grid.width, root.gap, grid.cols)
                    height: root.cardHeight
                    toggled: card.chosen
                    buttonRadius: card.chosen ? Appearance.rounding.verylarge : Appearance.rounding.normal
                    buttonRadiusPressed: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    colRipple: Appearance.colors.colLayer2Active
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive
                    colRippleToggled: Appearance.colors.colSecondaryContainerActive
                    onClicked: Config.options.bar.workspaces.numberMap = Numerals.maps[card.modelData.id]
                    onHoveredChanged: {
                        if (card.hovered)
                            root.hoveredId = card.modelData.id;
                        else if (root.hoveredId === card.modelData.id)
                            root.hoveredId = "";
                    }

                    contentItem: Item {
                        ColumnLayout {
                            anchors {
                                fill: parent
                                margins: root.cardPadding
                            }
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: card.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: card.colContent
                                opacity: 0.8
                                elide: Text.ElideRight
                            }

                            Item {
                                Layout.fillHeight: true
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Numerals.samples(Numerals.maps[card.modelData.id]).join(" ")
                                font.family: Appearance.font.family.main
                                font.pixelSize: root.sampleSize
                                font.variableAxes: ({
                                    "wght": root.axesIdle.wght + (root.axesChosen.wght - root.axesIdle.wght) * card.boldness,
                                    "wdth": root.axesIdle.wdth + (root.axesChosen.wdth - root.axesIdle.wdth) * card.boldness,
                                    "ROND": root.axesIdle.ROND
                                })
                                color: card.colContent
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
