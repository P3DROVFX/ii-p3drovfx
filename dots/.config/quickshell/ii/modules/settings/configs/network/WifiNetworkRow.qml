import QtQuick
import QtQuick.Layouts
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One scanned access point, with its actions folded away until the row is
 * opened. Connecting, entering a secret, forgetting and autoconnect all happen
 * in place — this page is the dialog, so there is nowhere else to send them.
 */
Rectangle {
    id: root

    required property WifiAccessPoint accessPoint
    property bool isFirst: false
    property bool isLast: false
    property bool expanded: false
    // Sticky: the actions panel below is built once, on first expand, rather
    // than staying alive from the start so a half-typed password isn't lost
    // if the row is collapsed again.
    property bool wasExpanded: false
    onExpandedChanged: if (root.expanded) root.wasExpanded = true

    readonly property string ssid: root.accessPoint?.ssid ?? ""
    readonly property int strength: root.accessPoint?.strength ?? 0
    readonly property bool isActive: root.accessPoint?.active ?? false
    readonly property bool secure: root.accessPoint?.isSecure ?? false
    readonly property bool enterprise: root.accessPoint?.enterprise ?? false
    readonly property bool isConnecting: Network.wifiConnectTarget === root.accessPoint
    readonly property bool hasError: Network.lastWifiExitCode !== 0
        && Network.wifiErrorTarget === root.accessPoint
    readonly property bool askingPassword: root.accessPoint?.askingPassword ?? false

    // One lookup instead of two: profileName used to run its own
    // Network.savedConnections scan via savedProfileFor(), then savedProfile
    // scanned the same array again to find the same entry by that name.
    readonly property var savedProfile: Network.savedConnections
        .find(entry => entry.type === "802-11-wireless" && entry.name === root.ssid) ?? null
    readonly property string profileName: root.savedProfile?.name ?? ""
    readonly property bool isSaved: (root.accessPoint?.known ?? false) || root.profileName.length > 0
    // A secured network with nothing stored can only be joined with a secret,
    // so the row opens on its fields rather than failing first and then asking.
    readonly property bool needsSecret: root.secure && !root.isSaved

    readonly property real outerRadius: Appearance.rounding.normal
    readonly property real innerRadius: Appearance.rounding.verysmall
    readonly property bool performanceMode: Config.options?.appearance?.settingsPerformanceMode ?? false

    function submit(): void {
        if (!root.needsSecret && !root.askingPassword) {
            Network.connectToWifiNetwork(root.accessPoint);
            return;
        }
        root.expanded = true;
        // Reachable only through controls that live inside the actions panel
        // itself, so by the time this runs the panel has already been built.
        const panel = actionsLoader.item;
        if (!panel)
            return;
        if (root.enterprise && panel.identityText.length === 0) {
            panel.focusIdentity();
            return;
        }
        if (panel.passwordText.length === 0) {
            panel.focusPassword();
            return;
        }
        Network.connectWithPassword(root.ssid, panel.passwordText, root.enterprise ? panel.identityText : "");
    }

    onAskingPasswordChanged: if (root.askingPassword) root.expanded = true

    Layout.fillWidth: true
    implicitHeight: rowContent.implicitHeight
    topLeftRadius: root.isFirst ? root.outerRadius : root.innerRadius
    topRightRadius: root.isFirst ? root.outerRadius : root.innerRadius
    bottomLeftRadius: root.isLast ? root.outerRadius : root.innerRadius
    bottomRightRadius: root.isLast ? root.outerRadius : root.innerRadius
    color: root.isActive ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
    clip: true

    Behavior on color {
        // The dynamic component instantiation below (createObject) runs once
        // per row at construction regardless of `enabled`, so performance
        // mode skips it outright instead of just muting playback — with a
        // few dozen rows on screen at once that's a few dozen fewer objects
        // built the moment the list mounts.
        animation: root.performanceMode ? null
            : Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    ColumnLayout {
        id: rowContent
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        Item {
            Layout.fillWidth: true
            implicitHeight: 58

            MouseArea {
                id: headerArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
            }

            Rectangle {
                anchors.fill: parent
                // A Rectangle clips its children to its bounding box, not to its
                // rounded shape, so a plain fill squares off the corners the row
                // just rounded. The highlight has to carry them itself.
                topLeftRadius: root.topLeftRadius
                topRightRadius: root.topRightRadius
                bottomLeftRadius: root.expanded ? 0 : root.bottomLeftRadius
                bottomRightRadius: root.expanded ? 0 : root.bottomRightRadius
                color: headerArea.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
                opacity: root.isActive ? 0.4 : 1
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                spacing: 12

                Item {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "wifi"
                        iconSize: 24
                        opacity: 0.25
                        color: Appearance.colors.colOnLayer1
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.strength > 80 ? "android_wifi_4_bar"
                            : root.strength > 60 ? "android_wifi_3_bar"
                            : root.strength > 40 ? "wifi_2_bar"
                            : root.strength > 20 ? "wifi_1_bar" : "signal_wifi_0_bar"
                        fill: 1
                        iconSize: 24
                        color: root.isActive ? Appearance.colors.colOnSecondaryContainer
                            : Appearance.colors.colOnLayer1
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: root.ssid.length > 0 ? root.ssid : Translation.tr("Hidden network")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: root.isActive ? Appearance.colors.colOnSecondaryContainer
                            : Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: {
                            const parts = [];
                            if (root.isActive)
                                parts.push(Translation.tr("Connected"));
                            else if (root.isConnecting)
                                parts.push(Translation.tr("Connecting…"));
                            else if (root.isSaved)
                                parts.push(Translation.tr("Saved"));
                            parts.push(root.secure ? (root.accessPoint?.security ?? "")
                                : Translation.tr("Open"));
                            const band = root.accessPoint?.bandLabel ?? "";
                            if (band.length > 0)
                                parts.push(band);
                            parts.push(`${root.strength}%`);
                            return parts.filter(part => part.length > 0).join("  •  ");
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                MaterialSymbol {
                    visible: root.secure && !root.isConnecting
                    text: root.enterprise ? "badge" : "lock"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.normal
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.35)
                }

                MaterialLoadingIndicator {
                    visible: root.isConnecting
                    loading: root.isConnecting
                    implicitSize: 20
                }

                MaterialSymbol {
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                    opacity: headerArea.containsMouse ? 1 : 0.6
                    rotation: root.expanded ? 0 : -90

                    Behavior on rotation {
                        enabled: !root.performanceMode
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: root.expanded && actionsLoader.item ? actionsLoader.item.implicitHeight + 16 : 0
            clip: true

            Behavior on implicitHeight {
                enabled: !root.performanceMode
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            // Deferred: most rows are never opened, and this panel alone
            // carries two MaterialTextFields plus several buttons. Building
            // all of that immediately for every network the moment the list
            // mounts is what made the Wi-Fi tab heavy to open with more than
            // a handful in range. Built once on first expand (see wasExpanded)
            // and kept alive after that so a half-typed password isn't lost.
            Loader {
                id: actionsLoader
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                active: root.wasExpanded
                opacity: root.expanded ? 1 : 0

                Behavior on opacity {
                    enabled: !root.performanceMode
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                    }
                }

                sourceComponent: ColumnLayout {
                    spacing: 8

                    property alias identityText: identityField.text
                    property alias passwordText: passwordField.text

                    function focusIdentity(): void { identityField.forceActiveFocus(); }
                    function focusPassword(): void { passwordField.forceActiveFocus(); }

                    MaterialTextField {
                        id: identityField
                        Layout.fillWidth: true
                        visible: root.enterprise && (root.needsSecret || root.askingPassword)
                        placeholderText: Translation.tr("Identity (username)")
                        onAccepted: root.submit()
                    }

                    MaterialTextField {
                        id: passwordField
                        Layout.fillWidth: true
                        visible: root.needsSecret || root.askingPassword
                        echoMode: revealSecret.checked ? TextInput.Normal : TextInput.Password
                        placeholderText: Translation.tr("Password")
                        error: root.hasError
                        onAccepted: root.submit()
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: passwordField.visible
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Show password")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        StyledSwitch {
                            id: revealSecret
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.hasError && Network.lastWifiError.length > 0
                        wrapMode: Text.Wrap
                        text: Network.lastWifiError
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.m3colors.m3error
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: !root.isActive && (root.accessPoint?.bssid ?? "").length > 0
                        elide: Text.ElideRight
                        text: Translation.tr("Access point %1").arg(root.accessPoint?.bssid ?? "")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RippleButtonWithIcon {
                            visible: !root.isActive
                            materialIcon: "link"
                            mainText: root.needsSecret || root.askingPassword
                                ? Translation.tr("Join") : Translation.tr("Connect")
                            colBackground: Appearance.colors.colPrimary
                            colText: Appearance.colors.colOnPrimary
                            onClicked: root.submit()
                        }

                        RippleButtonWithIcon {
                            visible: root.isActive
                            materialIcon: "link_off"
                            mainText: Translation.tr("Disconnect")
                            onClicked: Network.disconnectWifiNetwork()
                        }

                        RippleButtonWithIcon {
                            visible: root.isSaved
                            materialIcon: "delete"
                            mainText: Translation.tr("Forget")
                            onClicked: Network.forgetWifiNetwork(root.ssid)
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        StyledText {
                            visible: root.savedProfile !== null
                            text: Translation.tr("Connect automatically")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        StyledSwitch {
                            visible: root.savedProfile !== null
                            checked: root.savedProfile?.autoconnect ?? false
                            onToggled: {
                                NetworkCommands.setAutoconnect(root.profileName, checked,
                                    () => Network.refreshSaved());
                                checked = Qt.binding(() => root.savedProfile?.autoconnect ?? false);
                            }
                        }
                    }
                }
            }
        }
    }
}
