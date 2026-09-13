import QtQuick
import QtQuick.Layouts
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
                text: Translation.tr("Conversation & Formatting")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "forum"
            title: Translation.tr("Conversation")
            tooltip: Translation.tr("Retention, titles and status message preferences.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("Name new conversations automatically")
                    checked: Config.options.ai.autoTitle
                    onCheckedChanged: Config.options.ai.autoTitle = checked
                }

                ConfigSwitch {
                    buttonIcon: "inventory_2"
                    text: Translation.tr("Keep status messages in saved conversations")
                    checked: !Config.options.ai.ephemeralInterfaceMessages
                    onCheckedChanged: Config.options.ai.ephemeralInterfaceMessages = !checked
                }

                ConfigSpinBox {
                    icon: "delete_sweep"
                    text: Translation.tr("Days to keep deleted conversations")
                    value: Config.options.ai.sessions.retentionDays
                    from: 1
                    to: 3650
                    stepSize: 1
                    onValueChanged: Config.options.ai.sessions.retentionDays = value
                }
            }
        }

        ContentSection {
            icon: "chat"
            title: Translation.tr("Chat experience")
            tooltip: Translation.tr("Visual density, thinking levels, activity panels and indicators.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ContentSubsection {
                    Layout.fillWidth: true
                    title: Translation.tr("Default thinking")
                    icon: "psychology"

                    ConfigSelectionArray {
                        currentValue: Config.options.sidebar.ai.thinkingDefault
                        onSelected: newValue => Config.options.sidebar.ai.thinkingDefault = newValue
                        options: [
                            { displayName: Translation.tr("Remembered"), icon: "bookmark", value: "" },
                            { displayName: Translation.tr("Off"), icon: "block", value: "off" },
                            { displayName: Translation.tr("Low"), icon: "speed", value: "low" },
                            { displayName: Translation.tr("Medium"), icon: "balance", value: "medium" },
                            { displayName: Translation.tr("High"), icon: "psychology", value: "high" }
                        ]
                    }
                }

                ContentSubsection {
                    Layout.fillWidth: true
                    title: Translation.tr("Activity details")
                    icon: "pending_actions"

                    ConfigSelectionArray {
                        currentValue: Config.options.sidebar.ai.activityDefault
                        onSelected: newValue => Config.options.sidebar.ai.activityDefault = newValue
                        options: [
                            { displayName: Translation.tr("Automatic"), icon: "auto_mode", value: "auto" },
                            { displayName: Translation.tr("Expanded"), icon: "unfold_more", value: "expanded" },
                            { displayName: Translation.tr("Collapsed"), icon: "unfold_less", value: "collapsed" }
                        ]
                    }
                }

                ConfigSwitch {
                    buttonIcon: "schedule"
                    text: Translation.tr("Show message timestamps")
                    checked: Config.options.sidebar.ai.showTimestamps
                    onCheckedChanged: Config.options.sidebar.ai.showTimestamps = checked
                }

                ConfigSwitch {
                    buttonIcon: "timer"
                    text: Translation.tr("Show answer time")
                    checked: Config.options.sidebar.ai.showResponseTime
                    onCheckedChanged: Config.options.sidebar.ai.showResponseTime = checked
                }

                ConfigSwitch {
                    buttonIcon: "smart_toy"
                    text: Translation.tr("Show the answering model")
                    checked: Config.options.sidebar.ai.showAnswerModel
                    onCheckedChanged: Config.options.sidebar.ai.showAnswerModel = checked
                }

                ConfigSwitch {
                    buttonIcon: "motion_photos_off"
                    text: Translation.tr("Reduce motion in AI chat")
                    checked: Config.options.sidebar.ai.reducedMotion
                    onCheckedChanged: Config.options.sidebar.ai.reducedMotion = checked
                }
            }
        }

        ContentSection {
            icon: "code"
            title: Translation.tr("Answer formatting")
            tooltip: Translation.tr("Markdown, mathematical notation, code styling and greetings.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "markdown"
                    text: Translation.tr("Render Markdown")
                    checked: Config.options.sidebar.ai.renderMarkdown
                    onCheckedChanged: Config.options.sidebar.ai.renderMarkdown = checked
                }

                ConfigSwitch {
                    buttonIcon: "functions"
                    text: Translation.tr("Render mathematical notation")
                    checked: Config.options.sidebar.ai.renderLatex
                    onCheckedChanged: Config.options.sidebar.ai.renderLatex = checked
                }

                ConfigSwitch {
                    buttonIcon: "wrap_text"
                    text: Translation.tr("Wrap code blocks")
                    checked: Config.options.sidebar.ai.codeWrap
                    onCheckedChanged: Config.options.sidebar.ai.codeWrap = checked
                }

                ConfigSwitch {
                    buttonIcon: "format_list_numbered"
                    text: Translation.tr("Show code line numbers")
                    checked: Config.options.sidebar.ai.codeLineNumbers
                    onCheckedChanged: Config.options.sidebar.ai.codeLineNumbers = checked
                }

                ConfigSwitch {
                    buttonIcon: "unfold_less"
                    text: Translation.tr("Collapse long answers")
                    checked: Config.options.sidebar.ai.collapseLongAnswers
                    onCheckedChanged: Config.options.sidebar.ai.collapseLongAnswers = checked
                }

                ConfigSwitch {
                    buttonIcon: "keyboard"
                    text: Translation.tr("Show empty-chat keyboard hints")
                    checked: Config.options.sidebar.ai.emptyStateKeys
                    onCheckedChanged: Config.options.sidebar.ai.emptyStateKeys = checked
                }

                ConfigSwitch {
                    buttonIcon: "volume_up"
                    text: Translation.tr("Play a sound when an answer is ready")
                    checked: Config.options.sidebar.ai.soundOnAnswer
                    onCheckedChanged: Config.options.sidebar.ai.soundOnAnswer = checked
                }

                ConfigTextField {
                    Layout.fillWidth: true
                    text: Translation.tr("Empty-chat greeting")
                    icon: "waving_hand"
                    placeholderText: Translation.tr("Use a rotating greeting")
                    tooltip: Translation.tr("Leave empty to use the built-in rotating greeting.")
                    inputText: Config.options.sidebar.ai.greeting
                    textField.onEditingFinished: Config.options.sidebar.ai.greeting = textField.text
                }

                ConfigTextField {
                    Layout.fillWidth: true
                    text: Translation.tr("Toolbar items")
                    icon: "toolbar"
                    placeholderText: "keys, advanced, sessions, newChat"
                    tooltip: Translation.tr("Comma-separated: keys, advanced, sessions, newChat, model, thinking, tools, prompt, projects, memory, slash.")
                    inputText: Array.from(Config.options.sidebar.ai.barKeys ?? []).join(", ")
                    textField.onEditingFinished: {
                        const allowed = ["keys", "advanced", "sessions", "newChat", "model", "thinking", "tools", "prompt", "projects", "memory", "slash"];
                        const items = textField.text.split(",").map(item => item.trim())
                            .filter((item, index, all) => allowed.indexOf(item) >= 0 && all.indexOf(item) === index);
                        Config.options.sidebar.ai.barKeys = items;
                    }
                }
            }
        }
    }
}
