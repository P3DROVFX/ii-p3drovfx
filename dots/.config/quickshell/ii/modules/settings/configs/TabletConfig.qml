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
ContentPage {
    id: page
    forceWidth: false

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

        ConfigSwitch {
            buttonIcon: "push_pin"
            text: Translation.tr("Keep the app row pinned")
            checked: Config.options.dock.pinnedOnStartup
            onCheckedChanged: {
                if (Config.ready && checked !== Config.options.dock.pinnedOnStartup)
                    Config.options.dock.pinnedOnStartup = checked;
            }
            StyledToolTip {
                text: Translation.tr("Unpinned, the app row shows only while the workspace is empty and gets out of the way once something is running. The navigation buttons are always visible either way.")
            }
        }

        ConfigSubpageRow {
            buttonIcon: "apps"
            title: Translation.tr("Pinned apps")
            description: Translation.tr("Which apps sit on the left of the dock. Shared with the desktop shell's dock, since these are your favourite apps rather than one shell's setting.")
            configPage: Qt.resolvedUrl("widgets/DockContentConfig.qml")
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
            buttonIcon: "touch_app"
            title: Translation.tr("Edge and corner bindings")
            description: Translation.tr("What the remaining edges and the four corners do")
            configPage: Qt.resolvedUrl("TouchGesturesConfig.qml")
        }
    }
}
