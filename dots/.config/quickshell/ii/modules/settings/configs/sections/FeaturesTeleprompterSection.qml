import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Search proxy for the teleprompter's switches.
 *
 * The Settings search indexes the sections a page lists, not the expressive
 * components the page draws; this keeps every teleprompter option findable by
 * name while the live page owns the controls. Same bindings, same config keys.
 */
ContentSection {
    icon: "subtitles"
    title: Translation.tr("Teleprompter")

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Appearance.sizes.elevationMargin / 2

        ConfigSwitch {
            buttonIcon: "subtitles"
            text: Translation.tr("Teleprompter")
            checked: Config.options.dynamicIsland.widgets.teleprompter.enable === true
            onCheckedChanged: {
                const cfg = Config.options.dynamicIsland.widgets.teleprompter;
                if (checked !== (cfg.enable === true))
                    cfg.enable = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "repeat"
            text: Translation.tr("Loop the script")
            checked: Config.options.dynamicIsland.widgets.teleprompter.loop === true
            onCheckedChanged: {
                const cfg = Config.options.dynamicIsland.widgets.teleprompter;
                if (checked !== (cfg.loop === true))
                    cfg.loop = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "swap_horiz"
            text: Translation.tr("Mirror the text")
            checked: Config.options.dynamicIsland.widgets.teleprompter.mirror === true
            onCheckedChanged: {
                const cfg = Config.options.dynamicIsland.widgets.teleprompter;
                if (checked !== (cfg.mirror === true))
                    cfg.mirror = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "fullscreen"
            text: Translation.tr("Stay on screen while reading")
            checked: Config.options.dynamicIsland.widgets.teleprompter.holdVisible !== false
            onCheckedChanged: {
                const cfg = Config.options.dynamicIsland.widgets.teleprompter;
                if (checked !== (cfg.holdVisible !== false))
                    cfg.holdVisible = checked;
            }
        }
    }
}
