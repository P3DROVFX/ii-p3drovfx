import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * M3E LocalSend section: clean status card with high-contrast controls +
 * conditional inline alerts + grouped settings rows.
 */
AppSettingsSection {
    id: section

    property bool showManualCommand: false
    property bool showInstallLog: false

    symbol: "share"
    title: Translation.tr("LocalSend")
    description: Translation.tr("Send and receive files across your LAN with the official localsend-cli.")

    // ── Expressive LocalSend status card ────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        implicitHeight: statusCol.implicitHeight + 36
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: LocalSend.serverRunning
            color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.08)
        }

        ColumnLayout {
            id: statusCol
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                MaterialShapeWrappedMaterialSymbol {
                    shape: LocalSend.serverRunning
                        ? MaterialShape.Shape.Flower
                        : (LocalSend.available ? MaterialShape.Shape.Circle : MaterialShape.Shape.Square)
                    implicitSize: 50
                    padding: 8
                    iconSize: 22
                    text: LocalSend.serverRunning ? "wifi_tethering" : (LocalSend.available ? "share" : "download")
                    fill: LocalSend.serverRunning ? 1 : 0
                    color: LocalSend.serverRunning
                        ? Appearance.colors.colPrimary
                        : (LocalSend.available ? Appearance.colors.colLayer2 : Appearance.colors.colSecondaryContainer)
                    colSymbol: LocalSend.serverRunning
                        ? Appearance.colors.colOnPrimary
                        : (LocalSend.available ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnSecondaryContainer)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        StyledText {
                            text: Translation.tr("Receiver")
                            font.pixelSize: 18
                            font.variableAxes: ({ "wght": 750, "wdth": 100, "ROND": 0 })
                            color: Appearance.colors.colOnLayer1
                        }

                        Rectangle {
                            implicitWidth: verLabel.implicitWidth + 16
                            implicitHeight: 24
                            radius: Appearance.rounding.full
                            color: LocalSend.available
                                ? (LocalSend.serverRunning ? Appearance.colors.colPrimary : Appearance.colors.colLayer2)
                                : Appearance.colors.colSecondaryContainer

                            StyledText {
                                id: verLabel
                                anchors.centerIn: parent
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smaller - 1
                                font.weight: Font.DemiBold
                                text: LocalSend.available
                                    ? `CLI ${LocalSend.cliVersion || "ok"}`
                                    : Translation.tr("Missing CLI")
                                color: LocalSend.available
                                    ? (LocalSend.serverRunning ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2)
                                    : Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: {
                            if (LocalSend.installing)
                                return Translation.tr("Installing official localsend-cli…");
                            if (!LocalSend.available)
                                return Translation.tr("Prebuilt official Rust binary from GitHub releases (no Cargo required on x86_64/aarch64).");
                            if (LocalSend.serverRunning)
                                return Translation.tr("Listening on LAN · saving to %1").arg(LocalSend.getEffectiveDownloadPath());
                            return Translation.tr("Ready to receive files from phones and nearby devices.");
                        }
                    }
                }

                StyledSwitch {
                    visible: LocalSend.available && !LocalSend.installing
                    checked: LocalSend.serverRunning
                    onToggled: value => value ? LocalSend.startServer() : LocalSend.stopServer()
                }

                RowLayout {
                    visible: !LocalSend.available && !LocalSend.installing
                    spacing: 8

                    RippleButtonWithIcon {
                        materialIcon: "terminal"
                        mainText: ""
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colText: Appearance.colors.colOnLayer2
                        onClicked: section.showManualCommand = !section.showManualCommand
                        StyledToolTip {
                            text: Translation.tr("Manual install command")
                        }
                    }

                    RippleButtonWithIcon {
                        materialIcon: "download"
                        mainText: Translation.tr("Install CLI")
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colText: Appearance.colors.colOnPrimary
                        onClicked: LocalSend.installOfficialCli()
                    }
                }

                MaterialLoadingIndicator {
                    visible: LocalSend.installing
                    loading: visible
                    implicitSize: 28
                }
            }

            // Conditional inline manual command
            Rectangle {
                Layout.fillWidth: true
                visible: !LocalSend.available && section.showManualCommand
                implicitHeight: manualRow.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2

                RowLayout {
                    id: manualRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                        text: "bash ~/.config/quickshell/ii/scripts/localsend/install_localsend_cli.sh"
                    }

                    RippleButtonWithIcon {
                        materialIcon: "content_copy"
                        mainText: Translation.tr("Copy")
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer0
                        colText: Appearance.colors.colOnLayer0
                        onClicked: Quickshell.clipboardText = "bash ~/.config/quickshell/ii/scripts/localsend/install_localsend_cli.sh"
                    }
                }
            }

            // Conditional missing-pyte banner
            Rectangle {
                Layout.fillWidth: true
                visible: LocalSend.available && LocalSend.pyteChecked && !LocalSend.pyteAvailable
                implicitHeight: pyteRow.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSecondaryContainer

                RowLayout {
                    id: pyteRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    MaterialSymbol {
                        text: "warning"
                        iconSize: 18
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSecondaryContainer
                        text: Translation.tr("Sending requires Python package 'pyte' (receiving works without it): pip install --user pyte")
                    }

                    RippleButtonWithIcon {
                        materialIcon: "content_copy"
                        mainText: Translation.tr("Copy")
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer0
                        colText: Appearance.colors.colOnLayer0
                        onClicked: Quickshell.clipboardText = "pip install --user pyte"
                    }
                }
            }

            // Conditional install error
            Rectangle {
                Layout.fillWidth: true
                visible: LocalSend.installError !== ""
                implicitHeight: errCol.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: Appearance.colors.colErrorContainer

                ColumnLayout {
                    id: errCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "error"
                            iconSize: 18
                            color: Appearance.colors.colOnErrorContainer
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnErrorContainer
                            text: LocalSend.installError
                        }

                        RippleButtonWithIcon {
                            visible: LocalSend.installLog !== ""
                            materialIcon: section.showInstallLog ? "expand_less" : "expand_more"
                            mainText: Translation.tr("Log")
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer0
                            colText: Appearance.colors.colOnLayer0
                            onClicked: section.showInstallLog = !section.showInstallLog
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: section.showInstallLog && LocalSend.installLog !== ""
                        wrapMode: Text.Wrap
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller - 1
                        color: Appearance.colors.colOnErrorContainer
                        text: LocalSend.installLog.trim()
                    }
                }
            }
        }
    }

    // ── Grouped receiver settings ───────────────────────────────────────
    AppToggleRow {
        symbol: "power_settings_new"
        title: Translation.tr("Auto-start receiver")
        description: Translation.tr("Start LocalSend automatically with the shell")
        enabled: LocalSend.available
        checked: Config.options.localsend.autoStart
        onToggled: value => Config.options.localsend.autoStart = value
    }

    AppToggleRow {
        symbol: "notifications"
        title: Translation.tr("Transfer notifications")
        description: Translation.tr("Notify when incoming transfers arrive or finish")
        enabled: LocalSend.available
        checked: Config.options.localsend.showNotifications
        onToggled: value => Config.options.localsend.showNotifications = value
    }

    AppChoiceRow {
        symbol: "branding_watermark"
        title: Translation.tr("Incoming file prompt")
        description: Translation.tr("Choose whether incoming transfers open the shell popup or a desktop notification")
        enabled: LocalSend.available && Config.options.localsend.showNotifications
        currentValue: Config.options.localsend.preferPopupOverNotification
        options: [
            { label: Translation.tr("Shell popup"), icon: "picture_in_picture_alt", value: true },
            { label: Translation.tr("Notification"), icon: "notifications_active", value: false }
        ]
        onSelected: value => Config.options.localsend.preferPopupOverNotification = value
    }

    AppFieldRow {
        symbol: "folder"
        title: Translation.tr("Download folder")
        description: Translation.tr("Destination directory for received files")
        enabled: LocalSend.available
        value: Config.options.localsend.downloadPath
        placeholder: Translation.tr("~/Downloads")
        onEdited: text => Config.options.localsend.downloadPath = text
    }
}
