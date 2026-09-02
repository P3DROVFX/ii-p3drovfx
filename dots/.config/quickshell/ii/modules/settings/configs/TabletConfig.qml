import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets

/**
 * Everything specific to the tablet panel family, in one place.
 *
 * These controls used to be scattered through the pages of whichever desktop surface they
 * happened to resemble — the shade's pull-down edge sat under "Sidebars" — which meant
 * finding them required knowing which ii feature the tablet had borrowed from. They are
 * gathered here instead, and the page only exists for the family it configures.
 */
Item {
    id: tabletRoot
    anchors.fill: parent

    // Sub-pages slide in over the page. Without this host the rows that open one — pinned
    // apps, the gesture bindings — walked up looking for an `activeSubPage` to set, found
    // nothing, and silently did nothing when tapped.
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        ContentSection {
            title: Translation.tr("Notification shade")
            icon: "swipe_down"

            NoticeBox {
                Layout.fillWidth: true
                visible: !PanelFamily.isTablet
                materialIcon: "info"
                text: Translation.tr("These settings apply to the Tablet panel family. Switch to it to see them take effect.")
            }

            ConfigSpinBox {
                icon: "swipe_down"
                text: Translation.tr("Pull-down edge height (px)")
                value: Config.options.sidebar.tabletShade.edgeDragHeight
                from: 4
                to: 64
                stepSize: 2
                onValueChanged: {
                    if (Config.ready)
                        Config.options.sidebar.tabletShade.edgeDragHeight = value;
                }
                StyledToolTip {
                    text: Translation.tr("The strip at the very top that starts the pull-down. It sits above the bar, so whatever it covers stops being tappable — raise it for an easier grab, lower it to keep the bar usable.")
                }
            }

            ConfigSwitch {
                buttonIcon: "motion_photos_on"
                text: Translation.tr("Live backdrop")
                checked: Config.options.sidebar.tabletShade.liveBackdrop
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.sidebar.tabletShade.liveBackdrop)
                        Config.options.sidebar.tabletShade.liveBackdrop = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Keeps capturing the desktop behind the shade instead of freezing one frame. Costs a continuous screencopy and can smear, since the capture also sees the shade's own blur.")
                }
            }
        }

        ContentSection {
            title: Translation.tr("Dock")
            icon: "dock_to_bottom"

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "vertical_align_bottom"
                text: Translation.tr("The tablet dock reserves the bottom edge, so tiled applications stop above it instead of rendering underneath it.")
            }

            ConfigSwitch {
                buttonIcon: "space_bar"
                text: Translation.tr("Reserve screen space")
                checked: Config.options.tablet.dock.reserveSpace
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.dock.reserveSpace)
                        Config.options.tablet.dock.reserveSpace = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Keeps a real work area for the dock. Turn this off only if you prefer applications to extend behind it.")
                }
            }

            ConfigSwitch {
                buttonIcon: "push_pin"
                text: Translation.tr("Keep the app row pinned")
                checked: Config.options.dock.pinnedOnStartup
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.dock.pinnedOnStartup)
                        Config.options.dock.pinnedOnStartup = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Unpinned, the app row follows the automatic visibility rules below. This preference remains shared with the desktop dock for backwards compatibility.")
                }
            }

            ConfigSwitch {
                buttonIcon: "apps"
                text: Translation.tr("Show app row")
                checked: Config.options.tablet.dock.showAppRow
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.dock.showAppRow)
                        Config.options.tablet.dock.showAppRow = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "visibility_off"
                text: Translation.tr("Hide app row in occupied workspaces")
                visible: Config.options.tablet.dock.showAppRow
                checked: Config.options.tablet.dock.autoHideOnOccupiedWorkspace
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.dock.autoHideOnOccupiedWorkspace)
                        Config.options.tablet.dock.autoHideOnOccupiedWorkspace = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Keeps the home screen calm by hiding launchers once an application occupies the current workspace.")
                }
            }

            ConfigSwitch {
                buttonIcon: "running_with_errors"
                text: Translation.tr("Show running apps")
                visible: Config.options.tablet.dock.showAppRow
                checked: Config.options.tablet.dock.showRunningApps
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.dock.showRunningApps)
                        Config.options.tablet.dock.showRunningApps = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "apps_outage"
                text: Translation.tr("Show app drawer button")
                visible: Config.options.tablet.dock.showAppRow
                checked: Config.options.tablet.dock.showAppDrawerButton
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.dock.showAppDrawerButton)
                        Config.options.tablet.dock.showAppDrawerButton = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "vertical_split"
                text: Translation.tr("Show app dividers")
                visible: Config.options.tablet.dock.showAppRow
                checked: Config.options.tablet.dock.showAppDividers
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.dock.showAppDividers)
                        Config.options.tablet.dock.showAppDividers = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "pagination"
                text: Translation.tr("Show home-screen page counter")
                checked: Config.options.tablet.dock.showPageCounter
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.dock.showPageCounter)
                        Config.options.tablet.dock.showPageCounter = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "filter_1"
                text: Translation.tr("Hide page counter in occupied workspaces")
                visible: Config.options.tablet.dock.showPageCounter
                checked: Config.options.tablet.dock.hidePageCounterOnOccupiedWorkspace
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.dock.hidePageCounterOnOccupiedWorkspace)
                        Config.options.tablet.dock.hidePageCounterOnOccupiedWorkspace = checked;
                }
            }

            ConfigSpinBox {
                icon: "apps"
                text: Translation.tr("Running apps shown (0 fits the dock)")
                value: Config.options.tablet.dock.maximumRecents
                from: 0
                to: 24
                stepSize: 1
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.dock.maximumRecents)
                        Config.options.tablet.dock.maximumRecents = value;
                }
                StyledToolTip {
                    text: Translation.tr("0 fills the free space between the search pill and the navigation pill. Anything that still does not fit is grouped into the last slot rather than dropped.")
                }
            }

            ConfigSwitch {
                buttonIcon: "swap_horiz"
                text: Translation.tr("Show workspace arrows")
                checked: Config.options.tablet.dock.showWorkspaceArrows
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.dock.showWorkspaceArrows)
                        Config.options.tablet.dock.showWorkspaceArrows = checked;
                }
                StyledToolTip {
                    text: Translation.tr("A circular arrow at each end of the dock, moving one home screen at a time. The swipe needs bare wallpaper to start on; these do not.")
                }
            }

            ConfigSwitch {
                buttonIcon: "vertical_align_center"
                text: Translation.tr("Compact dock when the page counter is hidden")
                checked: Config.options.tablet.dock.compactWhenPageCounterHidden
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.dock.compactWhenPageCounterHidden)
                        Config.options.tablet.dock.compactWhenPageCounterHidden = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Removes the counter's unused vertical space instead of keeping the dock at its page-counter height.")
                }
            }

            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Dock height (px)")
                value: Config.options.tablet.dock.height
                from: 72
                to: 168
                stepSize: 4
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.dock.height)
                        Config.options.tablet.dock.height = value;
                }
            }

            ConfigSpinBox {
                icon: "photo_size_select_large"
                text: Translation.tr("App and navigation size (px)")
                value: Config.options.tablet.dock.iconSize
                from: 36
                to: 72
                stepSize: 4
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.dock.iconSize)
                        Config.options.tablet.dock.iconSize = value;
                }
                StyledToolTip {
                    text: Translation.tr("The navigation buttons share this touch target, keeping them aligned with the app icons on the right side of the dock.")
                }
            }

            ConfigSubpageRow {
                buttonIcon: "swap_horiz"
                title: Translation.tr("Navigation buttons")
                description: Translation.tr("Show or hide navigation, keep it visible during auto-hide, and choose its order")
                configPage: Qt.resolvedUrl("widgets/TabletDockNavigationConfig.qml")
            }

            ConfigSubpageRow {
                buttonIcon: "interests"
                title: Translation.tr("App icon appearance")
                description: Translation.tr("Adaptive Material shape, inactive-app treatment, and monochrome icons")
                configPage: Qt.resolvedUrl("widgets/TabletDockIconConfig.qml")
            }

            ConfigSubpageRow {
                buttonIcon: "search"
                title: Translation.tr("Dock search")
                description: Translation.tr("Pill or compact circle, and what each of its two buttons opens")
                configPage: Qt.resolvedUrl("widgets/TabletDockSearchConfig.qml")
            }

            ConfigSubpageRow {
                buttonIcon: "apps"
                title: Translation.tr("Pinned apps")
                description: Translation.tr("Which apps sit on the left of the dock. Shared with the desktop shell's dock, since these are your favourite apps rather than one shell's setting.")
                configPage: Qt.resolvedUrl("widgets/DockContentConfig.qml")
            }
        }

        ContentSection {
            title: Translation.tr("App drawer")
            icon: "grid_view"

            ConfigSubpageRow {
                buttonIcon: "grid_view"
                title: Translation.tr("Grid and search")
                description: Translation.tr("Sorting, category chips, tile size, long-press behaviour, and what the search reaches beyond applications")
                configPage: Qt.resolvedUrl("widgets/TabletAppDrawerConfig.qml")
            }
        }

        ContentSection {
            title: Translation.tr("Home screen")
            icon: "grid_view"

            ConfigSpinBox {
                icon: "grid_4x4"
                text: Translation.tr("Icon grid step (px)")
                // 0 in the config means "let the family decide". The fallback reads
                // familyWidgetGridStep, not the resolved widgetGridStep — the latter depends on
                // the key this control writes, which is a binding loop.
                value: Config.options.background.widgets.gridStep > 0
                    ? Config.options.background.widgets.gridStep
                    : Appearance.sizes.familyWidgetGridStep
                from: 10
                to: 120
                stepSize: 10
                onValueChanged: {
                    if (Config.ready)
                        Config.options.background.widgets.gridStep = value;
                }
                StyledToolTip {
                    text: Translation.tr("How far apart icons and desktop widgets snap when dragged. A coarse step makes the home screen read as a grid; a fine one lets you place things freely.")
                }
            }

            ConfigSwitch {
                buttonIcon: "grid_on"
                text: Translation.tr("Show the grid while dragging")
                checked: Config.options.background.widgets.enableGrid
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.background.widgets.enableGrid)
                        Config.options.background.widgets.enableGrid = checked;
                }
            }
        }

        ContentSection {
            title: Translation.tr("Gestures")
            icon: "gesture"

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "swipe"
                text: Translation.tr("The top edge pulls down the shade, the bottom edge opens the app drawer, the left edge opens Policies, and swiping across the wallpaper moves between home screens. Those four are owned by this family and are not rebindable.")
            }

            ConfigSubpageRow {
                buttonIcon: "swipe"
                title: Translation.tr("Multi-finger swipes")
                description: Translation.tr("Three fingers across the screen: workspaces sideways, the app drawer up, the shade down")
                configPage: Qt.resolvedUrl("widgets/TabletMultiFingerConfig.qml")
            }

            ConfigSubpageRow {
                buttonIcon: "touch_app"
                title: Translation.tr("Edge and corner bindings")
                description: Translation.tr("What the remaining edges and the four corners do")
                configPage: Qt.resolvedUrl("TouchGesturesConfig.qml")
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
