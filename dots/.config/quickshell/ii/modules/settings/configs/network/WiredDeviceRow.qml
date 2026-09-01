import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One Ethernet port, with what it is and what is wrong with it.
 *
 * A wired port fails quietly in ways a wireless one cannot: the cable is out,
 * the switch negotiated 100 Mb/s on a gigabit link, or NetworkManager was told
 * to leave the device alone and is therefore never going to configure it. All
 * three look identical from the outside — no address — so the row names them.
 */
Rectangle {
    id: root

    required property var device
    property bool isFirst: false
    property bool isLast: false
    property bool expanded: false

    signal toggleRequested()

    readonly property string ifname: root.device?.name ?? ""
    readonly property bool isConnected: root.device?.connected ?? false
    readonly property bool hasLink: root.device?.hasLink ?? false
    readonly property bool managed: root.device?.nmManaged ?? true
    readonly property int linkSpeed: root.device?.linkSpeed ?? 0
    readonly property string mac: root.device?.address ?? ""

    property var details: ({})

    readonly property string hardware: {
        const parts = [root.details.vendor ?? "", root.details.product ?? ""];
        return parts.filter(part => part.length > 0).join(" ");
    }

    readonly property real outerRadius: Appearance.rounding.normal
    readonly property real innerRadius: Appearance.rounding.verysmall

    function refresh(): void {
        if (root.ifname.length === 0) {
            root.details = ({});
            return;
        }
        // Asking about a port is asynchronous, and a port can be unplugged
        // while the question is still in flight — which destroys this row
        // before the answer comes back to it.
        NetworkCommands.readDeviceDetails(root.ifname, result => {
            if (!root)
                return;
            root.details = result;
        });
    }

    component DetailRow: RowLayout {
        id: detailRow
        property string label: ""
        property string value: ""

        Layout.fillWidth: true
        visible: detailRow.value.length > 0
        spacing: 12

        StyledText {
            Layout.preferredWidth: 150
            text: detailRow.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: detailRow.value
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1
        }
    }

    Layout.fillWidth: true
    implicitHeight: rowContent.implicitHeight
    topLeftRadius: root.isFirst ? root.outerRadius : root.innerRadius
    topRightRadius: root.isFirst ? root.outerRadius : root.innerRadius
    bottomLeftRadius: root.isLast ? root.outerRadius : root.innerRadius
    bottomRightRadius: root.isLast ? root.outerRadius : root.innerRadius
    color: root.isConnected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
    clip: true

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    onIfnameChanged: root.refresh()
    onIsConnectedChanged: root.refresh()
    onHasLinkChanged: root.refresh()
    Component.onCompleted: root.refresh()

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
                onClicked: root.toggleRequested()
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
                opacity: root.isConnected ? 0.4 : 1
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                spacing: 12

                MaterialSymbol {
                    Layout.preferredWidth: 24
                    text: root.hasLink ? "settings_ethernet" : "cable"
                    fill: root.isConnected ? 1 : 0
                    iconSize: 24
                    color: root.isConnected ? Appearance.colors.colOnSecondaryContainer
                        : Appearance.colors.colOnLayer1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: root.hardware.length > 0 ? root.hardware : root.ifname
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: root.isConnected ? Appearance.colors.colOnSecondaryContainer
                            : Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: {
                            const parts = [root.ifname];
                            if (!root.managed)
                                parts.push(Translation.tr("Not managed"));
                            else if (root.isConnected)
                                parts.push((root.details.connection ?? "").length > 0
                                    ? root.details.connection : Translation.tr("Connected"));
                            else if (!root.hasLink)
                                parts.push(Translation.tr("No cable"));
                            else
                                parts.push(Translation.tr("Cable connected, not in use"));
                            if (root.hasLink && root.linkSpeed > 0)
                                parts.push(Translation.tr("%1 Mb/s").arg(root.linkSpeed));
                            return parts.join("  •  ");
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                MaterialSymbol {
                    visible: !root.managed
                    text: "block"
                    iconSize: Appearance.font.pixelSize.normal
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.35)
                }

                MaterialSymbol {
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                    opacity: headerArea.containsMouse ? 1 : 0.6
                    rotation: root.expanded ? 0 : -90

                    Behavior on rotation {
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
            implicitHeight: root.expanded ? actions.implicitHeight + 16 : 0
            clip: true

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            ColumnLayout {
                id: actions
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                opacity: root.expanded ? 1 : 0
                spacing: 8

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                    }
                }

                DetailRow {
                    label: Translation.tr("Hardware address")
                    value: root.mac
                }

                DetailRow {
                    label: Translation.tr("Driver")
                    value: root.details.driver ?? ""
                }

                DetailRow {
                    label: Translation.tr("Negotiated speed")
                    // A port that cannot report a rate answers "unknown" — USB
                    // tethering adapters do. The Addressing section drops its
                    // speed row outright in that case; do the same here rather
                    // than showing the user the word "unknown".
                    value: {
                        const speed = root.details.speed ?? "";
                        return speed === "unknown" ? "" : speed;
                    }
                }

                DetailRow {
                    label: Translation.tr("Cable")
                    value: {
                        const carrier = root.details.carrier ?? "";
                        if (carrier.length === 0)
                            return "";
                        return carrier === "on" ? Translation.tr("Plugged in")
                            : Translation.tr("Not plugged in");
                    }
                }

                DetailRow {
                    label: Translation.tr("MTU")
                    value: (root.details.mtu ?? 0) > 0 ? String(root.details.mtu) : ""
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8

                    RippleButtonWithIcon {
                        enabled: root.isConnected && root.managed
                        materialIcon: "link_off"
                        mainText: Translation.tr("Disconnect")
                        onClicked: root.device?.disconnect()
                    }

                    RippleButtonWithIcon {
                        enabled: root.ifname.length > 0
                        materialIcon: "refresh"
                        mainText: Translation.tr("Refresh")
                        onClicked: root.refresh()
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: Translation.tr("Connect automatically")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Translation.tr("Brings up a saved connection for this port without being asked.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    StyledSwitch {
                        checked: root.device?.autoconnect ?? true
                        enabled: root.managed
                        onToggled: {
                            if (root.device)
                                root.device.autoconnect = checked;
                            checked = Qt.binding(() => root.device?.autoconnect ?? true);
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: Translation.tr("Let NetworkManager configure this port")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Translation.tr("Turn this off only if something else owns the port — systemd-networkd, a bridge, or a container runtime. While it is off, nothing on this page can address the port.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    StyledSwitch {
                        checked: root.managed
                        onToggled: {
                            if (root.device)
                                root.device.nmManaged = checked;
                            checked = Qt.binding(() => root.device?.nmManaged ?? true);
                        }
                    }
                }
            }
        }
    }
}
