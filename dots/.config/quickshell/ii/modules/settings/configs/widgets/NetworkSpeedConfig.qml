import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack()

    RowLayout {
        spacing: 12

        RippleButton {
            id: backButton
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Network Speed")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "speed"
        title: Translation.tr("Display")

        ContentSubsection {
            title: Translation.tr("Speed display")
            icon: "swap_vert"
            tooltip: Translation.tr("Which directions to show on the bar")

            ConfigSelectionArray {
                currentValue: Config.options.bar.networkSpeed.displayMode
                onSelected: newValue => {
                    Config.options.bar.networkSpeed.displayMode = newValue;
                }
                options: [
                    { displayName: Translation.tr("Both"),     icon: "swap_vert", value: "both" },
                    { displayName: Translation.tr("Download"), icon: "south",     value: "download" },
                    { displayName: Translation.tr("Upload"),   icon: "north",     value: "upload" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Units")
            icon: "exposure_zero"

            ConfigSelectionArray {
                currentValue: Config.options.bar.networkSpeed.unit
                onSelected: newValue => {
                    Config.options.bar.networkSpeed.unit = newValue;
                }
                options: [
                    { displayName: Translation.tr("Decimal (KB/s)"),  icon: "exposure_zero", value: "decimal" },
                    { displayName: Translation.tr("Binary (KiB/s)"),  icon: "looks_two",     value: "binary" }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "arrow_selector_tool"
            text: Translation.tr("Show directional icons")
            checked: Config.options.bar.networkSpeed.showIcon
            onCheckedChanged: {
                Config.options.bar.networkSpeed.showIcon = checked;
            }
        }

        ContentSubsection {
            visible: Config.options.bar.networkSpeed.showIcon
            title: Translation.tr("Icon position")
            icon: "dock_to_right"

            ConfigSelectionArray {
                currentValue: Config.options.bar.networkSpeed.iconPosition
                onSelected: newValue => {
                    Config.options.bar.networkSpeed.iconPosition = newValue;
                }
                options: [
                    { displayName: Translation.tr("Left"),  icon: "dock_to_right", value: "left" },
                    { displayName: Translation.tr("Right"), icon: "dock_to_left",  value: "right" }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "do_not_disturb_on"
            text: Translation.tr("Hide text when idle")
            checked: Config.options.bar.networkSpeed.hideWhenIdle
            onCheckedChanged: {
                Config.options.bar.networkSpeed.hideWhenIdle = checked;
            }
            StyledToolTip {
                text: Translation.tr("Hides the speed values after 10 seconds below ~1 KB/s, keeping the icons visible.")
            }
        }
    }

    ContentSection {
        icon: "timer"
        title: Translation.tr("Polling")

        ConfigSpinBox {
            icon: "speed"
            text: Translation.tr("Update interval (ms)")
            value: Config.options.bar.networkSpeed.pollingInterval
            from: 100
            to: 5000
            stepSize: 100
            onValueChanged: {
                Config.options.bar.networkSpeed.pollingInterval = value;
            }
            StyledToolTip {
                text: Translation.tr("How often network counters are sampled. Shorter intervals are more responsive at a small CPU cost.")
            }
        }

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            opacity: 0.7
            wrapMode: Text.WordWrap
            text: Translation.tr("Reads byte counters from /proc/net/dev for every interface except loopback. Polling pauses entirely while the widget is not shown in the bar.")
        }
    }
}
