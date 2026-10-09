pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.dock
import qs.modules.settings.configs.island
import qs.services
import "../../ii/dock/utilities/DockUtilityCatalog.js" as DockUtilityCatalog

/**
 * Settings → Dock.
 *
 * Leads with the dock itself, live at the edge of the wallpaper; then its look
 * (edge, the seven trays as cards that try themselves on the dock above, size and
 * corners), the features as tiles, the two ways into the sub-pages, and the plain
 * behaviour in its original section. Search indexes sections/DockLookSection.qml
 * for what the pane and the tiles draw.
 */
Item {
    id: dockConfigRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property var dock: Config.options.dock
    readonly property bool dockOn: Config.options.dock.enable

    function openSubPage(file) {
        dockConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/" + file);
    }

    readonly property var styleNames: ({
        "floating": Translation.tr("Floating"),
        "islands": Translation.tr("Islands"),
        "transparent": Translation.tr("Transparent"),
        "hug": Translation.tr("Hug"),
        "dynamic_island": Translation.tr("Dynamic Island"),
        "full_width": Translation.tr("Full width"),
        "full_width_concave": Translation.tr("Full width · rounded")
    })
    readonly property var styleLines: ({
        "floating": Translation.tr("A rounded tray floating just off the edge"),
        "islands": Translation.tr("Apps, widgets and buttons each on an island of their own"),
        "transparent": Translation.tr("Only the icons, straight on the wallpaper"),
        "hug": Translation.tr("Sits on the edge, rounding only the corners away from it"),
        "dynamic_island": Translation.tr("A notch that flares out of the edge"),
        "full_width": Translation.tr("Spans the whole edge, flat against it"),
        "full_width_concave": Translation.tr("Spans the edge and curves the screen into it")
    })
    readonly property var positionNames: ({
        "auto": Translation.tr("Opposite the bar"),
        "bottom": Translation.tr("Bottom edge"),
        "top": Translation.tr("Top edge"),
        "left": Translation.tr("Left edge"),
        "right": Translation.tr("Right edge")
    })

    /** What the dock holds besides apps, as glyphs for the widgets card. */
    readonly property var widgetGlyphs: {
        const d = dockConfigRoot.dock;
        const out = [];
        if (d.enableMediaWidget) out.push("play_circle");
        if (d.enableWeatherWidget) out.push("cloud");
        if (d.enableSportsWidget ?? true) out.push("sports_soccer");
        if (d.enableTasksWidget ?? false) out.push("checklist");
        if (d.enableLivePreviewWidget ?? false) out.push("live_tv");
        if (d.showPhoneButton ?? true) out.push("smartphone");
        for (const entry of DockUtilityCatalog.normalize(d.utilityWidgets ?? [])) {
            const info = DockUtilityCatalog.find(entry.kind);
            if (info)
                out.push(info.symbol);
        }
        if (d.showOverviewButton) out.push("apps");
        if (d.showPinButton) out.push("keep");
        if (d.showTrashButton) out.push("delete");
        return out;
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── The dock, live ────────────────────────────────────────────────
        DockPreviewStage {
            id: hero
            Layout.fillWidth: true
            Layout.preferredHeight: hero.preferredHeight
            Behavior on Layout.preferredHeight {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            styleOverride: stylePicker.tried

            // Name tag: the name in the title face over where it is and how it looks.
            Rectangle {
                id: heroTag
                anchors.left: parent.left
                anchors.margins: 11
                y: hero.pillEdge === "top" ? 11 : hero.height - height - 11
                height: tagColumn.implicitHeight + 12
                width: Math.min(hero.width - heroAction.width - 34, tagColumn.implicitWidth + 36)
                radius: Math.min(height / 2, Appearance.rounding.large)
                color: Appearance.colors.colSurfaceContainerHigh

                ColumnLayout {
                    id: tagColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Dock")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        spacing: 6
                        Rectangle {
                            width: 7
                            height: 7
                            radius: 3.5
                            color: dockConfigRoot.dockOn ? Appearance.colors.colPrimary : Appearance.colors.colOutline
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: !dockConfigRoot.dockOn ? Translation.tr("Off")
                                : (dockConfigRoot.styleNames[hero.dockStyle] ?? "") + " · "
                                    + (dockConfigRoot.positionNames[hero.pos] ?? "")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // The page's main action: same height as the tag, same edge.
            RippleButton {
                id: heroAction
                anchors.right: parent.right
                anchors.margins: 11
                y: heroTag.y
                visible: dockConfigRoot.dockOn
                implicitHeight: heroTag.height
                implicitWidth: hero.width < 600 ? heroTag.height : heroActionRow.implicitWidth + 36
                buttonRadius: height / 2
                buttonRadiusPressed: Appearance.rounding.small
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: dockConfigRoot.openSubPage("DockUtilitiesConfig.qml")
                StyledToolTip {
                    visible: hero.width < 600 && parent.hovered
                    text: Translation.tr("Widgets & buttons")
                }
                contentItem: Item {
                    RowLayout {
                        id: heroActionRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: "widgets"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            visible: hero.width >= 600
                            text: Translation.tr("Widgets & buttons")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }

            // Off: the stage is an invitation, not a switch.
            RippleButton {
                id: invite
                anchors.centerIn: parent
                visible: !dockConfigRoot.dockOn
                implicitHeight: 56
                implicitWidth: inviteRow.implicitWidth + 44
                buttonRadius: height / 2
                buttonRadiusPressed: Appearance.rounding.normal
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: Config.options.dock.enable = true
                contentItem: Item {
                    RowLayout {
                        id: inviteRow
                        anchors.centerIn: parent
                        spacing: 10
                        MaterialShapeWrappedMaterialSymbol {
                            text: "dock_to_bottom"
                            iconSize: 18
                            padding: 6
                            fill: 1
                            shape: invite.hovered ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie7Sided
                            color: Appearance.colors.colOnPrimary
                            colSymbol: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Turn on the dock")
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }

        // ── Its look ──────────────────────────────────────────────────────
        Rectangle {
            id: lookPane
            Layout.fillWidth: true
            visible: dockConfigRoot.dockOn
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
                        text: "dock_to_bottom"
                        iconSize: 24
                        padding: 12
                        fill: 1
                        shape: stylePicker.tried.length > 0 ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: dockConfigRoot.styleNames[hero.dockStyle] ?? Translation.tr("Style")
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            font.pixelSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        // While a card is under the pointer, this names it instead.
                        StyledText {
                            Layout.fillWidth: true
                            text: stylePicker.tried.length > 0
                                ? dockConfigRoot.styleLines[stylePicker.tried] ?? ""
                                : (dockConfigRoot.styleLines[hero.savedStyle] ?? "") + " · " + Translation.tr("%1 px").arg(dockConfigRoot.dock.height)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }
                }

                // Which edge: a connected group, the current one a pill.
                IslandSegmentedToggle {
                    Layout.fillWidth: true
                    labelMinWidth: 88
                    currentValue: dockConfigRoot.dock.position ?? "bottom"
                    options: [
                        { "value": "auto", "label": Translation.tr("Auto"), "icon": "auto_awesome", "shape": "Sunny" },
                        { "value": "bottom", "label": Translation.tr("Bottom"), "icon": "border_bottom", "shape": "Cookie9Sided" },
                        { "value": "top", "label": Translation.tr("Top"), "icon": "border_top", "shape": "Cookie9Sided" },
                        { "value": "left", "label": Translation.tr("Left"), "icon": "border_left", "shape": "Cookie9Sided" },
                        { "value": "right", "label": Translation.tr("Right"), "icon": "border_right", "shape": "Cookie9Sided" }
                    ]
                    onSelected: value => Config.options.dock.position = value
                }

                DockStylePicker {
                    id: stylePicker
                    Layout.fillWidth: true
                    currentValue: hero.savedStyle
                    onSelected: value => {
                        Config.options.dock.dockStyle = value;
                        Config.options.dock.islandsStyle = (value === "islands");
                    }
                }

                // Size and corners: side by side on a wide page.
                GridLayout {
                    Layout.fillWidth: true
                    columns: lookPane.width >= 1000 ? 2 : 1
                    columnSpacing: 8
                    rowSpacing: 8

                    ConfigSlider {
                        Layout.fillWidth: true
                        buttonIcon: "height"
                        text: Translation.tr("Dock height")
                        from: 30
                        to: Math.max(120, dockConfigRoot.dock.height)
                        stepSize: 1
                        usePercentTooltip: false
                        value: dockConfigRoot.dock.height
                        onValueChanged: Config.options.dock.height = value
                    }
                    ConfigSlider {
                        Layout.fillWidth: true
                        buttonIcon: "rounded_corner"
                        text: Translation.tr("Corner radius") + (dockConfigRoot.dock.dockRadius < 0 ? " (" + Translation.tr("Auto") + ")" : "")
                        from: 0
                        to: 40
                        stepSize: 1
                        usePercentTooltip: false
                        value: dockConfigRoot.dock.dockRadius < 0 ? 0 : dockConfigRoot.dock.dockRadius
                        onValueChanged: Config.options.dock.dockRadius = value === 0 ? -1 : value
                    }
                    ConfigSlider {
                        Layout.fillWidth: true
                        visible: hero.savedStyle === "islands"
                        buttonIcon: "space_bar"
                        text: Translation.tr("Island spacing")
                        from: 4
                        to: 32
                        stepSize: 1
                        usePercentTooltip: false
                        value: dockConfigRoot.dock.islandSpacing ?? 8
                        onValueChanged: Config.options.dock.islandSpacing = value
                    }
                }
            }
        }

        // ── Features ──────────────────────────────────────────────────────
        Item {
            id: tiles
            Layout.fillWidth: true
            Layout.topMargin: 12
            visible: dockConfigRoot.dockOn
            implicitHeight: tileFlow.implicitHeight

            readonly property int gap: 12
            readonly property int fits: Math.max(1, Math.floor((width + gap) / (300 + gap)))
            // Four tiles: one row of four, two of two or a column, never 3 + 1.
            readonly property int columns: fits >= 4 ? 4 : fits >= 2 ? 2 : 1
            readonly property int tileWidth: Math.floor((width - gap * (columns - 1)) / columns)
            readonly property int tileHeight: 200

            Flow {
                id: tileFlow
                width: parent.width
                spacing: tiles.gap

                ColorsFeatureTile {
                    width: tiles.tileWidth
                    height: tiles.tileHeight
                    symbol: "zoom_in"
                    shapeOn: MaterialShape.Shape.Cookie12Sided
                    title: Translation.tr("Magnification")
                    summary: checked
                        ? Translation.tr("%1× under the pointer · %2 motion")
                            .arg(Number(dockConfigRoot.dock.magnificationScale ?? 1.5).toFixed(2).replace(/\.?0+$/, ""))
                            .arg(({ "fast": Translation.tr("Fast"), "balanced": Translation.tr("Balanced"), "smooth": Translation.tr("Smooth") })[dockConfigRoot.dock.magnificationMotion ?? "balanced"] ?? "")
                        : Translation.tr("Icons swell as the pointer passes over them")
                    checked: dockConfigRoot.dock.enableMagnification ?? false
                    configurable: true
                    onConfigureRequested: dockConfigRoot.openSubPage("DockMagnificationConfig.qml")
                    onToggled: value => Config.options.dock.enableMagnification = value
                }

                ColorsFeatureTile {
                    id: hoverTile
                    width: tiles.tileWidth
                    height: tiles.tileHeight
                    symbol: "preview"
                    shapeOn: MaterialShape.Shape.Flower
                    title: Translation.tr("On hover")
                    summary: dockConfigRoot.dock.enablePreview ? Translation.tr("Window previews over running apps")
                        : dockConfigRoot.dock.enableAppTooltip ? Translation.tr("The app's name over its icon")
                        : Translation.tr("Nothing opens over the icons")
                    checked: dockConfigRoot.dock.enablePreview || dockConfigRoot.dock.enableAppTooltip
                    onToggled: value => {
                        Config.options.dock.enablePreview = value;
                        Config.options.dock.enableAppTooltip = false;
                    }

                    ColorsChip {
                        enabled: hoverTile.checked
                        label: Translation.tr("Name")
                        symbol: "subtitles"
                        chosen: dockConfigRoot.dock.enableAppTooltip && !dockConfigRoot.dock.enablePreview
                        colContent: hoverTile.colContent
                        colChosen: Appearance.colors.colPrimary
                        colOnChosen: Appearance.colors.colOnPrimary
                        onClicked: {
                            Config.options.dock.enablePreview = false;
                            Config.options.dock.enableAppTooltip = true;
                        }
                    }
                    ColorsChip {
                        enabled: hoverTile.checked
                        label: Translation.tr("Preview")
                        symbol: "preview"
                        chosen: dockConfigRoot.dock.enablePreview
                        colContent: hoverTile.colContent
                        colChosen: Appearance.colors.colPrimary
                        colOnChosen: Appearance.colors.colOnPrimary
                        onClicked: {
                            Config.options.dock.enablePreview = true;
                            Config.options.dock.enableAppTooltip = false;
                        }
                    }
                }

                ColorsFeatureTile {
                    width: tiles.tileWidth
                    height: tiles.tileHeight
                    symbol: "category"
                    shapeOn: MaterialShape.Shape.SoftBurst
                    title: Translation.tr("Smart grouping")
                    summary: checked ? Translation.tr("Sorted by category; anything you place by hand stays put")
                        : Translation.tr("Arrange the dock by app category")
                    checked: dockConfigRoot.dock.smartGrouping ?? false
                    onToggled: value => Config.options.dock.smartGrouping = value
                }

                ColorsFeatureTile {
                    width: tiles.tileWidth
                    height: tiles.tileHeight
                    symbol: "stacks"
                    shapeOn: MaterialShape.Shape.Clover4Leaf
                    title: Translation.tr("Widget stack")
                    summary: {
                        const n = (dockConfigRoot.dock.widgetStackItems ?? []).length;
                        if (!checked)
                            return Translation.tr("Several widgets in one slot, turned with the mouse wheel");
                        return n === 1 ? Translation.tr("1 widget in the stack · scroll over it to turn")
                            : Translation.tr("%1 widgets share one slot · scroll over it to turn").arg(n);
                    }
                    checked: dockConfigRoot.dock.enableWidgetStack ?? false
                    configurable: true
                    onConfigureRequested: dockConfigRoot.openSubPage("DockUtilitiesConfig.qml")
                    onToggled: value => Config.options.dock.enableWidgetStack = value
                }
            }
        }

        // ── The sub-pages ─────────────────────────────────────────────────
        Item {
            id: entries
            Layout.fillWidth: true
            visible: dockConfigRoot.dockOn
            readonly property bool stacked: width < 680
            readonly property int gap: 12
            readonly property real cardWidth: entries.stacked ? width : Math.floor((width - gap) / 2)
            implicitHeight: entries.stacked ? widgetsEntry.implicitHeight + gap + looksEntry.implicitHeight
                : Math.max(widgetsEntry.implicitHeight, looksEntry.implicitHeight)

            DockEntryCard {
                id: widgetsEntry
                x: 0
                y: 0
                width: entries.cardWidth
                height: entries.stacked ? implicitHeight : entries.implicitHeight
                symbol: "widgets"
                title: Translation.tr("Widgets & buttons")
                summary: Translation.tr("Media, weather, utilities, buttons and folders")
                count: dockConfigRoot.widgetGlyphs.length
                countLabel: Translation.tr("on the dock")
                glyphs: dockConfigRoot.widgetGlyphs
                onClicked: dockConfigRoot.openSubPage("DockUtilitiesConfig.qml")
            }

            DockEntryCard {
                id: looksEntry
                x: entries.stacked ? 0 : entries.cardWidth + entries.gap
                y: entries.stacked ? widgetsEntry.implicitHeight + entries.gap : 0
                width: entries.cardWidth
                height: entries.stacked ? implicitHeight : entries.implicitHeight
                symbol: "palette"
                shapeRest: MaterialShape.Shape.Flower
                shapeHover: MaterialShape.Shape.Sunny
                title: Translation.tr("Icons & motion")
                summary: {
                    const d = dockConfigRoot.dock;
                    const parts = [];
                    parts.push(d.monochromeIcons ? Translation.tr("Tinted icons") : d.dimInactiveIcons ? Translation.tr("Idle apps dimmed") : Translation.tr("Full-colour icons"));
                    if (d.enableShapeMask)
                        parts.push(Translation.tr("Adaptive icons"));
                    parts.push(Translation.tr("%1 on launch").arg(dockConfigRoot.animationName(d.launchAnimation)));
                    return parts.join(" · ");
                }
                glyphs: []
                onClicked: dockConfigRoot.openSubPage("DockAppearanceConfig.qml")
            }
        }

        // ── Behavior ──────────────────────────────────────────────────────
        // Search clones these controls out of context: nothing here may name a page id.
        ContentSection {
            Layout.topMargin: 12
            icon: "tune"
            title: Translation.tr("Behavior")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "toggle_on"
                    text: Translation.tr("Enable")
                    checked: Config.options.dock.enable
                    onCheckedChanged: Config.options.dock.enable = checked
                    StyledToolTip {
                        text: Translation.tr("Show the dock on screen")
                    }
                }
                ConfigSwitch {
                    enabled: Config.options.dock.enable
                    buttonIcon: "push_pin"
                    text: Translation.tr("Pinned on startup")
                    checked: Config.options.dock.pinnedOnStartup
                    onCheckedChanged: Config.options.dock.pinnedOnStartup = checked
                    StyledToolTip {
                        text: Translation.tr("Start with the dock kept on screen instead of hiding until you reach for it")
                    }
                }
            }

            ConfigRow {
                uniform: true
                visible: Config.options.dock.enable
                ConfigSwitch {
                    buttonIcon: "mouse"
                    text: Translation.tr("Hover to reveal")
                    checked: Config.options.dock.hoverToReveal
                    onCheckedChanged: Config.options.dock.hoverToReveal = checked
                    StyledToolTip {
                        text: Translation.tr("Bring the hidden dock back when the pointer reaches its edge")
                    }
                }
                ConfigSwitch {
                    enabled: Config.options.dock.hoverToReveal
                    buttonIcon: "fullscreen"
                    text: Translation.tr("Block hover in fullscreen")
                    checked: Config.options.dock.blockHoverInFullscreen
                    onCheckedChanged: Config.options.dock.blockHoverInFullscreen = checked
                    StyledToolTip {
                        text: Translation.tr("Prevent the dock from revealing on hover when a window or media is fullscreen")
                    }
                }
            }

            ConfigRow {
                uniform: true
                visible: Config.options.dock.enable
                ConfigSwitch {
                    buttonIcon: "monitor"
                    text: Translation.tr("Isolate monitors")
                    checked: Config.options.dock.isolateMonitors
                    onCheckedChanged: Config.options.dock.isolateMonitors = checked
                }
                ConfigSwitch {
                    buttonIcon: "center_focus_strong"
                    text: Translation.tr("Show only on focused monitor")
                    checked: Config.options.dock.showOnlyOnFocusedMonitor
                    onCheckedChanged: Config.options.dock.showOnlyOnFocusedMonitor = checked
                    StyledToolTip {
                        text: Translation.tr("When workspace is empty, show the dock only on the focused monitor instead of all monitors")
                    }
                }
            }

            ConfigRow {
                uniform: true
                visible: Config.options.dock.enable
                ConfigSwitch {
                    buttonIcon: "lock"
                    text: Translation.tr("Lock arrangement")
                    checked: Config.options.dock.lockReorder
                    onCheckedChanged: Config.options.dock.lockReorder = checked
                    StyledToolTip {
                        text: Translation.tr("Apps and widgets cannot be dragged: nothing is reordered, grouped or moved by accident")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "swipe_vertical"
                    text: Translation.tr("Switch presets on scroll")
                    checked: Config.options.dock.switchPresetsOnScroll ?? false
                    onCheckedChanged: Config.options.dock.switchPresetsOnScroll = checked
                    StyledToolTip {
                        text: Translation.tr("Scroll the mouse wheel anywhere over the dock to cycle between presets when more than 1 exists")
                    }
                }
            }

            ContentSubsection {
                visible: Config.options.dock.enable
                title: Translation.tr("Show on")
                icon: "desktop_windows"
                Layout.fillWidth: true
                tooltip: Translation.tr("The monitor the dock lives on. If it is disconnected, the dock shows on every monitor.")

                ConfigSelectionArray {
                    currentValue: {
                        const wanted = Config.options.dock.monitor ?? "";
                        return Quickshell.screens.some(screen => screen.name === wanted) ? wanted : "";
                    }
                    onSelected: newValue => Config.options.dock.monitor = newValue
                    options: [{
                        "displayName": Translation.tr("All monitors"),
                        "icon": "select_all",
                        "value": ""
                    }].concat(Quickshell.screens.map(screen => ({
                        "displayName": screen.model ? (screen.name + " · " + screen.model) : screen.name,
                        "icon": "monitor",
                        "value": screen.name
                    })))
                }
            }
        }

        // ── Presets ───────────────────────────────────────────────────────
        DockPresetsPane {
            Layout.fillWidth: true
            Layout.topMargin: 12
            visible: dockConfigRoot.dockOn
        }
    }

    function animationName(value) {
        return ({
            "none": Translation.tr("Still"),
            "bounce": Translation.tr("Bounce"),
            "hop": Translation.tr("Hop"),
            "pulse": Translation.tr("Pulse"),
            "wiggle": Translation.tr("Wiggle"),
            "ripple": Translation.tr("Ripple")
        })[value ?? "bounce"] ?? Translation.tr("Bounce");
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
