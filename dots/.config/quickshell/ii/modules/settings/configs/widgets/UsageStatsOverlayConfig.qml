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
                text: Translation.tr("Usage Overlay & Views")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Overlay Preferences")
            icon: "tune"
            tooltip: Translation.tr("Default timeframes, metrics, and display behaviors for the app usage overlay.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "history"
                    text: Translation.tr("Reopen on the last view used")
                    checked: root.opts.rememberLastView
                    onCheckedChanged: {
                        Config.options.appStats.rememberLastView = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("The period and metric are remembered; the overlay always opens on the current day, week or month")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "select_check_box"
                    text: Translation.tr("Keep the selected app between openings")
                    checked: root.opts.keepSelection
                    onCheckedChanged: {
                        Config.options.appStats.keepSelection = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "calendar_view_week"
                    text: Translation.tr("Weeks start on Monday")
                    checked: root.opts.weekStartsMonday
                    onCheckedChanged: {
                        Config.options.appStats.weekStartsMonday = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "trending_up"
                    text: Translation.tr("Compare with the previous period")
                    checked: root.opts.showComparison
                    onCheckedChanged: {
                        Config.options.appStats.showComparison = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Adds a percent change under the headline figure. Reads the period before the one on screen as well, which doubles the files a month view parses")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "terminal"
                    text: Translation.tr("Count background services")
                    checked: root.opts.showHeadless
                    onCheckedChanged: {
                        Config.options.appStats.showHeadless = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Processes owning no window. Recorded either way; this decides whether they appear in the list and the totals")
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Opens on")
                    icon: "calendar_month"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: root.opts.defaultGranularity
                        onSelected: newValue => {
                            Config.options.appStats.defaultGranularity = newValue;
                        }
                        options: [
                            {
                                "displayName": Translation.tr("Day"),
                                "value": "day"
                            },
                            {
                                "displayName": Translation.tr("Week"),
                                "value": "week"
                            },
                            {
                                "displayName": Translation.tr("Month"),
                                "value": "month"
                            }
                        ]
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Opens showing")
                    icon: "leaderboard"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: root.opts.defaultMetric
                        onSelected: newValue => {
                            Config.options.appStats.defaultMetric = newValue;
                        }
                        options: [
                            {
                                "displayName": Translation.tr("Screen time"),
                                "value": "fg"
                            },
                            {
                                "displayName": Translation.tr("Focused"),
                                "value": "focus"
                            },
                            {
                                "displayName": Translation.tr("Energy"),
                                "value": "energy"
                            },
                            {
                                "displayName": Translation.tr("CPU"),
                                "value": "cpu"
                            },
                            {
                                "displayName": Translation.tr("GPU"),
                                "value": "gpu"
                            }
                        ]
                    }
                }

                ContentSubsection {
                    title: Translation.tr("List filtering")
                    icon: "filter_alt"
                    Layout.fillWidth: true

                    ConfigSpinBox {
                        icon: "timer"
                        text: Translation.tr("Hide apps under (seconds)")
                        value: root.opts.minDurationSec
                        from: 0
                        to: 3600
                        stepSize: 30
                        onValueChanged: {
                            Config.options.appStats.minDurationSec = value;
                        }
                        StyledToolTip {
                            text: Translation.tr("Applies to the list only, and only to the metrics measured in time. The totals still count every app")
                        }
                    }
                }
            }
        }
    }
}
