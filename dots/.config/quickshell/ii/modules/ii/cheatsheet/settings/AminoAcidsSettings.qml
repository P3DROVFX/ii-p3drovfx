import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/** The Amino acids tab's settings. */
AppSettingsPage {
    title: Translation.tr("Amino acids settings")
    subtitle: Translation.tr("Classification Scheme")

    AppSettingsSection {
        title: Translation.tr("Classification Scheme")
        symbol: "palette"

        AppChoiceRow {
            symbol: "palette"
            title: Translation.tr("Side chain classes")
            currentValue: Config.options.cheatsheet.aminoAcidScheme
            onSelected: value => Config.options.cheatsheet.aminoAcidScheme = value
            options: [
                { "label": Translation.tr("5 classes"), "value": "five" },
                { "label": Translation.tr("7 classes"), "value": "seven" },
                { "label": Translation.tr("4 classes"), "value": "four" }
            ]
        }
    }
}
