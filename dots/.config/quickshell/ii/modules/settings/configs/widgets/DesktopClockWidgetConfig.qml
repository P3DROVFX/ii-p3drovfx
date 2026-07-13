import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

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
            text: Translation.tr("Clock Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Clock Settings")
        icon: "schedule"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ContentSubsectionLabel {
                text: Translation.tr("General")
            }

            ContentSubsection {
                title: Translation.tr("Position")
                Layout.fillWidth: true
                icon: "arrows_output"

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock.placementStrategy
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.placementStrategy = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Draggable"),
                            icon: "pan_tool",
                            value: "draggable"
                        },
                        {
                            displayName: Translation.tr("Least busy"),
                            icon: "low_priority",
                            value: "least_busy"
                        },
                        {
                            displayName: Translation.tr("Most busy"),
                            icon: "priority_high",
                            value: "most_busy"
                        }
                    ]
                }
            }


            ContentSubsection {
                title: Translation.tr("Clock style")
                icon: "style"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock.style
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.style = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Digital"),
                            icon: "123",
                            value: "digital"
                        },
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "cookie"
                        },
                        {
                            displayName: Translation.tr("Nagasaki"),
                            icon: "sports_martial_arts",
                            value: "nagasaki"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Clock style (locked)")
                icon: "lock_clock"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock.styleLocked
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.styleLocked = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Digital"),
                            icon: "123",
                            value: "digital"
                        },
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "cookie"
                        },
                        {
                            displayName: Translation.tr("Nagasaki"),
                            icon: "sports_martial_arts",
                            value: "nagasaki"
                        }
                    ]
                }
            }

            Item {
                Layout.preferredHeight: 16
                visible: Config.options.background.widgets.clock.style === "digital" || Config.options.background.widgets.clock.styleLocked === "digital"
            }

            // Digital Style Settings
            ColumnLayout {
                visible: Config.options.background.widgets.clock.style === "digital" || Config.options.background.widgets.clock.styleLocked === "digital"
                Layout.fillWidth: true
                spacing: 4

                ContentSubsectionLabel {
                    text: Translation.tr("Digital Style Settings")
                }

                ConfigSwitch {
                    buttonIcon: "swap_vert"
                    text: Translation.tr("Vertical")
                    checked: Config.options.background.widgets.clock.digital.vertical
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.vertical = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "animation"
                    text: Translation.tr("Animate time change")
                    checked: Config.options.background.widgets.clock.digital.animateChange
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.animateChange = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "calendar_today"
                    text: Translation.tr("Show date")
                    checked: Config.options.background.widgets.clock.digital.showDate
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.showDate = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "align_horizontal_center"
                    text: Translation.tr("Use adaptive alignment")
                    checked: Config.options.background.widgets.clock.digital.adaptiveAlignment
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.adaptiveAlignment = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "palette"
                    text: Translation.tr("Colorful digits")
                    checked: Config.options.background.widgets.clock.digital.colorful
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.colorful = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "more_vert"
                    text: Translation.tr("Show colon")
                    checked: Config.options.background.widgets.clock.digital.showColon
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.showColon = checked;
                    }
                }

                ConfigTextField {
                    icon: "font_download"
                    text: Translation.tr("Font family")
                    inputText: Config.options.background.widgets.clock.digital.font.family
                    onInputTextChanged: {
                        Config.options.background.widgets.clock.digital.font.family = inputText;
                    }
                }

                ConfigSlider {
                    buttonIcon: "format_bold"
                    text: Translation.tr("Font weight")
                    value: Config.options.background.widgets.clock.digital.font.weight
                    from: 100
                    to: 900
                    stepSize: 100
                    onValueChanged: {
                        Config.options.background.widgets.clock.digital.font.weight = value;
                    }
                }

                ConfigSlider {
                    buttonIcon: "format_size"
                    text: Translation.tr("Font size")
                    value: Config.options.background.widgets.clock.digital.font.size
                    from: 10
                    to: 300
                    stepSize: 1
                    onValueChanged: {
                        Config.options.background.widgets.clock.digital.font.size = value;
                    }
                }

                ConfigSlider {
                    buttonIcon: "width_normal"
                    text: Translation.tr("Font width")
                    value: Config.options.background.widgets.clock.digital.font.width
                    from: 10
                    to: 200
                    stepSize: 1
                    onValueChanged: {
                        Config.options.background.widgets.clock.digital.font.width = value;
                    }
                }

                ConfigSlider {
                    buttonIcon: "rounded_corner"
                    text: Translation.tr("Font roundness")
                    value: Config.options.background.widgets.clock.digital.font.roundness
                    from: 0
                    to: 100
                    stepSize: 1
                    onValueChanged: {
                        Config.options.background.widgets.clock.digital.font.roundness = value;
                    }
                }
            }

            Item {
                Layout.preferredHeight: 16
                visible: Config.options.background.widgets.clock.style === "cookie" || Config.options.background.widgets.clock.styleLocked === "cookie"
            }

            // Cookie Style Settings
            ColumnLayout {
                visible: Config.options.background.widgets.clock.style === "cookie" || Config.options.background.widgets.clock.styleLocked === "cookie"
                Layout.fillWidth: true
                spacing: 4

                ContentSubsectionLabel {
                    text: Translation.tr("Cookie Style Settings")
                }

                ConfigSpinBox {
                    icon: "interests"
                    text: Translation.tr("Sides")
                    value: Config.options.background.widgets.clock.cookie.sides
                    from: 3
                    to: 24
                    stepSize: 1
                    onValueChanged: {
                        Config.options.background.widgets.clock.cookie.sides = value;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "rotate_right"
                    text: Translation.tr("Constantly rotate")
                    checked: Config.options.background.widgets.clock.cookie.constantlyRotate
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.cookie.constantlyRotate = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "more_horiz"
                    text: Translation.tr("Hour marks")
                    checked: Config.options.background.widgets.clock.cookie.hourMarks
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.cookie.hourMarks = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "123"
                    text: Translation.tr("Digits in the middle")
                    checked: Config.options.background.widgets.clock.cookie.timeIndicators
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.cookie.timeIndicators = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("Auto style the cookie clock preset")
                    checked: Config.options.background.widgets.clock.cookie.aiStyling
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.cookie.aiStyling = checked;
                    }
                }

                ContentSubsection {
                    visible: Config.options.background.widgets.clock.cookie.aiStyling
                    title: Translation.tr("AI model")
                    icon: "psychology"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.background.widgets.clock.cookie.aiStylingModel
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.cookie.aiStylingModel = newValue;
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
                        currentValue: Config.options.background.widgets.clock.cookie.dialNumberStyle
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.cookie.dialNumberStyle = newValue;
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
                        currentValue: Config.options.background.widgets.clock.cookie.hourHandStyle
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.cookie.hourHandStyle = newValue;
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
                        currentValue: Config.options.background.widgets.clock.cookie.minuteHandStyle
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.cookie.minuteHandStyle = newValue;
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
                        currentValue: Config.options.background.widgets.clock.cookie.secondHandStyle
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.cookie.secondHandStyle = newValue;
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
                        currentValue: Config.options.background.widgets.clock.cookie.dateStyle
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.cookie.dateStyle = newValue;
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
                        currentValue: Config.options.background.widgets.clock.cookie.backgroundStyle
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.cookie.backgroundStyle = newValue;
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
                    visible: Config.options.background.widgets.clock.cookie.backgroundStyle === "shape"
                    title: Translation.tr("Background shape")
                    icon: "category"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.background.widgets.clock.cookie.backgroundShape
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.cookie.backgroundShape = newValue;
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
                    checked: Config.options.background.widgets.clock.quote.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.quote.enable = checked;
                    }
                }

                ConfigTextField {
                    enabled: Config.options.background.widgets.clock.quote.enable
                    icon: "edit"
                    text: Translation.tr("Quote text")
                    inputText: Config.options.background.widgets.clock.quote.text
                    onInputTextChanged: {
                        Config.options.background.widgets.clock.quote.text = inputText;
                    }
                }
            }
        }
    }
}
