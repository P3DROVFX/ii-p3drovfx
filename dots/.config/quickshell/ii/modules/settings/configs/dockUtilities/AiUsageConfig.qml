import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

UtilityConfigPage {
    id: page
    title: Translation.tr("AI usage")

    readonly property var cfg: Config.options.dock.utilities.aiUsage
    // The providers AiPlanUsage reads (the ones enabled in AI plan usage),
    // Antigravity split into its model pools, plus "follow the bar".
    readonly property var providerOptions: [
        { displayName: Translation.tr("Same as the bar"), icon: "sync_alt", value: "auto" }
    ].concat((AiPlanUsage.displayProviders ?? []).map(provider => ({
        displayName: String(provider.name ?? AiPlanUsage.providerName(String(provider.providerId ?? provider.id))),
        icon: "auto_awesome",
        value: String(provider.targetId ?? provider.id)
    })))

    ContentSection {
        title: Translation.tr("Provider")
        icon: "auto_awesome"
        tooltip: Translation.tr("Whose plan the widget shows. The list follows the services enabled in AI plan usage")

        ConfigSelectionArray {
            currentValue: page.cfg.provider
            onSelected: newValue => page.cfg.provider = newValue
            options: page.providerOptions
        }
    }

    ContentSection {
        title: Translation.tr("Square widget")
        icon: "crop_square"

        ConfigSelectionArray {
            currentValue: page.cfg.squareWindow
            onSelected: newValue => page.cfg.squareWindow = newValue
            options: [
                { displayName: Translation.tr("Week, day or month"), icon: "date_range", value: "long" },
                { displayName: Translation.tr("Session"), icon: "schedule", value: "short" }
            ]
        }
    }

    ContentSection {
        title: Translation.tr("Data")
        icon: "tune"

        ConfigSubpageRow {
            buttonIcon: "tune"
            title: Translation.tr("AI plan usage")
            description: Translation.tr("Enabled services, refresh interval and low-quota threshold, shared with the bar widget")
            configPage: Qt.resolvedUrl("../widgets/AiPlanUsageConfig.qml")
        }
    }
}
