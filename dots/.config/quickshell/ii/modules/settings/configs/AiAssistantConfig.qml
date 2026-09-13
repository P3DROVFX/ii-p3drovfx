import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.ai

Item {
    id: aiRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── General Preferences ───────────────────────────────────────────
        ContentSection {
            icon: "neurology"
            title: Translation.tr("General")
            tooltip: Translation.tr("Everyday behavior, key shortcuts and transcript layout.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                HelperLinkBox {
                    Layout.fillWidth: true
                    title: Translation.tr("Google AI Studio")
                    text: Translation.tr("Get your Gemini API Key here for free. Keys are entered from the key panel in the chat, and kept in the system keyring.")
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
                            Qt.openUrlExternally("https://aistudio.google.com/app/apikey");
                        }
                    }
                }

                ConfigSwitch {
                    buttonIcon: "smart_toy"
                    text: Translation.tr("List available models at startup")
                    checked: Config.options.ai.indexAtStartup
                    onCheckedChanged: {
                        Config.options.ai.indexAtStartup = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "text_fields"
                    text: Translation.tr("Fade answers in as they arrive")
                    checked: Config.options.sidebar.ai.textFadeIn
                    onCheckedChanged: {
                        Config.options.sidebar.ai.textFadeIn = checked;
                    }
                }

                ContentSubsection {
                    Layout.fillWidth: true
                    title: Translation.tr("Transcript density")
                    icon: "density_medium"

                    ConfigSelectionArray {
                        currentValue: Config.options.sidebar.ai.density
                        onSelected: newValue => Config.options.sidebar.ai.density = newValue
                        options: [
                            { displayName: Translation.tr("Comfortable"), icon: "view_agenda", value: "comfortable" },
                            { displayName: Translation.tr("Compact"), icon: "view_headline", value: "compact" }
                        ]
                    }
                }

                ContentSubsection {
                    Layout.fillWidth: true
                    title: Translation.tr("Send message with")
                    icon: "keyboard_return"

                    ConfigSelectionArray {
                        currentValue: Config.options.sidebar.ai.sendKey
                        onSelected: newValue => Config.options.sidebar.ai.sendKey = newValue
                        options: [
                            { displayName: Translation.tr("Enter"), icon: "keyboard_return", value: "enter" },
                            { displayName: Translation.tr("Ctrl+Enter"), icon: "keyboard", value: "ctrlEnter" }
                        ]
                    }
                }

                ConfigSwitch {
                    buttonIcon: "vertical_align_bottom"
                    text: Translation.tr("Follow new answers automatically")
                    checked: Config.options.sidebar.ai.autoScroll
                    onCheckedChanged: Config.options.sidebar.ai.autoScroll = checked
                }
            }
        }

        // ── Intelligence & Context ────────────────────────────────────────
        ContentSection {
            icon: "account_tree"
            title: Translation.tr("Intelligence & context")
            tooltip: Translation.tr("Context retention, attachments, local retrieval and document search.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSubpageRow {
                    buttonIcon: "psychology"
                    title: Translation.tr("Context & Memory")
                    description: Translation.tr("Message summaries, token limits and cross-session facts")
                    summary: Config.options.ai.memory.enabled ? Translation.tr("Memory on (%1 facts)").arg(Config.options.ai.memory.limit) : Translation.tr("Memory off")
                    onClicked: aiRoot.activeSubPage = Qt.resolvedUrl("ai/AiContextMemoryConfig.qml")
                }

                ConfigSubpageRow {
                    buttonIcon: "attach_file"
                    title: Translation.tr("Files, Vision & Voice")
                    description: Translation.tr("Attachments, local file search, OCR and dictation")
                    onClicked: aiRoot.activeSubPage = Qt.resolvedUrl("ai/AiFilesVisionVoiceConfig.qml")
                }

                ConfigSubpageRow {
                    buttonIcon: "manage_search"
                    title: Translation.tr("Local Retrieval (RAG)")
                    description: Translation.tr("Index chosen folders locally through Ollama")
                    onClicked: aiRoot.activeSubPage = Qt.resolvedUrl("ai/RagConfig.qml")
                }
            }
        }

        // ── Models & Execution ────────────────────────────────────────────
        ContentSection {
            icon: "tune"
            title: Translation.tr("Models & execution")
            tooltip: Translation.tr("Provider credentials, custom models, tool permissions and automation.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSubpageRow {
                    buttonIcon: "key"
                    title: Translation.tr("Models & Keys")
                    description: Translation.tr("Manage provider credentials and add custom models")
                    onClicked: aiRoot.activeSubPage = Qt.resolvedUrl("ai/AiModelsKeysConfig.qml")
                }

                ConfigSubpageRow {
                    buttonIcon: "service_toolbox"
                    title: Translation.tr("Tools & Permissions")
                    description: Translation.tr("Choose available tools and decide when they need approval")
                    onClicked: aiRoot.activeSubPage = Qt.resolvedUrl("ai/AiToolsPermissionsConfig.qml")
                }

                ConfigSubpageRow {
                    buttonIcon: "speed"
                    title: Translation.tr("Request Limits")
                    description: Translation.tr("Answer size, timeouts, retries and chat-toolbar metrics")
                    onClicked: aiRoot.activeSubPage = Qt.resolvedUrl("ai/AiRequestLimitsConfig.qml")
                }

                ConfigSubpageRow {
                    buttonIcon: "terminal"
                    title: Translation.tr("Remote Access & IPC")
                    description: Translation.tr("Ask this chat from scripts, cron or SSH via Quickshell IPC")
                    onClicked: aiRoot.activeSubPage = Qt.resolvedUrl("ai/AiRemoteAccessConfig.qml")
                }
            }
        }

        // ── Chat & Data ───────────────────────────────────────────────────
        ContentSection {
            icon: "forum"
            title: Translation.tr("Chat & data")
            tooltip: Translation.tr("Formatting, notifications, system prompts and usage tracking.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSubpageRow {
                    buttonIcon: "format_paint"
                    title: Translation.tr("Conversation & Formatting")
                    description: Translation.tr("Thinking presets, activity panel, markdown, latex, code styling")
                    onClicked: aiRoot.activeSubPage = Qt.resolvedUrl("ai/AiConversationAppearanceConfig.qml")
                }

                ConfigSubpageRow {
                    buttonIcon: "notifications_active"
                    title: Translation.tr("Notifications")
                    description: Translation.tr("Response readiness alerts and background banners")
                    summary: Config.options.ai.notify.whenDone ? Translation.tr("Notifications enabled") : Translation.tr("Notifications off")
                    onClicked: aiRoot.activeSubPage = Qt.resolvedUrl("ai/AiNotificationsConfig.qml")
                }

                ConfigSubpageRow {
                    buttonIcon: "monitoring"
                    title: Translation.tr("Usage & Cost")
                    description: Translation.tr("Token metrics, cost breakdown, and request dashboard")
                    onClicked: aiRoot.activeSubPage = Qt.resolvedUrl("ai/AiUsageCostConfig.qml")
                }

                ConfigSubpageRow {
                    buttonIcon: "description"
                    title: Translation.tr("System Prompt & Privacy")
                    description: Translation.tr("Base persona prompt and window-class metadata privacy")
                    onClicked: aiRoot.activeSubPage = Qt.resolvedUrl("ai/AiPromptPrivacyConfig.qml")
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
