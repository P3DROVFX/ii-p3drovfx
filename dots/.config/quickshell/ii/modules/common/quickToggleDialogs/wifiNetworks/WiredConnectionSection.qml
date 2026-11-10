import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    readonly property var wiredDevice: NetworkState.wiredDevice
    // The nmcli fallback reports a cable with no device object, so the section
    // follows the service flag, not the device.
    property bool wiredConnected: NetworkState.wiredConnected
    property string interfaceName: NetworkState.wiredInterface
    property int linkSpeed: NetworkState.wiredLinkSpeed
    readonly property string connectionName: NetworkState.wiredNetwork?.name
        ?? (root.interfaceName.length > 0 ? root.interfaceName : Translation.tr("Wired connection"))
    readonly property bool autoconnect: root.wiredDevice?.autoconnect ?? true
    readonly property bool managed: root.wiredDevice?.nmManaged ?? true
    property bool showActions: false

    // NetworkManager reports Mb/s; a gigabit port reads better as "1 Gb/s".
    function linkSpeedText(megabits: int): string {
        if (megabits >= 1000)
            return Translation.tr("%1 Gb/s").arg(String(Math.round(megabits / 100) / 10));
        return Translation.tr("%1 Mb/s").arg(String(megabits));
    }

    readonly property string statusText: {
        const parts = [Translation.tr("Connected")];
        if (root.linkSpeed > 0)
            parts.push(root.linkSpeedText(root.linkSpeed));
        // The profile name already says it when it is the interface itself.
        if (root.interfaceName.length > 0 && root.interfaceName !== root.connectionName)
            parts.push(root.interfaceName);
        return parts.join(" · ");
    }

    Layout.fillWidth: true
    spacing: 6
    visible: root.wiredConnected

    onWiredConnectedChanged: {
        if (!root.wiredConnected)
            root.showActions = false;
    }

    StyledText {
        Layout.fillWidth: true
        font.pixelSize: Appearance.font.pixelSize.normal
        font.bold: true
        color: Appearance.colors.colSubtext
        text: Translation.tr("Ethernet")
    }

    Rectangle {
        id: card

        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + 24
        radius: Appearance.rounding.large
        color: Appearance.colors.colPrimaryContainer
        clip: true

        Behavior on implicitHeight {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            id: cardColumn

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialShapeWrappedMaterialSymbol {
                    text: "lan"
                    fill: 1
                    iconSize: 24
                    padding: 10
                    shape: MaterialShape.Shape.Cookie4Sided
                    color: Appearance.colors.colPrimary
                    colSymbol: Appearance.colors.colOnPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.connectionName
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.statusText
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.8
                        }
                    }
                }

                RippleButton {
                    id: controlsButton

                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    toggled: root.showActions
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colBackgroundToggled: Appearance.colors.colPrimary
                    colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    onClicked: root.showActions = !root.showActions

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: root.showActions ? "expand_less" : "tune"
                        iconSize: 22
                        color: root.showActions ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnPrimaryContainer
                    }

                    StyledToolTip {
                        text: Translation.tr("Ethernet controls")
                    }
                }
            }

            // Controls fold out under the card instead of replacing it, so the
            // connection stays in view while it is being changed.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: root.showActions

                Repeater {
                    model: [
                        {
                            key: "autoconnect",
                            label: Translation.tr("Auto-connect"),
                            iconOn: "sync",
                            iconOff: "sync_disabled",
                            tipOn: Translation.tr("Connect automatically"),
                            tipOff: Translation.tr("Do not connect automatically")
                        },
                        {
                            key: "managed",
                            label: Translation.tr("Managed"),
                            iconOn: "settings_ethernet",
                            iconOff: "block",
                            tipOn: Translation.tr("Managed by NetworkManager"),
                            tipOff: Translation.tr("Not managed by NetworkManager")
                        }
                    ]

                    delegate: RippleButton {
                        id: controlChip

                        required property var modelData
                        readonly property bool isOn: controlChip.modelData.key === "autoconnect"
                            ? root.autoconnect : root.managed

                        Layout.fillWidth: true
                        implicitHeight: 40
                        enabled: root.wiredDevice !== null
                        buttonRadius: Appearance.rounding.full
                        toggled: controlChip.isOn
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colBackgroundToggled: Appearance.colors.colPrimary
                        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                        onClicked: {
                            if (controlChip.modelData.key === "autoconnect")
                                root.wiredDevice.autoconnect = !root.autoconnect;
                            else
                                root.wiredDevice.nmManaged = !root.managed;
                        }

                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: controlChip.isOn ? controlChip.modelData.iconOn : controlChip.modelData.iconOff
                                iconSize: 18
                                color: controlChip.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                text: controlChip.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: true
                                color: controlChip.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                            }
                        }

                        StyledToolTip {
                            text: controlChip.isOn ? controlChip.modelData.tipOn : controlChip.modelData.tipOff
                        }
                    }
                }
            }
        }
    }
}
