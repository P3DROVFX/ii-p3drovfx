import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Root Item wraps the scrollable page + the slide-in sub-page overlay.
// The `contentY` alias lets settings.qml search-scroll still work.
Item {
    id: barConfigRoot

    property alias contentY: page.contentY
    // ── Active sub-page URL ("" = none) ───────────────────────────────────
    property alias activeSubPage: subPageOverlay.activeSubPage

    // ── Main content page ─────────────────────────────────────────────────
    ContentPage {
        id: page

        function openWidgetPage(componentId) {
            const compInfo = BarComponentRegistry.getComponent(componentId);
            if (compInfo) {
                if (typeof compInfo.pageId !== "undefined") {
                    var win = barConfigRoot.QsWindow.window;
                    if (win && win.pageIndexById !== undefined) {
                        if (compInfo.sectionTitle)
                            win.pendingSectionHighlight = Translation.tr(compInfo.sectionTitle);

                        win.currentPage = win.pageIndexById(compInfo.pageId);
                    }
                } else if (compInfo.configPage) {
                    barConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/" + compInfo.configPage);
                }
            }
        }

        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        // ── Shell mode ────────────────────────────────────────────────────
        ContentSection {
            icon: "phone_android"
            title: Translation.tr("Shell mode")

            ContentSubsection {
                title: Translation.tr("Style")
                icon: "style"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.sidebar.sidebarStyle
                    onSelected: (newValue) => {
                        Config.options.sidebar.sidebarStyle = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Default"),
                        "icon": "view_sidebar",
                        "value": "default"
                    }, {
                        "displayName": Translation.tr("Connect"),
                        "icon": "phone_android",
                        "value": "connect"
                    }]
                }

            }

            NoticeBox {
                Layout.fillWidth: true
                visible: Config.options.bar.autoHide.enable
                text: Translation.tr("Bar auto-hide is not supported by Search Connect Mode yet. Disable auto-hide to use the drop search.")
            }
        }

        // ── Layout ────────────────────────────────────────────────────────
        ContentSection {
            icon: "view_stream"
            title: Translation.tr("Layout")

            ContentSubsection {
                title: Translation.tr("Left layout widgets")
                icon: "align_horizontal_left"
                tooltip: Translation.tr("Top layout in vertical mode")

                ConfigListView {
                    barSection: 0
                    listModel: Config.options.bar.layouts.left
                    onUpdated: (newList) => {
                        Config.options.bar.layouts.left = newList;
                    }
                }

            }

            ContentSubsection {
                title: Translation.tr("Center layout widgets")
                icon: "align_horizontal_center"
                tooltip: Translation.tr("Center the component with the button")

                ConfigListView {
                    barSection: 1
                    listModel: Config.options.bar.layouts.center
                    onUpdated: (newList) => {
                        Config.options.bar.layouts.center = newList;
                    }
                }

            }

            ContentSubsection {
                title: Translation.tr("Right layout widgets")
                icon: "align_horizontal_right"
                tooltip: Translation.tr("Bottom layout in vertical mode")

                ConfigListView {
                    barSection: 2
                    listModel: Config.options.bar.layouts.right
                    onUpdated: (newList) => {
                        Config.options.bar.layouts.right = newList;
                    }
                }

            }

        }

        // ── Position & size ───────────────────────────────────────────────
        ContentSection {
            icon: "open_in_full"
            title: Translation.tr("Position & size")

            ContentSubsection {
                title: Translation.tr("Bar position")
                icon: "dock"

                ConfigSelectionArray {
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: (newValue) => {
                        Config.options.bar.bottom = (newValue & 1) !== 0;
                        Config.options.bar.vertical = (newValue & 2) !== 0;
                    }
                    options: [{
                        "displayName": Translation.tr("Top"),
                        "icon": "arrow_upward",
                        "value": 0
                    }, {
                        "displayName": Translation.tr("Left"),
                        "icon": "arrow_back",
                        "value": 2
                    }, {
                        "displayName": Translation.tr("Bottom"),
                        "icon": "arrow_downward",
                        "value": 1
                    }, {
                        "displayName": Translation.tr("Right"),
                        "icon": "arrow_forward",
                        "value": 3
                    }]
                }

            }

            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Bar height")
                value: Config.options.bar.sizes.height
                from: 30
                to: 50
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.sizes.height = value;
                }
            }

            ConfigSpinBox {
                visible: Config.options.bar.vertical
                icon: "width"
                text: Translation.tr("Bar width")
                value: Config.options.bar.sizes.width
                from: 30
                to: 50
                stepSize: 1
                onValueChanged: {
                    Config.options.bar.sizes.width = value;
                }
            }

        }

        // ── Style ─────────────────────────────────────────────────────────
        ContentSection {
            icon: "palette"
            title: Translation.tr("Style")

            ContentSubsection {
                title: Translation.tr("Corner style")
                icon: "rounded_corner"

                ConfigSelectionArray {
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: (newValue) => {
                        Config.options.bar.cornerStyle = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Hug"),
                        "icon": "line_curve",
                        "value": 0
                    }, {
                        "displayName": Translation.tr("Float"),
                        "icon": "page_header",
                        "value": 1
                    }, {
                        "displayName": Translation.tr("Rect"),
                        "icon": "toolbar",
                        "value": 2
                    }, {
                        "displayName": Translation.tr("Dynamic Island"),
                        "icon": "water_drop",
                        "value": 3
                    }]
                }

            }

            ConfigSwitch {
                buttonIcon: "auto_fix"
                text: Translation.tr("Auto spacing")
                visible: Config.options.bar.cornerStyle === 3
                checked: Config.options.bar.dynamicIslandLoadBalance
                onCheckedChanged: {
                    Config.options.bar.dynamicIslandLoadBalance = checked;
                }
            }

            ConfigSlider {
                buttonIcon: "space_bar"
                text: Translation.tr("Dynamic Island spacing")
                visible: Config.options.bar.cornerStyle === 3 && !Config.options.bar.dynamicIslandLoadBalance
                usePercentTooltip: false
                from: Config.options.bar.vertical ? 16 : 48
                to: Config.options.bar.vertical ? 100 : 250
                stepSize: 1
                value: Config.options.bar.vertical ? Config.options.bar.dynamicIslandSpacingVertical : Config.options.bar.dynamicIslandSpacingHorizontal
                onValueChanged: {
                    if (Config.options.bar.vertical)
                        Config.options.bar.dynamicIslandSpacingVertical = value;
                    else
                        Config.options.bar.dynamicIslandSpacingHorizontal = value;
                }
            }

            ContentSubsection {
                title: Translation.tr("Group style")
                icon: "group_work"
                tooltip: Translation.tr("Island style makes the group background opaque when bar is transparent")

                ConfigSelectionArray {
                    currentValue: Config.options.bar.barGroupStyle
                    onSelected: (newValue) => {
                        Config.options.bar.barGroupStyle = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Pills"),
                        "icon": "location_chip",
                        "value": 0
                    }, {
                        "displayName": Translation.tr("Island"),
                        "icon": "shadow",
                        "value": 1
                    }, {
                        "displayName": Translation.tr("Transparent"),
                        "icon": "opacity",
                        "value": 2
                    }]
                }

            }

            ConfigSwitch {
                buttonIcon: "colorize"
                text: Translation.tr("Expressive group color")
                checked: Config.options.bar.expressiveGroupColor
                visible: Config.options.bar.barGroupStyle !== 2
                onCheckedChanged: {
                    Config.options.bar.expressiveGroupColor = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Use primary container color for pill/island group backgrounds")
                }

            }

            ContentSubsection {
                title: Translation.tr("Bar background style")
                icon: "format_paint"
                tooltip: Translation.tr("Adaptive style makes the bar background transparent when there are no active windows")

                ConfigSelectionArray {
                    currentValue: Config.options.bar.barBackgroundStyle
                    onSelected: (newValue) => {
                        Config.options.bar.barBackgroundStyle = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Visible"),
                        "icon": "visibility",
                        "value": 1
                    }, {
                        "displayName": Translation.tr("Adaptive"),
                        "icon": "masked_transitions",
                        "value": 2
                    }, {
                        "displayName": Translation.tr("Transparent"),
                        "icon": "opacity",
                        "value": 0
                    }, {
                        "displayName": Translation.tr("Islands"),
                        "icon": "grid_view",
                        "value": 3
                    }]
                }

            }

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Transparent bar blur/dim")
                checked: Config.options.bar.transparentGlow
                visible: Config.options.bar.barBackgroundStyle === 0
                onCheckedChanged: {
                    Config.options.bar.transparentGlow = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Adds a soft blur and dim gradient under the transparent bar")
                }

            }

            ConfigSwitch {
                buttonIcon: "format_color_fill"
                text: Translation.tr("Expressive bar solid colors")
                checked: Config.options.bar.expressiveColors
                onCheckedChanged: {
                    Config.options.bar.expressiveColors = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Use expressive solid layer colors")
                }

            }

            ConfigSwitch {
                buttonIcon: "filter_drama"
                text: Translation.tr("Bar drop-shadow")
                checked: Config.options.bar.dropShadow
                onCheckedChanged: {
                    Config.options.bar.dropShadow = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Shows a soft drop shadow underneath the status bar")
                }

            }

            ContentSubsection {
                title: Translation.tr("Expressive color theme")
                icon: "palette"
                visible: Config.options.bar.expressiveColors

                ConfigSelectionArray {
                    currentValue: Config.options.bar.expressiveColorTheme
                    onSelected: (newValue) => {
                        Config.options.bar.expressiveColorTheme = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Content"),
                        "icon": "brush",
                        "value": "content"
                    }, {
                        "displayName": Translation.tr("Vibrant"),
                        "icon": "brush",
                        "value": "primary"
                    }, {
                        "displayName": Translation.tr("Secondary"),
                        "icon": "brush",
                        "value": "secondary"
                    }, {
                        "displayName": Translation.tr("Surface"),
                        "icon": "brush",
                        "value": "surface"
                    }]
                }

            }

            ContentSubsection {
                title: Translation.tr("Fake screen rounding")
                icon: "fullscreen_exit"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.appearance.fakeScreenRounding
                    onSelected: (newValue) => {
                        Config.options.appearance.fakeScreenRounding = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("No"),
                        "icon": "close",
                        "value": 0
                    }, {
                        "displayName": Translation.tr("Yes"),
                        "icon": "check",
                        "value": 1
                    }, {
                        "displayName": Translation.tr("When not fullscreen"),
                        "icon": "fullscreen_exit",
                        "value": 2
                    }, {
                        "displayName": Translation.tr("Wrapped"),
                        "icon": "capture",
                        "value": 3
                    }, {
                        "displayName": Translation.tr("Edge"),
                        "icon": "border_bottom",
                        "value": 4
                    }]
                }

            }

            ConfigSpinBox {
                visible: Config.options.appearance.fakeScreenRounding === 3
                icon: "line_weight"
                text: Translation.tr("Wrapped frame thickness")
                value: Config.options.appearance.wrappedFrameThickness
                from: 5
                to: 25
                stepSize: 1
                onValueChanged: {
                    Config.options.appearance.wrappedFrameThickness = value;
                }
            }

            ContentSubsection {
                title: Translation.tr("Top Left Brand Icon")
                icon: "star"
                Layout.fillWidth: true

                ConfigSwitch {
                    buttonIcon: "text_fields"
                    text: Translation.tr("Use Material Symbol for top-left icon")
                    checked: Config.options.bar.useMaterialSymbolForTopLeftIcon
                    onCheckedChanged: {
                        Config.options.bar.useMaterialSymbolForTopLeftIcon = checked;
                    }
                }

                ConfigTextField {
                    id: topLeftIconField
                    text: Translation.tr("Top-left icon identifier")
                    icon: "image"
                    tooltip: Translation.tr("If not using Material Symbol, enter a preset SVG name (e.g. arch, fedora) or a Material Symbol name if the switch above is on.")
                    placeholderText: Translation.tr("Identifier...")
                    Component.onCompleted: {
                        inputText = Config.options.bar.topLeftIcon;
                    }
                    textField.onTextChanged: {
                        var val = textField.text.trim();
                        if (val !== "" && textField.activeFocus)
                            Config.options.bar.topLeftIcon = val;

                    }

                    Connections {
                        function onTopLeftIconChanged() {
                            topLeftIconField.textField.text = Config.options.bar.topLeftIcon;
                        }

                        target: Config.options.bar
                    }

                }

            }

        }

        // ── Behavior ──────────────────────────────────────────────────────
        ContentSection {
            icon: "tune"
            title: Translation.tr("Behavior")

            ConfigSwitch {
                buttonIcon: "visibility_off"
                text: Translation.tr("Automatically hide")
                checked: Config.options.bar.autoHide.enable
                onCheckedChanged: {
                    Config.options.bar.autoHide.enable = checked;
                }
            }

            ContentSubsection {
                title: Translation.tr("Scroll Actions")
                icon: "mouse"
                Layout.fillWidth: true

                ConfigSwitch {
                    buttonIcon: "volume_up"
                    text: Translation.tr("Scroll to change volume")
                    checked: Config.options.bar.enableVolumeScroll
                    onCheckedChanged: {
                        Config.options.bar.enableVolumeScroll = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Enable or disable scrolling on the bar to change volume")
                    }

                }

                ConfigSwitch {
                    buttonIcon: "brightness_5"
                    text: Translation.tr("Scroll to change brightness")
                    checked: Config.options.bar.enableBrightnessScroll
                    onCheckedChanged: {
                        Config.options.bar.enableBrightnessScroll = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Enable or disable scrolling on the bar to change brightness")
                    }

                }

            }

            ContentSubsection {
                title: Translation.tr("Tooltips & Popups")
                icon: "tooltip"
                Layout.fillWidth: true

                ConfigSwitch {
                    buttonIcon: "ads_click"
                    text: Translation.tr("Click to show tooltips")
                    checked: Config.options.bar.tooltips.clickToShow
                    onCheckedChanged: {
                        Config.options.bar.tooltips.clickToShow = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("You will not be able to use the buttons on some popups if you enable this option.")
                    }

                }

                ConfigSwitch {
                    buttonIcon: "compress"
                    text: Translation.tr("Compact popups")
                    checked: Config.options.bar.tooltips.compactPopups
                    onCheckedChanged: {
                        Config.options.bar.tooltips.compactPopups = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "colorize"
                    text: Translation.tr("Enable color picker popup")
                    checked: Config.options.bar.tooltips.enableColorPickerPopup
                    onCheckedChanged: {
                        Config.options.bar.tooltips.enableColorPickerPopup = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "bluetooth"
                    text: Translation.tr("Enable Bluetooth connection popup")
                    checked: Config.options.bar.tooltips.enableBluetoothConnectionPopup
                    onCheckedChanged: {
                        Config.options.bar.tooltips.enableBluetoothConnectionPopup = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "keyboard"
                    text: Translation.tr("Enable keyboard layout transition popup")
                    checked: Config.options.bar.tooltips.enableKeyboardLayoutTransitionPopup
                    onCheckedChanged: {
                        Config.options.bar.tooltips.enableKeyboardLayoutTransitionPopup = checked;
                    }
                }

            }

        }

        // ── Monitors ──────────────────────────────────────────────────────
        ContentSection {
            icon: "monitor"
            title: Translation.tr("Monitors")

            ConfigSwitch {
                buttonIcon: "desktop_windows"
                text: Translation.tr("Only show bar on single monitor")
                checked: Config.options.bar.onlyShowOnSingleMonitor
                onCheckedChanged: {
                    Config.options.bar.onlyShowOnSingleMonitor = checked;
                    if (checked && Config.options.bar.singleMonitorName === "" && Quickshell.screens.length > 0)
                        Config.options.bar.singleMonitorName = Quickshell.screens[0].name;

                }

                StyledToolTip {
                    text: Translation.tr("Display the bar on only one chosen monitor instead of all monitors")
                }

            }

            ContentSubsection {
                title: Translation.tr("Selected Monitor")
                icon: "settings_input_hdmi"
                visible: Config.options.bar.onlyShowOnSingleMonitor

                MonitorPicker {
                    currentValue: Config.options.bar.singleMonitorName
                    onSelected: (newValue) => {
                        Config.options.bar.singleMonitorName = newValue;
                    }
                }

            }

        }

        // ── Widgets ───────────────────────────────────────────────────────
        // Every bar component that carries its own settings page gets a card,
        // so per-widget settings are reachable without right-clicking the bar.
        ContentSection {
            icon: "widgets"
            title: Translation.tr("Widgets")

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Settings for the individual widgets that can sit on the bar. Right-clicking a widget on the bar opens the same page.")
                color: Appearance.colors.colOnLayer1
                opacity: 0.75
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: BarComponentRegistry.allComponents.filter((c) => {
                        return c.configPage || c.pageId;
                    })

                    delegate: ServiceCard {
                        required property var modelData

                        cardIcon: modelData.icon ?? "widgets"
                        cardHue: 210
                        cardShape: "Cookie4Sided"
                        title: Translation.tr(modelData.title)
                        description: Translation.tr("Widget settings")
                        onOpenCard: {
                            page.openWidgetPage(modelData.id);
                        }
                    }

                }

            }

        }

        ContentSection {
            icon: "grid_view"
            title: Translation.tr("Waffle")

            ServiceCard {
                cardIcon: "build"
                cardHue: 276
                cardShape: "Cookie4Sided"
                title: Translation.tr("Waffle tweaks")
                description: Translation.tr("Optional tweaks for the Waffle panel family")
                onOpenCard: {
                    barConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/WaffleTweaksConfig.qml");
                }
            }

        }

    }

    // ── Sub-page overlay (slides in from the right) ───────────────────────
    ConfigSubPageHost {
        id: subPageOverlay

        anchors.fill: parent
        z: 10
    }

}
