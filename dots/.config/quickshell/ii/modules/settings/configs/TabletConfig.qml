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
                buttonIcon: "linear_scale"
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
                StyledToolTip {
                    text: Translation.tr("The height of the band the controls sit in — the shelf itself. The page counter floats above it and is not counted, so raising this raises the dock and nothing else.")
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

            ContentSubsection {
                Layout.fillWidth: true
                icon: "format_color_fill"
                title: Translation.tr("Dock background")
                tooltip: Translation.tr("None is Android's home screen — icons straight on the wallpaper, outlined so they read against whatever is behind them. The other two give the dock a shelf of its own, like a Chrome OS or Windows taskbar, and drop the outlines because there is now a colour behind the glyphs. Contrast is checked against that colour, so the marks stay legible at any opacity.")

                ConfigSelectionArray {
                    currentValue: Config.options.tablet.dock.backgroundStyle
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.tablet.dock.backgroundStyle = newValue;
                    }
                    options: [
                        { value: "none", icon: "wallpaper", displayName: Translation.tr("None") },
                        { value: "translucent", icon: "opacity", displayName: Translation.tr("Translucent") },
                        { value: "solid", icon: "rectangle", displayName: Translation.tr("Solid") }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "crop_free"
                text: Translation.tr("Floating slab instead of a full-width bar")
                visible: Config.options.tablet.dock.backgroundStyle !== "none"
                checked: Config.options.tablet.dock.backgroundFloating
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.dock.backgroundFloating)
                        Config.options.tablet.dock.backgroundFloating = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Insets the surface from the screen edges and rounds all four corners, the way a floating taskbar looks. Off, it reaches the edges and is rounded only at the top.")
                }
            }

            ConfigSpinBox {
                icon: "opacity"
                text: Translation.tr("Background opacity (%)")
                visible: Config.options.tablet.dock.backgroundStyle === "translucent"
                value: Config.options.tablet.dock.backgroundOpacity
                from: 20
                to: 100
                stepSize: 5
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.dock.backgroundOpacity)
                        Config.options.tablet.dock.backgroundOpacity = value;
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                icon: "touch_app"
                title: Translation.tr("Tapping an app that is open")
                tooltip: Translation.tr("Go to it is what a taskbar does everywhere, and what the running dot under the icon promises. Start another copy is what this dock used to do for every tap. Either way a double tap always opens one more window.")

                ConfigSelectionArray {
                    currentValue: Config.options.tablet.dock.appTapAction
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.tablet.dock.appTapAction = newValue;
                    }
                    options: [
                        { value: "focus", icon: "open_in_new", displayName: Translation.tr("Go to it") },
                        { value: "launch", icon: "add", displayName: Translation.tr("Start another copy") }
                    ]
                }
            }

            ConfigSpinBox {
                icon: "ads_click"
                text: Translation.tr("Double-tap window (ms, 0 disables)")
                value: Config.options.tablet.dock.doubleTapLaunchMs
                from: 0
                to: 800
                stepSize: 20
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.dock.doubleTapLaunchMs)
                        Config.options.tablet.dock.doubleTapLaunchMs = value;
                }
                StyledToolTip {
                    text: Translation.tr("How long after a tap a second one still counts as \"one more window\" rather than as another tap.")
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
                icon: "home"
                text: Translation.tr("Home workspace")
                // 0 = the lowest ordinary workspace of the monitor Home was pressed on,
                // which is what a default Hyprland gives each output.
                value: Config.options.tablet.homeWorkspace
                from: 0
                to: 20
                stepSize: 1
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.homeWorkspace)
                        Config.options.tablet.homeWorkspace = value;
                }
                StyledToolTip {
                    text: Translation.tr("Which workspace the Home button lands on. 0 picks the monitor's first workspace automatically. Home has to be the same place every time — icons are stored per workspace, so landing on any free one would show a blank screen and leave your arrangement behind.")
                }
            }

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
            title: Translation.tr("Recent apps")
            icon: "overview"

            ContentSubsection {
                Layout.fillWidth: true
                icon: "grid_view"
                title: Translation.tr("Layout")
                tooltip: Translation.tr("A list is what Android does: one continuous row of cards you scrub sideways, going further back as you go. Grid pages show four windows at once, which is a better answer on a very large screen but makes you reason about pages that Recents does not really have.")

                ConfigSelectionArray {
                    currentValue: Config.options.tablet.recents.layout
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.tablet.recents.layout = newValue;
                    }
                    options: [
                        { value: "list", icon: "view_carousel", displayName: Translation.tr("List") },
                        { value: "grid", icon: "grid_view", displayName: Translation.tr("Grid pages") }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "screenshot_region"
                text: Translation.tr("Actions under the centred card")
                checked: Config.options.tablet.recents.showCardActions
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.recents.showCardActions)
                        Config.options.tablet.recents.showCardActions = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Screenshot and Split, under whichever card is in the middle of the view — where Android puts them. The same actions stay in each card's own menu either way.")
                }
            }

            ConfigSpinBox {
                icon: "opacity"
                text: Translation.tr("Backdrop opacity (%)")
                value: Config.options.tablet.recents.backdropOpacity
                from: 40
                to: 100
                stepSize: 2
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.recents.backdropOpacity)
                        Config.options.tablet.recents.backdropOpacity = value;
                }
                StyledToolTip {
                    text: Translation.tr("How much of the desktop behind Recents is washed out. It is never fully opaque by default, so what you were doing stays part of the transition instead of being replaced by a flat colour.")
                }
            }

            ConfigSpinBox {
                icon: "view_column"
                text: Translation.tr("Cards across")
                visible: Config.options.tablet.recents.layout === "grid"
                value: Config.options.tablet.recents.gridColumns
                from: 1
                to: 4
                stepSize: 1
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.recents.gridColumns)
                        Config.options.tablet.recents.gridColumns = value;
                }
            }

            ConfigSpinBox {
                icon: "table_rows"
                text: Translation.tr("Cards down")
                visible: Config.options.tablet.recents.layout === "grid"
                value: Config.options.tablet.recents.gridRows
                from: 1
                to: 3
                stepSize: 1
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.recents.gridRows)
                        Config.options.tablet.recents.gridRows = value;
                }
            }
        }

        ContentSection {
            title: Translation.tr("Windows")
            icon: "picture_in_picture"

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "info"
                text: Translation.tr("Hyprland tiles by default, so every application takes a whole workspace. Floating them gives a tablet the behaviour it expects — a window over what was already there — and the touch handles below are what make one arrangeable, since Hyprland's own move and resize both follow a pointer.")
            }

            ContentSubsection {
                Layout.fillWidth: true
                icon: "picture_in_picture"
                title: Translation.tr("Open new windows floating")
                tooltip: Translation.tr("Keep dialogs leaves anything the compositor already floated exactly where it put itself — an application's own dialog knows its size and position better than a placement rule does.")

                ConfigSelectionArray {
                    currentValue: Config.options.tablet.windows.floatMode
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.tablet.windows.floatMode = newValue;
                    }
                    options: [
                        { value: "off", icon: "grid_view", displayName: Translation.tr("Tile, as usual") },
                        { value: "all", icon: "picture_in_picture", displayName: Translation.tr("Everything") },
                        { value: "keepDialogs", icon: "web_asset", displayName: Translation.tr("Keep dialogs") }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "drag_pan"
                text: Translation.tr("Touch handles on the focused window")
                checked: Config.options.tablet.windows.touchControls
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.windows.touchControls)
                        Config.options.tablet.windows.touchControls = checked;
                }
                StyledToolTip {
                    text: Translation.tr("A title strip above the window to drag it by, with centre, tile, fullscreen and close, and a corner handle to resize it. Shown only for a floating window, so it costs nothing while everything is tiled.")
                }
            }

            ConfigSubpageRow {
                buttonIcon: "tune"
                title: Translation.tr("Placement and handles")
                description: Translation.tr("How large a floated window opens, whether they cascade, and the size of the touch handles")
                configPage: Qt.resolvedUrl("widgets/TabletWindowsConfig.qml")
            }
        }

        ContentSection {
            title: Translation.tr("Floating bubble")
            icon: "bubble_chart"

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "touch_app"
                text: Translation.tr("A small circle you can drag anywhere, which stays put even over a fullscreen application — exactly when the edge gestures are hardest to reach. Tapping it opens a sheet of large actions beside it.")
            }

            ConfigSwitch {
                buttonIcon: "bubble_chart"
                text: Translation.tr("Show the floating bubble")
                checked: Config.options.tablet.bubble.enable
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.bubble.enable)
                        Config.options.tablet.bubble.enable = checked;
                }
            }

            ConfigSubpageRow {
                buttonIcon: "bolt"
                title: Translation.tr("Bubble actions and appearance")
                description: Translation.tr("Which eight actions the sheet offers, the bubble's size, and how far it fades when idle")
                visible: Config.options.tablet.bubble.enable
                configPage: Qt.resolvedUrl("widgets/TabletBubbleConfig.qml")
            }
        }

        ContentSection {
            title: Translation.tr("Hub mode")
            icon: "dock"

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "info"
                text: Translation.tr("Charging and left alone, the tablet turns into a clock, weather and now-playing display readable from across a room — what a Pixel Tablet does when you dock it. Any touch brings it back.")
            }

            ConfigSwitch {
                buttonIcon: "dock"
                text: Translation.tr("Turn into a display when idle")
                checked: Config.options.tablet.hubMode.enable
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.hubMode.enable)
                        Config.options.tablet.hubMode.enable = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "power"
                text: Translation.tr("Only while charging")
                visible: Config.options.tablet.hubMode.enable
                checked: Config.options.tablet.hubMode.requireCharging
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.hubMode.requireCharging)
                        Config.options.tablet.hubMode.requireCharging = checked;
                }
                StyledToolTip {
                    text: Translation.tr("A charging cable is the closest this shell can get to knowing the device is docked rather than in your hands. Turn it off to use this as a desk display.")
                }
            }

            ConfigSwitch {
                buttonIcon: "play_circle"
                text: Translation.tr("Stay out of the way while something is playing")
                visible: Config.options.tablet.hubMode.enable
                checked: Config.options.tablet.hubMode.pauseWhilePlaying
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.hubMode.pauseWhilePlaying)
                        Config.options.tablet.hubMode.pauseWhilePlaying = checked;
                }
            }

            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Idle before it takes over (s)")
                visible: Config.options.tablet.hubMode.enable
                value: Config.options.tablet.hubMode.idleSeconds
                from: 15
                to: 900
                stepSize: 15
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.hubMode.idleSeconds)
                        Config.options.tablet.hubMode.idleSeconds = value;
                }
            }

            // Deliberately outside the `enable` gate above. Everything else on this page is
            // a preference you set once you know what it does; this is how you find that
            // out, and hiding it behind the switch would mean turning the feature on,
            // plugging in a cable and walking away for two minutes just to look at it.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8

                RippleButtonWithIcon {
                    buttonRadius: Appearance.rounding.small
                    materialIcon: "play_arrow"
                    mainText: Translation.tr("Show me what it looks like")
                    onClicked: GlobalStates.hubModePreview = true
                }

                StyledText {
                    Layout.fillWidth: true
                    text: PanelFamily.isTablet
                        ? Translation.tr("Tap the screen to leave it.")
                        : Translation.tr("Only the Tablet panel family draws this surface.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }
        }

        // The one surface this family cannot assume exists elsewhere. A tablet with no
        // keyboard reaches every text field through these two settings, so they are here
        // rather than only under the desktop shell's overlay page.
        ContentSection {
            title: Translation.tr("Keyboard")
            icon: "keyboard"

            // The one blocker on this page that leaves a keyboard-less device unable to
            // reach a text field, so it gets its own build button rather than a pointer
            // to the page that has one.
            NoticeBox {
                Layout.fillWidth: true
                visible: Config.options.osk.autoShow.enable && !OskAutoShow.binaryExists
                materialIcon: "build"
                text: OskAutoShow.building
                    ? Translation.tr("Building the keyboard helper — this takes about a minute the first time.")
                    : OskAutoShow.buildResult === "failed"
                        ? Translation.tr("The keyboard helper failed to build. Open On-screen keyboard below for what went wrong.")
                        : Translation.tr("The keyboard cannot raise itself yet: its helper has not been built.")

                RippleButtonWithIcon {
                    visible: OskAutoShow.cargoAvailable && OskAutoShow.buildResult !== "failed"
                    buttonRadius: Appearance.rounding.small
                    materialIcon: OskAutoShow.building ? "hourglass_top" : "build"
                    mainText: OskAutoShow.building
                        ? Translation.tr("Building…") : Translation.tr("Build it now")
                    enabled: !OskAutoShow.building
                    onClicked: OskAutoShow.buildHelper()
                }
            }

            // Built and switched on, and still nothing happens: the two remaining reasons,
            // which look identical from the outside and have different fixes.
            NoticeBox {
                Layout.fillWidth: true
                visible: Config.options.osk.autoShow.enable && OskAutoShow.binaryExists
                    && (OskAutoShow.permissionDenied
                        || (OskAutoShow.deviceReportReceived && !OskAutoShow.anyTriggerDevice))
                materialIcon: OskAutoShow.permissionDenied ? "vpn_key" : "touch_app"
                text: OskAutoShow.permissionDenied
                    ? Translation.tr("The keyboard helper cannot read /dev/input, so it cannot tell a finger from a mouse. See On-screen keyboard below.")
                    : Translation.tr("No touchscreen or pen was found, so nothing can raise the keyboard. See On-screen keyboard below.")
            }

            ConfigSwitch {
                buttonIcon: "touch_app"
                text: Translation.tr("Raise the keyboard when a text field is tapped")
                checked: Config.options.osk.autoShow.enable
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.osk.autoShow.enable)
                        Config.options.osk.autoShow.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Only focus caused by a finger or a pen counts, so a mouse click never raises it.")
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                icon: "lock"
                title: Translation.tr("Keyboard on the lock screen")
                tooltip: Translation.tr("The regular on-screen keyboard cannot appear on the lock screen — the session lock protocol covers every layer — so the lock screen draws its own. Without it, a device with no physical keyboard cannot be unlocked at all.")

                ConfigSelectionArray {
                    currentValue: Config.options.lock.touchKeyboard.show
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.lock.touchKeyboard.show = newValue;
                    }
                    options: [
                        { value: "auto", icon: "auto_awesome", displayName: Translation.tr("Auto") },
                        { value: "always", icon: "keyboard", displayName: Translation.tr("Always") },
                        { value: "never", icon: "keyboard_hide", displayName: Translation.tr("Never") }
                    ]
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                icon: "dialpad"
                title: Translation.tr("Lock keyboard layout")
                tooltip: Translation.tr("Letters gives a full keyboard with a symbols layer. PIN pad gives a numeric keypad, for a password that is only digits.")

                ConfigSelectionArray {
                    currentValue: Config.options.lock.touchKeyboard.mode
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.lock.touchKeyboard.mode = newValue;
                    }
                    options: [
                        { value: "text", icon: "keyboard", displayName: Translation.tr("Letters") },
                        { value: "pin", icon: "dialpad", displayName: Translation.tr("PIN pad") }
                    ]
                }
            }

            ConfigSubpageRow {
                buttonIcon: "keyboard_alt"
                title: Translation.tr("On-screen keyboard")
                description: Translation.tr("Style, height, layout, and when it raises itself")
                configPage: Qt.resolvedUrl("widgets/OnScreenKeyboardConfig.qml")
            }
        }

        ContentSection {
            title: Translation.tr("Gestures")
            icon: "gesture"

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "swipe"
                text: Translation.tr("The top edge pulls down the shade and swiping across the wallpaper moves between home screens. Those two are owned by this family and are not rebindable.")
            }

            ContentSubsection {
                Layout.fillWidth: true
                icon: "swipe_up"
                title: Translation.tr("Bottom edge")
                tooltip: Translation.tr("Android's layout: up is Home, up from the home screen opens the app drawer, up-and-hold opens Recents, and sideways along the edge walks back through the apps you were just in. App drawer only keeps the older behaviour, where this edge does one thing — at the cost of Home, Recents and quick switch having no gesture.")

                ConfigSelectionArray {
                    currentValue: Config.options.tablet.gestures.bottomEdge
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.tablet.gestures.bottomEdge = newValue;
                    }
                    options: [
                        { value: "android", icon: "home", displayName: Translation.tr("Home, drawer, recents") },
                        { value: "drawer", icon: "apps", displayName: Translation.tr("App drawer only") }
                    ]
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                icon: "swipe_left"
                title: Translation.tr("Side edges")
                tooltip: Translation.tr("On Android, swiping in from either side is Back — the most used gesture after Home. Policies puts the first Intelligence app back on the left edge instead, and leaves Back on the right. Unclaimed hands both edges to the bindings below.")

                ConfigSelectionArray {
                    currentValue: Config.options.tablet.gestures.sideEdges
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.tablet.gestures.sideEdges = newValue;
                    }
                    options: [
                        { value: "back", icon: "arrow_back", displayName: Translation.tr("Back") },
                        { value: "policies", icon: "neurology", displayName: Translation.tr("Policies on the left") },
                        { value: "none", icon: "block", displayName: Translation.tr("Unclaimed") }
                    ]
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                icon: "arrow_back"
                title: Translation.tr("What Back sends to the app")
                tooltip: Translation.tr("Back closes whatever the shell has open first — a dialog, a menu, the keyboard, the drawer. Once there is nothing of the shell's left, it becomes Android's Back: a key the focused application interprets. Alt+Left is what browsers, file managers and most toolkits bind their own back action to.")

                ConfigSelectionArray {
                    currentValue: Config.options.tablet.navigation.backKey
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.tablet.navigation.backKey = newValue;
                    }
                    options: [
                        { value: "alt_left", icon: "arrow_back", displayName: Translation.tr("Alt + Left") },
                        { value: "browser_back", icon: "public", displayName: Translation.tr("Browser Back key") },
                        { value: "escape", icon: "keyboard_return", displayName: Translation.tr("Escape") },
                        { value: "backspace", icon: "backspace", displayName: Translation.tr("Backspace") }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "keyboard_alt"
                text: Translation.tr("Let Back reach the focused app")
                checked: Config.options.tablet.navigation.sendBackKeyToApps
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.navigation.sendBackKeyToApps)
                        Config.options.tablet.navigation.sendBackKeyToApps = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Off keeps Back to the shell's own surfaces, so it does nothing once they are all closed — which is how this family behaved before. The key is only ever sent to a window on the workspace in front of you.")
                }
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
