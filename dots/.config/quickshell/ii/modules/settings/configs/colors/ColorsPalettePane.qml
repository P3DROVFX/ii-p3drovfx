pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The colour scheme: which palette is on, light or dark, and the swatches to pick
 * from — one source at a time (wallpaper schemes, built-in themes, custom themes)
 * behind filter chips instead of three grids stacked in a scroll box. The swatches
 * grow when a source has few of them, so no source leaves a lone straggler row.
 */
Rectangle {
    id: root

    readonly property int padding: 20
    readonly property int gap: 8
    readonly property real innerWidth: root.width - root.padding * 2
    readonly property bool narrow: root.width < 560
    readonly property string paletteType: Config.options.appearance.palette.type
    readonly property var customSchemes: Config.options.appearance.customColorSchemes ?? []

    function sourceOf(type: string): string {
        if (root.customSchemes.indexOf(type) !== -1)
            return "custom";
        if (themesGrid.builtInColorSchemes.indexOf(type) !== -1)
            return "themes";
        return "wallpaper";
    }

    /// The chips' choice; follows the palette until the user picks a source.
    property string source: root.sourceOf(root.paletteType)
    readonly property bool customizing: root.source === "customize"
    readonly property var currentGrid: root.source === "custom" ? customGrid
        : root.source === "themes" ? themesGrid
        : root.customizing ? root.sourceGrid(root.sourceOf(root.paletteType)) : wallpaperGrid
    function sourceGrid(source: string): var {
        return source === "custom" ? customGrid : source === "themes" ? themesGrid : wallpaperGrid;
    }
    readonly property var modeOverrides: Config.options.appearance.palette.overrides[Appearance.m3colors.darkmode ? "dark" : "light"]
    readonly property int overrideCount: ["primary", "secondary", "tertiary", "surface"]
        .filter(role => String(root.modeOverrides?.[role] ?? "").length > 0).length

    // Columns balanced over the rows a source needs, cells never under 72 px.
    function columnsFor(count: int): int {
        const maxColumns = Math.max(3, Math.floor((root.innerWidth + root.gap) / (72 + root.gap)));
        const rows = Math.max(1, Math.ceil(count / maxColumns));
        return Math.max(1, Math.ceil(count / rows));
    }
    function cellHeightFor(columns: int): real {
        const cellWidth = (root.innerWidth - root.gap * (columns - 1)) / columns;
        return Math.round(Math.max(64, Math.min(80, cellWidth * 0.6)));
    }

    function displayName(type: string): string {
        const name = type.startsWith("scheme-") ? type.split("-").slice(1).join(" ") : type.replace(/_/g, " ");
        return name.charAt(0).toUpperCase() + name.slice(1);
    }
    readonly property string currentName: root.currentGrid.hoveredName.length > 0
        ? root.currentGrid.hoveredName : root.displayName(root.paletteType)
    readonly property string currentSourceLabel: {
        const source = root.sourceOf(root.paletteType);
        const label = source === "custom" ? Translation.tr("Custom theme")
            : source === "themes" ? Translation.tr("Built-in theme")
            : Translation.tr("From your wallpaper");
        return root.overrideCount > 0 ? Translation.tr("%1 · customized").arg(label) : label;
    }

    color: Appearance.colors.colLayer1
    radius: Appearance.rounding.verylarge
    implicitHeight: content.implicitHeight + root.padding * 2

    ColumnLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: 16

        // ── Header ──────────────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            columns: root.narrow ? 1 : 2
            columnSpacing: 16
            rowSpacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                MaterialShapeWrappedMaterialSymbol {
                    text: "palette"
                    iconSize: 24
                    padding: 12
                    fill: 1
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.colors.colOnPrimaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Color scheme")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.currentGrid.hoveredName.length > 0
                            ? root.currentName
                            : Translation.tr("%1 · %2").arg(root.currentName).arg(root.currentSourceLabel)
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }

            ColorsModeToggle {
                Layout.fillWidth: root.narrow
                Layout.preferredWidth: root.narrow ? -1 : 248
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            }
        }

        // ── Sources ─────────────────────────────────────────────────────
        Flow {
            Layout.fillWidth: true
            spacing: 8

            ColorsChip {
                symbol: "wallpaper"
                label: Translation.tr("Wallpaper colors")
                count: wallpaperGrid.colorSchemes.length
                chosen: root.source === "wallpaper"
                onClicked: root.source = "wallpaper"
            }
            ColorsChip {
                symbol: "format_paint"
                label: Translation.tr("Themes")
                count: themesGrid.colorSchemes.length
                chosen: root.source === "themes"
                onClicked: root.source = "themes"
            }
            ColorsChip {
                visible: root.customSchemes.length > 0
                symbol: "brush"
                label: Translation.tr("Custom")
                count: customGrid.colorSchemes.length
                chosen: root.source === "custom"
                onClicked: root.source = "custom"
            }
            ColorsChip {
                symbol: "tune"
                label: Translation.tr("Customize")
                count: root.overrideCount > 0 ? root.overrideCount : -1
                chosen: root.customizing
                onClicked: root.source = "customize"
            }
        }

        // ── Swatches ────────────────────────────────────────────────────
        Item {
            id: swatches
            Layout.fillWidth: true
            implicitHeight: root.customizing ? (editorLoader.item?.implicitHeight ?? 0) : root.currentGrid.implicitHeight
            clip: true

            Behavior on implicitHeight {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            SchemeGrid {
                id: wallpaperGrid
            }
            SchemeGrid {
                id: themesGrid
                builtInTheme: true
            }
            SchemeGrid {
                id: customGrid
                customTheme: true
            }
            Loader {
                id: editorLoader
                width: swatches.width
                active: root.customizing
                visible: active
                sourceComponent: ColorsSchemeEditor {
                    width: swatches.width
                    availableWidth: swatches.width
                }
            }
        }
    }

    component SchemeGrid: ColorPreviewGrid {
        id: grid
        readonly property bool current: root.currentGrid === grid && !root.customizing

        width: swatches.width
        columns: root.columnsFor(grid.colorSchemes.length)
        cellHeight: root.cellHeightFor(grid.columns)
        // The header already names the swatch under the pointer.
        showTooltips: false
        columnSpacing: root.gap
        rowSpacing: root.gap
        visible: opacity > 0
        opacity: grid.current ? 1 : 0

        Behavior on opacity {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }
}
