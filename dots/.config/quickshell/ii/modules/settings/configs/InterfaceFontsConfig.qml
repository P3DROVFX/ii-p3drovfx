import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: false

    ContentSection {
        title: Translation.tr("System Rounding")
        icon: "rounded_corner"

        ContentSubsection {
            title: Translation.tr("Rounding style")
            icon: "style"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.appearance.globalRounding
                onSelected: newValue => {
                    Config.options.appearance.globalRounding = newValue;
                    Config.options.appearance.sharpMode = (newValue === "sharp");
                }
                options: [
                    {
                        displayName: Translation.tr("Sharp"),
                        icon: "square",
                        value: "sharp"
                    },
                    {
                        displayName: Translation.tr("Normal"),
                        icon: "rounded_corner",
                        value: "normal"
                    },
                    {
                        displayName: Translation.tr("Large"),
                        icon: "lens_blur",
                        value: "large"
                    },
                    {
                        displayName: Translation.tr("V. Large"),
                        icon: "circle",
                        value: "verylarge"
                    }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "buttons_alt"
            text: Translation.tr("Toggle window rounding with rounding style")
            checked: Config.options.appearance.toggleWindowRounding
            onCheckedChanged: {
                Config.options.appearance.toggleWindowRounding = checked;
            }
        }


    }

    ContentSection {
        title: Translation.tr("Decorative Options")
        icon: "auto_awesome"

        ConfigSwitch {
            buttonIcon: "colors"
            text: Translation.tr("Colorful scrollbar")
            checked: Config.options.appearance.colorfulScrollbar
            onCheckedChanged: {
                Config.options.appearance.colorfulScrollbar = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "animation"
            text: Translation.tr("Scroll animation in settings")
            checked: Config.options.appearance.scrollAnimations
            onCheckedChanged: {
                Config.options.appearance.scrollAnimations = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "blur_linear"
            text: Translation.tr("Scroll fade gradient mask in settings")
            checked: Config.options.appearance.scrollFadeMask
            onCheckedChanged: {
                Config.options.appearance.scrollFadeMask = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "smart_toy"
            text: Translation.tr("Show AI provider and model buttons")
            checked: Config.options.sidebar.ai.showProviderAndModelButtons
            onCheckedChanged: {
                Config.options.sidebar.ai.showProviderAndModelButtons = checked;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Base Icon Themes")
        icon: "category"

        ConfigSwitch {
            buttonIcon: "magic_button"
            text: Translation.tr("Themed icons (Experimental)")
            checked: Config.options.appearance.icons.enableThemed
            onCheckedChanged: {
                Config.options.appearance.icons.enableThemed = checked;
            }
            StyledToolTip {
                text: Translation.tr("When enabled, uses the dynamic Matugen generated icon pack. Fallbacks to Tint Icons.")
            }
        }


        ContentSubsection {
            visible: Config.options.appearance.icons.enableThemed
            title: Translation.tr("Base icon theme")
            icon: "palette"
            Layout.fillWidth: true
            tooltip: Translation.tr("Select the base icon theme to be recolored by Matugen.\nRequires generating colors again to apply.")

            ConfigSelectionArray {
                currentValue: Config.options.appearance.iconTheme
                onSelected: newValue => {
                    Config.options.appearance.iconTheme = newValue;
                }
                options: IconThemes.availableThemes.map(theme => ({
                    displayName: theme,
                    value: theme,
                    icon: "category"
                }))
            }
        }

        ConfigRow {
            visible: Config.options.appearance.icons.enableThemed
            Layout.fillWidth: true
            Layout.preferredHeight: 48

            RippleButtonWithIcon {
                materialIcon: "magic_button"
                mainText: Translation.tr("Apply Theme")
                buttonRadius: Appearance.rounding.normal
                Layout.fillHeight: true
                Layout.fillWidth: true
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                colText: Appearance.colors.colOnPrimaryContainer
                onClicked: {
                    IconThemes.applyTheme(false);
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "restart_alt"
            text: Translation.tr("Auto restart Quickshell on theme change")
            checked: Config.options.appearance.wallpaperTheming.autoRestartQuickshell
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.autoRestartQuickshell = checked;
            }
        }

        HelperLinkBox {
            Layout.fillWidth: true
            title: Translation.tr("Themed icons configuration")
            text: Translation.tr("You can configure specific tint settings for different interface elements below:")
            
            ConfigSwitch {
                Layout.fillWidth: true
                enabled: Config.options.dock.enable
                buttonIcon: "palette"
                text: Translation.tr("Tint dock icons")
                checked: Config.options.dock.monochromeIcons
                onCheckedChanged: {
                    Config.options.dock.monochromeIcons = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Applies monochrome tint to dock icons")
                }
            }

            ConfigSwitch {
                Layout.fillWidth: true
                enabled: Config.options.dock.enable && !Config.options.dock.monochromeIcons
                buttonIcon: "tonality"
                text: Translation.tr("Dim inactive dock icons")
                checked: Config.options.dock.dimInactiveIcons
                onCheckedChanged: {
                    Config.options.dock.dimInactiveIcons = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Dims icons of inactive applications in the dock")
                }
            }

            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "palette"
                text: Translation.tr("Tint workspaces icons")
                checked: Config.options.bar.workspaces.monochromeIcons
                onCheckedChanged: {
                    Config.options.bar.workspaces.monochromeIcons = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Applies monochrome tint to workspaces icons. Turn on show workspace icons to see this")
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Fonts Management")
        icon: "text_format"

        ConfigSwitch {
            buttonIcon: "custom_typography"
            text: Translation.tr("Enable custom fonts")
            checked: Config.options.appearance.fonts.enableCustom
            onCheckedChanged: {
                Config.options.appearance.fonts.enableCustom = checked;
                if (checked) {
                    Config.options.appearance.fonts.main = Persistent.states.settings.fonts.main;
                    Config.options.appearance.fonts.numbers = Persistent.states.settings.fonts.numbers;
                    Config.options.appearance.fonts.title = Persistent.states.settings.fonts.title;
                    Config.options.appearance.fonts.monospace = Persistent.states.settings.fonts.monospace;
                    Config.options.appearance.fonts.iconNerd = Persistent.states.settings.fonts.iconNerd;
                    Config.options.appearance.fonts.reading = Persistent.states.settings.fonts.reading;
                    Config.options.appearance.fonts.expressive = Persistent.states.settings.fonts.expressive;
                } else {
                    Config.options.appearance.fonts.main = "Google Sans Flex";
                    Config.options.appearance.fonts.numbers = "Google Sans Flex";
                    Config.options.appearance.fonts.title = "Google Sans Flex";
                    Config.options.appearance.fonts.iconNerd = "JetBrains Mono NF";
                    Config.options.appearance.fonts.monospace = "JetBrains Mono NF";
                    Config.options.appearance.fonts.reading = "Readex Pro";
                    Config.options.appearance.fonts.expressive = "Space Grotesk";
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "rounded_corner"
            text: Translation.tr("Full font roundness")
            checked: Config.options.appearance.fonts.roundnessFull
            onCheckedChanged: {
                Config.options.appearance.fonts.roundnessFull = checked;
                Persistent.states.settings.fonts.roundnessFull = checked;
            }
            StyledToolTip {
                text: Translation.tr("Use rounded font variant (ROND: 100) for variable fonts like Google Sans Flex")
            }
        }

        ContentSubsection {
            title: Translation.tr("Main font")
            icon: "font_download"
            Layout.fillWidth: true

            MaterialTextArea {
                enabled: Config.options.appearance.fonts.enableCustom
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family name (e.g., Google Sans Flex)")
                text: Persistent.states.settings.fonts.main
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    if (!enabled) return
                    Persistent.states.settings.fonts.main = text;
                    Config.options.appearance.fonts.main = text;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Numbers font")
            icon: "pin"
            Layout.fillWidth: true

            MaterialTextArea {
                enabled: Config.options.appearance.fonts.enableCustom
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family name")
                text: Persistent.states.settings.fonts.numbers
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    if (!enabled) return
                    Persistent.states.settings.fonts.numbers = text;
                    Config.options.appearance.fonts.numbers = text;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Title font")
            icon: "title"
            Layout.fillWidth: true

            MaterialTextArea {
                enabled: Config.options.appearance.fonts.enableCustom
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family name")
                text: Persistent.states.settings.fonts.title
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    if (!enabled) return
                    Persistent.states.settings.fonts.title = text;
                    Config.options.appearance.fonts.title = text;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Monospace font")
            icon: "space_bar"
            Layout.fillWidth: true

            MaterialTextArea {
                enabled: Config.options.appearance.fonts.enableCustom
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family name (e.g., JetBrains Mono NF)")
                text: Persistent.states.settings.fonts.monospace
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    if (!enabled) return
                    Persistent.states.settings.fonts.monospace = text;
                    Config.options.appearance.fonts.monospace = text;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Nerd font icons")
            icon: "emoji_symbols"
            Layout.fillWidth: true
            HelperLinkBox {
                Layout.fillWidth: true
                title: Translation.tr("NerdFonts Cheat Sheet")
                text: Translation.tr("Find icon names and symbols for your Nerd Fonts here.")
                isFirst: true

                RippleButtonWithIcon {
                    mainText: Translation.tr("Open Website")
                    materialIcon: "open_in_new"
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    colBackground: Appearance.colors.colLayer0
                    colBackgroundHover: Appearance.colors.colLayer0Hover
                    colRipple: Appearance.colors.colLayer0Active
                    downAction: () => {
                        Qt.openUrlExternally("https://www.nerdfonts.com/cheat-sheet")
                    }
                }
            }

            MaterialTextArea {
                enabled: Config.options.appearance.fonts.enableCustom
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family name (e.g., JetBrains Mono NF)")
                text: Persistent.states.settings.fonts.iconNerd
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    if (!enabled) return
                    Persistent.states.settings.fonts.iconNerd = text;
                    Config.options.appearance.fonts.iconNerd = text;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Reading font")
            icon: "menu_book"
            Layout.fillWidth: true

            MaterialTextArea {
                enabled: Config.options.appearance.fonts.enableCustom
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family name (e.g., Readex Pro)")
                text: Persistent.states.settings.fonts.reading
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    if (!enabled) return
                    Persistent.states.settings.fonts.reading = text;
                    Config.options.appearance.fonts.reading = text;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Expressive font")
            icon: "brush"
            Layout.fillWidth: true

            MaterialTextArea {
                enabled: Config.options.appearance.fonts.enableCustom
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family name (e.g., Space Grotesk)")
                text: Persistent.states.settings.fonts.expressive
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    if (!enabled) return
                    Persistent.states.settings.fonts.expressive = text;
                    Config.options.appearance.fonts.expressive = text;
                }
            }
        }
    }
}
