import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    property bool showDate: Config.options.bar.verbose
    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: true // Forced expressive

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : pill.implicitWidth
    implicitHeight: vertical ? pill.implicitHeight : Appearance.sizes.baseBarHeight

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutQuint
        }
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutQuint
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }
    }

    Canvas {
        id: pill
        visible: root.isMaterial
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.vertical ? 0 : -1

        property color pillColor: GlobalStates.sidebarRightOpen 
            ? (mouseArea.containsMouse ? Appearance.colors.colLayer4Hover : "transparent")
            : (mouseArea.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimaryContainer)

        property color borderColor: GlobalStates.sidebarRightOpen 
            ? Appearance.colors.colPrimary
            : "transparent"

        property real borderWidth: GlobalStates.sidebarRightOpen ? 1.5 : 0
        property real dashLength: GlobalStates.sidebarRightOpen ? 6 : 0
        property real gapLength: GlobalStates.sidebarRightOpen ? 4 : 0
        property real radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full
        property real dashOffset: 0

        implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth - 8 : flow.implicitWidth + 10
        implicitHeight: root.vertical ? flow.implicitHeight + 10 : Appearance.sizes.baseBarHeight - 8

        width: implicitWidth
        height: implicitHeight

        Behavior on implicitWidth {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutQuint
            }
        }

        Behavior on implicitHeight {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutQuint
            }
        }

        onPillColorChanged: requestPaint()
        onBorderColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onDashOffsetChanged: requestPaint()

        Behavior on pillColor {
            ColorAnimation { duration: 150 }
        }

        onPaint: {
            if (width <= 0 || height <= 0) return;
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            var w = width;
            var h = height;
            var bw = borderWidth;
            var r = Math.min(radius, (w - 2 * bw) / 2, (h - 2 * bw) / 2);

            ctx.save();

            ctx.beginPath();
            ctx.moveTo(bw + r, bw);
            ctx.arcTo(w - bw, bw, w - bw, h - bw, r);
            ctx.arcTo(w - bw, h - bw, bw, h - bw, r);
            ctx.arcTo(bw, h - bw, bw, bw, r);
            ctx.arcTo(bw, bw, w - bw, bw, r);
            ctx.closePath();

            ctx.fillStyle = pillColor;
            ctx.fill();

            if (bw > 0) {
                ctx.strokeStyle = borderColor;
                ctx.lineWidth = bw;
                ctx.setLineDash([dashLength, gapLength]);
                ctx.lineDashOffset = dashOffset;
                ctx.stroke();
            }

            ctx.restore();
        }
    }

    NumberAnimation {
        id: dashSlideAnim
        target: pill
        property: "dashOffset"
        from: 0
        to: 20
        duration: 800
        easing.type: Easing.OutCubic
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) {
                dashSlideAnim.restart();
            } else {
                pill.dashOffset = 0;
            }
        }
    }

    Grid {
        id: flow
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.vertical ? 0 : -1
        flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
        columns: root.vertical ? 1 : Math.max(1, flow.visibleChildren.length)
        spacing: isMaterial ? 6 : 10

        move: Transition {
            NumberAnimation { properties: "x,y"; duration: 250; easing.type: Easing.OutQuint }
        }

        Revealer {
            reveal: Config.options.bar.dashboardButton.showVolume
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: volumeWrapper
                vertical: root.vertical
                MaterialSymbol {
                    width: parent.width
                    height: parent.height
                    text: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
                    iconSize: Appearance.font.pixelSize.larger
                    color: volumeWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showMic && (Audio.source?.audio?.muted ?? false)
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: micWrapper
                vertical: root.vertical
                MaterialSymbol {
                    width: parent.width
                    height: parent.height
                    text: "mic_off"
                    iconSize: Appearance.font.pixelSize.larger
                    color: micWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showNetwork
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: netWrapper
                vertical: root.vertical

                readonly property string fullWifiIcon: {
                    var sym = Network.materialSymbol;
                    if (sym.startsWith("android_wifi") || sym.startsWith("wifi") || sym.startsWith("signal_wifi")) return "wifi";
                    return "";
                }

                MaterialSymbol {
                    visible: netWrapper.fullWifiIcon !== ""
                    width: parent.width
                    height: parent.height
                    text: netWrapper.fullWifiIcon
                    iconSize: Appearance.font.pixelSize.larger
                    opacity: 0.3
                    color: netWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                }

                MaterialSymbol {
                    width: parent.width
                    height: parent.height
                    text: Network.materialSymbol
                    iconSize: Appearance.font.pixelSize.larger
                    color: netWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showBluetooth && BluetoothStatus.available
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: btWrapper
                vertical: root.vertical
                MaterialSymbol {
                    width: parent.width
                    height: parent.height
                    text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                    iconSize: Appearance.font.pixelSize.larger
                    color: btWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showNotifications && (Notifications.silent || Notifications.unread > 0)
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: notifWrapper
                vertical: root.vertical
                Loader {
                    id: notifLoader
                    source: "ExpressiveNotificationUnreadCount.qml"
                    anchors.fill: parent
                    Binding {
                        target: notifLoader.item
                        property: "width"
                        value: notifLoader.width
                        when: notifLoader.item !== null
                    }
                    Binding {
                        target: notifLoader.item
                        property: "height"
                        value: notifLoader.height
                        when: notifLoader.item !== null
                    }
                    Binding {
                        target: notifLoader.item
                        property: "color"
                        value: notifWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                        when: notifLoader.item !== null
                    }
                    Binding {
                        target: notifLoader.item
                        property: "iconSize"
                        value: Appearance.font.pixelSize.larger
                        when: notifLoader.item !== null
                    }
                }
            }
        }
    }
}

