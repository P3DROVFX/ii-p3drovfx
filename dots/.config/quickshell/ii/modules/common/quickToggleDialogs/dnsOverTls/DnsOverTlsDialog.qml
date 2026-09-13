import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundWidth: 420

    readonly property var options: Config.options.dnsOverTls
    readonly property bool customPreset: root.options.preset === "custom"
    readonly property bool addressValid: root.options.serverAddress.trim().length > 0

    // The polkit rule can't be installed from here, so re-check on every open and
    // show the one-off command while it is missing.
    Component.onCompleted: DnsOverTls.refresh()

    function selectPreset(key: string): void {
        if (key === "custom") {
            root.options.preset = "custom";
        } else {
            DnsOverTls.applyPreset(key);
        }
        if (DnsOverTls.active)
            DnsOverTls.applyNow();
    }

    WindowDialogTitle {
        text: Translation.tr("Encrypted DNS")
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        text: Translation.tr("Sends DNS queries over TLS so the network can't read or tamper with them.")
    }

    Loader {
        Layout.fillWidth: true
        active: !DnsOverTls.polkitRuleInstalled
        visible: active // Inactive items still take up space in a ColumnLayout, invisible ones don't

        sourceComponent: Rectangle {
            implicitHeight: setupColumn.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSecondaryContainer

            ColumnLayout {
                id: setupColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                    rightMargin: 12
                }
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: "admin_panel_settings"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Asks for your password on every switch")
                        color: Appearance.colors.colOnSecondaryContainer
                        font.pixelSize: Appearance.font.pixelSize.small
                        wrapMode: Text.Wrap
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Run this once in a terminal to skip the prompt. It only grants the DNS calls this toggle needs.")
                    color: Appearance.colors.colOnSecondaryContainer
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: commandText.implicitHeight + 16
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2

                    StyledText {
                        id: commandText
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 8
                            rightMargin: 8
                        }
                        text: DnsOverTls.installCommand
                        color: Appearance.colors.colOnLayer2
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.WrapAnywhere
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Item {
                        Layout.fillWidth: true
                    }

                    DialogButton {
                        buttonText: Translation.tr("Re-check")
                        onClicked: DnsOverTls.refresh()
                    }

                    DialogButton {
                        buttonText: Translation.tr("Copy command")
                        onClicked: {
                            const command = StringUtils.shellSingleQuoteEscape(DnsOverTls.installCommand);
                            Quickshell.execDetached(["bash", "-c", `printf '%s' '${command}' | wl-copy`]);
                        }
                    }
                }
            }
        }
    }

    WindowDialogSectionHeader {
        text: Translation.tr("Server")
    }

    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }

    Column {
        id: presetColumn
        spacing: 2
        Layout.topMargin: -16
        Layout.fillWidth: true

        Repeater {
            model: DnsOverTls.presets

            // Clicking a RadioButton overwrites `checked` imperatively, so exclusion
            // is driven by the config value and the binding is restored afterwards.
            delegate: StyledRadioButton {
                id: presetButton
                required property var modelData
                anchors {
                    left: parent?.left
                    right: parent?.right
                }
                autoExclusive: false
                description: modelData.label
                checked: root.options.preset === modelData.key
                onClicked: {
                    root.selectPreset(modelData.key);
                    presetButton.checked = Qt.binding(() => root.options.preset === presetButton.modelData.key);
                }
            }
        }

        StyledRadioButton {
            id: customButton
            anchors {
                left: parent?.left
                right: parent?.right
            }
            autoExclusive: false
            description: Translation.tr("Custom")
            checked: root.customPreset
            onClicked: {
                root.selectPreset("custom");
                customButton.checked = Qt.binding(() => root.customPreset);
            }
        }
    }

    FadeLoader {
        Layout.fillWidth: true
        shown: root.customPreset

        sourceComponent: ColumnLayout {
            spacing: 8

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Server address")
                text: root.options.serverAddress
                error: text.trim().length === 0
                onEditingFinished: root.options.serverAddress = text.trim()
            }

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Fallback address (optional)")
                text: root.options.fallbackAddress
                onEditingFinished: root.options.fallbackAddress = text.trim()
            }

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("TLS server name, e.g. dns.adguard-dns.com")
                text: root.options.serverName
                onEditingFinished: root.options.serverName = text.trim()
            }
        }
    }

    WindowDialogSectionHeader {
        text: Translation.tr("Behavior")
    }

    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }

    Column {
        spacing: 4
        Layout.topMargin: -16
        Layout.fillWidth: true

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "lock"
            text: Translation.tr("Strict mode")
            checked: root.options.strict
            onCheckedChanged: {
                if (checked === root.options.strict)
                    return;
                root.options.strict = checked;
                if (DnsOverTls.active)
                    DnsOverTls.applyNow();
            }
        }

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "alt_route"
            text: Translation.tr("Route every domain")
            checked: root.options.routeAllQueries
            onCheckedChanged: {
                if (checked === root.options.routeAllQueries)
                    return;
                root.options.routeAllQueries = checked;
                if (DnsOverTls.active)
                    DnsOverTls.applyNow();
            }
        }

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "autorenew"
            text: Translation.tr("Reapply after network changes")
            checked: root.options.reapplyOnNetworkChange
            onCheckedChanged: root.options.reapplyOnNetworkChange = checked
        }
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        Layout.topMargin: -8
        text: Translation.tr("Strict mode never falls back to unencrypted DNS — turn it off on networks with a sign-in page, which need plain DNS to show the portal. These settings only last until the connection is reconfigured, so they are put back automatically.")
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        Layout.topMargin: 4
        text: !DnsOverTls.resolvedAvailable ? Translation.tr("systemd-resolved isn't running, so encrypted DNS can't be set up.") : !DnsOverTls.available ? Translation.tr("No active network connection.") : DnsOverTls.active ? Translation.tr("Active on %1 — %2, %3").arg(DnsOverTls.link).arg(DnsOverTls.statusText).arg(DnsOverTls.activeServers) : Translation.tr("Inactive on %1 — currently using %2").arg(DnsOverTls.link).arg(DnsOverTls.activeServers)
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: DnsOverTls.active ? Translation.tr("Turn off") : Translation.tr("Turn on")
            enabled: DnsOverTls.available && !DnsOverTls.busy && (DnsOverTls.active || root.addressValid)
            colText: enabled ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
            onClicked: DnsOverTls.toggle()
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
