import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

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
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Bar appearance")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "palette"
            title: Translation.tr("Corner & Group Style")
            tooltip: Translation.tr("Customize bar shapes, corners, spacing and group treatments.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ContentSubsection {
                    title: Translation.tr("Corner style")
                    icon: "rounded_corner"

                    NoticeBox {
                        Layout.fillWidth: true
                        visible: Config.options.bar.barBackgroundStyle === 3 && (Config.options.bar.cornerStyle === 2 || Config.options.bar.cornerStyle === 3)
                        materialIcon: "grid_view"
                        text: Translation.tr("Rect and Dynamic Island corner styles are incompatible with Islands background. Only Hug and Float are available while Islands is active.")
                    }

                    ConfigSelectionArray {
                        id: cornerStyleSelector
                        currentValue: Config.options.bar.cornerStyle
                        onSelected: (newValue) => {
                            if (newValue === 3 && !Config.options.bar.vertical && Config.options.sidebar.sidebarStyle === "connect") {
                                Config.options.sidebar.sidebarStyle = "default";
                            }
                            Config.options.bar.cornerStyle = newValue;
                        }
                        options: {
                            var opts = [{
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
                            }];
                            if (Config.options.bar.barBackgroundStyle === 3) {
                                opts[2].enabled = false;
                                opts[3].enabled = false;
                            }
                            return opts;
                        }
                    }
                }

                ConfigSwitch {
                    visible: Config.options.bar.cornerStyle === 1
                    buttonIcon: "shadow"
                    text: Translation.tr("Show shadow in Float style")
                    checked: Config.options.bar.floatStyleShadow ?? true
                    onCheckedChanged: {
                        Config.options.bar.floatStyleShadow = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Shows a subtle drop shadow behind the bar when floating.")
                    }
                }

                ContentSubsectionLabel {
                    text: Translation.tr("Dynamic Island behavior")
                    visible: Config.options.bar.cornerStyle === 3
                    Layout.topMargin: 4
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

                ContentSubsectionLabel {
                    text: Translation.tr("Group color")
                    visible: Config.options.bar.barGroupStyle !== 2
                    Layout.topMargin: 4
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
            }
        }

        ContentSection {
            icon: "format_paint"
            title: Translation.tr("Background & Colors")
            tooltip: Translation.tr("Configure transparency, blur, shadows, and expressive color themes.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ContentSubsection {
                    title: Translation.tr("Bar background style")
                    icon: "format_paint"
                    tooltip: Translation.tr("Adaptive style makes the bar background transparent when there are no active windows")

                    NoticeBox {
                        Layout.fillWidth: true
                        visible: ShellModePolicy.barPositionLocked
                        materialIcon: "lock"
                        text: Translation.tr("Bar background is locked to Transparent or Islands while 'Dynamic Island in bar center' is active. Visible and Adaptive options are unavailable.")
                    }

                    ConfigSelectionArray {
                        currentValue: Config.options.bar.barBackgroundStyle
                        onSelected: (newValue) => {
                            Config.options.bar.barBackgroundStyle = newValue;
                            if (newValue === 3 && (Config.options.bar.cornerStyle === 2 || Config.options.bar.cornerStyle === 3))
                                Config.options.bar.cornerStyle = 0;

                            if (newValue === 3) {
                                let centerList = Config.options.bar.layouts.center;
                                let hasCentered = centerList.some((item) => {
                                    return item.centered;
                                });
                                if (hasCentered)
                                    Config.options.bar.layouts.center = centerList.map((item) => {
                                    return ({
                                        "id": item.id,
                                        "centered": false,
                                        "visible": item.visible
                                    });
                                });
                            }
                        }
                        options: {
                            const locked = ShellModePolicy.barPositionLocked;
                            return [{
                                "displayName": Translation.tr("Visible"),
                                "icon": "visibility",
                                "value": 1,
                                "enabled": !locked
                            }, {
                                "displayName": Translation.tr("Adaptive"),
                                "icon": "masked_transitions",
                                "value": 2,
                                "enabled": !locked
                            }, {
                                "displayName": Translation.tr("Transparent"),
                                "icon": "opacity",
                                "value": 0
                            }, {
                                "displayName": Translation.tr("Islands"),
                                "icon": "grid_view",
                                "value": 3
                            }];
                        }
                    }
                }

                ContentSubsectionLabel {
                    text: Translation.tr("Bar effects")
                    Layout.topMargin: 4
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
                    enabled: !ShellModePolicy.barDropShadowBlocked
                    checked: Config.options.bar.dropShadow && !ShellModePolicy.barDropShadowBlocked
                    onCheckedChanged: {
                        if (!ShellModePolicy.barDropShadowBlocked)
                            Config.options.bar.dropShadow = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Shows a soft drop shadow underneath the status bar")
                    }
                }

                NoticeBox {
                    Layout.fillWidth: true
                    visible: ShellModePolicy.barDropShadowBlocked
                    materialIcon: "lock"
                    text: Translation.tr("Bar drop-shadow is disabled while Connect mode and transparency are both active to keep the bar color consistent with Sidebar Policies.")
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

                    NoticeBox {
                        Layout.fillWidth: true
                        visible: ShellModePolicy.barPositionLocked
                        materialIcon: "lock"
                        text: Translation.tr("Wrapped Frame and Edge modes are locked while 'Dynamic Island in bar center' is active. They would render floating above the island, causing visual conflicts.")
                    }

                    ConfigSelectionArray {
                        currentValue: Config.options.appearance.fakeScreenRounding
                        onSelected: (newValue) => {
                            Config.options.appearance.fakeScreenRounding = newValue;
                        }
                        options: {
                            const locked = ShellModePolicy.barPositionLocked;
                            return [{
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
                                "value": 3,
                                "enabled": !locked
                            }, {
                                "displayName": Translation.tr("Edge"),
                                "icon": "border_bottom",
                                "value": 4,
                                "enabled": !locked
                            }];
                        }
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
            }
        }

        ContentSection {
            icon: "brand_family"
            title: Translation.tr("Top-left brand icon")
            tooltip: Translation.tr("Choose a distro preset, custom symbol or Google Material Symbol for the top-left launcher icon.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                ContentSubsection {
                    title: Translation.tr("Preset icons")
                    icon: "image"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        enabled: !Config.options.bar.useMaterialSymbolForTopLeftIcon
                        opacity: enabled ? 1.0 : 0.4
                        currentValue: Config.options.bar.useMaterialSymbolForTopLeftIcon ? "" : Config.options.bar.topLeftIcon
                        onSelected: (newValue) => {
                            Config.options.bar.topLeftIcon = newValue;
                        }
                        options: [
                            { "displayName": Translation.tr("Distro"), "symbol": SystemInfo.distroIcon, "value": "distro" },
                            { "displayName": "Arch", "symbol": "arch-symbolic", "value": "arch" },
                            { "displayName": "CachyOS", "symbol": "cachyos-symbolic", "value": "cachyos" },
                            { "displayName": "EndeavourOS", "symbol": "endeavouros-symbolic", "value": "endeavouros" },
                            { "displayName": "Fedora", "symbol": "fedora-symbolic", "value": "fedora" },
                            { "displayName": "Red Hat", "symbol": "redhat-symbolic", "value": "redhat" },
                            { "displayName": "Debian", "symbol": "debian-symbolic", "value": "debian" },
                            { "displayName": "Ubuntu", "symbol": "ubuntu-symbolic", "value": "ubuntu" },
                            { "displayName": "Mint", "symbol": "mint-symbolic", "value": "mint" },
                            { "displayName": "Pop!_OS", "symbol": "popos-symbolic", "value": "popos" },
                            { "displayName": "Manjaro", "symbol": "manjaro-symbolic", "value": "manjaro" },
                            { "displayName": "NixOS", "symbol": "nixos-symbolic", "value": "nixos" },
                            { "displayName": "openSUSE", "symbol": "opensuse-symbolic", "value": "opensuse" },
                            { "displayName": "Gentoo", "symbol": "gentoo-symbolic", "value": "gentoo" },
                            { "displayName": "Void", "symbol": "void-symbolic", "value": "void" },
                            { "displayName": "Alpine", "symbol": "alpine-symbolic", "value": "alpine" },
                            { "displayName": "Kali", "symbol": "kali-symbolic", "value": "kali" },
                            { "displayName": "FreeBSD", "symbol": "freebsd-symbolic", "value": "freebsd" },
                            { "displayName": "SteamOS", "symbol": "steamos-symbolic", "value": "steamos" },
                            { "displayName": "Linux", "symbol": "linux-symbolic", "value": "linux" },
                            { "displayName": "Android", "symbol": "android-symbolic", "value": "android" },
                            { "displayName": "Apple", "symbol": "apple-symbolic", "value": "apple" },
                            { "displayName": "Windows", "symbol": "microsoft-symbolic", "value": "microsoft" },
                            { "displayName": "Spark", "symbol": "spark-symbolic", "value": "spark" },
                            { "displayName": "Nyarch", "symbol": "nyarch-symbolic", "value": "nyarch" },
                            { "displayName": "Docker", "symbol": "docker.svg", "value": "docker" },
                            { "displayName": "Flatpak", "symbol": "flatpak-symbolic", "value": "flatpak" },
                            { "displayName": "GitHub", "symbol": "github-symbolic", "value": "github" },
                            { "displayName": "Desktop", "symbol": "desktop-symbolic", "value": "desktop" },
                            { "displayName": "Crosshair", "symbol": "crosshair-symbolic", "value": "crosshair" },
                            { "displayName": "Cloudflare", "symbol": "cloudflare-dns-symbolic", "value": "cloudflare-dns" },
                            { "displayName": "Gemini", "symbol": "google-gemini-symbolic", "value": "google-gemini" },
                            { "displayName": "DeepSeek", "symbol": "deepseek-symbolic", "value": "deepseek" },
                            { "displayName": "OpenAI", "symbol": "openai-symbolic", "value": "openai" },
                            { "displayName": "Mistral", "symbol": "mistral-symbolic", "value": "mistral" },
                            { "displayName": "Ollama", "symbol": "ollama-symbolic", "value": "ollama" },
                            { "displayName": "OpenRouter", "symbol": "openrouter-symbolic", "value": "openrouter" }
                        ]
                    }
                }

                ConfigSwitch {
                    buttonIcon: "text_fields"
                    text: Translation.tr("Use Material Symbol for top-left icon")
                    checked: Config.options.bar.useMaterialSymbolForTopLeftIcon
                    onCheckedChanged: {
                        Config.options.bar.useMaterialSymbolForTopLeftIcon = checked;
                    }
                }

                NoticeBox {
                    visible: Config.options.bar.useMaterialSymbolForTopLeftIcon
                    Layout.fillWidth: true
                    materialIcon: "info"
                    text: Translation.tr("Browse thousands of Google Material Symbols to customize your top-left bar icon.")

                    RippleButton {
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colTertiary
                        colBackgroundHover: Appearance.colors.colTertiaryHover
                        colRipple: Appearance.colors.colTertiaryActive
                        implicitHeight: 32
                        implicitWidth: linkRow.implicitWidth + 20
                        onClicked: Quickshell.execDetached(["xdg-open", "https://fonts.google.com/icons"])

                        RowLayout {
                            id: linkRow
                            anchors.centerIn: parent
                            spacing: 6

                            StyledText {
                                text: Translation.tr("Open Icons Page")
                                color: Appearance.colors.colOnTertiary
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.bold: true
                            }

                            MaterialSymbol {
                                text: "open_in_new"
                                iconSize: 14
                                color: Appearance.colors.colOnTertiary
                            }
                        }
                    }
                }

                ConfigTextField {
                    id: topLeftIconField
                    visible: Config.options.bar.useMaterialSymbolForTopLeftIcon
                    text: Translation.tr("Material Symbol name")
                    icon: "search"
                    tooltip: Translation.tr("Type any Google Material Symbol identifier (e.g. spark, terminal, favorite, home).")
                    placeholderText: Translation.tr("e.g. spark, terminal, favorite...")
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
    }
}
