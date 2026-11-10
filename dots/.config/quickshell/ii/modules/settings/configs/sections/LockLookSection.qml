import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Search proxy for the Lock Screen page: the lock's look (effects). The elements and behavior sections are on the page itself. The page itself draws these
// options as a live preview, sliders and tiles; SearchRegistry indexes this file
// (see SettingsPageRegistry `searchSources`) so the options stay searchable.
ColumnLayout {
    ContentSection {
        icon: "blur_on"
        title: Translation.tr("Blur style")

        ConfigSwitch {
            buttonIcon: "lens_blur"
            text: Translation.tr("Enable blur")
            checked: Config.options.lock.blur.enable
            onCheckedChanged: Config.options.lock.blur.enable = checked
        }

        ConfigSlider {
            buttonIcon: "blur_circular"
            text: Translation.tr("Blur intensity")
            enabled: Config.options.lock.blur.enable
            from: 0
            to: 50
            stepSize: 5
            value: Config.options.lock.blur.radius
            usePercentTooltip: false
            onValueChanged: Config.options.lock.blur.radius = value
        }
    }

    ContentSection {
        icon: "incomplete_circle"
        title: Translation.tr("Style: Desaturated")

        ConfigSwitch {
            buttonIcon: "deblur"
            text: Translation.tr("Desaturate wallpaper on lock")
            checked: Config.options.lock.desaturate.enable
            onCheckedChanged: Config.options.lock.desaturate.enable = checked
        }

        ConfigSlider {
            buttonIcon: "palette"
            text: Translation.tr("Desaturation amount")
            enabled: Config.options.lock.desaturate.enable
            from: 0
            to: 100
            stepSize: 5
            value: Config.options.lock.desaturate.amount * 100
            usePercentTooltip: true
            onValueChanged: Config.options.lock.desaturate.amount = value / 100
        }
    }

    ContentSection {
        icon: "palette"
        title: Translation.tr("Style: Color Wash")

        ConfigSwitch {
            buttonIcon: "format_color_fill"
            text: Translation.tr("Color wash overlay on lock")
            checked: Config.options.lock.colorWash.enable
            onCheckedChanged: Config.options.lock.colorWash.enable = checked
        }

        ConfigSlider {
            buttonIcon: "opacity"
            text: Translation.tr("Color wash intensity")
            enabled: Config.options.lock.colorWash.enable
            from: 0
            to: 100
            stepSize: 5
            value: Config.options.lock.colorWash.amount * 100
            usePercentTooltip: true
            onValueChanged: Config.options.lock.colorWash.amount = value / 100
        }
    }

    ContentSection {
        icon: "vignette"
        title: Translation.tr("Style: Vignette")

        ConfigSwitch {
            buttonIcon: "gradient"
            text: Translation.tr("Vignette effect on lock")
            checked: Config.options.lock.vignette.enable
            onCheckedChanged: Config.options.lock.vignette.enable = checked
        }

        ConfigSlider {
            buttonIcon: "dark_mode"
            text: Translation.tr("Vignette intensity")
            enabled: Config.options.lock.vignette.enable
            from: 0
            to: 100
            stepSize: 5
            value: Config.options.lock.vignette.amount * 100
            usePercentTooltip: true
            onValueChanged: Config.options.lock.vignette.amount = value / 100
        }
    }

}
