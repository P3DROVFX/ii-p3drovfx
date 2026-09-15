import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentPage {
    id: root

    signal goBack()
    forceWidth: false

    RowLayout {
        spacing: Appearance.rounding.small

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
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
            text: Translation.tr("Port Watcher")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "lan"
        title: Translation.tr("Monitoring")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "shield"
            text: Translation.tr("Port Watcher lists the ports your own applications are serving on, read with ss. Stopping a port sends a signal to the process that owns it, and only processes owned by your user session can be managed.")
        }

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Enable port monitoring")
            checked: Config.options.bar.portWatcher.enabled
            onCheckedChanged: Config.options.bar.portWatcher.enabled = checked
        }

        ConfigSwitch {
            enabled: Config.options.bar.portWatcher.enabled
            buttonIcon: "sync"
            text: Translation.tr("Refresh automatically")
            checked: Config.options.bar.portWatcher.autoRefresh
            onCheckedChanged: Config.options.bar.portWatcher.autoRefresh = checked
        }

        ConfigSpinBox {
            enabled: Config.options.bar.portWatcher.enabled
                && Config.options.bar.portWatcher.autoRefresh
            icon: "timer"
            text: Translation.tr("Refresh interval (seconds)")
            value: Math.round(Config.options.bar.portWatcher.refreshInterval / 1000)
            from: 2
            to: 60
            stepSize: 1
            onValueChanged: Config.options.bar.portWatcher.refreshInterval = value * 1000
        }

        ConfigSwitch {
            enabled: Config.options.bar.portWatcher.enabled
            buttonIcon: "notifications_active"
            text: Translation.tr("Notify when a port becomes reachable from the network")
            checked: Config.options.bar.portWatcher.notifyNewExposed
            onCheckedChanged: Config.options.bar.portWatcher.notifyNewExposed = checked
        }

        ConfigSwitch {
            enabled: Config.options.bar.portWatcher.enabled
            buttonIcon: "visibility_off"
            text: Translation.tr("Hide the bar widget while nothing is served")
            checked: Config.options.bar.portWatcher.hideWhenEmpty
            onCheckedChanged: Config.options.bar.portWatcher.hideWhenEmpty = checked
        }
    }

    ContentSection {
        icon: "filter_alt"
        title: Translation.tr("Which ports to show")

        ConfigSwitch {
            buttonIcon: "settings_ethernet"
            text: Translation.tr("TCP ports")
            checked: Config.options.bar.portWatcher.showTcp
            onCheckedChanged: Config.options.bar.portWatcher.showTcp = checked
        }

        ConfigSwitch {
            buttonIcon: "sensors"
            text: Translation.tr("UDP ports")
            checked: Config.options.bar.portWatcher.showUdp
            onCheckedChanged: Config.options.bar.portWatcher.showUdp = checked
        }

        ConfigSwitch {
            buttonIcon: "home_pin"
            text: Translation.tr("Ports bound only to localhost")
            checked: Config.options.bar.portWatcher.showLoopback
            onCheckedChanged: Config.options.bar.portWatcher.showLoopback = checked
        }

        ConfigSwitch {
            buttonIcon: "admin_panel_settings"
            text: Translation.tr("System and other users' ports")
            checked: Config.options.bar.portWatcher.showSystem
            onCheckedChanged: Config.options.bar.portWatcher.showSystem = checked
        }

        ConfigSwitch {
            buttonIcon: "public"
            text: Translation.tr("Only ports reachable from the network")
            checked: Config.options.bar.portWatcher.exposedOnly
            onCheckedChanged: Config.options.bar.portWatcher.exposedOnly = checked
        }
    }

    ContentSection {
        icon: "linear_scale"
        title: Translation.tr("Port range")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "info"
            text: Translation.tr("The range stops at 32767 by default. Above that lies the kernel's ephemeral range, where applications open short-lived sockets that nobody chose to serve on.")
        }

        ConfigSpinBox {
            icon: "first_page"
            text: Translation.tr("Lowest port")
            value: Config.options.bar.portWatcher.minPort
            from: 1
            to: 65535
            stepSize: 1
            onValueChanged: Config.options.bar.portWatcher.minPort = value
        }

        ConfigSpinBox {
            icon: "last_page"
            text: Translation.tr("Highest port")
            value: Config.options.bar.portWatcher.maxPort
            from: 1
            to: 65535
            stepSize: 1
            onValueChanged: Config.options.bar.portWatcher.maxPort = value
        }
    }

    ContentSection {
        icon: "playlist_add_check"
        title: Translation.tr("Watch and ignore lists")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "info"
            text: Translation.tr("Comma separated ports or ranges, for example: 3000, 5173, 8000-8999")
        }

        ConfigTextField {
            icon: "playlist_add_check"
            text: Translation.tr("Show only these ports")
            placeholderText: Translation.tr("Empty means every port in range")
            inputText: Config.options.bar.portWatcher.watchPorts
            onInputTextChanged: Config.options.bar.portWatcher.watchPorts = inputText
        }

        ConfigTextField {
            icon: "block"
            text: Translation.tr("Never show these ports")
            placeholderText: Translation.tr("For example: 53, 5353, 631")
            inputText: Config.options.bar.portWatcher.ignorePorts
            onInputTextChanged: Config.options.bar.portWatcher.ignorePorts = inputText
        }

        ConfigTextField {
            icon: "apps_outage"
            text: Translation.tr("Never show these processes")
            placeholderText: Translation.tr("For example: firefox, syncthing")
            inputText: Config.options.bar.portWatcher.ignoreProcesses
            onInputTextChanged: Config.options.bar.portWatcher.ignoreProcesses = inputText
        }
    }

    ContentSection {
        icon: "sort"
        title: Translation.tr("Ordering")

        ConfigSelectionArray {
            currentValue: Config.options.bar.portWatcher.sortMode
            onSelected: newValue => {
                Config.options.bar.portWatcher.sortMode = newValue;
            }
            options: [
                {
                    displayName: Translation.tr("Port"),
                    icon: "tag",
                    value: "port"
                },
                {
                    displayName: Translation.tr("Process"),
                    icon: "memory",
                    value: "process"
                },
                {
                    displayName: Translation.tr("Activity"),
                    icon: "swap_vert",
                    value: "activity"
                }
            ]
        }
    }

    ContentSection {
        icon: "monitoring"
        title: Translation.tr("Right now")

        ConfigRow {
            uniform: true

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 44
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: PortWatcher.refresh()

                contentItem: RowLayout {
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                    }

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "refresh"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Rescan now")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("%1 shown · %2 exposed").arg(PortWatcher.count).arg(PortWatcher.exposedCount)
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: PortWatcher.exposedCount > 0
                        ? Appearance.colors.colError
                        : Appearance.colors.colOnLayer2
                }
            }
        }
    }
}
