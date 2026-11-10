pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The top-left brand icon: the current one large on a burst, named beside it, over a
 * dense grid of the presets (icons only — the header names the one under the pointer,
 * so the grid needs no labels or tooltips). Shape is the state: a preset at rest is a
 * pill, the chosen one a primary rounded square. Columns are balanced over the rows the
 * set needs, so no row ends with a straggler.
 *
 * options: [{ value, displayName, symbol }]
 */
ColumnLayout {
    id: root

    readonly property real cell: 44
    readonly property real cellGap: 6
    readonly property real badge: 68

    property var options: []
    property string currentValue: ""
    /// The Material Symbol mode replaces the grid; the badge shows the symbol instead.
    property bool symbolMode: false
    property string symbolName: ""
    signal selected(string value)

    property int pointed: -1
    readonly property var currentOption: root.options.find(option => option.value === root.currentValue) ?? null
    readonly property var shownOption: root.pointed >= 0 ? root.options[root.pointed] : root.currentOption

    spacing: 14

    function sourceOf(option) {
        return option ? option.symbol : "";
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 16

        MaterialShape {
            implicitSize: root.badge
            clip: true
            shape: root.pointed >= 0 ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.SoftBurst
            color: Appearance.colors.colPrimaryContainer

            CustomIcon {
                anchors.centerIn: parent
                visible: !root.symbolMode
                width: 30
                height: 30
                source: root.sourceOf(root.shownOption)
                colorize: true
                color: Appearance.colors.colOnPrimaryContainer
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.symbolMode
                text: root.symbolName
                iconSize: 32
                fill: 1
                color: Appearance.colors.colOnPrimaryContainer
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.symbolMode ? root.symbolName : (root.shownOption?.displayName ?? "")
                font.family: Appearance.font.family.main
                font.pixelSize: 30
                font.variableAxes: ({ "wght": 720, "wdth": 52, "ROND": 100 })
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: root.symbolMode ? Translation.tr("Material Symbol")
                    : root.pointed >= 0 && root.options[root.pointed]?.value !== root.currentValue
                        ? Translation.tr("Click to use it")
                        : Translation.tr("On the bar now")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
    }

    Item {
        id: grid
        Layout.fillWidth: true
        visible: !root.symbolMode
        readonly property int count: root.options.length
        readonly property int maxCols: Math.max(1, Math.floor((width + root.cellGap) / (root.cell + root.cellGap)))
        readonly property int rows: Math.ceil(grid.count / grid.maxCols)
        readonly property int cols: Math.ceil(grid.count / Math.max(1, grid.rows))
        readonly property real cellWidth: (width - root.cellGap * (grid.cols - 1)) / Math.max(1, grid.cols)
        implicitHeight: grid.rows * root.cell + (grid.rows - 1) * root.cellGap

        HoverHandler {
            onHoveredChanged: if (!hovered) root.pointed = -1
        }

        Repeater {
            model: root.options

            delegate: RippleButton {
                id: preset
                required property var modelData
                required property int index
                readonly property bool chosen: preset.modelData.value === root.currentValue

                x: (preset.index % grid.cols) * (grid.cellWidth + root.cellGap)
                y: Math.floor(preset.index / grid.cols) * (root.cell + root.cellGap)
                width: grid.cellWidth
                height: root.cell
                padding: 0
                buttonRadius: preset.chosen ? Appearance.rounding.small : height / 2
                buttonRadiusPressed: Appearance.rounding.verysmall
                colBackground: preset.chosen ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
                colBackgroundHover: preset.chosen ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
                colRipple: preset.chosen ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer1Active
                onHoveredChanged: if (preset.hovered) root.pointed = preset.index
                onClicked: if (!preset.chosen) root.selected(preset.modelData.value)

                contentItem: Item {
                    CustomIcon {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        source: preset.modelData.symbol
                        colorize: true
                        color: preset.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }
}
