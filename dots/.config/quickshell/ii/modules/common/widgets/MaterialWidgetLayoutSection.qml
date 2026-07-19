import QtQuick
import qs.services
import qs.modules.common

/**
 * The "Material 3 Design" layout block shared by material-style bar widgets
 * (battery, keyboard layout, clock). `config` is the widget's
 * Config.options.bar.<widget> object holding the four layout keys
 * (secondaryOpposite, showPrimary, showSecondary, swapPrimaryWithSecondary).
 * Extra widget-specific switches can be added as children — they appear
 * after the shared four.
 */
ContentSection {
    id: root

    property var config: null

    icon: "interests"
    title: Translation.tr("Material 3 Design")

    ConfigSwitch {
        buttonIcon: "flip"
        text: Translation.tr("Move secondary component to the opposite")
        checked: root.config?.secondaryOpposite ?? false
        onCheckedChanged: {
            if (root.config)
                root.config.secondaryOpposite = checked;
        }
    }

    ConfigSwitch {
        buttonIcon: "radio_button_checked"
        text: Translation.tr("Show primary component")
        checked: root.config?.showPrimary ?? true
        onCheckedChanged: {
            if (root.config)
                root.config.showPrimary = checked;
        }
    }

    ConfigSwitch {
        buttonIcon: "radio_button_unchecked"
        text: Translation.tr("Show secondary component")
        checked: root.config?.showSecondary ?? true
        onCheckedChanged: {
            if (root.config)
                root.config.showSecondary = checked;
        }
    }

    ConfigSwitch {
        buttonIcon: "sync"
        text: Translation.tr("Swap secondary component with the primary")
        checked: root.config?.swapPrimaryWithSecondary ?? false
        onCheckedChanged: {
            if (root.config)
                root.config.swapPrimaryWithSecondary = checked;
        }
    }
}
