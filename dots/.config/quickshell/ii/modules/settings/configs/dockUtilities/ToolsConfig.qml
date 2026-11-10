import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../ii/dock/utilities/UtilityTools.js" as UtilityTools

UtilityConfigPage {
    id: page
    title: Translation.tr("Tools")

    readonly property var cfg: Config.options.dock.utilities.tools

    function setShown(id, on) {
        const current = UtilityTools.shown(page.cfg.shown);
        page.cfg.shown = on ? UtilityTools.shown(current.concat([id])) : current.filter(other => other !== id);
    }

    ContentSection {
        title: Translation.tr("Tools")
        icon: "handyman"
        tooltip: Translation.tr("The wide widget shows them in this order; the panel shows them all")

        Repeater {
            model: UtilityTools.tools
            delegate: ConfigSwitch {
                required property var modelData
                buttonIcon: modelData.symbol
                text: Translation.tr(modelData.title)
                checked: page.cfg.shown.includes(modelData.id)
                onCheckedChanged: if (checked !== page.cfg.shown.includes(modelData.id)) page.setShown(modelData.id, checked)
            }
        }
    }
}
