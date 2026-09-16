import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentPage {
    id: page

    forceWidth: false

    property bool hasAnimationEdit: false
    readonly property var hyprlandEntries: HyprlandSettings.appLaunchEntries(Config.options.appearance.appLaunchAnimation)
    readonly property bool unsavedChanges: Config.ready && HyprlandGui.ready
        && !HyprlandGui.animationsSaved(page.hyprlandEntries)

    Component.onCompleted: HyprlandGui.attach()
    Component.onDestruction: HyprlandGui.detach()

    NoticeBox {
        Layout.fillWidth: true
        materialIcon: HyprlandGui.lastError !== "" ? "error" : "info"
        text: HyprlandGui.lastError !== "" ? HyprlandGui.lastError
            : page.unsavedChanges
                ? Translation.tr("Animation preview active. Save animations to Hyprland to keep them after reloads and restarts.")
                : Translation.tr("Animations saved to Hyprland.")
        visible: page.hasAnimationEdit && Config.ready && HyprlandGui.ready
    }

    FloatingActionButton {
        parent: page
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 25
        z: 10
        opacity: page.hasAnimationEdit ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        iconText: HyprlandGui.busy ? "hourglass_top" : page.unsavedChanges ? "save" : "check"
        buttonText: Translation.tr("Save animations to Hyprland")
        expanded: page.unsavedChanges || HyprlandGui.busy
        enabled: Config.ready && HyprlandGui.ready && !HyprlandGui.busy
        colBackground: page.unsavedChanges ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
        colBackgroundHover: page.unsavedChanges ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimaryContainerHover
        colBackgroundActive: page.unsavedChanges ? Appearance.colors.colPrimaryActive : Appearance.colors.colPrimaryContainerActive
        colOnBackground: page.unsavedChanges ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
        onClicked: HyprlandGui.saveAnimations(page.hyprlandEntries)

        StyledToolTip {
            text: Translation.tr("Save only window animations to ~/.config/hypr/custom/general.lua. A backup is created before writing.")
        }
    }

    ContentSection {
        title: Translation.tr("Transparency & Blur")
        icon: "opacity"

        WarningBox {
            Layout.fillWidth: true
            text: Translation.tr("Heavy blur effects can significantly impact battery life and performance on weaker GPUs.")
            isFirst: true
        }

        ConfigSwitch {
            buttonIcon: "ev_shadow"
            text: Translation.tr("Enable transparency")
            checked: Config.options.appearance.transparency.enable
            onCheckedChanged: {
                Config.options.appearance.transparency.enable = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "magic_button"
            text: Translation.tr("Calculate transparency automatically")
            checked: Config.options.appearance.transparency.automatic
            onCheckedChanged: {
                Config.options.appearance.transparency.automatic = checked;
            }

            StyledToolTip {
                text: Translation.tr("Calculate transparency automatically based on wallpaper colors")
            }

        }

        ConfigSwitch {
            buttonIcon: "opacity"
            text: Translation.tr("Transparency in popups")
            checked: Config.options.appearance.transparency.popups
            onCheckedChanged: {
                Config.options.appearance.transparency.popups = checked;
            }
        }

        ConfigSlider {
            buttonIcon: "blur_on"
            text: Translation.tr("Background transparency")
            enabled: Config.options.appearance.transparency.enable && !Config.options.appearance.transparency.automatic
            value: Config.options.appearance.transparency.backgroundTransparency
            onValueChanged: {
                Config.options.appearance.transparency.backgroundTransparency = value;
            }
        }

        ConfigSlider {
            buttonIcon: "opacity"
            text: Translation.tr("Content transparency")
            enabled: Config.options.appearance.transparency.enable && !Config.options.appearance.transparency.automatic
            value: Config.options.appearance.transparency.contentTransparency
            onValueChanged: {
                Config.options.appearance.transparency.contentTransparency = value;
            }
        }

        ConfigSlider {
            buttonIcon: "lens_blur"
            text: Translation.tr("Blur Size")
            usePercentTooltip: false
            from: 0
            to: 50
            stepSize: 1
            snapMode: Slider.NoSnap
            stopIndicatorValues: []
            badgeText: Math.round(value) === 0 ? Translation.tr("Off") : String(Math.round(value)) + " px"
            tooltipContent: badgeText
            value: Config.options.appearance.blurSize
            onMoved: Config.options.appearance.blurSize = Math.round(value)
        }

        ConfigSlider {
            id: ignoreAlphaSlider
            buttonIcon: "gradient"
            text: Translation.tr("Ignore Alpha")
            value: Config.options.appearance.ignoreAlpha
            from: 0
            to: 1
            stepSize: 0.001
            snapMode: Slider.NoSnap
            stopIndicatorValues: []
            badgeText: (value * 100).toFixed(1) + "%"
            tooltipContent: badgeText
            isLast: false
            onMoved: Config.options.appearance.ignoreAlpha = Math.round(value * 1000) / 1000
        }

        NoticeBox {
            id: ignoreAlphaNotice
            Layout.fillWidth: true
            visible: Math.round(ignoreAlphaSlider.value * 100) <= 30
            isFirst: false
            isLast: false
            materialIcon: "info"
            text: Translation.tr("Low Ignore Alpha values can cause visual artifacts around element borders. It is recommended to keep this value high.")
        }

        ConfigSwitch {
            id: advancedBlurSwitch
            buttonIcon: "tune"
            text: Translation.tr("Advanced blur options")
            description: Translation.tr("Show extra blur controls without changing their values.")
            // ConfigSwitch assigns checked on click. An explicit Binding keeps
            // this visibility switch in sync with changes from another view.
            Binding {
                target: advancedBlurSwitch
                property: "checked"
                value: Config.options.appearance.blur.advancedOptions
            }
            onCheckedChanged: {
                if (Config.ready && checked !== Config.options.appearance.blur.advancedOptions)
                    Config.options.appearance.blur.advancedOptions = checked;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Blur appearance")
        icon: "lens_blur"
        visible: Config.options.appearance.blur.advancedOptions

        ConfigSlider {
            buttonIcon: "layers"
            text: Translation.tr("Blur Passes")
            from: 1
            to: 10
            stepSize: 1
            snapMode: Slider.NoSnap
            stopIndicatorValues: []
            usePercentTooltip: false
            badgeText: String(Math.round(value))
            tooltipContent: badgeText
            value: Config.options.appearance.blur.passes
            onMoved: Config.options.appearance.blur.passes = Math.round(value)
        }

        ConfigSlider {
            buttonIcon: "grain"
            text: Translation.tr("Blur noise")
            from: 0
            to: 1
            stepSize: 0.001
            snapMode: Slider.NoSnap
            stopIndicatorValues: []
            usePercentTooltip: false
            badgeText: (value * 100).toFixed(1) + "%"
            tooltipContent: badgeText
            value: Config.options.appearance.blur.noise
            onMoved: Config.options.appearance.blur.noise = Math.round(value * 1000) / 1000
        }

        ConfigSlider {
            buttonIcon: "contrast"
            text: Translation.tr("Blur contrast")
            from: 0
            to: 2
            stepSize: 0.001
            snapMode: Slider.NoSnap
            stopIndicatorValues: []
            usePercentTooltip: false
            badgeText: (value * 100).toFixed(1) + "%"
            tooltipContent: badgeText
            value: Config.options.appearance.blur.contrast
            onMoved: Config.options.appearance.blur.contrast = Math.round(value * 1000) / 1000
        }

        ConfigSlider {
            buttonIcon: "brightness_6"
            text: Translation.tr("Blur brightness")
            from: 0
            to: 2
            stepSize: 0.001
            snapMode: Slider.NoSnap
            stopIndicatorValues: []
            usePercentTooltip: false
            badgeText: (value * 100).toFixed(1) + "%"
            tooltipContent: badgeText
            value: Config.options.appearance.blur.brightness
            onMoved: Config.options.appearance.blur.brightness = Math.round(value * 1000) / 1000
        }

        ConfigSlider {
            buttonIcon: "palette"
            text: Translation.tr("Blur vibrancy")
            from: 0
            to: 1
            stepSize: 0.001
            snapMode: Slider.NoSnap
            stopIndicatorValues: []
            usePercentTooltip: false
            badgeText: (value * 100).toFixed(1) + "%"
            tooltipContent: badgeText
            value: Config.options.appearance.blur.vibrancy
            onMoved: Config.options.appearance.blur.vibrancy = Math.round(value * 1000) / 1000
        }

        ConfigSlider {
            buttonIcon: "tonality"
            text: Translation.tr("Vibrancy in dark areas")
            from: 0
            to: 1
            stepSize: 0.001
            snapMode: Slider.NoSnap
            stopIndicatorValues: []
            usePercentTooltip: false
            badgeText: (value * 100).toFixed(1) + "%"
            tooltipContent: badgeText
            value: Config.options.appearance.blur.vibrancyDarkness
            onMoved: Config.options.appearance.blur.vibrancyDarkness = Math.round(value * 1000) / 1000
        }
    }

    ContentSection {
        title: Translation.tr("Blur behavior")
        visible: Config.options.appearance.blur.advancedOptions
        icon: "deblur"

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "info"
            text: Translation.tr("These adjustments affect panels and applications allowed to blur. Game Mode can temporarily disable blur.")
        }

        ConfigSwitch {
            buttonIcon: "opacity"
            text: Translation.tr("Keep blur strength when windows fade")
            description: Translation.tr("Ignore window opacity when calculating blur intensity.")
            checked: Config.options.appearance.blur.ignoreOpacity
            onCheckedChanged: {
                if (Config.ready && checked !== Config.options.appearance.blur.ignoreOpacity)
                    Config.options.appearance.blur.ignoreOpacity = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "speed"
            text: Translation.tr("Optimize blur rendering")
            description: Translation.tr("Reuse the blurred background to reduce GPU work.")
            checked: Config.options.appearance.blur.newOptimizations
            onCheckedChanged: {
                if (Config.ready && checked !== Config.options.appearance.blur.newOptimizations)
                    Config.options.appearance.blur.newOptimizations = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "filter_none"
            text: Translation.tr("X-ray blur for floating windows")
            description: Translation.tr("Ignore tiled windows behind floating windows. Requires optimized blur rendering.")
            enabled: Config.options.appearance.blur.newOptimizations
            checked: Config.options.appearance.blur.xray
            onCheckedChanged: {
                if (Config.ready && checked !== Config.options.appearance.blur.xray)
                    Config.options.appearance.blur.xray = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "space_dashboard"
            text: Translation.tr("Blur behind special workspaces")
            description: Translation.tr("Blur the desktop behind a special workspace. Uses more GPU resources.")
            checked: Config.options.appearance.blur.special
            onCheckedChanged: {
                if (Config.ready && checked !== Config.options.appearance.blur.special)
                    Config.options.appearance.blur.special = checked;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Blur in application popups")
        visible: Config.options.appearance.blur.advancedOptions
        icon: "web_asset"

        ConfigSwitch {
            buttonIcon: "menu_open"
            text: Translation.tr("Blur application menus")
            description: Translation.tr("Apply blur to application popups, such as right-click menus. Shell popup transparency is configured above.")
            checked: Config.options.appearance.blur.popups
            onCheckedChanged: {
                if (Config.ready && checked !== Config.options.appearance.blur.popups)
                    Config.options.appearance.blur.popups = checked;
            }
        }

        ConfigSlider {
            buttonIcon: "gradient"
            text: Translation.tr("Application menu alpha threshold")
            enabled: Config.options.appearance.blur.popups
            from: 0
            to: 1
            stepSize: 0.001
            snapMode: Slider.NoSnap
            stopIndicatorValues: []
            badgeText: (value * 100).toFixed(1) + "%"
            tooltipContent: badgeText
            value: Config.options.appearance.blur.popupsIgnoreAlpha
            onMoved: Config.options.appearance.blur.popupsIgnoreAlpha = Math.round(value * 1000) / 1000
        }

        ConfigSwitch {
            buttonIcon: "keyboard"
            text: Translation.tr("Blur input method popups")
            description: Translation.tr("Apply blur to input method windows, such as Fcitx5 candidate lists.")
            checked: Config.options.appearance.blur.inputMethods
            onCheckedChanged: {
                if (Config.ready && checked !== Config.options.appearance.blur.inputMethods)
                    Config.options.appearance.blur.inputMethods = checked;
            }
        }

        ConfigSlider {
            buttonIcon: "gradient"
            text: Translation.tr("Input method alpha threshold")
            enabled: Config.options.appearance.blur.inputMethods
            from: 0
            to: 1
            stepSize: 0.001
            snapMode: Slider.NoSnap
            stopIndicatorValues: []
            badgeText: (value * 100).toFixed(1) + "%"
            tooltipContent: badgeText
            value: Config.options.appearance.blur.inputMethodsIgnoreAlpha
            onMoved: Config.options.appearance.blur.inputMethodsIgnoreAlpha = Math.round(value * 1000) / 1000
        }
    }

    ContentSection {
        title: Translation.tr("Gaps")
        icon: "margin"

        ConfigSlider {
            buttonIcon: "padding"
            text: Translation.tr("Gaps In")
            usePercentTooltip: false
            from: 0
            to: 60
            stepSize: 1
            value: Config.options.appearance.gapsIn ?? 4
            onValueChanged: {
                Config.options.appearance.gapsIn = Math.round(value);
            }
        }

        ConfigSlider {
            buttonIcon: "fullscreen"
            text: Translation.tr("Gaps Out")
            usePercentTooltip: false
            from: 0
            to: 60
            stepSize: 1
            value: Config.options.appearance.gapsOut ?? 5
            onValueChanged: {
                Config.options.appearance.gapsOut = Math.round(value);
            }
        }

    }

    ContentSection {
        title: Translation.tr("Borders")
        icon: "border_outer"

        ConfigSwitch {
            buttonIcon: "border_clear"
            text: Translation.tr("Borderless windows")
            checked: Config.options.appearance.borderless
            onCheckedChanged: {
                Config.options.appearance.borderless = checked;
            }
        }

        ConfigSlider {
            buttonIcon: "border_outer"
            text: Translation.tr("Border Width")
            usePercentTooltip: false
            enabled: !Config.options.appearance.borderless
            from: 0
            to: 20
            stepSize: 1
            value: Config.options.appearance.borderWidth ?? 2
            onValueChanged: {
                Config.options.appearance.borderWidth = Math.round(value);
            }
        }

        ContentSubsection {
            title: Translation.tr("Active Border Color Type")
            icon: "border_color"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.appearance.borderColorType
                onSelected: (newValue) => {
                    Config.options.appearance.borderColorType = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Primary"),
                    "value": "primary"
                }, {
                    "displayName": Translation.tr("Secondary"),
                    "value": "secondary"
                }, {
                    "displayName": Translation.tr("Tertiary"),
                    "value": "tertiary"
                }, {
                    "displayName": Translation.tr("Primary Container"),
                    "value": "primaryContainer"
                }, {
                    "displayName": Translation.tr("Surface"),
                    "value": "surface"
                }]
            }

        }

    }

    ContentSection {
        title: Translation.tr("Default layout")
        icon: "view_quilt"

        // This was a Default/Scrolling picker writing a setting nothing ever read, so choosing
        // either did nothing at all. The tiling engine is Hyprland's own general:layout, and the
        // Hyprland page sets it for real - along with the options that belong to each engine.
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Which engine arranges your windows - dwindle, master, scrolling or monocle - is a Hyprland setting. Its options, and a diagram of where the next window would land, are on the Hyprland page.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RelatedChip {
                pageId: "hyprland"
                label: Translation.tr("Tiling engine")
                sectionHighlight: Translation.tr("Tiling engine")
            }
        }

    }


    ContentSection {
        title: Translation.tr("Window Animations")
        icon: "animation"

        ConfigSwitch {
            buttonIcon: "open_in_new"
            text: Translation.tr("Window open and close animation")
            checked: Config.options.appearance.appLaunchAnimation.enable ?? true
            onClicked: {
                page.hasAnimationEdit = true;
                checked = !checked;
            }
            onCheckedChanged: {
                Config.options.appearance.appLaunchAnimation.enable = checked;
                HyprlandSettings.updateAppLaunchAnimation(Config.options.appearance.appLaunchAnimation);
            }
        }

        ContentSubsection {
            title: Translation.tr("Animation style")
            icon: "motion_play"
            Layout.fillWidth: true
            enabled: Config.options.appearance.appLaunchAnimation.enable ?? true

            ConfigSelectionArray {
                currentValue: Config.options.appearance.appLaunchAnimation.style ?? "scale"
                onSelected: (newValue) => {
                    page.hasAnimationEdit = true;
                    Config.options.appearance.appLaunchAnimation.style = newValue;
                    HyprlandSettings.updateAppLaunchAnimation(Config.options.appearance.appLaunchAnimation);
                }
                options: [{
                    "displayName": Translation.tr("Scale"),
                    "value": "scale"
                }, {
                    "displayName": Translation.tr("Slide"),
                    "value": "slide"
                }]
            }
        }

        ContentSubsection {
            title: Translation.tr("Slide direction")
            icon: "swipe"
            Layout.fillWidth: true
            visible: (Config.options.appearance.appLaunchAnimation.style ?? "scale") === "slide"
            enabled: Config.options.appearance.appLaunchAnimation.enable ?? true

            ConfigSelectionArray {
                currentValue: Config.options.appearance.appLaunchAnimation.slideDirection ?? "auto"
                onSelected: (newValue) => {
                    page.hasAnimationEdit = true;
                    Config.options.appearance.appLaunchAnimation.slideDirection = newValue;
                    HyprlandSettings.updateAppLaunchAnimation(Config.options.appearance.appLaunchAnimation);
                }
                options: [{
                    "displayName": Translation.tr("Nearest edge"),
                    "value": "auto"
                }, {
                    "displayName": Translation.tr("Bottom"),
                    "value": "bottom"
                }, {
                    "displayName": Translation.tr("Top"),
                    "value": "top"
                }, {
                    "displayName": Translation.tr("Left"),
                    "value": "left"
                }, {
                    "displayName": Translation.tr("Right"),
                    "value": "right"
                }]
            }
        }

        ConfigSlider {
            buttonIcon: "aspect_ratio"
            text: Translation.tr("Opening initial scale")
            usePercentTooltip: true
            visible: (Config.options.appearance.appLaunchAnimation.style ?? "scale") !== "slide"
            enabled: Config.options.appearance.appLaunchAnimation.enable ?? true
            from: 5
            to: 90
            stepSize: 5
            snapMode: Slider.SnapAlways
            stopIndicatorValues: [5, 20, 40, 60, 80, 90]
            value: Config.options.appearance.appLaunchAnimation.startPercent ?? 20
            onPressedChanged: if (pressed) page.hasAnimationEdit = true
            onMoved: {
                page.hasAnimationEdit = true;
                Config.options.appearance.appLaunchAnimation.startPercent = Math.round(value);
                HyprlandSettings.updateAppLaunchAnimation(Config.options.appearance.appLaunchAnimation);
            }
        }

        ConfigSlider {
            buttonIcon: "timer"
            text: Translation.tr("Animation duration")
            usePercentTooltip: false
            tooltipContent: `${Math.round(value * 100)} ms`
            enabled: Config.options.appearance.appLaunchAnimation.enable ?? true
            from: 1.0
            to: 8.0
            stepSize: 0.2
            value: Config.options.appearance.appLaunchAnimation.speed ?? 4.0
            onPressedChanged: if (pressed) page.hasAnimationEdit = true
            onMoved: {
                page.hasAnimationEdit = true;
                Config.options.appearance.appLaunchAnimation.speed = value;
                HyprlandSettings.updateAppLaunchAnimation(Config.options.appearance.appLaunchAnimation);
            }
        }
    }

    ContentSection {
        icon: "link"
        title: Translation.tr("Related settings")

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RelatedChip {
                pageId: "wallpaper"
                label: Translation.tr("Wallpaper blur")
            }

            RelatedChip {
                pageId: "lockScreen"
                label: Translation.tr("Lock screen blur")
                sectionHighlight: Translation.tr("Blur style")
            }
        }
    }
}
