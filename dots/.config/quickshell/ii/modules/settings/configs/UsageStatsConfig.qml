pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: usageStatsRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property var opts: Config.options.appStats

    function humanBytes(bytes) {
        if (bytes < 0)
            return "—";
        if (bytes < 1024)
            return `${bytes} B`;
        if (bytes < 1024 * 1024)
            return `${Math.round(bytes / 1024)} KiB`;
        return `${(bytes / 1048576).toFixed(1)} MiB`;
    }

    Component.onCompleted: AppStats.measureStorage()

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        KeyboardShortcutBox {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            text: Translation.tr("Toggle app usage stats")
            keys: ["Super", "U"]
        }

        // ── General ───────────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("General")
            icon: "bar_chart"
            tooltip: Translation.tr("Master statistics collection and overlay enablement.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "monitoring"
                    text: Translation.tr("Collect usage statistics")
                    checked: usageStatsRoot.opts.enable
                    onCheckedChanged: {
                        Config.options.appStats.enable = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Turning this off stops the sampler but keeps the history already recorded")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "dashboard"
                    text: Translation.tr("Load the usage overlay")
                    checked: usageStatsRoot.opts.overlayEnabled
                    onCheckedChanged: {
                        Config.options.appStats.overlayEnabled = checked;
                    }
                }
            }
        }

        // ── Storage & History ─────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("History & Storage")
            icon: "database"
            tooltip: Translation.tr("Data retention window, stored database size and disk flushing.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ContentSubsection {
                    title: Translation.tr("How long data is kept")
                    icon: "auto_delete"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: usageStatsRoot.opts.retentionMode
                        onSelected: newValue => {
                            Config.options.appStats.retentionMode = newValue;
                        }
                        options: [
                            {
                                "displayName": Translation.tr("Keep the previous month"),
                                "value": "previousMonth"
                            },
                            {
                                "displayName": Translation.tr("Fixed number of days"),
                                "value": "fixed"
                            }
                        ]
                    }

                    ConfigSpinBox {
                        icon: "event_repeat"
                        text: usageStatsRoot.opts.retentionMode === "previousMonth" ? Translation.tr("At least this many days") : Translation.tr("Days kept")
                        value: usageStatsRoot.opts.retentionDays
                        from: 1
                        to: 365
                        stepSize: 1
                        onValueChanged: {
                            Config.options.appStats.retentionDays = value;
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: {
                            const oldest = AppStats.oldestDate();
                            if (usageStatsRoot.opts.retentionMode !== "previousMonth")
                                return Translation.tr("Keeping from %1 onwards.").arg(oldest);
                            return Translation.tr("Keeping from %1 onwards — enough that last month is always whole, so the window slides between 31 and 62 days.").arg(oldest);
                        }
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Stored right now")
                    icon: "folder_open"
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: AppStats.storedDays < 0 ? Translation.tr("Measuring…") : Translation.tr("%1 days, %2").arg(AppStats.storedDays).arg(usageStatsRoot.humanBytes(AppStats.storedBytes))
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RippleButton {
                            implicitHeight: 34
                            horizontalPadding: 16
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer2
                            buttonText: Translation.tr("Write now")
                            onClicked: {
                                AppStats.refresh();
                                AppStats.measureStorage();
                            }

                            StyledToolTip {
                                text: Translation.tr("Flush the current hour to disk instead of waiting for the next write")
                            }
                        }

                        RippleButton {
                            implicitHeight: 34
                            horizontalPadding: 16
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer2
                            buttonText: Translation.tr("Open folder")
                            onClicked: AppStats.openStateDir()
                        }

                        RippleButton {
                            implicitHeight: 34
                            horizontalPadding: 16
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer2
                            buttonText: Translation.tr("Delete history")
                            onClicked: deleteDialog.show = true
                        }

                        Item {
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        // ── Navigation to Overlay Views & Collection Tuning ───────────────────
        ContentSection {
            title: Translation.tr("Views & Collection")
            tooltip: Translation.tr("Configure default metrics, views, intervals and energy tracking.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSubpageRow {
                    buttonIcon: "tune"
                    title: Translation.tr("Overlay preferences & views")
                    description: Translation.tr("Default timeframes, screen time / energy metrics, and list filters")
                    summary: Translation.tr("Opens on %1 · %2").arg(usageStatsRoot.opts.defaultGranularity).arg(usageStatsRoot.opts.defaultMetric)
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/UsageStatsOverlayConfig.qml"))
                }

                ConfigSubpageRow {
                    buttonIcon: "settings_input_component"
                    title: Translation.tr("Collection settings & sampler")
                    description: Translation.tr("Energy source (RAPL / Battery), sampling intervals, and idle timeout")
                    summary: Translation.tr("Source: %1 · %2ms").arg(usageStatsRoot.opts.energySource).arg(usageStatsRoot.opts.sampleIntervalMs)
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/UsageStatsCollectionConfig.qml"))
                }
            }
        }
    }

    WindowDialog {
        id: deleteDialog
        parent: page.parent ? page.parent : page
        anchors.fill: parent
        show: false
        backgroundWidth: 360
        onDismiss: show = false
        z: 100000

        WindowDialogTitle {
            text: Translation.tr("Delete usage history?")
        }

        WindowDialogParagraph {
            text: Translation.tr("Every day file is removed. Collection carries on, so today's starts filling again at the next write.")
        }

        WindowDialogButtonRow {
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: deleteDialog.show = false
            }
            DialogButton {
                buttonText: Translation.tr("Delete")
                onClicked: {
                    AppStats.clearHistory();
                    deleteDialog.show = false;
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
