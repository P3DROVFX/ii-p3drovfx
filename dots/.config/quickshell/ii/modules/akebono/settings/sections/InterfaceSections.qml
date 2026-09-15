import QtQuick
import QtQuick.Layouts
import QtQml.Models
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    Layout.fillWidth: true
    spacing: 18

    ContentSection {
        icon: "dock_to_bottom"
        title: Translation.tr("Shelf")

        ContentSubsection {
            title: Translation.tr("Left zone")
            ConfigListView {
                barSection: 0
                listModel: Config.options.akebono.shelf.layout.left
                sourceListModel: Config.options.akebono.shelf.layout.availableComps
                onUpdated: newList => Config.options.akebono.shelf.layout.left = newList
                onSourceUpdated: newList => Config.options.akebono.shelf.layout.availableComps = newList
            }
        }
        ContentSubsection {
            title: Translation.tr("Center zone")
            tooltip: Translation.tr("Use the center button to pin a component to the middle")
            ConfigListView {
                barSection: 1
                listModel: Config.options.akebono.shelf.layout.center
                sourceListModel: Config.options.akebono.shelf.layout.availableComps
                onUpdated: newList => Config.options.akebono.shelf.layout.center = newList
                onSourceUpdated: newList => Config.options.akebono.shelf.layout.availableComps = newList
            }
        }
        ContentSubsection {
            title: Translation.tr("Right zone")
            ConfigListView {
                barSection: 2
                listModel: Config.options.akebono.shelf.layout.right
                sourceListModel: Config.options.akebono.shelf.layout.availableComps
                onUpdated: newList => Config.options.akebono.shelf.layout.right = newList
                onSourceUpdated: newList => Config.options.akebono.shelf.layout.availableComps = newList
            }
        }

        ContentSubsection {
            title: Translation.tr("Position")
            ConfigSelectionArray {
                currentValue: Config.options.akebono.shelf.position
                onSelected: newValue => Config.options.akebono.shelf.position = newValue
                options: [
                    { value: "bottom", displayName: Translation.tr("Bottom"), icon: "vertical_align_bottom" },
                    { value: "top", displayName: Translation.tr("Top"), icon: "vertical_align_top" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Shape")
            ConfigSelectionArray {
                currentValue: Config.options.akebono.shelf.shape
                onSelected: newValue => Config.options.akebono.shelf.shape = newValue
                options: [
                    { value: "float", displayName: Translation.tr("Float"), icon: "flip_to_front" },
                    { value: "inverseHug", displayName: Translation.tr("Inverse hug"), icon: "rounded_corner" },
                    { value: "hug", displayName: Translation.tr("Hug"), icon: "line_curve" },
                    { value: "rect", displayName: Translation.tr("Rect"), icon: "crop_square" }
                ]
            }
            ConfigSwitch {
                buttonIcon: "rounded_corner"
                text: Translation.tr("Module pills")
                checked: Config.options.akebono.shelf.pills
                onCheckedChanged: Config.options.akebono.shelf.pills = checked
                StyledToolTip {
                    text: Translation.tr("Rounded background behind each module, vs bare content on the bar")
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Size")
            ConfigSelectionArray {
                currentValue: Config.options.akebono.shelf.lengthMode
                onSelected: newValue => Config.options.akebono.shelf.lengthMode = newValue
                options: [
                    { value: "full", displayName: Translation.tr("Full"), icon: "width_full" },
                    { value: "fit", displayName: Translation.tr("Fit content"), icon: "width_normal" },
                    { value: "fixed", displayName: Translation.tr("Fixed"), icon: "straighten" }
                ]
            }
            ConfigSpinBox {
                enabled: Config.options.akebono.shelf.lengthMode === "fixed"
                icon: "straighten"
                text: Translation.tr("Fixed length")
                value: Config.options.akebono.shelf.fixedLength
                from: 400
                to: 3840
                stepSize: 20
                onValueChanged: Config.options.akebono.shelf.fixedLength = value
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Height")
                value: Config.options.akebono.shelf.height
                from: 36
                to: 96
                stepSize: 2
                onValueChanged: Config.options.akebono.shelf.height = value
            }
        }

        ContentSubsection {
            title: Translation.tr("Workspace style")
            ConfigSelectionArray {
                currentValue: Config.options.bar.workspaces.style
                onSelected: newValue => Config.options.bar.workspaces.style = newValue
                options: [
                    { value: 0, displayName: Translation.tr("Classic"), icon: "view_carousel" },
                    { value: 1, displayName: Translation.tr("Dots"), icon: "more_horiz" },
                    { value: 2, displayName: Translation.tr("Windows"), icon: "grid_view" }
                ]
            }
            ConfigSwitch {
                visible: Config.options.bar.workspaces.style === 0
                buttonIcon: "award_star"
                text: Translation.tr("Show app icons")
                checked: Config.options.bar.workspaces.showAppIcons
                onCheckedChanged: Config.options.bar.workspaces.showAppIcons = checked
            }
            ConfigSwitch {
                visible: Config.options.bar.workspaces.style === 0 && Config.options.bar.workspaces.showAppIcons
                buttonIcon: "colors"
                text: Translation.tr("Tint app icons")
                checked: Config.options.bar.workspaces.monochromeIcons
                onCheckedChanged: Config.options.bar.workspaces.monochromeIcons = checked
            }
            ConfigSwitch {
                buttonIcon: "counter_1"
                text: Translation.tr("Always show numbers")
                checked: Config.options.bar.workspaces.alwaysShowNumbers
                onCheckedChanged: Config.options.bar.workspaces.alwaysShowNumbers = checked
            }
            ConfigSwitch {
                buttonIcon: "filter_list"
                text: Translation.tr("Only occupied workspaces")
                checked: Config.options.bar.workspaces.dynamic
                onCheckedChanged: Config.options.bar.workspaces.dynamic = checked
                StyledToolTip {
                    text: Translation.tr("Show occupied and active workspaces instead of a fixed count")
                }
            }
            ConfigSwitch {
                buttonIcon: "touch_long"
                text: Translation.tr("Show numbers while holding Super")
                enabled: !Config.options.bar.workspaces.alwaysShowNumbers
                checked: Config.options.bar.workspaces.showNumberOnSuperHold
                onCheckedChanged: Config.options.bar.workspaces.showNumberOnSuperHold = checked
            }
            ConfigSpinBox {
                icon: "workspaces"
                text: Translation.tr("Workspaces shown")
                enabled: !Config.options.bar.workspaces.dynamic
                value: Config.options.bar.workspaces.shown
                from: 1
                to: 20
                stepSize: 1
                onValueChanged: Config.options.bar.workspaces.shown = value
            }
            ConfigSpinBox {
                visible: Config.options.bar.workspaces.style === 0
                icon: "select_window"
                text: Translation.tr("Max window icons per workspace")
                value: Config.options.bar.workspaces.maxWindowCount
                from: 1
                to: 20
                stepSize: 1
                onValueChanged: Config.options.bar.workspaces.maxWindowCount = value
            }
        }

        ContentSubsection {
            title: Translation.tr("Number style")
            ConfigSelectionArray {
                currentValue: JSON.stringify(Config.options.bar.workspaces.numberMap)
                onSelected: newValue => Config.options.bar.workspaces.numberMap = JSON.parse(newValue)
                options: [
                    {
                        displayName: Translation.tr("Normal"),
                        icon: "timer_10",
                        value: '[]'
                    },
                    {
                        displayName: Translation.tr("Han chars"),
                        icon: "square_dot",
                        value: '["一","二","三","四","五","六","七","八","九","十","十一","十二","十三","十四","十五","十六","十七","十八","十九","二十"]'
                    },
                    {
                        displayName: Translation.tr("Roman"),
                        icon: "account_balance",
                        value: '["I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII","XIII","XIV","XV","XVI","XVII","XVIII","XIX","XX"]'
                    },
                    {
                        displayName: Translation.tr("Spark"),
                        icon: "spark",
                        value: '["spark","spark","spark","spark","spark","spark","spark","spark","spark","spark","spark","spark","spark","spark","spark","spark","spark","spark","spark","spark"]'
                    }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Behaviour")
            ConfigSwitch {
                buttonIcon: "minimize"
                text: Translation.tr("Minimize app on icon click")
                checked: Config.options.akebono.shelf.minimizeOnClick
                onCheckedChanged: Config.options.akebono.shelf.minimizeOnClick = checked
                StyledToolTip {
                    text: Translation.tr("Click a focused app's icon to stash its windows")
                }
            }
            ConfigSwitch {
                buttonIcon: "preview"
                text: Translation.tr("Live window previews on hover")
                checked: Config.options.akebono.preview.enable
                onCheckedChanged: Config.options.akebono.preview.enable = checked
            }
            ConfigSwitch {
                buttonIcon: "open_in_new"
                text: Translation.tr("Detached popups")
                checked: Config.options.akebono.shelf.popupsDetached
                onCheckedChanged: Config.options.akebono.shelf.popupsDetached = checked
                StyledToolTip {
                    text: Translation.tr("Launcher, tray and panels float above the shelf instead of melting into it")
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Status pod")
            tooltip: Translation.tr("Which indicators show in the quick settings pill")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "wifi"
                    text: Translation.tr("Network")
                    checked: Config.options.akebono.shelf.status.network
                    onCheckedChanged: Config.options.akebono.shelf.status.network = checked
                }
                ConfigSwitch {
                    buttonIcon: "bluetooth"
                    text: Translation.tr("Bluetooth")
                    checked: Config.options.akebono.shelf.status.bluetooth
                    onCheckedChanged: Config.options.akebono.shelf.status.bluetooth = checked
                }
            }
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "volume_up"
                    text: Translation.tr("Volume")
                    checked: Config.options.akebono.shelf.status.volume
                    onCheckedChanged: Config.options.akebono.shelf.status.volume = checked
                }
                ConfigSwitch {
                    buttonIcon: "mic_off"
                    text: Translation.tr("Mic mute")
                    checked: Config.options.akebono.shelf.status.mic
                    onCheckedChanged: Config.options.akebono.shelf.status.mic = checked
                }
            }
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "notifications"
                    text: Translation.tr("Notifications")
                    checked: Config.options.akebono.shelf.status.notifications
                    onCheckedChanged: Config.options.akebono.shelf.status.notifications = checked
                }
                ConfigSwitch {
                    buttonIcon: "battery_android_full"
                    text: Translation.tr("Battery")
                    checked: Config.options.akebono.shelf.status.battery
                    onCheckedChanged: Config.options.akebono.shelf.status.battery = checked
                }
            }
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "font_download"
                    text: Translation.tr("Caps lock")
                    checked: Config.options.akebono.shelf.status.capsLock
                    onCheckedChanged: Config.options.akebono.shelf.status.capsLock = checked
                }
                ConfigSwitch {
                    buttonIcon: "keyboard"
                    text: Translation.tr("Keyboard layout")
                    checked: Config.options.akebono.shelf.status.keyboardLayout
                    onCheckedChanged: Config.options.akebono.shelf.status.keyboardLayout = checked
                    StyledToolTip {
                        text: Translation.tr("Only shows when more than one xkb layout is configured")
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "side_navigation"
        title: Translation.tr("Sidebars")

        ContentSubsection {
            title: Translation.tr("Corner open")
            tooltip: Translation.tr("Open the sidebars by clicking or hovering the screen corners")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.sidebar.cornerOpen.enable
                    onCheckedChanged: Config.options.sidebar.cornerOpen.enable = checked
                }
                ConfigSwitch {
                    buttonIcon: "highlight_mouse_cursor"
                    text: Translation.tr("Hover to trigger")
                    enabled: Config.options.sidebar.cornerOpen.enable
                    checked: Config.options.sidebar.cornerOpen.clickless
                    onCheckedChanged: Config.options.sidebar.cornerOpen.clickless = checked
                    StyledToolTip {
                        text: Translation.tr("When this is off you'll have to click the corner")
                    }
                }
            }
            ConfigSwitch {
                buttonIcon: "adjust"
                text: Translation.tr("Force hover open at absolute corner")
                enabled: Config.options.sidebar.cornerOpen.enable && !Config.options.sidebar.cornerOpen.clickless
                checked: Config.options.sidebar.cornerOpen.clicklessCornerEnd
                onCheckedChanged: Config.options.sidebar.cornerOpen.clicklessCornerEnd = checked
                StyledToolTip {
                    text: Translation.tr("With hover off, the very corner still opens the sidebar\nand the rest of the region stays free for volume/brightness scroll")
                }
            }
            ConfigSpinBox {
                icon: "arrow_cool_down"
                text: Translation.tr("Corner vertical offset")
                enabled: Config.options.sidebar.cornerOpen.enable && !Config.options.sidebar.cornerOpen.clickless && Config.options.sidebar.cornerOpen.clicklessCornerEnd
                value: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset
                from: 0
                to: 20
                stepSize: 1
                onValueChanged: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset = value
            }
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "vertical_align_bottom"
                    text: Translation.tr("Place at bottom")
                    enabled: Config.options.sidebar.cornerOpen.enable
                    checked: Config.options.sidebar.cornerOpen.bottom
                    onCheckedChanged: Config.options.sidebar.cornerOpen.bottom = checked
                    StyledToolTip {
                        text: Translation.tr("Use the bottom corners instead of the top ones")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "unfold_more_double"
                    text: Translation.tr("Value scroll")
                    enabled: Config.options.sidebar.cornerOpen.enable
                    checked: Config.options.sidebar.cornerOpen.valueScroll
                    onCheckedChanged: Config.options.sidebar.cornerOpen.valueScroll = checked
                    StyledToolTip {
                        text: Translation.tr("Scroll the corners for brightness (left) and volume (right)")
                    }
                }
            }
            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Visualize region")
                enabled: Config.options.sidebar.cornerOpen.enable
                checked: Config.options.sidebar.cornerOpen.visualize
                onCheckedChanged: Config.options.sidebar.cornerOpen.visualize = checked
            }
            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "arrow_range"
                    text: Translation.tr("Region width")
                    enabled: Config.options.sidebar.cornerOpen.enable
                    value: Config.options.sidebar.cornerOpen.cornerRegionWidth
                    from: 1
                    to: 300
                    stepSize: 1
                    onValueChanged: Config.options.sidebar.cornerOpen.cornerRegionWidth = value
                }
                ConfigSpinBox {
                    icon: "height"
                    text: Translation.tr("Region height")
                    enabled: Config.options.sidebar.cornerOpen.enable
                    value: Config.options.sidebar.cornerOpen.cornerRegionHeight
                    from: 1
                    to: 300
                    stepSize: 1
                    onValueChanged: Config.options.sidebar.cornerOpen.cornerRegionHeight = value
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "memory"
            text: Translation.tr("Keep right sidebar loaded")
            checked: Config.options.sidebar.keepRightSidebarLoaded
            onCheckedChanged: Config.options.sidebar.keepRightSidebarLoaded = checked
            StyledToolTip {
                text: Translation.tr("Faster to open, uses a bit more memory")
            }
        }
    }

    ContentSection {
        icon: "widgets"
        title: Translation.tr("Dock")

        ConfigSwitch {
            buttonIcon: "dock_to_bottom"
            text: Translation.tr("Standalone dock")
            checked: Config.options.akebono.standaloneDock
            onCheckedChanged: Config.options.akebono.standaloneDock = checked
            StyledToolTip {
                text: Translation.tr("A separate auto-hiding app dock at the bottom. Pairs well with the shelf on top")
            }
        }
        ColumnLayout {
            visible: Config.options.akebono.standaloneDock
            Layout.fillWidth: true
            spacing: 4

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "highlight_mouse_cursor"
                    text: Translation.tr("Hover to reveal")
                    checked: Config.options.dock.hoverToReveal
                    onCheckedChanged: Config.options.dock.hoverToReveal = checked
                    StyledToolTip {
                        text: Translation.tr("When off, the dock only reveals on empty workspaces")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "keep"
                    text: Translation.tr("Pinned")
                    checked: Config.options.dock.pinnedOnStartup
                    onCheckedChanged: Config.options.dock.pinnedOnStartup = checked
                    StyledToolTip {
                        text: Translation.tr("Always visible, reserves screen space")
                    }
                }
            }
            ConfigSwitch {
                buttonIcon: "delete"
                text: Translation.tr("Show trash")
                checked: Config.options.dock.showTrash
                onCheckedChanged: Config.options.dock.showTrash = checked
                StyledToolTip {
                    text: Translation.tr("A macOS-style trash at the end of the dock. Drag files onto it to delete")
                }
            }
            ConfigSwitch {
                buttonIcon: "colors"
                text: Translation.tr("Tint app icons")
                checked: Config.options.dock.monochromeIcons
                onCheckedChanged: Config.options.dock.monochromeIcons = checked
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Size")
                value: Config.options.dock.height
                from: 44
                to: 110
                stepSize: 2
                onValueChanged: Config.options.dock.height = value
            }
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("Quick settings")

        ConfigSwitch {
            buttonIcon: "swipe"
            text: Translation.tr("Single-row toggles")
            checked: Config.options.akebono.shelf.quickSettings.flickable
            onCheckedChanged: Config.options.akebono.shelf.quickSettings.flickable = checked
            StyledToolTip {
                text: Translation.tr("Toggles scroll horizontally instead of wrapping")
            }
        }
    }

    ContentSection {
        icon: "music_note"
        title: Translation.tr("Media")

        ContentSubsection {
            title: Translation.tr("Bar widget")
            ConfigSelectionArray {
                currentValue: Config.options.akebono.shelf.media.layout
                onSelected: newValue => Config.options.akebono.shelf.media.layout = newValue
                options: [
                    { value: "art", displayName: Translation.tr("Album art"), icon: "art_track" },
                    { value: "icon", displayName: Translation.tr("Icon"), icon: "music_note" }
                ]
            }
            ConfigSwitch {
                buttonIcon: "title"
                text: Translation.tr("Show title")
                checked: Config.options.akebono.shelf.media.showTitle
                onCheckedChanged: Config.options.akebono.shelf.media.showTitle = checked
                StyledToolTip {
                    text: Translation.tr("Album-art mode: off shows just the cover")
                }
            }
        }
        ConfigSwitch {
            buttonIcon: "lyrics"
            text: Translation.tr("Show lyrics in the bar")
            checked: Config.options.akebono.shelf.media.showLyricsInline
            onCheckedChanged: Config.options.akebono.shelf.media.showLyricsInline = checked
            StyledToolTip {
                text: Translation.tr("Replace the title with the live synced lyrics (3 lines)")
            }
        }
        ConfigSwitch {
            buttonIcon: "graphic_eq"
            text: Translation.tr("Audio-reactive popup ripple")
            checked: Config.options.akebono.shelf.media.audioRipple
            onCheckedChanged: Config.options.akebono.shelf.media.audioRipple = checked
            StyledToolTip {
                text: Translation.tr("Bass-driven bumps ride the popup's edge (experimental, WIP)")
            }
        }

        ContentSubsection {
            title: Translation.tr("Lyrics")
            visible: Config.options.akebono.shelf.media.showLyricsInline
            ConfigSwitch {
                buttonIcon: "width_full"
                text: Translation.tr("Expand to fit the lyric line")
                checked: Config.options.akebono.shelf.media.lyricsExpand
                onCheckedChanged: Config.options.akebono.shelf.media.lyricsExpand = checked
                StyledToolTip {
                    text: Translation.tr("Grow the widget to the full line instead of a fixed width")
                }
            }
            ConfigSwitch {
                buttonIcon: "cloud_download"
                text: Translation.tr("Fetch from LRCLIB")
                checked: Config.options.media.lyrics.online
                onCheckedChanged: Config.options.media.lyrics.online = checked
                StyledToolTip {
                    text: Translation.tr("Download synced lyrics when no local .lrc file is found")
                }
            }
            ConfigSpinBox {
                icon: "av_timer"
                text: Translation.tr("Sync offset (ms)")
                value: Math.round(Config.options.media.lyrics.offset * 1000)
                from: -3000
                to: 3000
                stepSize: 50
                onValueChanged: Config.options.media.lyrics.offset = value / 1000
            }
        }
    }

    ContentSection {
        icon: "apps"
        title: Translation.tr("Launcher")

        ContentSubsection {
            title: Translation.tr("Style")
            ConfigSelectionArray {
                currentValue: Config.options.akebono.runner.style
                onSelected: newValue => Config.options.akebono.runner.style = newValue
                options: [
                    { value: "shelf", displayName: Translation.tr("Shelf"), icon: "dock_to_bottom" },
                    { value: "sheet", displayName: Translation.tr("Sheet"), icon: "web_asset" }
                ]
            }
        }
        ContentSubsection {
            title: Translation.tr("Sheet size")
            visible: Config.options.akebono.runner.style === "sheet"
            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "arrow_range"
                    text: Translation.tr("Width")
                    value: Config.options.akebono.runner.sheetWidth
                    from: 480
                    to: 1600
                    stepSize: 20
                    onValueChanged: Config.options.akebono.runner.sheetWidth = value
                }
                ConfigSpinBox {
                    icon: "height"
                    text: Translation.tr("Height")
                    value: Config.options.akebono.runner.sheetHeight
                    from: 360
                    to: 1200
                    stepSize: 20
                    onValueChanged: Config.options.akebono.runner.sheetHeight = value
                }
            }
        }
        ConfigSwitch {
            buttonIcon: "star"
            text: Translation.tr("Show favourites when empty")
            checked: Config.options.akebono.runner.favourites
            onCheckedChanged: Config.options.akebono.runner.favourites = checked
        }
        ConfigSwitch {
            buttonIcon: "blur_on"
            text: Translation.tr("Dim background")
            checked: Config.options.akebono.runner.dim
            onCheckedChanged: Config.options.akebono.runner.dim = checked
        }
        ConfigSwitch {
            buttonIcon: "mood"
            text: Translation.tr("Separate glyph picker")
            checked: Config.options.akebono.runner.glyphPicker
            onCheckedChanged: Config.options.akebono.runner.glyphPicker = checked
            StyledToolTip {
                text: Translation.tr("Emoji and symbols open in a small picker at the cursor instead of the full launcher")
            }
        }
        ContentSubsection {
            title: Translation.tr("Glyph picker size")
            visible: Config.options.akebono.runner.glyphPicker
            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "arrow_range"
                    text: Translation.tr("Width")
                    value: Config.options.akebono.runner.glyphPickerWidth
                    from: 240
                    to: 900
                    stepSize: 20
                    onValueChanged: Config.options.akebono.runner.glyphPickerWidth = value
                }
                ConfigSpinBox {
                    icon: "height"
                    text: Translation.tr("Height")
                    value: Config.options.akebono.runner.glyphPickerHeight
                    from: 200
                    to: 800
                    stepSize: 20
                    onValueChanged: Config.options.akebono.runner.glyphPickerHeight = value
                }
            }
            ConfigSpinBox {
                icon: "format_size"
                text: Translation.tr("Content scale (%)")
                value: Config.options.akebono.runner.glyphPickerScale
                from: 70
                to: 200
                stepSize: 10
                onValueChanged: Config.options.akebono.runner.glyphPickerScale = value
            }
        }
    }

    ContentSection {
        icon: "power_settings_new"
        title: Translation.tr("Session")

        ContentSubsection {
            title: Translation.tr("GIF above the buttons")
            tooltip: Translation.tr("Link or path to a gif or image, shown in the session screen. Leave empty to disable")
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Height")
                value: Config.options.akebono.session.gifHeight
                from: 80
                to: 600
                stepSize: 20
                onValueChanged: Config.options.akebono.session.gifHeight = value
            }
            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Link or path")
                text: Config.options.akebono.session.gifPath
                onEditingFinished: Config.options.akebono.session.gifPath = text
            }
        }
    }

    ContentSection {
        icon: "water_drop"
        title: Translation.tr("Look")

        ContentSubsection {
            title: Translation.tr("Squircle corner smoothing")
            tooltip: Translation.tr("2 = circular, higher = squircle")
            ConfigSpinBox {
                icon: "rounded_corner"
                text: Translation.tr("Smoothing")
                value: Math.round(Config.options.akebono.squircle.smoothing)
                from: 2
                to: 8
                stepSize: 1
                onValueChanged: Config.options.akebono.squircle.smoothing = value
            }
        }
        ContentSubsection {
            title: Translation.tr("Window title bars")
            tooltip: Translation.tr("Needs the hyprbars plugin")

            ConfigSwitch {
                buttonIcon: "web_asset"
                text: Translation.tr("Enable")
                checked: Config.options.akebono.hyprbars.enable
                onCheckedChanged: Config.options.akebono.hyprbars.enable = checked
            }
            ConfigSwitch {
                visible: Config.options.akebono.hyprbars.enable
                buttonIcon: "crop_square"
                text: Translation.tr("Glyph buttons")
                checked: Config.options.akebono.hyprbars.glyphs
                onCheckedChanged: Config.options.akebono.hyprbars.glyphs = checked
                StyledToolTip {
                    text: Translation.tr("Minimize/maximize/close icons instead of blank semaphore dots")
                }
            }
            ConfigSwitch {
                visible: Config.options.akebono.hyprbars.enable
                buttonIcon: "palette"
                text: Translation.tr("macOS colors")
                checked: Config.options.akebono.hyprbars.macColors
                onCheckedChanged: Config.options.akebono.hyprbars.macColors = checked
                StyledToolTip {
                    text: Translation.tr("Classic red / yellow / green instead of your theme accents")
                }
            }
            MaterialTextField {
                Layout.fillWidth: true
                visible: Config.options.akebono.hyprbars.enable
                placeholderText: Translation.tr("Title font, empty follows the title font")
                text: Config.options.akebono.hyprbars.font
                onEditingFinished: Config.options.akebono.hyprbars.font = text
            }
        }
    }
}
