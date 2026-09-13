import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One Bluetooth device, with everything it can be asked to do folded away until
 * the row is opened. Pairing, trusting, blocking, renaming and forgetting all
 * happen in place — this page is the dialog.
 */
Rectangle {
    id: root

    required property BluetoothDevice device
    property bool isFirst: false
    property bool isLast: false
    property bool expanded: false
    // Sticky: the actions panel below is built once, on first expand.
    property bool wasExpanded: false
    onExpandedChanged: if (root.expanded) root.wasExpanded = true

    readonly property string deviceName: {
        const name = root.device?.name ?? "";
        if (name.length > 0)
            return name;
        return root.device?.deviceName ?? root.device?.address ?? "";
    }
    readonly property string address: root.device?.address ?? ""
    readonly property bool isConnected: root.device?.connected ?? false
    readonly property bool isPaired: root.device?.paired ?? false
    readonly property bool isPairing: root.device?.pairing ?? false
    readonly property int state: root.device?.state ?? BluetoothDeviceState.Disconnected
    readonly property bool busy: root.isPairing || root.state === BluetoothDeviceState.Connecting
        || root.state === BluetoothDeviceState.Disconnecting
    readonly property int battery: Math.round((root.device?.battery ?? 0) * 100)
    readonly property bool hasBattery: (root.device?.batteryAvailable ?? false) && root.battery > 0

    readonly property real outerRadius: Appearance.rounding.normal
    readonly property real innerRadius: Appearance.rounding.verysmall
    readonly property bool performanceMode: Config.options?.appearance?.settingsPerformanceMode ?? false

    // An unpaired device has to be paired before it can carry anything, so the
    // obvious action on it is pairing rather than a connection that would fail.
    function primaryAction(): void {
        if (!root.device)
            return;
        if (root.isPairing) {
            root.device.cancelPair();
            return;
        }
        if (!root.isPaired) {
            root.device.pair();
            return;
        }
        if (root.isConnected)
            root.device.disconnect();
        else
            root.device.connect();
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
        // createObject runs once per row at construction regardless of
        // `enabled`, so performance mode skips it outright — with several
        // devices around that's several fewer objects built the moment the
        // list mounts.
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
                opacity: root.isConnected ? 0.4 : 1
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                spacing: 12

                MaterialSymbol {
                    Layout.preferredWidth: 24
                    text: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon ?? "")
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
                        text: root.deviceName
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: root.isConnected ? Appearance.colors.colOnSecondaryContainer
                            : Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: {
                            const parts = [];
                            if (root.isPairing)
                                parts.push(Translation.tr("Pairing…"));
                            else if (root.state === BluetoothDeviceState.Connecting)
                                parts.push(Translation.tr("Connecting…"));
                            else if (root.state === BluetoothDeviceState.Disconnecting)
                                parts.push(Translation.tr("Disconnecting…"));
                            else if (root.isConnected)
                                parts.push(Translation.tr("Connected"));
                            else if (root.isPaired)
                                parts.push(Translation.tr("Paired"));
                            if (root.hasBattery)
                                parts.push(Translation.tr("Battery %1%").arg(root.battery));
                            if (root.device?.blocked ?? false)
                                parts.push(Translation.tr("Blocked"));
                            parts.push(root.address);
                            return parts.filter(part => part.length > 0).join("  •  ");
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                MaterialSymbol {
                    visible: root.device?.trusted ?? false
                    text: "verified_user"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.normal
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.35)
                }

                MaterialLoadingIndicator {
                    visible: root.busy
                    loading: root.busy
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

            // Deferred: most discovered/paired devices are never opened, and
            // this panel builds a MaterialTextField plus several buttons and
            // switches. Building all of that immediately for every device the
            // moment the list mounts is what made the Bluetooth tab heavy to
            // open with several devices around. Built once on first expand.
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

                sourceComponent: BluetoothDeviceActions {
                    device: root.device
                }
            }
        }
    }
}
