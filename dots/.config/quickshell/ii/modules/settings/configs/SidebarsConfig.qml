import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: false

    property bool showBackButton: false
    signal goBack()

    RowLayout {
        spacing: 12
        visible: page.showBackButton

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: page.goBack()
        }

        StyledText {
            text: Translation.tr("Sidebars & Panels Settings")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }



    ContentSection {
        title: Translation.tr("Sidebar Profile Header Settings")
        icon: "account_circle"

        ContentSubsection {
            title: Translation.tr("Profile Image Type")
            icon: "image"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.sidebar.dashboardHeader.profileImageType
                onSelected: newValue => {
                    Config.options.sidebar.dashboardHeader.profileImageType = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("User Profile"),
                        icon: "account_circle",
                        value: "user_profile"
                    },
                    {
                        displayName: Translation.tr("Distro Icon"),
                        icon: "computer",
                        value: "distro"
                    },
                    {
                        displayName: Translation.tr("None"),
                        icon: "do_not_disturb",
                        value: "none"
                    }
                ]
            }
        }


        ContentSubsection {
            title: Translation.tr("Header Text Mode")
            icon: "title"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.sidebar.dashboardHeader.textMode
                onSelected: newValue => {
                    Config.options.sidebar.dashboardHeader.textMode = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Username"),
                        icon: "person",
                        value: "username"
                    },
                    {
                        displayName: Translation.tr("Uptime"),
                        icon: "schedule",
                        value: "uptime"
                    },
                    {
                        displayName: Translation.tr("Custom Text"),
                        icon: "edit",
                        value: "custom"
                    },
                    {
                        displayName: Translation.tr("None"),
                        icon: "do_not_disturb",
                        value: "none"
                    }
                ]
            }
        }

        ContentSubsection {
            visible: Config.options.sidebar.dashboardHeader.textMode === "custom"
            title: Translation.tr("Custom Header Text")
            icon: "edit_note"
            Layout.fillWidth: true

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Enter custom text")
                text: Config.options.sidebar.dashboardHeader.customText
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    Config.options.sidebar.dashboardHeader.customText = text;
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Right Control Sidebar")
        icon: "view_sidebar"

        ConfigSwitch {
            buttonIcon: "keep"
            text: Translation.tr("Keep right sidebar loaded")
            checked: Config.options.sidebar.keepRightSidebarLoaded
            onCheckedChanged: {
                Config.options.sidebar.keepRightSidebarLoaded = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Sidebar position")
            icon: "switch_right"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.sidebar.position
                onSelected: newValue => {
                    Config.options.sidebar.position = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Default"),
                        icon: "vertical_align_center",
                        value: "default"
                    },
                    {
                        displayName: Translation.tr("Inverted"),
                        icon: "swap_horiz",
                        value: "inverted"
                    },
                    {
                        displayName: Translation.tr("Left"),
                        icon: "keyboard_arrow_left",
                        value: "left"
                    },
                    {
                        displayName: Translation.tr("Right"),
                        icon: "keyboard_arrow_right",
                        value: "right"
                    }
                ]
            }
        }
    }

    ContentSection {
        title: Translation.tr("Quick Toggles & Sliders")
        icon: "tune"

        ContentSubsection {
            title: Translation.tr("Quick toggles style")
            icon: "apps"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.sidebar.quickToggles.style
                onSelected: newValue => {
                    Config.options.sidebar.quickToggles.style = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Classic"),
                        icon: "grid_view",
                        value: "classic"
                    },
                    {
                        displayName: Translation.tr("Android"),
                        icon: "android",
                        value: "android"
                    }
                ]
            }
        }

        ConfigSpinBox {
            visible: Config.options.sidebar.quickToggles.style === "android"
            icon: "view_column"
            text: Translation.tr("Android style Columns")
            value: Config.options.sidebar.quickToggles.android.columns
            from: 1
            to: 6
            stepSize: 1
            onValueChanged: {
                Config.options.sidebar.quickToggles.android.columns = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "linear_scale"
            text: Translation.tr("Enable fixed sliders")
            checked: Config.options.sidebar.quickSliders.enable
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Enabling this, the sliders will be fixed on top of the sidebar, disable this if you wan sliders to be inside a page.")
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.quickSliders.enable
            buttonIcon: "brightness_high"
            text: Translation.tr("Show Brightness")
            checked: Config.options.sidebar.quickSliders.showBrightness
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.showBrightness = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.quickSliders.enable
            buttonIcon: "contrast"
            text: Translation.tr("Show Gamma")
            checked: Config.options.sidebar.quickSliders.showGamma
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.showGamma = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.quickSliders.enable
            buttonIcon: "volume_up"
            text: Translation.tr("Show Volume")
            checked: Config.options.sidebar.quickSliders.showVolume
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.showVolume = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.quickSliders.enable
            buttonIcon: "mic"
            text: Translation.tr("Show Microphone")
            checked: Config.options.sidebar.quickSliders.showMic
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.showMic = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.quickSliders.enable
            buttonIcon: "swap_vert"
            text: Translation.tr("Vertical layout for sliders")
            checked: Config.options.sidebar.quickSliders.vertical
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.vertical = checked;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Corner Mouse Actions")
        icon: "mouse"

        ConfigSwitch {
            buttonIcon: "touch_app"
            text: Translation.tr("Enable corner open")
            checked: Config.options.sidebar.cornerOpen.enable
            onCheckedChanged: {
                Config.options.sidebar.cornerOpen.enable = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.cornerOpen.enable
            buttonIcon: "pan_tool_alt"
            text: Translation.tr("Hover to trigger")
            checked: Config.options.sidebar.cornerOpen.clickless
            onCheckedChanged: {
                Config.options.sidebar.cornerOpen.clickless = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.cornerOpen.enable && Config.options.sidebar.cornerOpen.clickless
            buttonIcon: "format_align_justify"
            text: Translation.tr("Force hover open at absolute corner")
            checked: Config.options.sidebar.cornerOpen.clicklessCornerEnd
            onCheckedChanged: {
                Config.options.sidebar.cornerOpen.clicklessCornerEnd = checked;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.sidebar.cornerOpen.enable
            icon: "vertical_align_top"
            text: Translation.tr("Vertical offset")
            value: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset
            from: 0
            to: 500
            stepSize: 10
            onValueChanged: {
                Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset = value;
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.cornerOpen.enable
            buttonIcon: "vertical_align_bottom"
            text: Translation.tr("Place at bottom")
            checked: Config.options.sidebar.cornerOpen.bottom
            onCheckedChanged: {
                Config.options.sidebar.cornerOpen.bottom = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.cornerOpen.enable
            buttonIcon: "swap_vert"
            text: Translation.tr("Value scroll (Volume/Brightness)")
            checked: Config.options.sidebar.cornerOpen.valueScroll
            onCheckedChanged: {
                Config.options.sidebar.cornerOpen.valueScroll = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.sidebar.cornerOpen.enable
            buttonIcon: "visibility"
            text: Translation.tr("Visualize corner region")
            checked: Config.options.sidebar.cornerOpen.visualize
            onCheckedChanged: {
                Config.options.sidebar.cornerOpen.visualize = checked;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.sidebar.cornerOpen.enable
            icon: "straighten"
            text: Translation.tr("Region width")
            value: Config.options.sidebar.cornerOpen.cornerRegionWidth
            from: 1
            to: 100
            stepSize: 1
            onValueChanged: {
                Config.options.sidebar.cornerOpen.cornerRegionWidth = value;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.sidebar.cornerOpen.enable
            icon: "height"
            text: Translation.tr("Region height")
            value: Config.options.sidebar.cornerOpen.cornerRegionHeight
            from: 1
            to: 500
            stepSize: 5
            onValueChanged: {
                Config.options.sidebar.cornerOpen.cornerRegionHeight = value;
            }
        }
    }

    ContentSection {
        icon: "policy"
        title: Translation.tr("Sidebar Policies Visibility")

        NoticeBox {
            Layout.fillWidth: true
            isFirst: true
            text: Translation.tr("Choose which policy tabs are visible in the left sidebar when it is opened.")
        }

        ConfigToggleGrid {
            Layout.fillWidth: true
            gridColumns: Math.max(1, Math.floor(parent.width / 300))
            currentValues: {
                return {
                    ai: Config.options.policies.ai,
                    weeb: Config.options.policies.weeb,
                    wallpapers: Config.options.policies.wallpapers,
                    translator: Config.options.policies.translator,
                    player: Config.options.policies.player,
                    phone: Config.options.policies.phone
                };
            }
            model: [
                {
                    key: "ai",
                    name: Translation.tr("AI"),
                    icon: "smart_toy",
                    options: [
                        { displayName: Translation.tr("No"), icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                        { displayName: Translation.tr("Local"), icon: "sync_saved_locally", value: 2 }
                    ]
                },
                {
                    key: "weeb",
                    name: Translation.tr("Weeb"),
                    icon: "face",
                    options: [
                        { displayName: Translation.tr("No"), icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                        { displayName: Translation.tr("Closet"), icon: "ev_shadow", value: 2 }
                    ]
                },
                {
                    key: "wallpapers",
                    name: Translation.tr("Wallpaper browser"),
                    icon: "wallpaper",
                    options: [
                        { displayName: Translation.tr("No"), icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 }
                    ]
                },
                {
                    key: "translator",
                    name: Translation.tr("Translator"),
                    icon: "translate",
                    options: [
                        { displayName: Translation.tr("No"), icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 }
                    ]
                },
                {
                    key: "player",
                    name: Translation.tr("Sidebar player"),
                    icon: "music_note",
                    options: [
                        { displayName: Translation.tr("No"), icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 }
                    ]
                },
                {
                    key: "phone",
                    name: Translation.tr("Phone"),
                    icon: "smartphone",
                    options: [
                        { displayName: Translation.tr("No"), icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 }
                    ]
                }
            ]
            onItemChanged: (key, value) => {
                Config.options.policies[key] = value;
            }
        }
    }
}
