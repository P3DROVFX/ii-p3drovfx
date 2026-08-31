import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * The two shadow toggles under "Visual Options" are *global* — they apply to
 * every desktop widget, not to the page they sit on — but the block had been
 * copy-pasted into 50 separate per-widget config pages, which meant 50 places
 * to keep in step. This is that block, once.
 *
 *   DesktopWidgetVisualOptions { visible: Config.isWidgetActive("date_default") }
 */
ColumnLayout {
    id: root

    spacing: 4

    ContentSubsectionLabel {
        text: Translation.tr("Visual Options")
    }

    ConfigSwitch {
        buttonIcon: "wb_sunny"
        text: Translation.tr("Enable Shadows")
        checked: Config.options.background.widgets.enableShadows ?? true
        onCheckedChanged: {
            Config.options.background.widgets.enableShadows = checked;
        }
    }

    ConfigSwitch {
        buttonIcon: "blur_on"
        text: Translation.tr("Enable Inner Shadows")
        checked: Config.options.background.widgets.enableInnerShadow ?? true
        onCheckedChanged: {
            Config.options.background.widgets.enableInnerShadow = checked;
        }
    }
}
