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
            text: Translation.tr("Resources Tracker")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "style"
        title: Translation.tr("Style & Layout")

        ContentSubsection {
            title: Translation.tr("Visual style")
            icon: "palette"
            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.resources
                onSelected: newValue => {
                    Config.options.bar.styles.resources = String(newValue);
                }
                options: [
                    { displayName: Translation.tr("Default"), icon: "dock_to_bottom", value: "default" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" },
                    { displayName: Translation.tr("Sculpt"), icon: "shapes", value: "sculpt" }
                ]
            }
        }

        ExpressiveColorModeSubsection {
            visible: Config.options.bar.styles.resources === "sculpt"
            currentValue: Config.options.bar.resources.colorMode
            onSelected: newValue => Config.options.bar.resources.colorMode = String(newValue)
        }

        ContentSubsection {
            visible: Config.options.bar.styles.resources === "sculpt"
            title: Translation.tr("Sculpt variant")

            ConfigSelectionArray {
                currentValue: Config.options.bar.resources.sculptVariant
                onSelected: newValue => Config.options.bar.resources.sculptVariant = String(newValue)
                options: [
                    { displayName: Translation.tr("Pressure"), icon: "compress", value: "pressure" },
                    { displayName: Translation.tr("Bars"), icon: "bar_chart", value: "bars" },
                    { displayName: Translation.tr("Trace"), icon: "show_chart", value: "trace" }
                ]
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Config.options.bar.styles.resources === "sculpt" && Config.options.bar.resources.sculptVariant === "pressure"
            materialIcon: "compress"
            text: Translation.tr("Every number is set under the load it reports: idle is light and wide, busy is black and condensed, so the row's texture says which part of the machine is working.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Config.options.bar.styles.resources === "sculpt" && Config.options.bar.resources.sculptVariant === "bars"
            materialIcon: "bar_chart"
            text: Translation.tr("A tiny chart with one bar per metric. The busiest bar takes the vivid tone and a sunburst on top, and its number is read out beside the chart.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Config.options.bar.styles.resources === "sculpt" && Config.options.bar.resources.sculptVariant === "trace"
            materialIcon: "show_chart"
            text: Translation.tr("A card per metric with its recent history drawn behind the number, cropped by the card. Disk and temperature fill up to their level instead.")
        }
    }

    ContentSection {
        icon: "memory"
        title: Translation.tr("Resources Tracker")

        ConfigSwitch {
            buttonIcon: "percent"
            text: Translation.tr("Show percentage text")
            checked: Config.options.bar.resources.showPercentageText
            onCheckedChanged: {
                Config.options.bar.resources.showPercentageText = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "memory"
            text: Translation.tr("Always show RAM")
            checked: Config.options.bar.resources.alwaysShowRam
            onCheckedChanged: Config.options.bar.resources.alwaysShowRam = checked
        }
        ConfigSwitch {
            buttonIcon: "planner_review"
            text: Translation.tr("Always show CPU")
            checked: Config.options.bar.resources.alwaysShowCpu
            onCheckedChanged: Config.options.bar.resources.alwaysShowCpu = checked
        }
        ConfigSwitch {
            buttonIcon: "thermostat"
            text: Translation.tr("Always show Temp")
            checked: Config.options.bar.resources.alwaysShowCpuTemp
            onCheckedChanged: Config.options.bar.resources.alwaysShowCpuTemp = checked
        }
        ConfigSwitch {
            buttonIcon: "hard_drive"
            text: Translation.tr("Always show Disk")
            checked: Config.options.bar.resources.alwaysShowDisk
            onCheckedChanged: Config.options.bar.resources.alwaysShowDisk = checked
        }
        ConfigSwitch {
            buttonIcon: "swap_horiz"
            text: Translation.tr("Always show Swap")
            checked: Config.options.bar.resources.alwaysShowSwap
            onCheckedChanged: Config.options.bar.resources.alwaysShowSwap = checked
        }
        ConfigSwitch {
            buttonIcon: "dns"
            text: Translation.tr("Always show Docker")
            checked: Config.options.bar.resources.showDocker
            onCheckedChanged: Config.options.bar.resources.showDocker = checked
        }

        ConfigSpinBox {
            icon: "memory"
            text: Translation.tr("Resources polling interval (ms)")
            value: Config.options.resources.updateInterval
            from: 100
            to: 10000
            stepSize: 100
            onValueChanged: {
                Config.options.resources.updateInterval = value;
            }
        }
    }

    ContentSection {
        icon: "hard_drive"
        title: Translation.tr("Disk")

        ConfigTextField {
            text: Translation.tr("Mount point to monitor")
            icon: "folder"
            placeholderText: Translation.tr("e.g. / or /home or /mnt/data")
            inputText: Config.options.resources.diskMount
            textField.onEditingFinished: {
                const v = textField.text.trim();
                if (v.length > 0)
                    Config.options.resources.diskMount = v;
            }
        }

        ConfigSpinBox {
            icon: "schedule"
            text: Translation.tr("Disk polling interval (ms)")
            value: Config.options.resources.diskInterval
            from: 5000
            to: 300000
            stepSize: 5000
            onValueChanged: {
                Config.options.resources.diskInterval = value;
            }
        }
    }

    ContentSection {
        icon: "developer_board"
        title: Translation.tr("GPU")

        ConfigSelectionArray {
            currentValue: Config.options.resources.gpuPreference
            onSelected: newValue => {
                Config.options.resources.gpuPreference = newValue;
            }
            options: [
                {
                    displayName: Translation.tr("Auto"),
                    icon: "auto_awesome",
                    value: "auto"
                },
                {
                    displayName: "NVIDIA",
                    icon: "developer_board",
                    value: "nvidia"
                },
                {
                    displayName: "AMD",
                    icon: "developer_board",
                    value: "amd"
                },
                {
                    displayName: "Intel",
                    icon: "developer_board",
                    value: "intel"
                }
            ]
        }
    }

    ContentSection {
        icon: "inventory_2"
        title: Translation.tr("Docker Backend")

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Enable Docker monitoring")
            checked: Config.options.resources.enableDocker
            onCheckedChanged: {
                Config.options.resources.enableDocker = checked
            }
        }
    }
}
