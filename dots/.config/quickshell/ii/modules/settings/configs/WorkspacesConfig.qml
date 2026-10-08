import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.lockscreen
import qs.modules.settings.configs.workspaces
import "workspaces/WorkspacesCatalog.js" as Catalog

/**
 * Settings → Workspaces.
 *
 * Leads with the workspace row live on a pretend bar, then the style cards and
 * colour swatches, the switches as tiles, the counts as steppers, the numerals as
 * type specimens, the active indicator acted out and the compactor. Anything the
 * pointer rests on is tried on the stage (and on the floating peek once the stage
 * has scrolled away). Search indexes sections/WorkspacesOptionsSection.qml.
 */
Item {
    id: workspacesRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property var cfg: Config.options.bar.workspaces
    readonly property string savedStyle: Config.options.bar.styles.workspaces
    readonly property var spec: Catalog.style(workspacesRoot.savedStyle)
    readonly property string indicatorMode: Catalog.indicatorOf(workspacesRoot.cfg)

    readonly property int tileMinWidth: 260
    readonly property int tileHeight: 188
    readonly property int blockGap: 12
    readonly property int wideBreakpoint: 640

    readonly property var styleNames: ({
        "default": Translation.tr("Default"),
        "minimal": Translation.tr("Minimal"),
        "expressive": Translation.tr("Expressive"),
        "dock": Translation.tr("Dock"),
        "index": Translation.tr("Index")
    })
    readonly property var styleLines: ({
        "default": Translation.tr("Pills that melt together, with icons and numbers"),
        "minimal": Translation.tr("A quiet row of dots and a sliding mark"),
        "expressive": Translation.tr("Round chips, the current one stretched and numbered"),
        "dock": Translation.tr("Buttons carrying each workspace's app"),
        "index": Translation.tr("Numerals only, the current one set large")
    })
    readonly property var colorNames: ({
        "primary": Translation.tr("Primary"),
        "primaryContainer": Translation.tr("Primary container"),
        "secondary": Translation.tr("Secondary"),
        "secondaryContainer": Translation.tr("Secondary container"),
        "tertiary": Translation.tr("Tertiary"),
        "tertiaryContainer": Translation.tr("Tertiary container"),
        "neutral": Translation.tr("Neutral"),
        "neutralContainer": Translation.tr("Neutral container")
    })
    readonly property var indicatorNames: ({
        "pill": Translation.tr("Pill"),
        "shape": Translation.tr("Material shape"),
        "random": Translation.tr("Random shape"),
        "arrow": Translation.tr("Direction arrow")
    })
    readonly property var indicatorLines: ({
        "pill": Translation.tr("Stretches over the whole workspace"),
        "shape": Translation.tr("Always the shape you pick below"),
        "random": Translation.tr("A new shape on every switch"),
        "arrow": Translation.tr("Points the way you moved, then settles")
    })
    readonly property var numeralNames: ({
        "normal": Translation.tr("Normal"),
        "han": Translation.tr("Han chars"),
        "roman": Translation.tr("Roman"),
        "greek": Translation.tr("Greek"),
        "rods": Translation.tr("Counting rods")
    })

    BarWidgetPalette {
        id: savedTone
        colorMode: workspacesRoot.cfg.colorMode
    }

    WorkspacesPreviewState {
        id: previewState
        stageVisible: workspacesRoot.visible && !subPageOverlay.isOpen
        tryProps: {
            const t = {};
            if (stylePicker.tried !== "")
                t.style = stylePicker.tried;
            if (swatches.tried !== "")
                t.colorMode = swatches.tried;
            if (indicatorPicker.tried !== "")
                t.indicator = indicatorPicker.tried;
            if (indicatorShapes.tried !== "") {
                t.indicator = "shape";
                t.indicatorShape = indicatorShapes.tried;
            }
            if (numerals.tried !== "") {
                t.numberMap = Catalog.numeralMap(numerals.tried);
                t.alwaysNumbers = true;
            }
            if (iconsPane.triedShape !== "") {
                t.showIcons = true;
                t.maskIcons = true;
                t.maskShape = iconsPane.triedShape;
            }
            if (iconsTile.engaged)
                t.showIcons = !workspacesRoot.cfg.showAppIcons;
            if (dynamicTile.engaged)
                t.dynamic = !workspacesRoot.cfg.dynamicWorkspaces;
            if (numbersTile.engaged)
                t.alwaysNumbers = !workspacesRoot.cfg.alwaysShowNumbers;
            return t;
        }
    }

    readonly property string caption: {
        if (stylePicker.tried !== "")
            return Translation.tr("Trying %1").arg(workspacesRoot.styleNames[stylePicker.tried]);
        if (swatches.tried !== "")
            return Translation.tr("Trying %1").arg(workspacesRoot.colorNames[swatches.tried]);
        if (indicatorShapes.tried !== "")
            return Translation.tr("Trying %1").arg(indicatorShapes.tried);
        if (indicatorPicker.tried !== "")
            return Translation.tr("Trying %1").arg(workspacesRoot.indicatorNames[indicatorPicker.tried]);
        if (numerals.tried !== "")
            return Translation.tr("Trying %1").arg(workspacesRoot.numeralNames[numerals.tried]);
        if (iconsPane.triedShape !== "")
            return Translation.tr("Icons as %1").arg(iconsPane.triedShape);
        if (iconsTile.engaged)
            return workspacesRoot.cfg.showAppIcons ? Translation.tr("Without app icons") : Translation.tr("With app icons");
        if (dynamicTile.engaged)
            return workspacesRoot.cfg.dynamicWorkspaces ? Translation.tr("Showing every slot") : Translation.tr("Hiding empty workspaces");
        if (numbersTile.engaged)
            return workspacesRoot.cfg.alwaysShowNumbers ? Translation.tr("Numbers only while Super is held") : Translation.tr("Numbers always shown");
        return "";
    }

    function openSubPage(file) {
        workspacesRoot.activeSubPage = Qt.resolvedUrl(file);
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        WorkspacesPreview {
            id: hero
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            preview: previewState
            caption: workspacesRoot.caption
        }

        Rectangle {
            id: lookPane
            Layout.fillWidth: true
            implicitHeight: lookColumn.implicitHeight + 40
            radius: Appearance.rounding.verylarge
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: lookColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20
                spacing: 18

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    MaterialShapeWrappedMaterialSymbol {
                        id: styleGlyph
                        text: workspacesRoot.spec.icon
                        iconSize: 24
                        padding: 12
                        fill: 1
                        shape: styleGlyph.getShape(workspacesRoot.spec.shape)
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: workspacesRoot.styleNames[workspacesRoot.savedStyle] ?? Translation.tr("Style")
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            font.pixelSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: workspacesRoot.styleLines[stylePicker.tried !== "" ? stylePicker.tried : workspacesRoot.savedStyle] ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }
                }

                WorkspacesStylePicker {
                    id: stylePicker
                    Layout.fillWidth: true
                    preview: previewState
                    currentValue: workspacesRoot.savedStyle
                    names: workspacesRoot.styleNames
                    lines: workspacesRoot.styleLines
                    onSelected: value => Config.options.bar.styles.workspaces = value
                }

                StyledText {
                    text: Translation.tr("Colour treatment")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                WorkspacesColorSwatches {
                    id: swatches
                    Layout.fillWidth: true
                    currentValue: savedTone.effectiveMode
                    names: workspacesRoot.colorNames
                    onSelected: value => workspacesRoot.cfg.colorMode = value
                }
            }
        }

        Item {
            id: tiles
            Layout.fillWidth: true
            Layout.topMargin: workspacesRoot.blockGap
            implicitHeight: tileFlow.implicitHeight

            readonly property int fits: Math.max(1, Math.floor((width + workspacesRoot.blockGap) / (workspacesRoot.tileMinWidth + workspacesRoot.blockGap)))
            readonly property int columns: fits >= 4 ? 4 : fits >= 2 ? 2 : 1
            readonly property int tileWidth: Math.floor((width - workspacesRoot.blockGap * (columns - 1)) / columns)

            Flow {
                id: tileFlow
                width: parent.width
                spacing: workspacesRoot.blockGap

                ColorsFeatureTile {
                    id: iconsTile
                    width: tiles.tileWidth
                    height: workspacesRoot.tileHeight
                    symbol: "award_star"
                    shapeOn: MaterialShape.Shape.Clover8Leaf
                    title: Translation.tr("Show app icons")
                    summary: checked
                        ? Translation.tr("Up to %1 per workspace").arg(workspacesRoot.cfg.maxWindowCount)
                        : Translation.tr("Numbers and dots only")
                    checked: workspacesRoot.cfg.showAppIcons
                    onToggled: value => workspacesRoot.cfg.showAppIcons = value
                }

                ColorsFeatureTile {
                    id: dynamicTile
                    width: tiles.tileWidth
                    height: workspacesRoot.tileHeight
                    symbol: "hdr_weak"
                    shapeOn: MaterialShape.Shape.Cookie12Sided
                    title: Translation.tr("Dynamic workspaces")
                    summary: checked
                        ? Translation.tr("Empty workspaces step aside")
                        : Translation.tr("Always %1 workspaces in a row").arg(workspacesRoot.cfg.shown)
                    checked: workspacesRoot.cfg.dynamicWorkspaces
                    onToggled: value => workspacesRoot.cfg.dynamicWorkspaces = value
                }

                ColorsFeatureTile {
                    id: numbersTile
                    width: tiles.tileWidth
                    height: workspacesRoot.tileHeight
                    symbol: "counter_1"
                    shapeOn: MaterialShape.Shape.Pentagon
                    title: Translation.tr("Always show numbers")
                    summary: checked
                        ? Translation.tr("Every workspace wears its numeral")
                        : Translation.tr("Numbers appear while Super is held")
                    checked: workspacesRoot.cfg.alwaysShowNumbers
                    onToggled: value => workspacesRoot.cfg.alwaysShowNumbers = value
                }

                ColorsFeatureTile {
                    width: tiles.tileWidth
                    height: workspacesRoot.tileHeight
                    symbol: "map"
                    shapeOn: MaterialShape.Shape.Gem
                    title: Translation.tr("Use workspace map")
                    summary: checked
                        ? Translation.tr("Each monitor keeps its own range")
                        : Translation.tr("Every monitor shares one row")
                    checked: workspacesRoot.cfg.useWorkspaceMap
                    configurable: true
                    onToggled: value => workspacesRoot.cfg.useWorkspaceMap = value
                    onConfigureRequested: workspacesRoot.openSubPage("widgets/WorkspaceMapConfig.qml")
                }
            }
        }

        WorkspacesIconsPane {
            id: iconsPane
            Layout.fillWidth: true
            Layout.topMargin: workspacesRoot.blockGap
            visible: workspacesRoot.cfg.showAppIcons || workspacesRoot.savedStyle === "dock"
        }

        WorkspacesSectionHeader {
            symbol: "view_column"
            shape: MaterialShape.Shape.Cookie4Sided
            title: Translation.tr("How many")
            summary: Translation.tr("Scroll over a card to step it")
        }

        GridLayout {
            Layout.fillWidth: true
            columns: width >= workspacesRoot.wideBreakpoint ? 2 : 1
            columnSpacing: workspacesRoot.blockGap
            rowSpacing: workspacesRoot.blockGap

            WorkspacesStepper {
                Layout.fillWidth: true
                Layout.fillHeight: true
                enabled: !workspacesRoot.cfg.dynamicWorkspaces
                symbol: "view_column"
                title: Translation.tr("Workspaces shown")
                summary: Translation.tr("How many slots the row holds")
                note: workspacesRoot.cfg.dynamicWorkspaces ? Translation.tr("Dynamic workspaces decides this while it is on") : ""
                from: 1
                to: 30
                value: workspacesRoot.cfg.shown
                onStepped: value => workspacesRoot.cfg.shown = value
            }

            WorkspacesStepper {
                Layout.fillWidth: true
                Layout.fillHeight: true
                symbol: "select_window"
                title: Translation.tr("Maximum window count per workspace")
                summary: Translation.tr("Icons past this many are left out")
                from: 1
                to: 20
                value: workspacesRoot.cfg.maxWindowCount
                onStepped: value => workspacesRoot.cfg.maxWindowCount = value
            }
        }

        WorkspacesSectionHeader {
            symbol: "format_list_numbered"
            shape: MaterialShape.Shape.Pentagon
            colGlyph: Appearance.colors.colTertiaryContainer
            colOnGlyph: Appearance.colors.colOnTertiaryContainer
            title: Translation.tr("Number style")
            summary: Translation.tr("Point at a set to read it on the bar")
        }

        WorkspacesNumeralPicker {
            id: numerals
            Layout.fillWidth: true
            currentValue: Catalog.numeralOf(workspacesRoot.cfg.numberMap)
            names: workspacesRoot.numeralNames
            onSelected: value => workspacesRoot.cfg.numberMap = Catalog.numeralMap(value)
        }

        Rectangle {
            Layout.fillWidth: true
            visible: !workspacesRoot.cfg.alwaysShowNumbers
            implicitHeight: delayRow.implicitHeight + 32
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            LockSliderRow {
                id: delayRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 18
                symbol: "touch_long"
                label: Translation.tr("Number show delay when pressing Super (ms)")
                activeShape: MaterialShape.Shape.Cookie6Sided
                from: 0
                to: 1000
                stepSize: 50
                value: workspacesRoot.cfg.showNumberDelay
                zeroText: Translation.tr("Instant")
                format: v => Translation.tr("%1 ms").arg(Math.round(v))
                onMoved: v => workspacesRoot.cfg.showNumberDelay = Math.round(v)
            }
        }

        WorkspacesSectionHeader {
            symbol: "token"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Active indicator")
            summary: workspacesRoot.spec.indicator
                ? Translation.tr("How the workspace you are on is marked")
                : Translation.tr("The %1 style marks the current workspace its own way").arg(workspacesRoot.styleNames[workspacesRoot.savedStyle])
        }

        WorkspacesIndicatorPicker {
            id: indicatorPicker
            Layout.fillWidth: true
            enabled: workspacesRoot.spec.indicator
            opacity: enabled ? 1 : 0.5
            currentValue: workspacesRoot.indicatorMode
            shapeName: workspacesRoot.cfg.activeIndicatorShape
            names: workspacesRoot.indicatorNames
            lines: workspacesRoot.indicatorLines
            unavailable: ({
                "arrow": !workspacesRoot.spec.arrow,
                "arrowText": Translation.tr("Only the Default style points the way")
            })
            onSelected: value => Catalog.applyIndicator(workspacesRoot.cfg, value)
        }

        Rectangle {
            Layout.fillWidth: true
            visible: workspacesRoot.indicatorMode === "shape" && workspacesRoot.spec.indicator
            implicitHeight: indicatorShapes.implicitHeight + 32
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            WorkspacesShapeGrid {
                id: indicatorShapes
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 16
                currentValue: workspacesRoot.cfg.activeIndicatorShape
                onSelected: value => workspacesRoot.cfg.activeIndicatorShape = value
            }
        }

        WorkspacesDockCard {
            Layout.fillWidth: true
            Layout.topMargin: workspacesRoot.blockGap
            visible: workspacesRoot.savedStyle === "dock"
            onMoreRequested: workspacesRoot.openSubPage("widgets/DockWorkspaceConfig.qml")
        }

        WorkspacesCompactorCard {
            Layout.fillWidth: true
            Layout.topMargin: workspacesRoot.blockGap
        }

        ContentSection {
            icon: "link"
            title: Translation.tr("Related settings")

            Flow {
                Layout.fillWidth: true
                spacing: 8

                RelatedChip {
                    pageId: "bar"
                    label: Translation.tr("Bar layout")
                }
                RelatedChip {
                    pageId: "overview"
                    label: Translation.tr("Overview")
                }
                RelatedChip {
                    pageId: "hyprland"
                    label: Translation.tr("Workspace gestures")
                }
            }
        }
    }

    WorkspacesPeek {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        z: 5
        preview: previewState
        caption: workspacesRoot.caption
        shown: !subPageOverlay.isOpen && page.contentY > hero.y + hero.height * 0.8
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
