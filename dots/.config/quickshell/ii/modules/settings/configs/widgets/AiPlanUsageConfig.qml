pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.widgets.aiPlanUsage
import qs.services

ContentPage {
    id: root

    signal goBack()
    forceWidth: false

    function providerEnabled(providerId: string): bool {
        return Array.from(Config.options.bar.aiPlanUsage.enabledProviders).indexOf(providerId) >= 0;
    }

    function setProviderEnabled(providerId: string, enabled: bool): void {
        const providers = Array.from(Config.options.bar.aiPlanUsage.enabledProviders);
        const index = providers.indexOf(providerId);
        if (enabled && index < 0)
            providers.push(providerId);
        else if (!enabled && index >= 0)
            providers.splice(index, 1);
        Config.options.bar.aiPlanUsage.enabledProviders = providers;
    }

    function providerStatus(providerId: string): string {
        const provider = AiPlanUsage.providerById(providerId);
        if (!provider)
            return Translation.tr("Waiting");
        if (provider.available === true) {
            if (providerId === "openrouter" && (provider.items ?? []).length > 0)
                return AiPlanUsage.creditAmountText(provider.items[0]) + " " + Translation.tr("remaining");
            return Translation.tr("%1 quotas").arg(String((provider.items ?? []).length));
        }
        return Translation.tr("Unavailable");
    }

    RowLayout {
        spacing: Appearance.rounding.small

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
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
            text: Translation.tr("AI Plan Usage")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "cloud_sync"
        title: Translation.tr("Tracking")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "shield_lock"
            text: Translation.tr("Plan Usage reads local client credentials only in memory and caches quota snapshots without tokens. Enabled cloud providers use their read-only usage endpoints; Antigravity reuses its local server.")
        }

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Enable AI plan tracking")
            checked: Config.options.bar.aiPlanUsage.enabled
            onCheckedChanged: Config.options.bar.aiPlanUsage.enabled = checked
        }

        ConfigSwitch {
            enabled: Config.options.bar.aiPlanUsage.enabled
            buttonIcon: "sync"
            text: Translation.tr("Refresh automatically")
            checked: Config.options.bar.aiPlanUsage.autoRefresh
            onCheckedChanged: Config.options.bar.aiPlanUsage.autoRefresh = checked
        }

        ConfigSpinBox {
            enabled: Config.options.bar.aiPlanUsage.enabled
                && Config.options.bar.aiPlanUsage.autoRefresh
            icon: "timer"
            text: Translation.tr("Refresh interval (minutes)")
            value: Math.round(Config.options.bar.aiPlanUsage.refreshInterval / 60000)
            from: 1
            to: 60
            stepSize: 1
            onValueChanged: Config.options.bar.aiPlanUsage.refreshInterval = value * 60000
        }

        ConfigSwitch {
            enabled: Config.options.bar.aiPlanUsage.enabled
            buttonIcon: "visibility_off"
            text: Translation.tr("Hide the bar widget while quota data is unavailable")
            checked: Config.options.bar.aiPlanUsage.hideWhenUnavailable
            onCheckedChanged: Config.options.bar.aiPlanUsage.hideWhenUnavailable = checked
        }
    }

    ContentSection {
        icon: "hub"
        title: Translation.tr("AI services")

        ConfigSwitch {
            enabled: Config.options.bar.aiPlanUsage.enabled
            buttonIcon: "smart_toy"
            text: Translation.tr("ChatGPT / Codex")
            description: Translation.tr("Reads the newest local Codex rate-limit snapshot")
            checked: root.providerEnabled("chatgpt")
            onCheckedChanged: root.setProviderEnabled("chatgpt", checked)
        }

        ConfigSwitch {
            enabled: Config.options.bar.aiPlanUsage.enabled
            buttonIcon: "psychology"
            text: Translation.tr("Claude")
            description: Translation.tr("Reads Claude Code credentials and the cached usage endpoint")
            checked: root.providerEnabled("claude")
            onCheckedChanged: root.setProviderEnabled("claude", checked)
        }

        ConfigSwitch {
            visible: root.providerEnabled("claude")
            enabled: Config.options.bar.aiPlanUsage.enabled
            buttonIcon: "cloud"
            text: Translation.tr("Allow Claude quota network checks")
            checked: Config.options.bar.aiPlanUsage.claudeNetworkEnabled
            onCheckedChanged: Config.options.bar.aiPlanUsage.claudeNetworkEnabled = checked
        }

        ConfigSwitch {
            enabled: Config.options.bar.aiPlanUsage.enabled
            buttonIcon: "rocket_launch"
            text: Translation.tr("Antigravity (agy)")
            description: Translation.tr("Uses an already-running agy language server; never starts another instance")
            checked: root.providerEnabled("antigravity")
            onCheckedChanged: root.setProviderEnabled("antigravity", checked)
        }

        ConfigSwitch {
            enabled: Config.options.bar.aiPlanUsage.enabled
            buttonIcon: "data_object"
            text: Translation.tr("Z.AI GLM Coding Plan")
            description: Translation.tr("Reads the 5-hour and weekly GLM quota using a supported client's Z.AI key")
            checked: root.providerEnabled("zai")
            onCheckedChanged: root.setProviderEnabled("zai", checked)
        }

        ConfigSwitch {
            enabled: Config.options.bar.aiPlanUsage.enabled
            buttonIcon: "dark_mode"
            text: Translation.tr("Kimi Code")
            description: Translation.tr("Reads Kimi Code's 5-hour and weekly quota without refreshing its credentials")
            checked: root.providerEnabled("kimi")
            onCheckedChanged: root.setProviderEnabled("kimi", checked)
        }

        ConfigSwitch {
            enabled: Config.options.bar.aiPlanUsage.enabled
            buttonIcon: "terminal"
            text: Translation.tr("OpenCode Go")
            description: Translation.tr("Reads 5-hour, weekly, and monthly usage from the connected OpenCode Go account")
            checked: root.providerEnabled("opencode")
            onCheckedChanged: root.setProviderEnabled("opencode", checked)
        }

        ConfigSwitch {
            enabled: Config.options.bar.aiPlanUsage.enabled
            buttonIcon: "account_balance_wallet"
            text: Translation.tr("OpenRouter credits")
            description: Translation.tr("Shows only remaining account credits, or the remaining cap of a limited key")
            checked: root.providerEnabled("openrouter")
            onCheckedChanged: root.setProviderEnabled("openrouter", checked)
        }
    }

    ContentSection {
        icon: "palette"
        title: Translation.tr("Presentation")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "auto_awesome"
            text: Translation.tr("Each provider automatically shows the quota windows it publishes. Antigravity model pools are separate stops; OpenRouter always shows remaining credits regardless of the percentage setting.")
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 78
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors.centerIn: parent
                spacing: 12

                MaterialSymbol {
                    text: "preview"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }

                Repeater {
                    model: AiPlanUsage.selectedItems

                    delegate: AiQuotaIndicator {
                        required property var modelData
                        required property int index

                        quota: modelData
                        visualization: Config.options.bar.aiPlanUsage.visualization
                        showWindowLabel: Config.options.bar.aiPlanUsage.showWindowLabel
                        contentColor: Appearance.colors.colOnLayer2
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Widget design")

            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.aiPlanUsage
                onSelected: newValue => Config.options.bar.styles.aiPlanUsage = String(newValue)
                options: [
                    { displayName: Translation.tr("Default"), icon: "style", value: "default" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Indicator shape")

            ConfigSelectionArray {
                currentValue: Config.options.bar.aiPlanUsage.visualization
                onSelected: newValue => Config.options.bar.aiPlanUsage.visualization = String(newValue)
                options: [
                    { displayName: Translation.tr("Resources"), icon: "donut_large", value: "resource" },
                    { displayName: Translation.tr("Semicircle"), icon: "speed", value: "semicircle" },
                    { displayName: Translation.tr("Circle"), icon: "data_usage", value: "circle" },
                    { displayName: Translation.tr("Shape"), icon: "interests", value: "shape" },
                    { displayName: Translation.tr("Progress bar"), icon: "linear_scale", value: "bar" },
                    { displayName: Translation.tr("Text only"), icon: "percent", value: "text" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Percentage meaning")

            ConfigSelectionArray {
                currentValue: Config.options.bar.aiPlanUsage.percentMode
                onSelected: newValue => Config.options.bar.aiPlanUsage.percentMode = String(newValue)
                options: [
                    { displayName: Translation.tr("Remaining"), icon: "hourglass_top", value: "remaining" },
                    { displayName: Translation.tr("Used"), icon: "hourglass_bottom", value: "used" }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "label"
            text: Translation.tr("Show the quota window below each indicator")
            checked: Config.options.bar.aiPlanUsage.showWindowLabel
            onCheckedChanged: Config.options.bar.aiPlanUsage.showWindowLabel = checked
        }

        ConfigSpinBox {
            icon: "warning"
            text: Translation.tr("Low remaining quota warning (%)")
            value: Config.options.bar.aiPlanUsage.lowRemainingThreshold
            from: 0
            to: 50
            stepSize: 5
            onValueChanged: Config.options.bar.aiPlanUsage.lowRemainingThreshold = value
        }
    }

    ContentSection {
        icon: "monitoring"
        title: Translation.tr("Right now")

        ConfigRow {
            uniform: true

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 46
                enabled: !AiPlanUsage.refreshing
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: AiPlanUsage.refresh(true)

                contentItem: RowLayout {
                    spacing: 8

                    Item { Layout.fillWidth: true }
                    MaterialSymbol {
                        text: AiPlanUsage.refreshing ? "sync" : "refresh"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        text: AiPlanUsage.refreshing
                            ? Translation.tr("Refreshing…")
                            : Translation.tr("Refresh now")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 46
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("%1 services ready").arg(String(AiPlanUsage.availableProviderCount))
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: AiPlanUsage.available
                        ? Appearance.colors.colOnLayer2
                        : Appearance.colors.colError
                }
            }
        }

        Repeater {
            model: ["chatgpt", "claude", "antigravity", "zai", "kimi", "opencode", "openrouter"]

            delegate: Rectangle {
                required property string modelData

                Layout.fillWidth: true
                implicitHeight: 52
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                opacity: root.providerEnabled(modelData) ? 1.0 : 0.48

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    CustomIcon {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        source: AiPlanUsage.providerIcon(modelData)
                        colorize: true
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: AiPlanUsage.providerName(modelData)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        text: root.providerEnabled(modelData)
                            ? root.providerStatus(modelData)
                            : Translation.tr("Disabled")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        NoticeBox {
            visible: AiPlanUsage.errorMessage.length > 0
            Layout.fillWidth: true
            materialIcon: "info"
            text: AiPlanUsage.errorMessage
        }
    }
}
