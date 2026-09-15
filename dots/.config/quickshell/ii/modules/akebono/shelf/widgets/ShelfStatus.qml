pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
    id: root
    property real barHeight: 54
    property var shelf

    readonly property real iconSize: Math.round(barHeight * 0.38)

    readonly property var statusCfg: Config.options.akebono?.shelf.status
    readonly property bool showNotifications: statusCfg?.notifications ?? true
    readonly property bool showMic: statusCfg?.mic ?? true
    readonly property bool showCapsLock: statusCfg?.capsLock ?? true
    readonly property bool showKeyboardLayout: statusCfg?.keyboardLayout ?? false
    readonly property bool showBluetooth: statusCfg?.bluetooth ?? true
    readonly property bool showVolume: statusCfg?.volume ?? true
    readonly property bool showNetwork: statusCfg?.network ?? true
    readonly property bool showBattery: statusCfg?.battery ?? true

    readonly property bool sinkMuted: Audio.sink?.audio?.muted ?? false
    readonly property bool micMuted: Audio.source?.audio?.muted ?? false
    readonly property real volume: Audio.sink?.audio?.volume ?? 0
    readonly property int batteryLevel: Math.round(Battery.percentage * 6)
    readonly property bool batteryLow: Battery.isLow && !Battery.isCharging
    property bool capsLockOn: false

    function abbreviateLayoutCode(fullCode) {
        return fullCode.split(':').map(layout => {
            const baseLayout = layout.split('-')[0];
            return baseLayout.slice(0, 4);
        }).join("\n");
    }

    implicitWidth: pill.implicitWidth
    implicitHeight: barHeight * 0.7
    Layout.alignment: Qt.AlignVCenter

    Timer {
        interval: 200
        running: root.showCapsLock
        repeat: true
        onTriggered: checkCapsLock.running = true
    }

    Process {
        id: checkCapsLock
        command: ["bash", "-c", "cat /sys/class/leds/*capslock/brightness 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: root.capsLockOn = (text.trim() === "1")
        }
    }

    ShelfPill {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: statusRow.implicitWidth + 20
        implicitHeight: root.barHeight * 0.7
        hovered: statusMouse.containsMouse || (root.shelf?.qsOpen ?? false)

        Component.onCompleted: root.shelf.registerStatusAnchor(pill)
        Component.onDestruction: root.shelf.unregisterStatusAnchor(pill)
        onXChanged: root.shelf.publishStatus()

        WheelHandler {
            onWheel: (event) => {
                if (event.angleDelta.y < 0)
                    Audio.decrementVolume();
                else if (event.angleDelta.y > 0)
                    Audio.incrementVolume();
            }
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        }

        RowLayout {
            id: statusRow
            anchors.centerIn: parent
            spacing: 0
            readonly property real realSpacing: 7

            Revealer {
                reveal: root.showNotifications && (Notifications.silent || Notifications.unread > 0)
                Layout.fillHeight: true
                Layout.rightMargin: reveal ? statusRow.realSpacing : 0
                Behavior on Layout.rightMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                MaterialSymbol {
                    id: notifSymbol
                    readonly property bool showUnreadCount: Config.options.bar.indicators.notifications.showUnreadCount
                    text: Notifications.silent ? "notifications_paused" : "notifications"
                    iconSize: root.iconSize
                    color: Appearance.colors.colOnLayer1

                    Rectangle {
                        visible: !Notifications.silent && Notifications.unread > 0
                        anchors {
                            right: parent.right
                            top: parent.top
                            rightMargin: notifSymbol.showUnreadCount ? 0 : 1
                            topMargin: notifSymbol.showUnreadCount ? 0 : 3
                        }
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimary
                        z: 1
                        implicitHeight: notifSymbol.showUnreadCount ? Math.max(unreadText.implicitWidth, unreadText.implicitHeight) : 7
                        implicitWidth: implicitHeight

                        StyledText {
                            id: unreadText
                            visible: notifSymbol.showUnreadCount
                            anchors.centerIn: parent
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnPrimary
                            text: Notifications.unread
                        }
                    }
                }
            }

            Revealer {
                reveal: root.showMic && root.micMuted
                Layout.fillHeight: true
                Layout.rightMargin: reveal ? statusRow.realSpacing : 0
                Behavior on Layout.rightMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                MaterialSymbol {
                    text: "mic_off"
                    iconSize: root.iconSize
                    color: Appearance.colors.colOnLayer1
                }
            }

            Revealer {
                reveal: root.showCapsLock && root.capsLockOn
                Layout.fillHeight: true
                Layout.rightMargin: reveal ? statusRow.realSpacing : 0
                Behavior on Layout.rightMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                MaterialSymbol {
                    text: "font_download"
                    fill: 1
                    iconSize: root.iconSize
                    color: Appearance.colors.colOnLayer1
                }
            }

            Revealer {
                reveal: root.showKeyboardLayout && HyprlandXkb.layoutCodes.length > 1
                Layout.fillHeight: true
                Layout.rightMargin: reveal ? statusRow.realSpacing : 0
                Behavior on Layout.rightMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                StyledText {
                    text: root.abbreviateLayoutCode(HyprlandXkb.currentLayoutCode)
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: text.includes("\n") ? Appearance.font.pixelSize.smallie : Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    animateChange: true
                }
            }

            Revealer {
                reveal: root.showBluetooth && BluetoothStatus.available && BluetoothStatus.enabled
                Layout.fillHeight: true
                Layout.rightMargin: reveal ? statusRow.realSpacing : 0
                Behavior on Layout.rightMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                MaterialSymbol {
                    text: BluetoothStatus.connected ? "bluetooth_connected" : "bluetooth"
                    iconSize: root.iconSize
                    color: Appearance.colors.colOnLayer1
                }
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                visible: root.showVolume
                Layout.rightMargin: (root.showNetwork || (root.showBattery && Battery.available)) ? statusRow.realSpacing : 0
                text: root.sinkMuted ? "volume_off"
                    : root.volume < 0.01 ? "volume_mute"
                    : root.volume < 0.5 ? "volume_down"
                    : "volume_up"
                iconSize: root.iconSize
                color: Appearance.colors.colOnLayer1
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                visible: root.showNetwork
                Layout.rightMargin: (root.showBattery && Battery.available) ? statusRow.realSpacing : 0
                text: Network.materialSymbol
                iconSize: root.iconSize
                color: Appearance.colors.colOnLayer1
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                visible: root.showBattery && Battery.available
                text: (Battery.isCharging && Battery.percentage < 1) ? "battery_android_bolt"
                    : root.batteryLow ? "battery_android_alert"
                    : root.batteryLevel >= 6 ? "battery_android_full"
                    : `battery_android_${root.batteryLevel}`
                iconSize: root.iconSize
                color: root.batteryLow ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
            }
        }

        MouseArea {
            id: statusMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.shelf.toggleQuickSettings()
        }
    }
}
