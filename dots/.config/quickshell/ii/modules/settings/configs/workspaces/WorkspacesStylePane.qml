pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "WorkspacesGrid.js" as GridMath

/**
 * The workspace widget's look: five styles as cards (hovering one tries it on the
 * stage above, through `tried`) and the colour treatment as swatches that pair the
 * indicator's fill with its text, the way the bar will draw them.
 */
WorkspacesPane {
    id: root

    readonly property int gap: 10
    readonly property real styleMinCell: 150
    readonly property real styleCardHeight: 128
    readonly property real cardPadding: 14
    readonly property real swatchMinCell: 84
    readonly property real swatchHeight: 72
    readonly property real swatchSize: 34
    readonly property real captionSpacing: 8

    /** The style under the pointer, "" when none. */
    property string tried: ""
    property string hoveredColor: ""

    readonly property var styles: [
        { "value": "default", "label": Translation.tr("Default"), "symbol": "workspaces", "shape": "Cookie9Sided",
          "line": Translation.tr("Numbered pills, one sliding indicator") },
        { "value": "minimal", "label": Translation.tr("Minimal"), "symbol": "navigation", "shape": "Pill",
          "line": Translation.tr("Small dots under a stretching pill") },
        { "value": "expressive", "label": Translation.tr("Expressive"), "symbol": "fluid_med", "shape": "Flower",
          "line": Translation.tr("Shapes that morph as you move") },
        { "value": "dock", "label": Translation.tr("Dock"), "symbol": "dock_to_left", "shape": "Clover4Leaf",
          "line": Translation.tr("App icons and window dots") },
        { "value": "index", "label": Translation.tr("Index"), "symbol": "format_list_numbered", "shape": "Sunny",
          "line": Translation.tr("Numerals, the current one large") }
    ]
    readonly property var colors: [
        { "value": "primary", "label": Translation.tr("Primary") },
        { "value": "primaryContainer", "label": Translation.tr("Primary container") },
        { "value": "secondary", "label": Translation.tr("Secondary") },
        { "value": "secondaryContainer", "label": Translation.tr("Secondary container") },
        { "value": "tertiary", "label": Translation.tr("Tertiary") },
        { "value": "tertiaryContainer", "label": Translation.tr("Tertiary container") },
        { "value": "neutral", "label": Translation.tr("Neutral") },
        { "value": "neutralContainer", "label": Translation.tr("Neutral container") }
    ]

    readonly property string currentStyle: Config.options.bar.styles.workspaces ?? "default"
    readonly property var currentStyleEntry: root.styles.find(entry => entry.value === root.currentStyle) ?? root.styles[0]
    readonly property var triedEntry: root.styles.find(entry => entry.value === root.tried) ?? null
    readonly property var hoveredColorEntry: root.colors.find(entry => entry.value === root.hoveredColor) ?? null
    readonly property var currentColorEntry: root.colors.find(entry => entry.value === currentPalette.effectiveMode) ?? root.colors[0]

    symbol: "style"
    title: Translation.tr("Style")
    engaged: root.tried.length > 0 || root.hoveredColor.length > 0
    subtitle: root.triedEntry ? root.triedEntry.label + " · " + root.triedEntry.line
        : root.hoveredColorEntry ? root.hoveredColorEntry.label
        : root.currentStyleEntry.label + " · " + root.currentColorEntry.label

    BarWidgetPalette {
        id: currentPalette
        colorMode: Config.options.bar.workspaces.colorMode
    }

    Item {
        id: styleGrid
        Layout.fillWidth: true
        implicitHeight: GridMath.rowCount(root.styles.length, styleGrid.cols) * (root.styleCardHeight + root.gap) - root.gap

        readonly property int cols: GridMath.columns(root.styles.length, styleGrid.width, root.gap, root.styleMinCell)

        Flow {
            width: parent.width
            spacing: root.gap

            Repeater {
                model: root.styles
                delegate: StyleCard {
                    required property var modelData
                    required property int index
                    entry: modelData
                    width: GridMath.cellWidth(index, root.styles.length, styleGrid.width, root.gap, styleGrid.cols)
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: root.captionSpacing

        StyledText {
            text: Translation.tr("Colour treatment")
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: Appearance.colors.colSubtext
        }

        Item {
            id: swatchGrid
            Layout.fillWidth: true
            implicitHeight: GridMath.rowCount(root.colors.length, swatchGrid.cols) * (root.swatchHeight + root.gap) - root.gap

            readonly property int cols: GridMath.columns(root.colors.length, swatchGrid.width, root.gap, root.swatchMinCell)

            Flow {
                width: parent.width
                spacing: root.gap

                Repeater {
                    model: root.colors
                    delegate: ColorSwatch {
                        required property var modelData
                        required property int index
                        entry: modelData
                        width: GridMath.cellWidth(index, root.colors.length, swatchGrid.width, root.gap, swatchGrid.cols)
                    }
                }
            }
        }
    }

    component StyleCard: RippleButton {
        id: card

        required property var entry
        readonly property bool chosen: root.currentStyle === card.entry.value
        readonly property color colContent: card.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2

        height: root.styleCardHeight
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
        onClicked: Config.options.bar.styles.workspaces = card.entry.value
        onHoveredChanged: {
            if (card.hovered)
                root.tried = card.entry.value;
            else if (root.tried === card.entry.value)
                root.tried = "";
        }

        contentItem: Item {
            ColumnLayout {
                anchors {
                    fill: parent
                    margins: root.cardPadding
                }
                spacing: 0

                MaterialShapeWrappedMaterialSymbol {
                    id: glyph
                    text: card.entry.symbol
                    iconSize: 20
                    padding: 9
                    fill: card.chosen ? 1 : 0
                    shape: card.chosen || card.hovered ? glyph.getShape(card.entry.shape) : MaterialShape.Shape.Circle
                    color: card.chosen ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    colSymbol: card.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                StyledText {
                    Layout.fillWidth: true
                    text: card.entry.label
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: card.colContent
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: card.entry.line
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

    component ColorSwatch: RippleButton {
        id: swatch

        required property var entry
        readonly property bool chosen: currentPalette.effectiveMode === swatch.entry.value
        readonly property color colContent: swatch.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2

        height: root.swatchHeight
        toggled: swatch.chosen
        buttonRadius: swatch.chosen ? Appearance.rounding.verylarge : Appearance.rounding.normal
        buttonRadiusPressed: Appearance.rounding.small
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active
        colRipple: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive
        colRippleToggled: Appearance.colors.colSecondaryContainerActive
        onClicked: Config.options.bar.workspaces.colorMode = swatch.entry.value
        onHoveredChanged: {
            if (swatch.hovered)
                root.hoveredColor = swatch.entry.value;
            else if (root.hoveredColor === swatch.entry.value)
                root.hoveredColor = "";
        }

        BarWidgetPalette {
            id: swatchPalette
            colorMode: swatch.entry.value
        }

        contentItem: Item {
            MaterialShape {
                anchors.centerIn: parent
                implicitSize: root.swatchSize
                shape: swatch.chosen ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                color: swatchPalette.colBackground

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "check"
                    iconSize: Appearance.font.pixelSize.large
                    fill: 1
                    color: swatchPalette.colOnBackground
                    opacity: swatch.chosen ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }
}
