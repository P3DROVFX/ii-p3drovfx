import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick.Controls
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

StyledFlickable {
    id: root

    Layout.fillWidth: true
    Layout.fillHeight: true
    contentHeight: mainLayout.implicitHeight + 36
    clip: true

    property string routeDraft: ""

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

        StyledIndeterminateProgressBar {
            visible: TailscaleService.loading || TailscaleService.netcheckLoading
            Layout.fillWidth: true
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 160
            visible: TailscaleService.loading
            PagePlaceholder {
                anchors.fill: parent
                shown: parent.visible
                icon: "sync"
                title: Translation.tr("Loading Tailscale status")
                description: Translation.tr("Checking the local daemon and tailnet connection…")
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            visible: !TailscaleService.loading && !TailscaleService.enabled
            PagePlaceholder {
                anchors.fill: parent
                shown: parent.visible
                icon: "hub"
                title: Translation.tr("Tailscale Mesh Disabled")
                description: Translation.tr("Enable Tailscale mesh integration in Privacy & Security settings.")
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            visible: !TailscaleService.loading && TailscaleService.enabled && !TailscaleService.available
            PagePlaceholder {
                anchors.fill: parent
                shown: parent.visible
                icon: "hub"
                title: Translation.tr("Tailscale Unavailable")
                description: Translation.tr("Tailscale CLI binary was not found. Install tailscale package to connect.")
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }

        Rectangle {
            visible: TailscaleService.enabled && TailscaleService.errorMessage.length > 0
            Layout.fillWidth: true
            implicitHeight: errorText.implicitHeight + 20
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
                    id: errorText
                    Layout.fillWidth: true
                    text: TailscaleService.errorMessage
                    color: Appearance.colors.colOnErrorContainer
                    wrapMode: Text.Wrap
                }
            }
        }

        Item {
            visible: TailscaleService.enabled && TailscaleService.available
            Layout.fillWidth: true
            implicitHeight: 56
            RowLayout {
                anchors.fill: parent
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    radius: Appearance.rounding.full
                    color: TailscaleService.active ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 12
                        MaterialSymbol {
                            text: TailscaleService.active ? "hub" : (TailscaleService.backendState === "NeedsLogin" ? "key" : "vpn_lock")
                            iconSize: Appearance.font.pixelSize.huge
                            color: TailscaleService.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                text: TailscaleService.nodeName || Translation.tr("Tailscale Mesh")
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.bold: true
                                color: TailscaleService.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: TailscaleService.statusText + (TailscaleService.tailnetName.length > 0 ? " · " + TailscaleService.tailnetName : "")
                                color: TailscaleService.active ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
                RippleButton {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    buttonRadius: Appearance.rounding.full
                    enabled: !TailscaleService.loading
                    colBackground: TailscaleService.active ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: TailscaleService.active ? "close" : "power_settings_new"
                        iconSize: Appearance.font.pixelSize.large
                        color: TailscaleService.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                    }
                    onClicked: TailscaleService.toggleTailscale()
                    StyledToolTip { text: TailscaleService.active ? Translation.tr("Disconnect") : Translation.tr("Connect") }
                }
            }
        }

        Rectangle {
            visible: TailscaleService.backendState === "NeedsLogin" || TailscaleService.loginUrl.length > 0
            Layout.fillWidth: true
            implicitHeight: loginColumn.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSecondaryContainer
            ColumnLayout {
                id: loginColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Authentication required")
                    font.bold: true
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: TailscaleService.loginUrl.length > 0
                    text: TailscaleService.loginUrl
                    color: Appearance.colors.colOnSecondaryContainer
                    elide: Text.ElideMiddle
                }
                RippleButton {
                    Layout.alignment: Qt.AlignLeft
                    implicitHeight: 36
                    implicitWidth: loginButtonText.implicitWidth + 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    contentItem: StyledText {
                        id: loginButtonText
                        text: Translation.tr("Open login link")
                        color: Appearance.colors.colOnPrimary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    enabled: TailscaleService.loginUrl.length > 0 && !TailscaleService.loading
                    onClicked: TailscaleService.openLoginUrl()
                }
            }
        }

        StyledText {
            text: Translation.tr("Local node")
            font.bold: true
            color: Appearance.colors.colSubtext
            Layout.fillWidth: true
        }

        Rectangle {
            visible: TailscaleService.available
            Layout.fillWidth: true
            implicitHeight: localColumn.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSurfaceContainerHighest
            ColumnLayout {
                id: localColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("IPv4: %1").arg(TailscaleService.tailscaleIp4 || Translation.tr("Unavailable"))
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("IPv6: %1").arg(TailscaleService.tailscaleIp6 || Translation.tr("Unavailable"))
                    color: Appearance.colors.colSubtext
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    useDynamicRadius: false
                    buttonIcon: "dns"
                    text: Translation.tr("MagicDNS")
                    checked: TailscaleService.acceptDns
                    onCheckedChanged: {
                        if (checked !== TailscaleService.acceptDns)
                            TailscaleService.setAcceptDns(checked)
                    }
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    useDynamicRadius: false
                    buttonIcon: "terminal"
                    text: Translation.tr("Tailscale SSH")
                    checked: TailscaleService.sshEnabled
                    onCheckedChanged: {
                        if (checked !== TailscaleService.sshEnabled)
                            TailscaleService.setSshEnabled(checked)
                    }
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    useDynamicRadius: false
                    buttonIcon: "security"
                    text: Translation.tr("Shields-up")
                    checked: TailscaleService.shieldsUp
                    onCheckedChanged: {
                        if (checked !== TailscaleService.shieldsUp)
                            TailscaleService.setShieldsUp(checked)
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        enabled: !TailscaleService.loading
                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            MaterialSymbol {
                                text: "refresh"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                text: Translation.tr("Refresh")
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                        onClicked: TailscaleService.refresh()
                    }
                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        enabled: !TailscaleService.netcheckLoading
                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            MaterialSymbol {
                                text: "network_check"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                text: Translation.tr("Netcheck")
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                        onClicked: TailscaleService.netcheck()
                    }
                }
                StyledText {
                    visible: TailscaleService.diagnosticsText.length > 0
                    Layout.fillWidth: true
                    text: TailscaleService.diagnosticsText
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                    maximumLineCount: 5
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            visible: TailscaleService.available
            Layout.fillWidth: true
            implicitHeight: diagnosticsColumn.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSurfaceContainerHighest
            ColumnLayout {
                id: diagnosticsColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    MaterialSymbol {
                        text: "monitor_heart"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Diagnostics")
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                    }
                    StyledText {
                        text: TailscaleService.permissionState
                        color: Appearance.colors.colSubtext
                    }
                }
                StyledText {
                    visible: Config.options.tailscale.enableDiagnostics && TailscaleService.diagnosticsText.length > 0
                    Layout.fillWidth: true
                    text: TailscaleService.diagnosticsText
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                    maximumLineCount: 5
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            visible: TailscaleService.available
            Layout.fillWidth: true
            implicitHeight: exitColumn.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSurfaceContainerHighest
            ColumnLayout {
                id: exitColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    MaterialSymbol {
                        text: "output"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Exit node")
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                    }
                    StyledText {
                        visible: TailscaleService.currentExitNode.length > 0
                        text: TailscaleService.currentExitNode
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                    RippleButton {
                        visible: TailscaleService.currentExitNode.length > 0
                        implicitHeight: 32
                        implicitWidth: clearExitText.implicitWidth + 20
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colErrorContainer
                        contentItem: StyledText {
                            id: clearExitText
                            text: Translation.tr("Clear")
                            color: Appearance.colors.colOnErrorContainer
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        enabled: !TailscaleService.loading
                        onClicked: TailscaleService.clearExitNode()
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: TailscaleService.exitNodes
                        delegate: RippleButton {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 44
                            buttonRadius: Appearance.rounding.full
                            colBackground: TailscaleService.currentExitNode === modelData.hostname ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                            enabled: modelData.online && !TailscaleService.loading
                            contentItem: RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                MaterialSymbol { text: "router"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer2 }
                                StyledText { Layout.fillWidth: true; text: modelData.hostname; color: Appearance.colors.colOnLayer2; elide: Text.ElideRight }
                                StyledText { text: modelData.online ? Translation.tr("Available") : Translation.tr("Offline"); color: Appearance.colors.colSubtext }
                            }
                            onClicked: TailscaleService.setExitNode(modelData.hostname)
                        }
                    }
                    StyledText {
                        visible: TailscaleService.exitNodes.length === 0
                        Layout.fillWidth: true
                        text: Translation.tr("No exit nodes available")
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        StyledText {
            visible: TailscaleService.available
            text: Translation.tr("Advertised routes")
            font.bold: true
            color: Appearance.colors.colSubtext
        }
        ConfigTextField {
            visible: TailscaleService.available
            id: routeField
            Layout.fillWidth: true
            icon: "alt_route"
            text: Translation.tr("Subnet route")
            placeholderText: Translation.tr("CIDR, e.g. 192.168.1.0/24")
            inputText: root.routeDraft
            color: Appearance.colors.colSurfaceContainerHighest
            topLeftRadius: Appearance.rounding.windowRounding
            topRightRadius: Appearance.rounding.windowRounding
            bottomLeftRadius: Appearance.rounding.windowRounding
            bottomRightRadius: Appearance.rounding.windowRounding
            textField.onTextChanged: {
                if (root.routeDraft !== textField.text)
                    root.routeDraft = textField.text
            }
            rightAction: Component {
                RippleButton {
                    implicitWidth: addRouteText.implicitWidth + 20
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colBackgroundActive: Appearance.colors.colPrimaryActive
                    colRipple: Appearance.colors.colPrimaryActive
                    enabled: /^([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}$/.test(root.routeDraft.trim()) && !TailscaleService.loading
                    contentItem: StyledText {
                        id: addRouteText
                        text: Translation.tr("Add")
                        color: Appearance.colors.colOnPrimary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        const route = root.routeDraft.trim()
                        const routes = (TailscaleService.advertiseRoutes || []).slice()
                        if (!routes.includes(route)) routes.push(route)
                        TailscaleService.setAdvertiseRoutes(routes)
                        root.routeDraft = ""
                    }
                }
            }
        }

        Flow {
            visible: TailscaleService.available
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: TailscaleService.advertiseRoutes
                delegate: RippleButton {
                    required property string modelData
                    implicitHeight: 32
                    implicitWidth: routeText.implicitWidth + 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    contentItem: StyledText {
                        id: routeText
                        text: modelData + "  ×"
                        color: Appearance.colors.colOnSecondaryContainer
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        const routes = (TailscaleService.advertiseRoutes || []).filter(route => route !== modelData)
                        TailscaleService.setAdvertiseRoutes(routes)
                    }
                }
            }
        }
        ConfigSwitch {
            visible: TailscaleService.available
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            forceUniformRadius: true
            useDynamicRadius: false
            buttonIcon: "output"
            text: Translation.tr("Advertise exit node")
            checked: TailscaleService.advertiseExitNode
            onCheckedChanged: {
                if (checked !== TailscaleService.advertiseExitNode)
                    TailscaleService.setAdvertiseExitNode(checked)
            }
        }
        RippleButton {
            visible: TailscaleService.available
            Layout.alignment: Qt.AlignLeft
            implicitHeight: 36
            implicitWidth: logoutText.implicitWidth + 28
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colErrorContainer
            enabled: !TailscaleService.loading
            contentItem: StyledText {
                id: logoutText
                text: Translation.tr("Log out")
                color: Appearance.colors.colOnErrorContainer
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: TailscaleService.logout()
        }

        StyledText {
            visible: Config.options.tailscale.showPeers
            text: Translation.tr("Tailnet peers (%1)").arg(TailscaleService.peers.length)
            font.bold: true
            color: Appearance.colors.colSubtext
            Layout.fillWidth: true
        }

        ColumnLayout {
            visible: Config.options.tailscale.showPeers
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: TailscaleService.peers
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSurfaceContainerHighest
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 10
                            Rectangle {
                                width: 10
                                height: 10
                                radius: 5
                                color: modelData.online ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.hostname
                                    font.bold: true
                                    color: Appearance.colors.colOnSurface
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.ip + (modelData.os ? " · " + modelData.os : "")
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                    RippleButton {
                        implicitWidth: 48
                        Layout.preferredHeight: 52
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        enabled: modelData.online && !TailscaleService.loading
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "network_ping"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        onClicked: TailscaleService.pingPeer(modelData.ip, function() {})
                        StyledToolTip { text: Translation.tr("Ping peer") }
                    }
                }
            }
            StyledText {
                visible: Config.options.tailscale.showPeers && TailscaleService.peers.length === 0
                text: Translation.tr("No peers detected or Tailscale is offline")
                color: Appearance.colors.colSubtext
                Layout.alignment: Qt.AlignHCenter
            }
        }

        StyledText {
            visible: TailscaleService.lastPingResult.length > 0
            Layout.fillWidth: true
            text: TailscaleService.lastPingResult
            color: TailscaleService.lastPingSuccess ? Appearance.colors.colPrimary : Appearance.colors.colError
            wrapMode: Text.Wrap
        }
    }
}
