import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A named choice on Edit Mode's panel: a grid of tiles that fills the width,
 * joined like a connected button group (outer corners open, seams tight).
 *
 * Columns are balanced over the rows the set needs, and the last row's tiles
 * share the full width, so no set ends with a lone straggler. Icon options
 * stack their glyph in a shape over the name; a set too large for two rows
 * of names drops to icons, and the header names the option under the pointer
 * (or the chosen one), which is why the tiles carry no tooltips.
 *
 * Chosen = secondary container, corners opening to a pill, the glyph on a
 * primary shape, and the name in a heavier cut.
 */
ColumnLayout {
    id: root

    readonly property real gap: 3
    readonly property real tileHeightStacked: 66
    readonly property real tileHeightIcon: 50
    readonly property real tileHeightText: 46
    readonly property real tileMinIcon: 48
    readonly property real tileMinText: 56
    readonly property real tileMaxStacked: 84
    readonly property real tilePadding: 8
    readonly property real textPadding: 14
    readonly property int maxStackedRows: 2
    readonly property real shapeSize: 30
    readonly property real glyphSize: 18
    readonly property real checkSize: 16
    readonly property real headerInset: 10
    readonly property real hostRadius: Appearance.rounding.verylarge
    readonly property real hostPadding: 14
    readonly property real radiusOuter: Math.max(Appearance.rounding.verysmall, root.hostRadius - root.hostPadding)
    readonly property real radiusSeam: Math.max(Appearance.rounding.unsharpen, Math.round(root.radiusOuter * 0.34))
    readonly property var axesIdle: ({ "wght": 450, "wdth": 92, "ROND": 100 })
    readonly property var axesChosen: ({ "wght": 680, "wdth": 100, "ROND": 100 })
    readonly property string shapeChosen: "Cookie7Sided"
    readonly property string shapeIdle: "Circle"

    property string label: ""
    property var options: []
    property var currentValue: null
    property string lockedNote: ""
    // Off for a choice whose icons cannot carry it on their own: names stay
    // on the tiles however many rows that takes.
    property bool compact: true

    signal selected(var value)

    spacing: 8
    Layout.fillWidth: true
    Layout.bottomMargin: 8

    property int hoveredIndex: -1
    readonly property int count: root.options.length
    readonly property bool allIcons: root.count > 0 && root.options.every(option => (option.icon ?? "") !== "")
    readonly property var currentOption: root.options.find(option => String(option.value) === String(root.currentValue)) ?? null
    readonly property var shownOption: root.hoveredIndex >= 0 && root.hoveredIndex < root.count
        ? root.options[root.hoveredIndex] : root.currentOption

    function nameOf(option) {
        return option ? (option.displayName ?? String(option.value)) : "";
    }

    // The widest name, measured in the chosen cut so a tile never grows when
    // it is picked.
    readonly property real widestName: {
        let widest = 0;
        for (let i = 0; i < measures.count; i++)
            widest = Math.max(widest, measures.itemAt(i)?.implicitWidth ?? 0);
        return widest;
    }

    function plan(minTile, height) {
        const width = Math.max(1, grid.width);
        const maxCols = Math.max(1, Math.floor((width + root.gap) / (minTile + root.gap)));
        const rows = Math.max(1, Math.ceil(root.count / maxCols));
        return { "cols": Math.ceil(root.count / rows), "rows": rows, "height": height };
    }

    readonly property var layoutPlan: {
        if (root.count === 0)
            return { "cols": 1, "rows": 0, "height": 0, "mode": "text" };
        if (!root.allIcons) {
            const p = root.plan(Math.max(root.tileMinText, root.widestName + root.textPadding * 2 + root.checkSize), root.tileHeightText);
            p.mode = "text";
            return p;
        }
        const stackedMin = Math.max(root.tileMinIcon, root.widestName + root.tilePadding * 2);
        const stacked = root.plan(root.compact ? Math.min(root.tileMaxStacked, stackedMin) : stackedMin, root.tileHeightStacked);
        if (!root.compact || stacked.rows <= root.maxStackedRows) {
            stacked.mode = "stacked";
            return stacked;
        }
        const icons = root.plan(root.tileMinIcon, root.tileHeightIcon);
        icons.mode = "icon";
        return icons;
    }

    Repeater {
        id: measures
        model: root.options
        delegate: StyledText {
            required property var modelData
            visible: false
            text: root.nameOf(modelData)
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.variableAxes: root.axesChosen
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: root.headerInset
        Layout.rightMargin: root.headerInset
        visible: root.label !== "" || root.layoutPlan.mode === "icon"
        spacing: 12

        StyledText {
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: root.nameOf(root.shownOption)
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.variableAxes: root.axesChosen
            color: root.hoveredIndex >= 0 ? Appearance.colors.colOnSurface : Appearance.colors.colPrimary
            elide: Text.ElideRight

            Behavior on color {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    Item {
        id: grid
        Layout.fillWidth: true
        implicitHeight: root.layoutPlan.rows * root.layoutPlan.height + Math.max(0, root.layoutPlan.rows - 1) * root.gap

        readonly property int cols: root.layoutPlan.cols
        readonly property int rows: root.layoutPlan.rows
        readonly property int lastRowCount: root.count - grid.cols * (grid.rows - 1)
        // Laid out once before anything slides: a page opening must not
        // replay the tiles growing from zero width.
        property bool settled: false
        onWidthChanged: {
            if (!grid.settled && grid.width > 0)
                Qt.callLater(() => grid.settled = true);
        }

        Repeater {
            model: root.options

            delegate: Rectangle {
                id: tile
                required property var modelData
                required property int index

                readonly property int row: Math.floor(tile.index / grid.cols)
                readonly property int col: tile.index % grid.cols
                readonly property bool lastRow: tile.row === grid.rows - 1
                readonly property int rowCount: tile.lastRow ? grid.lastRowCount : grid.cols
                readonly property real cellWidth: (grid.width - root.gap * (tile.rowCount - 1)) / tile.rowCount
                readonly property bool current: String(tile.modelData.value) === String(root.currentValue)
                readonly property bool available: tile.modelData.enabled !== false
                readonly property string mode: root.layoutPlan.mode
                readonly property bool open: tile.current || tileMouse.pressed
                readonly property real radiusOpen: Math.min(tile.height / 2, Appearance.rounding.large)

                function corner(outer) {
                    return tile.open ? tile.radiusOpen : (outer ? root.radiusOuter : root.radiusSeam);
                }

                x: tile.col * (tile.cellWidth + root.gap)
                y: tile.row * (root.layoutPlan.height + root.gap)
                width: tile.cellWidth
                height: root.layoutPlan.height
                opacity: tile.available ? 1 : 0.4

                topLeftRadius: tile.corner(tile.row === 0 && tile.col === 0)
                topRightRadius: tile.corner(tile.row === 0 && tile.col === tile.rowCount - 1)
                bottomLeftRadius: tile.corner(tile.lastRow && tile.col === 0)
                bottomRightRadius: tile.corner(tile.lastRow && tile.col === tile.rowCount - 1)

                color: tile.current
                    ? (tileMouse.pressed ? Appearance.colors.colSecondaryContainerActive
                        : tileMouse.containsMouse ? Appearance.colors.colSecondaryContainerHover
                        : Appearance.colors.colSecondaryContainer)
                    : (tileMouse.pressed ? Appearance.colors.colSurfaceContainerHighestActive
                        : tileMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighest
                        : Appearance.colors.colSurfaceContainerHigh)
                readonly property color colOn: tile.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

                property real boldness: tile.current ? 1 : 0
                readonly property var axes: {
                    const t = Math.max(0, Math.min(1, tile.boldness));
                    return {
                        "wght": Math.round(root.axesIdle.wght + (root.axesChosen.wght - root.axesIdle.wght) * t),
                        "wdth": Math.round(root.axesIdle.wdth + (root.axesChosen.wdth - root.axesIdle.wdth) * t),
                        "ROND": 100
                    };
                }

                Behavior on boldness {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(tile)
                }
                Behavior on color {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(tile)
                }
                Behavior on x {
                    enabled: !Appearance.reducedMotion && grid.settled
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(tile)
                }
                Behavior on width {
                    enabled: !Appearance.reducedMotion && grid.settled
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(tile)
                }
                Behavior on topLeftRadius {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(tile)
                }
                Behavior on topRightRadius {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(tile)
                }
                Behavior on bottomLeftRadius {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(tile)
                }
                Behavior on bottomRightRadius {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(tile)
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width - root.tilePadding * 2
                    visible: tile.mode !== "text"
                    spacing: 4

                    MaterialShapeWrappedMaterialSymbol {
                        id: glyphShape
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitSize: root.shapeSize
                        shape: glyphShape.getShape(tile.current ? root.shapeChosen : root.shapeIdle)
                        text: tile.modelData.icon ?? ""
                        iconSize: root.glyphSize
                        fill: tile.current ? 1 : 0
                        color: tile.current ? Appearance.colors.colPrimary : "transparent"
                        colSymbol: tile.current ? Appearance.colors.colOnPrimary : tile.colOn

                        Behavior on color {
                            enabled: !Appearance.reducedMotion
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(glyphShape)
                        }
                    }
                    StyledText {
                        width: parent.width
                        visible: tile.mode === "stacked"
                        horizontalAlignment: Text.AlignHCenter
                        text: root.nameOf(tile.modelData)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: Appearance.font.pixelSize.smallest
                        font.variableAxes: tile.axes
                        color: tile.colOn
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: textRow
                    readonly property bool hasIcon: (tile.modelData.icon ?? "") !== ""
                    readonly property bool leadShown: textRow.hasIcon || tile.current
                    anchors.centerIn: parent
                    visible: tile.mode === "text"
                    spacing: textRow.leadShown ? 6 : 0

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: textRow.hasIcon ? tile.modelData.icon : "check"
                        iconSize: root.checkSize
                        fill: tile.current ? 1 : 0
                        color: tile.colOn
                        width: textRow.leadShown ? root.checkSize : 0
                        opacity: textRow.leadShown ? 1 : 0
                        clip: true

                        Behavior on width {
                            enabled: !Appearance.reducedMotion
                            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                        }
                        Behavior on opacity {
                            enabled: !Appearance.reducedMotion
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, tile.width - root.textPadding * 2 - root.checkSize)
                        text: root.nameOf(tile.modelData)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.variableAxes: tile.axes
                        color: tile.colOn
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    enabled: tile.available
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: {
                        if (tileMouse.containsMouse)
                            root.hoveredIndex = tile.index;
                        else if (root.hoveredIndex === tile.index)
                            root.hoveredIndex = -1;
                    }
                    onClicked: root.selected(tile.modelData.value)
                }
            }
        }
    }

    EditPanelNotice {
        Layout.fillWidth: true
        visible: root.lockedNote !== ""
        text: root.lockedNote
    }
}
