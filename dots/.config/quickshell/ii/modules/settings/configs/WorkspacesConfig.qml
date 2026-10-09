import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.workspaces
import qs.services

/**
 * Settings → Workspaces.
 *
 * Leads with the bar's own workspace widget, live. Under it: its style and colour (cards
 * that try themselves on it), the numerals and the active indicator (with a track that
 * plays the indicator's behaviour), what each workspace shows as tiles, the numbers
 * as cards, the icon shape and the compactor. Search indexes sections/WorkspacesOptionsSection.qml
 * for everything the panes and tiles draw.
 */
Item {
    id: workspacesRoot
    anchors.fill: parent

    readonly property real sectionGap: 12
    readonly property int tileGap: 12
    readonly property real tileMin: 300
    readonly property int tileHeight: 200
    readonly property real countMin: 230
    readonly property var cfg: Config.options.bar.workspaces
    readonly property bool showIcons: workspacesRoot.cfg.showAppIcons
    readonly property bool dockStyle: Config.options.bar.styles.workspaces === "dock"

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    function openSubPage(file) {
        workspacesRoot.activeSubPage = Qt.resolvedUrl("widgets/" + file);
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── The widget, live ──────────────────────────────────────────────
        WorkspacesStage {
            id: stage
            Layout.fillWidth: true
            Layout.preferredHeight: stage.preferredHeight
            styleOverride: stylePane.tried
            tagTitle: Translation.tr("Workspaces")
            tagSubtitle: (stylePane.triedEntry ?? stylePane.currentStyleEntry).label + " · "
                + (workspacesRoot.cfg.dynamicWorkspaces ? Translation.tr("Dynamic")
                    : Translation.tr("%1 shown").arg(workspacesRoot.cfg.shown))
            actionLabel: Translation.tr("Workspace map")
            actionSymbol: "map"
            onActionClicked: workspacesRoot.openSubPage("WorkspaceMapConfig.qml")
        }

        WorkspacesStylePane {
            id: stylePane
            Layout.fillWidth: true
        }

        WorkspacesNumeralPane {
            Layout.fillWidth: true
        }

        WorkspacesIndicatorPane {
            Layout.fillWidth: true
        }

        // ── What each workspace shows ─────────────────────────────────────
        AppSettingsSection {
            Layout.topMargin: workspacesRoot.sectionGap
            title: Translation.tr("On each workspace")
            symbol: "dashboard_customize"

            Item {
                id: tiles
                Layout.fillWidth: true
                implicitHeight: tileFlow.implicitHeight

                readonly property int fits: Math.max(1, Math.floor((width + workspacesRoot.tileGap) / (workspacesRoot.tileMin + workspacesRoot.tileGap)))
                // Four tiles: one row of four, two of two or a column, never 3 + 1.
                readonly property int columns: fits >= 4 ? 4 : fits >= 2 ? 2 : 1
                readonly property int tileWidth: Math.floor((width - workspacesRoot.tileGap * (columns - 1)) / columns)

                Flow {
                    id: tileFlow
                    width: parent.width
                    spacing: workspacesRoot.tileGap

                    ColorsFeatureTile {
                        width: tiles.tileWidth
                        height: workspacesRoot.tileHeight
                        symbol: "counter_1"
                        shapeOn: MaterialShape.Shape.Cookie12Sided
                        title: Translation.tr("Always show numbers")
                        summary: workspacesRoot.cfg.alwaysShowNumbers
                            ? Translation.tr("Every workspace wears its number")
                            : Translation.tr("Numbers appear while you hold Super, after %1 ms").arg(workspacesRoot.cfg.showNumberDelay)
                        checked: workspacesRoot.cfg.alwaysShowNumbers
                        onToggled: value => workspacesRoot.cfg.alwaysShowNumbers = value
                    }

                    ColorsFeatureTile {
                        id: iconsTile
                        width: tiles.tileWidth
                        height: workspacesRoot.tileHeight
                        symbol: "award_star"
                        shapeOn: MaterialShape.Shape.Flower
                        title: Translation.tr("Show app icons")
                        summary: workspacesRoot.showIcons
                            ? Translation.tr("Up to %1 windows drawn on each workspace").arg(workspacesRoot.cfg.maxWindowCount)
                            : Translation.tr("See what is open on each workspace")
                        checked: workspacesRoot.showIcons
                        onToggled: value => workspacesRoot.cfg.showAppIcons = value

                        ColorsChip {
                            enabled: iconsTile.checked
                            label: Translation.tr("Tint")
                            symbol: "palette"
                            chosen: workspacesRoot.cfg.monochromeIcons
                            colContent: iconsTile.colContent
                            colChosen: Appearance.colors.colPrimary
                            colOnChosen: Appearance.colors.colOnPrimary
                            onClicked: workspacesRoot.cfg.monochromeIcons = !chosen
                        }
                    }

                    ColorsFeatureTile {
                        width: tiles.tileWidth
                        height: workspacesRoot.tileHeight
                        symbol: "hdr_weak"
                        shapeOn: MaterialShape.Shape.SoftBurst
                        title: Translation.tr("Dynamic workspaces")
                        summary: workspacesRoot.cfg.dynamicWorkspaces
                            ? Translation.tr("Only the workspaces that have windows")
                            : Translation.tr("Always shows %1 workspaces").arg(workspacesRoot.cfg.shown)
                        checked: workspacesRoot.cfg.dynamicWorkspaces
                        onToggled: value => workspacesRoot.cfg.dynamicWorkspaces = value
                    }

                    ColorsFeatureTile {
                        width: tiles.tileWidth
                        height: workspacesRoot.tileHeight
                        symbol: "map"
                        shapeOn: MaterialShape.Shape.Clover4Leaf
                        title: Translation.tr("Use workspace map")
                        summary: workspacesRoot.cfg.useWorkspaceMap
                            ? Translation.tr("Each monitor owns its own range of workspaces")
                            : Translation.tr("Isolate workspace ranges on multi-monitor setups")
                        checked: workspacesRoot.cfg.useWorkspaceMap
                        configurable: true
                        onConfigureRequested: workspacesRoot.openSubPage("WorkspaceMapConfig.qml")
                        onToggled: value => workspacesRoot.cfg.useWorkspaceMap = value
                    }
                }
            }
        }

        // ── Counts and timing ─────────────────────────────────────────────
        AppSettingsSection {
            Layout.topMargin: workspacesRoot.sectionGap
            title: Translation.tr("Counts & timing")
            symbol: "tune"

            Item {
                id: counts
                Layout.fillWidth: true
                implicitHeight: countFlow.implicitHeight

                readonly property int fits: Math.max(1, Math.floor((width + workspacesRoot.tileGap) / (workspacesRoot.countMin + workspacesRoot.tileGap)))
                readonly property int columns: fits >= 3 ? 3 : 1
                readonly property int cardWidth: Math.floor((width - workspacesRoot.tileGap * (columns - 1)) / columns)

                Flow {
                    id: countFlow
                    width: parent.width
                    spacing: workspacesRoot.tileGap

                    WorkspacesCountCard {
                        width: counts.cardWidth
                        enabled: !workspacesRoot.cfg.dynamicWorkspaces
                        symbol: "view_column"
                        shape: MaterialShape.Shape.Cookie9Sided
                        title: Translation.tr("Workspaces shown")
                        hint: workspacesRoot.cfg.dynamicWorkspaces
                            ? Translation.tr("Automatic while dynamic")
                            : Translation.tr("On the bar at once")
                        value: workspacesRoot.cfg.shown
                        from: 1
                        to: 30
                        onMoved: next => workspacesRoot.cfg.shown = next
                    }

                    WorkspacesCountCard {
                        width: counts.cardWidth
                        symbol: "select_window"
                        shape: MaterialShape.Shape.Clover4Leaf
                        title: Translation.tr("Max windows")
                        hint: Translation.tr("Icons per workspace")
                        dotRoundness: 0.25
                        value: workspacesRoot.cfg.maxWindowCount
                        from: 1
                        to: 20
                        onMoved: next => workspacesRoot.cfg.maxWindowCount = next
                    }

                    WorkspacesCountCard {
                        width: counts.cardWidth
                        symbol: "touch_long"
                        shape: MaterialShape.Shape.Sunny
                        title: Translation.tr("Number delay")
                        hint: Translation.tr("Holding Super shows the numbers")
                        unit: Translation.tr("ms")
                        visual: "bar"
                        value: workspacesRoot.cfg.showNumberDelay
                        from: 0
                        to: 1000
                        stepSize: 50
                        onMoved: next => workspacesRoot.cfg.showNumberDelay = next
                    }
                }
            }
        }

        ContentSection {
            visible: workspacesRoot.showIcons && workspacesRoot.cfg.monochromeIcons
            title: Translation.tr("App icon tint")
            icon: "humidity_percentage"

            ConfigSlider {
                buttonIcon: "humidity_percentage"
                text: Translation.tr("Tint (%)")
                value: Config.options.appearance.iconTintPercentage ?? 0.6
                onValueChanged: Config.options.appearance.iconTintPercentage = value
            }
        }

        WorkspacesIconShapePane {
            Layout.fillWidth: true
            Layout.topMargin: workspacesRoot.sectionGap
        }

        ContentSection {
            visible: workspacesRoot.dockStyle
            title: Translation.tr("Dock Workspace Style")
            icon: "dock"

            ConfigSwitch {
                buttonIcon: "dock"
                text: Translation.tr("Dock workspace style options")
                checked: workspacesRoot.cfg.dockShowActiveIndicator
                configPage: Qt.resolvedUrl("widgets/DockWorkspaceConfig.qml")
                onCheckedChanged: workspacesRoot.cfg.dockShowActiveIndicator = checked
                StyledToolTip {
                    text: Translation.tr("Click button text to configure active indicator, window count dots, hover effects, and app icons in dock style.")
                }
            }
        }

        WorkspacesCompactPane {
            Layout.fillWidth: true
            Layout.topMargin: workspacesRoot.sectionGap
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
