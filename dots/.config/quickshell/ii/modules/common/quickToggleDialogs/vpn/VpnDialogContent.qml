import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Qt5Compat.GraphicalEffects

StyledFlickable {
    id: root


    Layout.fillWidth: true
    Layout.fillHeight: true

    contentHeight: mainLayout.implicitHeight + 36
    clip: true

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Item {
            id: maskRoot
            width: root.width
            height: root.height

            property color topFadeColor: root.atYBeginning ? Appearance.colors.colOnSurface : "transparent"
            property color bottomFadeColor: root.atYEnd ? Appearance.colors.colOnSurface : "transparent"

            Column {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    width: parent.width
                    height: Math.min(46, parent.height / 2)
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: maskRoot.topFadeColor }
                        GradientStop { position: 1.0; color: Appearance.colors.colOnSurface }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Math.max(0, parent.height - Math.min(46, parent.height / 2) - Math.min(56, parent.height / 2))
                    color: Appearance.colors.colOnSurface
                }

                Rectangle {
                    width: parent.width
                    height: Math.min(56, parent.height / 2)
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Appearance.colors.colOnSurface }
                        GradientStop { position: 1.0; color: maskRoot.bottomFadeColor }
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: mainLayout
        width: root.width
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 4
        spacing: 12

        // Progress indicator
        StyledIndeterminateProgressBar {
            visible: VpnService.loading
            Layout.fillWidth: true
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 160
            visible: VpnService.loading
            PagePlaceholder {
                anchors.fill: parent
                shown: parent.visible
                icon: "sync"
                title: Translation.tr("Loading VPN status")
                description: Translation.tr("Checking NetworkManager and available providers…")
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            visible: !VpnService.loading && !VpnService.enabled
            PagePlaceholder {
                anchors.fill: parent
                shown: parent.visible
                icon: "vpn_lock"
                title: Translation.tr("VPN Integration Disabled")
                description: Translation.tr("Enable VPN integration in Privacy & Security settings to manage connections.")
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            visible: !VpnService.loading && VpnService.enabled && !VpnService.available
            PagePlaceholder {
                anchors.fill: parent
                shown: parent.visible
                icon: "vpn_lock"
                title: Translation.tr("VPN Unavailable")
                description: Translation.tr("NetworkManager VPN daemon or supported CLI tools were not found on this system.")
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }

        // ── Section: Connected VPN ──────────────────────────
        StyledText {
            visible: VpnService.enabled && VpnService.displayActive
            text: Translation.tr("Connected VPN")
            font.pixelSize: Appearance.font.pixelSize.normal
            font.bold: true
            color: Appearance.colors.colSubtext
            Layout.fillWidth: true
            Layout.topMargin: 0
        }

        // Connected VPN item (same style as Bluetooth/Wifi connected items)
        Item {
            visible: VpnService.enabled && VpnService.displayActive
            Layout.fillWidth: true
            implicitHeight: 56
            height: implicitHeight

            RowLayout {
                anchors.fill: parent
                spacing: 8

                // Main info card
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 12

                        MaterialSymbol {
                            text: "vpn_lock"
                            iconSize: 22
                            color: Appearance.colors.colOnPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: VpnService.activeProfile || Translation.tr("VPN Active")
                                font.bold: true
                                horizontalAlignment: Text.AlignLeft
                                color: Appearance.colors.colOnPrimary
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Connected")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                horizontalAlignment: Text.AlignLeft
                                color: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.2)
                            }
                        }
                    }
                }

                // External Action Button (Disconnect)
                RippleButton {
                    Layout.preferredWidth: 56
                    Layout.fillHeight: true
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "check"
                        iconSize: 22
                        color: Appearance.colors.colOnPrimary
                    }
                    onClicked: {
                        VpnService.disconnectVpn()
                    }
                    StyledToolTip {
                        text: Translation.tr("Disconnect VPN")
                    }
                }
            }
        }

        // Error Notice
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: errText.implicitHeight + 20
            visible: VpnService.errorMessage.length > 0
            radius: Appearance.rounding.normal
            color: Appearance.colors.colErrorContainer

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                MaterialSymbol {
                    text: "error"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnErrorContainer
                }

                StyledText {
                    id: errText
                    Layout.fillWidth: true
                    text: VpnService.errorMessage
                    color: Appearance.colors.colOnErrorContainer
                    wrapMode: Text.Wrap
                }
            }
        }

        RowLayout {
            visible: VpnService.available
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Providers")
                font.bold: true
                color: Appearance.colors.colSubtext
            }
            RippleButton {
                implicitHeight: 36
                implicitWidth: importText.implicitWidth + 28
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                enabled: !VpnService.loading
                contentItem: StyledText {
                    id: importText
                    text: Translation.tr("Import profile")
                    color: Appearance.colors.colOnSecondaryContainer
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: VpnService.openFilePicker()
            }
        }

        ConfigSelectionArray {
            visible: VpnService.available
            Layout.fillWidth: true
            options: VpnService.availableProviders.map(provider => ({
                displayName: provider === "networkmanager" ? Translation.tr("NetworkManager") : provider === "protonvpn" ? Translation.tr("Proton VPN") : Translation.tr("NordVPN"),
                icon: provider === "networkmanager" ? "lan" : "vpn_key",
                value: provider
            }))
            onSelected: value => {
                Config.options.vpn.defaultProvider = value
                if (!VpnService.loading && value !== "networkmanager")
                    VpnService.connectProvider(value, Config.options.vpn.defaultLocation)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: VpnService.available
            implicitHeight: safetyColumn.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSurfaceContainerHighest
            ColumnLayout {
                id: safetyColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Safety & diagnostics")
                    font.bold: true
                    color: Appearance.colors.colOnSurface
                    wrapMode: Text.WordWrap
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    useDynamicRadius: false
                    buttonIcon: "security"
                    text: VpnService.killSwitchSupported ? Translation.tr("Kill switch") : Translation.tr("Kill switch (unsupported)")
                    checked: Config.options.vpn.killSwitch
                    enabled: VpnService.killSwitchSupported
                    onCheckedChanged: Config.options.vpn.killSwitch = checked
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    useDynamicRadius: false
                    buttonIcon: "lan"
                    text: VpnService.blockLanSupported ? Translation.tr("Block local network") : Translation.tr("Block local network (unsupported)")
                    checked: Config.options.vpn.blockLan
                    enabled: VpnService.blockLanSupported
                    onCheckedChanged: Config.options.vpn.blockLan = checked
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: !VpnService.killSwitchSupported || !VpnService.blockLanSupported
                    text: Translation.tr("Safety firewall controls are not supported by this backend.")
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: Config.options.vpn.enableDiagnostics && VpnService.lastErrorOutput.length > 0
                    text: VpnService.lastErrorOutput
                    color: Appearance.colors.colError
                    wrapMode: Text.WordWrap
                }
                RippleButton {
                    Layout.alignment: Qt.AlignLeft
                    implicitHeight: 34
                    implicitWidth: refreshText.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    enabled: !VpnService.loading
                    contentItem: StyledText {
                        id: refreshText
                        text: Translation.tr("Refresh diagnostics")
                        color: Appearance.colors.colOnSecondaryContainer
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: VpnService.runDiagnostics()
                }
            }
        }

        // Profiles section
        StyledText {
            visible: VpnService.enabled && VpnService.available
            text: Translation.tr("Profiles & Connections")
            font.pixelSize: Appearance.font.pixelSize.normal
            font.bold: true
            color: Appearance.colors.colSubtext
            Layout.topMargin: 4
        }

        ColumnLayout {
            visible: VpnService.enabled && VpnService.available
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: VpnService.profiles

                delegate: Item {
                    required property var modelData
                    readonly property bool isSelected: VpnService.activeProfile === modelData.name
                    Layout.fillWidth: true
                    implicitHeight: 52
                    height: implicitHeight

                    RowLayout {
                        anchors.fill: parent
                        spacing: 8

                        // Item Main Card Info
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Appearance.rounding.full
                            color: isSelected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest

                            Behavior on color {
                                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                spacing: 12

                                MaterialSymbol {
                                    text: "tune"
                                    iconSize: 22
                                    color: isSelected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        font.bold: true
                                        horizontalAlignment: Text.AlignLeft
                                        color: isSelected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.type
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        horizontalAlignment: Text.AlignLeft
                                        color: isSelected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }

                        // Standalone Action Button outside card (Full pill radius, correct Error Container tokens)
                        RippleButton {
                            Layout.preferredWidth: 56
                            Layout.fillHeight: true
                            buttonRadius: Appearance.rounding.full
                            colBackground: isSelected ? Appearance.colors.colErrorContainer : Appearance.colors.colSurfaceContainerHighest
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: isSelected ? "close" : "play_arrow"
                                iconSize: 22
                                color: isSelected ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSurface
                            }
                            onClicked: {
                                if (isSelected) {
                                    VpnService.disconnectVpn()
                                } else {
                                    VpnService.connectProfile(modelData.name)
                                }
                            }
                            StyledToolTip {
                                text: isSelected ? Translation.tr("Stop Profile") : Translation.tr("Connect Profile")
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: VpnService.profiles.length === 0
                text: Translation.tr("No VPN profiles found in NetworkManager")
                color: Appearance.colors.colSubtext
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 16
                Layout.bottomMargin: 16
            }
        }
    }
}
