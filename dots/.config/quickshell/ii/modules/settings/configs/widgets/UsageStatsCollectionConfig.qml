import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    readonly property var opts: Config.options.appStats

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Usage Collection & Sampler")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Collection Settings")
            icon: "settings_input_component"
            tooltip: Translation.tr("The sampler reads these once when it starts, so changing any of them restarts it.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ContentSubsection {
                    title: Translation.tr("Energy source")
                    icon: "bolt"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: root.opts.energySource
                        onSelected: newValue => {
                            Config.options.appStats.energySource = newValue;
                        }
                        options: [
                            {
                                "displayName": Translation.tr("Automatic"),
                                "value": "auto"
                            },
                            {
                                "displayName": Translation.tr("RAPL counters"),
                                "value": "rapl"
                            },
                            {
                                "displayName": Translation.tr("Battery drain"),
                                "value": "battery"
                            },
                            {
                                "displayName": Translation.tr("None"),
                                "value": "none"
                            }
                        ]
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("RAPL needs the udev rule from the sampler's README. Battery drain is much cruder and reads zero on AC.")
                    }
                }

                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Sample every (ms)")
                    value: root.opts.sampleIntervalMs
                    from: 1000
                    to: 60000
                    stepSize: 1000
                    onValueChanged: {
                        Config.options.appStats.sampleIntervalMs = value;
                    }
                    StyledToolTip {
                        text: Translation.tr("How often the counters are read. Shorter means finer window attribution and more CPU")
                    }
                }

                ConfigSpinBox {
                    icon: "save"
                    text: Translation.tr("Write to disk every (ms)")
                    value: root.opts.flushIntervalMs
                    from: 5000
                    to: 600000
                    stepSize: 5000
                    onValueChanged: {
                        Config.options.appStats.flushIntervalMs = value;
                    }
                }

                ConfigSpinBox {
                    icon: "motion_sensor_idle"
                    text: Translation.tr("Pause after idle for (seconds)")
                    value: root.opts.idleTimeoutSec
                    from: 0
                    to: 3600
                    stepSize: 30
                    onValueChanged: {
                        Config.options.appStats.idleTimeoutSec = value;
                    }
                    StyledToolTip {
                        text: Translation.tr("Foreground time stops accruing once there has been no input for this long. 0 keeps it running")
                    }
                }

                ConfigSpinBox {
                    icon: "stadia_controller"
                    text: Translation.tr("Full GPU rescan every (samples)")
                    value: root.opts.gpuFullEvery
                    from: 1
                    to: 600
                    stepSize: 5
                    onValueChanged: {
                        Config.options.appStats.gpuFullEvery = value;
                    }
                    StyledToolTip {
                        text: Translation.tr("Only a backstop — a new window forces a rescan immediately. Lower values cost a full sweep of every process's file descriptors")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "terminal"
                    text: Translation.tr("Record background services")
                    checked: root.opts.trackHeadless
                    onCheckedChanged: {
                        Config.options.appStats.trackHeadless = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Off means processes with no window are never written down, and cannot be shown later")
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Sampler Status")
                    icon: "monitor_heart"
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: {
                            if (!AppStats.enabled)
                                return Translation.tr("Turned off.");
                            if (!AppStats.running)
                                return Translation.tr("Not running — check that the binary is built at scripts/appStats/app_stats.");
                            switch (AppStats.source) {
                            case "rapl":
                                return Translation.tr("Running, reading energy from RAPL counters.");
                            case "battery":
                                return Translation.tr("Running, estimating energy from battery drain.");
                            default:
                                return Translation.tr("Running without an energy source; watt-hours will stay empty.");
                            }
                        }
                    }
                }
            }
        }
    }
}
