import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()
    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property var shelfUsedIds: {
        const ids = [];
        const lists = [
            Config.options.akebono.shelf.layout.left,
            Config.options.akebono.shelf.layout.center,
            Config.options.akebono.shelf.layout.right
        ];
        for (const list of lists)
            for (const item of list)
                ids.push(item.id);
        return ids;
    }

    // Shelf components whose metadata comes from the shared bar registry gain
    // the bar's extras (inline style picker, settings sub-page, sidebar page
    // button). Duplicates are blocked once in use, unless the registry marks
    // the component as allowMultiple (audio visualizer).
    readonly property var shelfAvailableComponents: Config.options.akebono.shelf.layout.availableComps.filter(comp => {
        if (!root.shelfUsedIds.includes(comp.id))
            return true;
        const barInfo = BarComponentRegistry.getComponent(comp.id);
        return barInfo !== null && barInfo.allowMultiple;
    })

    function shelfComponentInfo(compId) {
        const comp = Config.options.akebono.shelf.layout.availableComps.find(x => x.id === compId);
        if (!comp)
            return null;
        const barInfo = BarComponentRegistry.getComponent(compId);
        return barInfo ? Object.assign({}, barInfo, comp) : comp;
    }

    function openWidgetPage(componentId) {
        page.openWidgetPage(componentId);
    }

    // Style selector for one shelf widget. Writes the shared bar style key, the
    // same one BarWidgetRegistry.getStyle() reads back for the shelf chip, so
    // both bar and shelf stay in sync.
    component ShelfStyleRow: ColumnLayout {
        id: styleRow
        required property string title
        required property string configKey
        required property var styleOptions

        function read() {
            const s = Config.options.bar.styles;
            switch (styleRow.configKey) {
                case "utilButtons": return s.utilButtons;
                case "battery": return s.battery;
                case "keyboard": return s.keyboard;
                case "bluetooth": return s.bluetooth;
                case "sports": return s.sports;
                case "portWatcher": return s.portWatcher;
                case "aiPlanUsage": return s.aiPlanUsage;
                case "activeWindow": return s.activeWindow;
                case "dashboard": return s.dashboard;
                default: return "default";
            }
        }
        function write(newValue) {
            const s = Config.options.bar.styles;
            switch (styleRow.configKey) {
                case "utilButtons": s.utilButtons = String(newValue); break;
                case "battery": s.battery = String(newValue); break;
                case "keyboard": s.keyboard = String(newValue); break;
                case "bluetooth": s.bluetooth = String(newValue); break;
                case "sports": s.sports = String(newValue); break;
                case "portWatcher": s.portWatcher = String(newValue); break;
                case "aiPlanUsage": s.aiPlanUsage = String(newValue); break;
                case "activeWindow": s.activeWindow = String(newValue); break;
                case "dashboard": s.dashboard = String(newValue); break;
            }
        }

        Layout.fillWidth: true
        spacing: 2

        StyledText {
            Layout.fillWidth: true
            text: styleRow.title
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnLayer0
        }

        ConfigSelectionArray {
            currentValue: styleRow.read()
            onSelected: newValue => styleRow.write(newValue)
            options: styleRow.styleOptions
        }
    }

    ContentPage {
        id: page

        function openWidgetPage(componentId) {
            const compInfo = BarComponentRegistry.getComponent(componentId);
            if (!compInfo)
                return;
            if (typeof compInfo.pageId !== "undefined") {
                var win = root.QsWindow.window;
                if (win && win.pageIndexById !== undefined) {
                    if (compInfo.sectionTitle)
                        win.pendingSectionHighlight = Translation.tr(compInfo.sectionTitle);
                    win.currentPage = win.pageIndexById(compInfo.pageId);
                }
            } else if (compInfo.configPage) {
                subPageOverlay.open(Qt.resolvedUrl("widgets/" + compInfo.configPage));
            }
        }

        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 20
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Akebono")
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
            }
        }

        ContentSection {
            icon: "flip_to_front"
            title: Translation.tr("Desktop mode")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                ConfigSwitch {
                    buttonIcon: "web_stories"
                    text: Translation.tr("Floating windows while Aqebono is active")
                    checked: Config.options.akebono.desktop.floating
                    onCheckedChanged: Config.options.akebono.desktop.floating = checked
                }

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "info"
                    text: Translation.tr("Everything already on screen floats; windows placed with “Separated windows” stay as they are. The recommendation is honor-safe: on the shelf sandbox the change only lands while this family is the panel family.")
                }

                ConfigSubpageRow {
                    Layout.fillWidth: true
                    buttonIcon: "desktop_windows"
                    title: Translation.tr("Desktop")
                    description: Translation.tr("Wallpaper, blurred-glass panels, background time and the desktop grid")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("../../akebono/settings/pages/DesktopConfig.qml"))
                }
            }
        }

        ContentSection {
            icon: "web_asset"
            title: Translation.tr("Window title bars")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "info"
                    text: Translation.tr("Aqebono's title bars come from the hyprbars plugin. Changes here apply to already-open windows, so there is no need to restart Hyprland.")
                }

                ConfigSwitch {
                    buttonIcon: "web_asset"
                    text: Translation.tr("Enable")
                    checked: Config.options.akebono.hyprbars.enable
                    onCheckedChanged: Config.options.akebono.hyprbars.enable = checked
                }

                ConfigSpinBox {
                    icon: "height"
                    text: Translation.tr("Bar height")
                    value: Config.options.akebono.hyprbars.barHeight
                    from: 20
                    to: 56
                    stepSize: 2
                    onValueChanged: Config.options.akebono.hyprbars.barHeight = value
                }

                ConfigSwitch {
                    buttonIcon: "crop_square"
                    text: Translation.tr("Glyph buttons")
                    checked: Config.options.akebono.hyprbars.glyphs
                    onCheckedChanged: Config.options.akebono.hyprbars.glyphs = checked
                    StyledToolTip {
                        text: Translation.tr("Minimize/maximize/close icons instead of blank semaphore dots")
                    }
                }

                ConfigSwitch {
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
                    placeholderText: Translation.tr("Title font, empty follows the title font")
                    text: Config.options.akebono.hyprbars.font
                    onEditingFinished: Config.options.akebono.hyprbars.font = text
                }
            }
        }

        ContentSection {
            icon: "dock_to_bottom"
            title: Translation.tr("Shelf")

            ContentSubsection {
                title: Translation.tr("Left zone")
                ConfigListView {
                    barSection: 0
                    listModel: Config.options.akebono.shelf.layout.left
                    availableComponents: root.shelfAvailableComponents
                    infoProvider: compId => root.shelfComponentInfo(compId)
                    normalizeEntry: comp => ({ id: comp.id, icon: comp.icon, title: comp.title, centered: comp.centered, visible: comp.visible, scrollTo: comp.scrollTo })
                    onUpdated: newList => Config.options.akebono.shelf.layout.left = newList
                }
            }

            ContentSubsection {
                title: Translation.tr("Center zone")
                tooltip: Translation.tr("Use the center button to pin a component to the middle")
                ConfigListView {
                    barSection: 1
                    listModel: Config.options.akebono.shelf.layout.center
                    availableComponents: root.shelfAvailableComponents
                    infoProvider: compId => root.shelfComponentInfo(compId)
                    normalizeEntry: comp => ({ id: comp.id, icon: comp.icon, title: comp.title, centered: comp.centered, visible: comp.visible, scrollTo: comp.scrollTo })
                    onUpdated: newList => Config.options.akebono.shelf.layout.center = newList
                }
            }

            ContentSubsection {
                title: Translation.tr("Right zone")
                ConfigListView {
                    barSection: 2
                    listModel: Config.options.akebono.shelf.layout.right
                    availableComponents: root.shelfAvailableComponents
                    infoProvider: compId => root.shelfComponentInfo(compId)
                    normalizeEntry: comp => ({ id: comp.id, icon: comp.icon, title: comp.title, centered: comp.centered, visible: comp.visible, scrollTo: comp.scrollTo })
                    onUpdated: newList => Config.options.akebono.shelf.layout.right = newList
                }
            }

            ContentSubsection {
                title: Translation.tr("Position")
                ConfigSelectionArray {
                    currentValue: Config.options.akebono.shelf.position
                    onSelected: newValue => Config.options.akebono.shelf.position = newValue
                    options: [
                        {
                            displayName: Translation.tr("Top"),
                            icon: "arrow_upward",
                            value: "top"
                        },
                        {
                            displayName: Translation.tr("Bottom"),
                            icon: "arrow_downward",
                            value: "bottom"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Shape")
                ConfigSelectionArray {
                    currentValue: Config.options.akebono.shelf.shape
                    onSelected: newValue => Config.options.akebono.shelf.shape = newValue
                    options: [
                        { displayName: Translation.tr("Float"), icon: "flip_to_front", value: "float" },
                        { displayName: Translation.tr("Inverse hug"), icon: "rounded_corner", value: "inverseHug" },
                        { displayName: Translation.tr("Hug"), icon: "line_curve", value: "hug" },
                        { displayName: Translation.tr("Rect"), icon: "crop_square", value: "rect" }
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
                title: Translation.tr("Behaviour")
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
                title: Translation.tr("Widget styles")

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ShelfStyleRow {
                        title: Translation.tr("Utility buttons")
                        configKey: "utilButtons"
                        styleOptions: [
                            { displayName: Translation.tr("Default"), icon: "style", value: "default" },
                            { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" },
                            { displayName: Translation.tr("Segments"), icon: "view_week", value: "segments" }
                        ]
                    }
                    ShelfStyleRow {
                        title: Translation.tr("Battery")
                        configKey: "battery"
                        styleOptions: [
                            { displayName: Translation.tr("Default"), icon: "battery_full", value: "default" },
                            { displayName: Translation.tr("Expressive"), icon: "battery_charging_full", value: "expressive" }
                        ]
                    }
                    ShelfStyleRow {
                        title: Translation.tr("Keyboard layout")
                        configKey: "keyboard"
                        styleOptions: [
                            { displayName: Translation.tr("Default"), icon: "keyboard", value: "default" },
                            { displayName: Translation.tr("Expressive"), icon: "keyboard_capslock", value: "expressive" }
                        ]
                    }
                    ShelfStyleRow {
                        title: Translation.tr("Bluetooth")
                        configKey: "bluetooth"
                        styleOptions: [
                            { displayName: Translation.tr("Default"), icon: "bluetooth", value: "default" },
                            { displayName: Translation.tr("Expressive"), icon: "bluetooth_searching", value: "expressive" }
                        ]
                    }
                    ShelfStyleRow {
                        title: Translation.tr("Sports")
                        configKey: "sports"
                        styleOptions: [
                            { displayName: Translation.tr("Default"), icon: "sports_soccer", value: "default" },
                            { displayName: Translation.tr("Expressive"), icon: "sports_volleyball", value: "expressive" }
                        ]
                    }
                    ShelfStyleRow {
                        title: Translation.tr("Port watcher")
                        configKey: "portWatcher"
                        styleOptions: [
                            { displayName: Translation.tr("Default"), icon: "router", value: "default" },
                            { displayName: Translation.tr("Expressive"), icon: "lan", value: "expressive" }
                        ]
                    }
                    ShelfStyleRow {
                        title: Translation.tr("AI plan usage")
                        configKey: "aiPlanUsage"
                        styleOptions: [
                            { displayName: Translation.tr("Default"), icon: "memory", value: "default" },
                            { displayName: Translation.tr("Expressive"), icon: "auto_awesome", value: "expressive" }
                        ]
                    }
                    ShelfStyleRow {
                        title: Translation.tr("Active window")
                        configKey: "activeWindow"
                        styleOptions: [
                            { displayName: Translation.tr("Default"), icon: "crop_square", value: "default" },
                            { displayName: Translation.tr("Expressive"), icon: "picture_in_picture_alt", value: "expressive" }
                        ]
                    }
                    ShelfStyleRow {
                        title: Translation.tr("Quick settings")
                        configKey: "dashboard"
                        styleOptions: [
                            { displayName: Translation.tr("Default"), icon: "tune", value: "default" },
                            { displayName: Translation.tr("Expressive"), icon: "tune", value: "expressive" },
                            { displayName: Translation.tr("Orbs"), icon: "blur_on", value: "orbs" }
                        ]
                    }
                }
            }
        }

        ContentSection {
            icon: "tune"
            title: Translation.tr("Quick settings")

            ContentSubsection {
                title: Translation.tr("Style")
                ConfigSelectionArray {
                    currentValue: Config.options.akebono.shelf.quickSettings.style
                    onSelected: newValue => Config.options.akebono.shelf.quickSettings.style = newValue
                    options: [
                        { value: "android", displayName: "Android", icon: "smartphone" },
                        { value: "classic", displayName: Translation.tr("Classic"), icon: "view_list" },
                        { value: "abstract", displayName: Translation.tr("Compact"), icon: "widgets" }
                    ]
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Independent from the sidebar quick toggles")
                    color: Appearance.colors.colSubtextOnLayer2
                    font.pixelSize: 12
                }
            }

            ConfigSwitch {
                buttonIcon: "swipe"
                text: Translation.tr("Single-row toggles")
                checked: Config.options.akebono.shelf.quickSettings.flickable
                onCheckedChanged: Config.options.akebono.shelf.quickSettings.flickable = checked
                StyledToolTip {
                    text: Translation.tr("Toggles scroll horizontally instead of wrapping")
                }
            }

            ConfigSpinBox {
                visible: Config.options.akebono.shelf.quickSettings.style === "android"
                icon: "view_column"
                text: Translation.tr("Android style Columns")
                // The family's own grid, not a shared one. See PanelFamily.quickToggleLayout.
                value: Config.options.akebono.shelf.quickSettings.columns
                from: 1
                to: 6
                stepSize: 1
                onValueChanged: Config.options.akebono.shelf.quickSettings.columns = value
            }

            ConfigSwitch {
                visible: Config.options.akebono.shelf.quickSettings.style === "android"
                buttonIcon: "tune"
                text: Translation.tr("Use 2x1 Capsule Sliders for 3-State Toggles")
                checked: Config.options.akebono.shelf.quickSettings.useThreeWaySliders
                onCheckedChanged: Config.options.akebono.shelf.quickSettings.useThreeWaySliders = checked
                StyledToolTip {
                    text: Translation.tr("Convert compatible 3-state widgets (ANC, Power Profiles, Keyboard Light) into 2x1 slide/swipe toggles.")
                }
            }

            ContentSubsection {
                title: Translation.tr("Fixed sliders")
                icon: "linear_scale"
                visible: Config.options.akebono.shelf.quickSettings.style === "android"

                ConfigSwitch {
                    buttonIcon: "linear_scale"
                    text: Translation.tr("Enable fixed sliders")
                    checked: Config.options.akebono.shelf.quickSliders.enable
                    onCheckedChanged: Config.options.akebono.shelf.quickSliders.enable = checked
                    StyledToolTip {
                        text: Translation.tr("Pin the sliders above the Android quick-toggle grid instead of keeping them inside a page.")
                    }
                }

                ConfigSwitch {
                    enabled: Config.options.akebono.shelf.quickSliders.enable
                    buttonIcon: "brightness_high"
                    text: Translation.tr("Show Brightness")
                    checked: Config.options.akebono.shelf.quickSliders.showBrightness
                    onCheckedChanged: Config.options.akebono.shelf.quickSliders.showBrightness = checked
                }

                ConfigSwitch {
                    enabled: Config.options.akebono.shelf.quickSliders.enable
                    buttonIcon: "contrast"
                    text: Translation.tr("Show Gamma")
                    checked: Config.options.akebono.shelf.quickSliders.showGamma
                    onCheckedChanged: Config.options.akebono.shelf.quickSliders.showGamma = checked
                }

                ConfigSwitch {
                    enabled: Config.options.akebono.shelf.quickSliders.enable
                    buttonIcon: "volume_up"
                    text: Translation.tr("Show Volume")
                    checked: Config.options.akebono.shelf.quickSliders.showVolume
                    onCheckedChanged: Config.options.akebono.shelf.quickSliders.showVolume = checked
                }

                ConfigSwitch {
                    enabled: Config.options.akebono.shelf.quickSliders.enable
                    buttonIcon: "mic"
                    text: Translation.tr("Show Microphone")
                    checked: Config.options.akebono.shelf.quickSliders.showMic
                    onCheckedChanged: Config.options.akebono.shelf.quickSliders.showMic = checked
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
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}