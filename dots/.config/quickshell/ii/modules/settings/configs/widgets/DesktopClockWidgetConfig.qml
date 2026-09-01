import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack

    RowLayout {
        spacing: 12

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

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Cookie Clock Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Cookie Clock Settings")
        icon: "schedule"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            // Cookie Style Settings
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ContentSubsectionLabel {
                    text: Translation.tr("Cookie Style Settings")
                }

                ConfigSpinBox {
                    icon: "interests"
                    text: Translation.tr("Sides")
                    value: Config.options.background.widgets.clock_cookie.sides
                    from: 3
                    to: 24
                    stepSize: 1
                    onValueChanged: {
                        Config.options.background.widgets.clock_cookie.sides = value;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "rotate_right"
                    text: Translation.tr("Constantly rotate")
                    checked: Config.options.background.widgets.clock_cookie.constantlyRotate
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_cookie.constantlyRotate = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "more_horiz"
                    text: Translation.tr("Hour marks")
                    checked: Config.options.background.widgets.clock_cookie.hourMarks
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_cookie.hourMarks = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "123"
                    text: Translation.tr("Digits in the middle")
                    checked: Config.options.background.widgets.clock_cookie.timeIndicators
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_cookie.timeIndicators = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("Auto style the cookie clock preset")
                    checked: Config.options.background.widgets.clock_cookie.aiStyling
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_cookie.aiStyling = checked;
                    }
                }

                ContentSubsection {
                    visible: Config.options.background.widgets.clock_cookie.aiStyling
                    title: Translation.tr("AI model")
                    icon: "psychology"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.background.widgets.clock_cookie.aiStylingModel
                        onSelected: newValue => {
                            Config.options.background.widgets.clock_cookie.aiStylingModel = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Gemini"),
                                icon: "smart_toy",
                                value: "gemini"
                            },
                            {
                                displayName: Translation.tr("ChatGPT"),
                                icon: "smart_toy",
                                value: "chatgpt"
                            },
                            {
                                displayName: Translation.tr("Claude"),
                                icon: "smart_toy",
                                value: "claude"
                            }
                        ]
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Dial style")
                    icon: "settings_overscan"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.background.widgets.clock_cookie.dialNumberStyle
                        onSelected: newValue => {
                            Config.options.background.widgets.clock_cookie.dialNumberStyle = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("None"),
                                icon: "do_not_disturb",
                                value: "none"
                            },
                            {
                                displayName: Translation.tr("Dots"),
                                icon: "fiber_manual_record",
                                value: "dots"
                            },
                            {
                                displayName: Translation.tr("Shapes"),
                                icon: "category",
                                value: "shapes"
                            },
                            {
                                displayName: Translation.tr("Numbers"),
                                icon: "123",
                                value: "numbers"
                            },
                            {
                                displayName: Translation.tr("Lines"),
                                icon: "horizontal_rule",
                                value: "full"
                            }
                        ]
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Hour hand")
                    icon: "arrow_downward"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.background.widgets.clock_cookie.hourHandStyle
                        onSelected: newValue => {
                            Config.options.background.widgets.clock_cookie.hourHandStyle = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Classic"),
                                icon: "horizontal_rule",
                                value: "classic"
                            },
                            {
                                displayName: Translation.tr("Fill"),
                                icon: "square",
                                value: "fill"
                            },
                            {
                                displayName: Translation.tr("Hollow"),
                                icon: "crop_square",
                                value: "hollow"
                            },
                            {
                                displayName: Translation.tr("Hide"),
                                icon: "do_not_disturb",
                                value: "hide"
                            }
                        ]
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Minute hand")
                    icon: "arrow_downward"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.background.widgets.clock_cookie.minuteHandStyle
                        onSelected: newValue => {
                            Config.options.background.widgets.clock_cookie.minuteHandStyle = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Thin"),
                                icon: "horizontal_rule",
                                value: "thin"
                            },
                            {
                                displayName: Translation.tr("Medium"),
                                icon: "remove",
                                value: "medium"
                            },
                            {
                                displayName: Translation.tr("Bold"),
                                icon: "add",
                                value: "bold"
                            },
                            {
                                displayName: Translation.tr("Classic"),
                                icon: "format_list_bulleted",
                                value: "classic"
                            },
                            {
                                displayName: Translation.tr("Hide"),
                                icon: "do_not_disturb",
                                value: "hide"
                            }
                        ]
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Second hand")
                    icon: "arrow_downward"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.background.widgets.clock_cookie.secondHandStyle
                        onSelected: newValue => {
                            Config.options.background.widgets.clock_cookie.secondHandStyle = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("None"),
                                icon: "do_not_disturb",
                                value: "hide"
                            },
                            {
                                displayName: Translation.tr("Line"),
                                icon: "horizontal_rule",
                                value: "line"
                            },
                            {
                                displayName: Translation.tr("Dot"),
                                icon: "fiber_manual_record",
                                value: "dot"
                            },
                            {
                                displayName: Translation.tr("Classic"),
                                icon: "format_list_bulleted",
                                value: "classic"
                            }
                        ]
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Date style")
                    icon: "calendar_today"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.background.widgets.clock_cookie.dateStyle
                        onSelected: newValue => {
                            Config.options.background.widgets.clock_cookie.dateStyle = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("None"),
                                icon: "do_not_disturb",
                                value: "hide"
                            },
                            {
                                displayName: Translation.tr("Bubble"),
                                icon: "bubble_chart",
                                value: "bubble"
                            },
                            {
                                displayName: Translation.tr("Rectangle"),
                                icon: "crop_square",
                                value: "rect"
                            },
                            {
                                displayName: Translation.tr("Border"),
                                icon: "border_style",
                                value: "border"
                            }
                        ]
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Background style")
                    icon: "wallpaper"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.background.widgets.clock_cookie.backgroundStyle
                        onSelected: newValue => {
                            Config.options.background.widgets.clock_cookie.backgroundStyle = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Cookie"),
                                icon: "cookie",
                                value: "cookie"
                            },
                            {
                                displayName: Translation.tr("Sine"),
                                icon: "graphic_eq",
                                value: "sine"
                            },
                            {
                                displayName: Translation.tr("Shape"),
                                icon: "category",
                                value: "shape"
                            }
                        ]
                    }
                }

                ContentSubsection {
                    visible: Config.options.background.widgets.clock_cookie.backgroundStyle === "shape"
                    title: Translation.tr("Background shape")
                    icon: "category"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.background.widgets.clock_cookie.backgroundShape
                        onSelected: newValue => {
                            Config.options.background.widgets.clock_cookie.backgroundShape = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Circle"),
                                icon: "circle",
                                value: "Circle"
                            },
                            {
                                displayName: Translation.tr("Square"),
                                icon: "square",
                                value: "Square"
                            },
                            {
                                displayName: Translation.tr("Cookie"),
                                icon: "cookie",
                                value: "Cookie12Sided"
                            }
                        ]
                    }
                }
            }

            Item {
                Layout.preferredHeight: 16
            }

            // Quote Settings
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ContentSubsectionLabel {
                    text: Translation.tr("Quote Settings")
                }

                ConfigSwitch {
                    buttonIcon: "format_quote"
                    text: Translation.tr("Enable quote")
                    checked: Config.options.background.widgets.clock_cookie.quoteEnable
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_cookie.quoteEnable = checked;
                    }
                }

                ConfigTextField {
                    enabled: Config.options.background.widgets.clock_cookie.quoteEnable
                    icon: "edit"
                    text: Translation.tr("Quote text")
                    inputText: Config.options.background.widgets.clock_cookie.quoteText
                    onInputTextChanged: {
                        Config.options.background.widgets.clock_cookie.quoteText = inputText;
                    }
                }
            }

            Item {
                Layout.preferredHeight: 16
                visible: Config.isWidgetActive("clock_cookie")
            }

            // Visual Options (Shadows)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: Config.isWidgetActive("clock_cookie")

                DesktopWidgetVisualOptions {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
