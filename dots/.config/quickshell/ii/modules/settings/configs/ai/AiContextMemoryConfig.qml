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
                text: Translation.tr("Context & Memory")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "account_tree"
            title: Translation.tr("Conversation Context")
            tooltip: Translation.tr("Manage message history truncation and token allocation for long conversations.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "summarize"
                    text: Translation.tr("Manage long conversations")
                    checked: Config.options.ai.context.manage
                    onCheckedChanged: {
                        Config.options.ai.context.manage = checked;
                    }
                }

                ConfigSwitch {
                    enabled: Config.options.ai.context.manage
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("Summarise earlier messages when needed")
                    checked: Config.options.ai.context.summarise
                    onCheckedChanged: {
                        Config.options.ai.context.summarise = checked;
                    }
                }

                ConfigSpinBox {
                    enabled: Config.options.ai.context.manage
                    icon: "data_usage"
                    text: Translation.tr("Tokens reserved for each answer")
                    value: Config.options.ai.context.reserveTokens
                    from: 256
                    to: 32768
                    stepSize: 256
                    onValueChanged: {
                        Config.options.ai.context.reserveTokens = value;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "text_snippet"
                    text: Translation.tr("Extract text from attached documents")
                    checked: Config.options.ai.extractDocuments
                    onCheckedChanged: {
                        Config.options.ai.extractDocuments = checked;
                    }
                }
            }
        }

        ContentSection {
            icon: "psychology"
            title: Translation.tr("Long-Term Memory")
            tooltip: Translation.tr("Persist key facts and preferences across different chat sessions.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "psychology"
                    text: Translation.tr("Remember facts between conversations")
                    checked: Config.options.ai.memory.enabled
                    onCheckedChanged: {
                        Config.options.ai.memory.enabled = checked;
                    }
                }

                ConfigSpinBox {
                    enabled: Config.options.ai.memory.enabled
                    icon: "memory"
                    text: Translation.tr("Facts remembered between conversations")
                    value: Config.options.ai.memory.limit
                    from: 0
                    to: 200
                    stepSize: 1
                    onValueChanged: {
                        Config.options.ai.memory.limit = value;
                    }
                }
            }
        }
    }
}
