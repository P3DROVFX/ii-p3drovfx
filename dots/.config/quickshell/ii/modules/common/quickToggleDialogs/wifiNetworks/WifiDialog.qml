import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    // Dialogs may be hosted by surfaces other than the dashboard. Keep the
    // historical dashboard behaviour as the default, while allowing hosts such
    // as Welcome to opt out of sidebar-specific side effects.
    property bool closeOwningSidebarOnDetails: true
    property bool showDetailsAction: true

    signal detailsRequested()

    backgroundHeight: 600

    // ── Share page state ──────────────────────────────────
    /// True while the dialog shows the "Share Wi-Fi" QR page instead of the list.
    property bool sharing: false
    /// "loading" | "ready" | "error"
    property string shareState: "loading"
    property string shareSsid: ""
    property string sharePassword: ""
    property string shareKeyMgmt: ""
    property bool shareHidden: false
    property bool sharePasswordVisible: false
    property int _shareRequest: 0
    readonly property string sharePayload: root.shareState === "ready"
        ? QrCode.wifiPayload(root.shareSsid, root.sharePassword, root.shareKeyMgmt, root.shareHidden)
        : ""

    function openShare(ssid: string): void {
        const request = ++root._shareRequest;
        root.shareSsid = ssid;
        root.sharePassword = "";
        root.shareKeyMgmt = "";
        root.shareHidden = false;
        root.sharePasswordVisible = false;
        root.shareState = "loading";
        root.sharing = true;
        NetworkCommands.readWifiShareInfo(ssid, info => {
            // Closed, or asked again for another network, while nmcli answered.
            if (request !== root._shareRequest || !root.sharing)
                return;
            if (!info.ok || info.keyMgmt === "wpa-eap") {
                root.shareState = "error";
                return;
            }
            root.shareSsid = info.ssid;
            root.sharePassword = info.password;
            root.shareKeyMgmt = info.keyMgmt;
            root.shareHidden = info.hidden;
            root.shareState = "ready";
        });
    }

    // The secret leaves memory as soon as the page does.
    function closeShare(): void {
        root._shareRequest++;
        root.sharing = false;
        root.sharePassword = "";
        root.sharePasswordVisible = false;
        root.shareState = "loading";
        wifiContent.closeQuickActions();
    }

    function prepareForOpen() {
        Network.enableWifi();
        Network.rescanWifi();
        NetworkSpeed.start();
    }

    onShowChanged: {
        // Scanning is asked for only while this is visible, so a dialog left
        // closed never keeps the radio busy.
        Network.setWifiScanHolder("wifiDialog", root.show);
        if (show)
            root.prepareForOpen();
        else {
            NetworkSpeed.stop();
            root.closeShare();
        }
    }

    // A dialog torn down while open would otherwise hold the scan for good.
    Component.onDestruction: Network.setWifiScanHolder("wifiDialog", false)

    // Escape steps back from the share page before it closes the dialog.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && root.sharing) {
            root.closeShare();
            event.accepted = true;
        }
    }

    // ── Header ────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 8

        // The page frame (pageMode) already has a back button at this spot.
        RippleButton {
            visible: root.sharing && !root.pageMode
            implicitWidth: 36
            implicitHeight: 36
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            onClicked: root.closeShare()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer2
            }

            StyledToolTip {
                text: Translation.tr("Back")
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.sharing ? Translation.tr("Share Wi-Fi") : Translation.tr("Wi-Fi")
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer1
        }

        StyledSwitch {
            visible: !root.sharing
            checked: Network.wifiEnabled
            onToggled: Network.toggleWifi()
        }
    }

    // ── Content (scrollable) ──────────────────────────────
    WifiDialogContent {
        id: wifiContent
        visible: !root.sharing
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: -4
        onShareRequested: ssid => root.openShare(ssid)
    }

    // ── Share page ────────────────────────────────────────
    ColumnLayout {
        id: sharePage
        visible: root.sharing
        Layout.fillWidth: true
        Layout.fillHeight: !root.pageMode
        spacing: 14

        Item {
            Layout.fillHeight: true
        }

        // QR card, framed by a soft tonal backdrop like Android's share sheet.
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: shareQrHolder.implicitWidth + 24
            implicitHeight: shareQrHolder.implicitHeight + 24
            radius: Appearance.rounding.verylarge
            color: Appearance.colors.colLayer2

            Item {
                id: shareQrHolder
                anchors.centerIn: parent
                implicitWidth: 220
                implicitHeight: 220

                StyledQrCode {
                    anchors.centerIn: parent
                    visible: root.shareState === "ready"
                    text: root.sharePayload
                    ecc: "M"
                    implicitSize: 220
                    radius: Appearance.rounding.large
                }

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: root.shareState === "loading"
                    loading: visible
                    implicitSize: 48
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    visible: root.shareState === "error"
                    spacing: 10

                    MaterialShapeWrappedMaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "wifi_lock"
                        iconSize: 26
                        padding: 12
                        shape: MaterialShape.Shape.Cookie7Sided
                        color: Appearance.colors.colErrorContainer
                        colSymbol: Appearance.colors.colOnErrorContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: Translation.tr("This network can't be shared. Only saved personal (password or open) networks can be turned into a QR code.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        // Network name
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: sharePage.width
            spacing: 6

            MaterialSymbol {
                text: "wifi"
                iconSize: 20
                fill: 1
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.maximumWidth: sharePage.width - 32
                elide: Text.ElideRight
                text: root.shareSsid
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer1
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: root.shareState !== "error"
            text: Translation.tr("Scan this QR code with another device to join the network")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        // Password row: hidden by default, revealable and copyable.
        Rectangle {
            Layout.fillWidth: true
            visible: root.shareState === "ready" && root.sharePassword.length > 0
            implicitHeight: 56
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: 18
                    rightMargin: 8
                }
                spacing: 6

                MaterialSymbol {
                    text: "key"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer2
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: Translation.tr("Password")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.sharePasswordVisible ? root.sharePassword : "•".repeat(Math.min(root.sharePassword.length, 16))
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: root.sharePasswordVisible ? Appearance.font.family.monospace : Appearance.font.family.main
                        font.bold: true
                        color: Appearance.colors.colOnLayer2
                    }
                }

                RippleButton {
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.sharePasswordVisible = !root.sharePasswordVisible
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.sharePasswordVisible ? "visibility_off" : "visibility"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledToolTip {
                        text: root.sharePasswordVisible ? Translation.tr("Hide password") : Translation.tr("Show password")
                    }
                }

                RippleButton {
                    id: copyPasswordBtn
                    property bool copied: false
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: {
                        Quickshell.clipboardText = root.sharePassword;
                        copyPasswordBtn.copied = true;
                        copiedReset.restart();
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: copyPasswordBtn.copied ? "check" : "content_copy"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer2
                    }

                    Timer {
                        id: copiedReset
                        interval: 1500
                        onTriggered: copyPasswordBtn.copied = false
                    }

                    StyledToolTip {
                        text: Translation.tr("Copy password")
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }

    // ── Bottom buttons ────────────────────────────────────
    WindowDialogButtonRow {
        Layout.leftMargin: 0
        Layout.rightMargin: 0
        Layout.bottomMargin: -8

        RippleButton {
            id: detailsBtn
            visible: root.showDetailsAction || root.sharing
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: "transparent"
            colRipple: "transparent"
            implicitHeight: 36
            implicitWidth: detailsText.implicitWidth + 48

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: detailsBtn.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                radius: parent.buttonEffectiveRadius
                Behavior on border.color {
                    ColorAnimation { duration: 150 }
                }
            }

            contentItem: StyledText {
                id: detailsText
                text: Translation.tr("Details")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: ({"wght": 500})
                color: detailsBtn.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            onClicked: {
                GlobalStates.openSettingsPage("network", "", Network.ethernet ? "Ethernet ports" : "Wi-Fi");
                root.detailsRequested();
                if (root.closeOwningSidebarOnDetails)
                    GlobalStates.sidebarRightOpen = false;
            }
        }

        Item { Layout.fillWidth: true }

        RippleButton {
            id: doneBtn
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            implicitHeight: 36
            implicitWidth: doneText.implicitWidth + 48

            contentItem: StyledText {
                id: doneText
                text: Translation.tr("Done")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: ({"wght": 700})
                color: Appearance.colors.colOnPrimary
            }
            onClicked: root.dismiss()
        }
    }
}
