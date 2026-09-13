import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentPage {
    id: page

    property bool showBackButton: false
    signal goBack()

    forceWidth: false

    RowLayout {
        visible: page.showBackButton
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
            onClicked: page.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            text: Translation.tr("Advanced Drive Settings")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    readonly property var driveOptions: (Persistent.ready ? Persistent.states.googleDrive : null) || Config.options.googleDrive

    function updateDriveOption(key, value) {
        if (Persistent.ready) {
            Persistent.states.googleDrive[key] = value;
        }
        if (Config.ready) {
            Config.options.googleDrive[key] = value;
        }
    }

    ContentSection {
        Layout.fillWidth: true
        icon: "folder_special"
        title: Translation.tr("Destination")

        NoticeBox {
            Layout.fillWidth: true
            text: Translation.tr("Backups are stored in this top-level Google Drive folder. Leave empty to use the automatic name.")
        }

        ConfigTextField {
            Layout.fillWidth: true
            icon: "folder"
            text: Translation.tr("Remote backup folder")
            placeholderText: GoogleDriveService.defaultDriveBasePath
            inputText: GoogleDriveService.effectiveDriveBasePath
            tooltip: Translation.tr("Use letters, numbers, dots, underscores, dashes or nested folders. Leave empty to restore the automatic name.")
            textField.onEditingFinished: {
                const value = textField.text.trim();
                if (value === "") {
                    root.updateDriveOption("driveBasePath", "");
                    return;
                }
                if (/^[A-Za-z0-9][A-Za-z0-9._/-]*$/.test(value) && !value.includes(".."))
                    root.updateDriveOption("driveBasePath", value);
            }
        }
    }

    ContentSection {
        Layout.fillWidth: true
        icon: "speed"
        title: Translation.tr("Transfer & Network")

        NoticeBox {
            Layout.fillWidth: true
            text: Translation.tr("These options are useful for slower connections or automatic backups triggered by network changes.")
        }

        ConfigSlider {
            Layout.fillWidth: true
            buttonIcon: "speed"
            text: Translation.tr("Bandwidth limit (KB/s)")
            from: 0
            to: 10000
            stepSize: 100
            value: root.driveOptions.bandwidthLimitKbps
            usePercentTooltip: false
            tooltipContent: root.driveOptions.bandwidthLimitKbps === 0
                ? Translation.tr("Unlimited")
                : String(root.driveOptions.bandwidthLimitKbps) + " KB/s"
            onValueChanged: {
                if (value !== root.driveOptions.bandwidthLimitKbps)
                    root.updateDriveOption("bandwidthLimitKbps", Math.round(value));
            }
        }

        ConfigSwitch {
            buttonIcon: "signal_cellular_alt"
            text: Translation.tr("Pause on metered connections")
            checked: root.driveOptions.pauseOnMeteredConnection
            onCheckedChanged: {
                if (checked !== root.driveOptions.pauseOnMeteredConnection)
                    root.updateDriveOption("pauseOnMeteredConnection", checked);
            }
        }

        ConfigSwitch {
            buttonIcon: "wifi_find"
            text: Translation.tr("Sync when network connects")
            checked: root.driveOptions.syncOnNetworkChange
            onCheckedChanged: {
                if (checked !== root.driveOptions.syncOnNetworkChange)
                    root.updateDriveOption("syncOnNetworkChange", checked);
            }
        }

        ConfigSwitch {
            buttonIcon: "update"
            text: Translation.tr("Backup only files modified since last backup")
            checked: Config.options.googleDrive.onlyModifiedSinceLastSync
            onCheckedChanged: {
                if (checked !== root.driveOptions.onlyModifiedSinceLastSync)
                    root.updateDriveOption("onlyModifiedSinceLastSync", checked);
            }
        }
    }

    ContentSection {
        Layout.fillWidth: true
        icon: "history"
        title: Translation.tr("Retention & Cleanup")

        NoticeBox {
            Layout.fillWidth: true
            text: Translation.tr("Retention controls affect how many historical copies remain and how remote files are handled when local folders change.")
        }

        ConfigSpinBox {
            icon: "history"
            text: Translation.tr("Versions to keep")
            from: 1
            to: 10
            value: root.driveOptions.keepVersions
            onValueChanged: {
                if (value !== root.driveOptions.keepVersions)
                    root.updateDriveOption("keepVersions", value);
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Orphan policy")
            color: Appearance.colors.colSubtext
        }

        ConfigSelectionArray {
            Layout.fillWidth: true
            currentValue: root.driveOptions.deleteRemoteOrphans ? "delete" : "keep"
            options: [
                { displayName: Translation.tr("Keep on Drive"), value: "keep", icon: "cloud" },
                { displayName: Translation.tr("Delete from Drive"), value: "delete", icon: "delete_sweep" }
            ]
            onSelected: value => root.updateDriveOption("deleteRemoteOrphans", value === "delete")
        }
    }

    ContentSection {
        Layout.fillWidth: true
        icon: "notifications"
        title: Translation.tr("Notifications")

        ConfigSwitch {
            buttonIcon: "cloud_done"
            text: Translation.tr("Notify on backup complete")
            checked: root.driveOptions.notifyOnComplete
            onCheckedChanged: {
                if (checked !== root.driveOptions.notifyOnComplete)
                    root.updateDriveOption("notifyOnComplete", checked);
            }
        }

        ConfigSwitch {
            buttonIcon: "error"
            text: Translation.tr("Notify on errors")
            checked: root.driveOptions.notifyOnError
            onCheckedChanged: {
                if (checked !== root.driveOptions.notifyOnError)
                    root.updateDriveOption("notifyOnError", checked);
            }
        }
    }
}
