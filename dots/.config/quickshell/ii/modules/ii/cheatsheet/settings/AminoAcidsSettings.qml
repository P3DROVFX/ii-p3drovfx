import QtQuick
import qs.modules.common
import qs.services

/** The Amino acids tab's settings. */
CheatsheetSettingsPage {
    title: Translation.tr("Amino acids settings")
    subtitle: Translation.tr("Classification Scheme")

    CheatsheetSettingsSection {
        title: Translation.tr("Classification Scheme")
        symbol: "palette"

        CheatsheetChoiceRow {
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
