import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    readonly property var wiredDevice: NetworkState.wiredDevice
    readonly property bool wiredConnected: root.wiredDevice?.connected ?? false
    readonly property string connectionName: NetworkState.wiredNetwork?.name
        ?? Translation.tr("Wired connection")
    readonly property bool autoconnect: root.wiredDevice?.autoconnect ?? true
    readonly property bool managed: root.wiredDevice?.nmManaged ?? true
    property bool showActions: false

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
        text: Translation.tr("Connected Ethernet")
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: 56

        Flickable {
            id: actionsFlick

            anchors.fill: parent
            contentWidth: actionsFlick.width * 2 + 8
            contentHeight: actionsFlick.height
            interactive: false
            clip: true
            contentX: root.showActions ? actionsFlick.width + 8 : 0

            Behavior on contentX {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            Row {
                height: actionsFlick.height
                spacing: 8

                // PAGE 1: the connected Ethernet pill, matching Connected Wi-Fi.
                RowLayout {
                    width: actionsFlick.width
                    height: actionsFlick.height
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimary

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 20
                                rightMargin: 16
                            }
                            spacing: 10

                            MaterialSymbol {
                                text: "lan"
                                fill: 1
                                iconSize: 22
                                color: Appearance.colors.colOnPrimary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: root.connectionName
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.bold: true
                                    color: Appearance.colors.colOnPrimary
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: NetworkState.wiredLinkSpeed > 0
                                        ? Translation.tr("Connected · %1 Mb/s").arg(String(NetworkState.wiredLinkSpeed))
                                        : Translation.tr("Connected")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnPrimary
                                    opacity: 0.72
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 56
                        Layout.fillHeight: true
                        radius: Appearance.rounding.full
                        color: actionsMouse.containsPress ? Appearance.colors.colPrimaryActive
                            : actionsMouse.containsMouse ? Appearance.colors.colPrimaryHover
                            : Appearance.colors.colPrimary

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        MouseArea {
                            id: actionsMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showActions = true
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: actionsMouse.containsMouse ? "arrow_back" : "check"
                            iconSize: 22
                            color: Appearance.colors.colOnPrimary
                        }

                        StyledToolTip {
                            text: Translation.tr("Ethernet controls")
                            alternativeVisibleCondition: actionsMouse.containsMouse
                            extraVisibleCondition: false
                        }
                    }
                }

                // PAGE 2: compact inline toggles, using the Wi-Fi action-page pattern.
                RowLayout {
                    width: actionsFlick.width
                    height: actionsFlick.height
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 56
                        Layout.fillHeight: true
                        radius: Appearance.rounding.full
                        color: backMouse.containsPress ? Appearance.colors.colPrimaryActive
                            : backMouse.containsMouse ? Appearance.colors.colPrimaryHover
                            : Appearance.colors.colPrimary

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        MouseArea {
                            id: backMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showActions = false
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "arrow_forward"
                            iconSize: 24
                            color: Appearance.colors.colOnPrimary
                        }

                        StyledToolTip {
                            text: Translation.tr("Back")
                            alternativeVisibleCondition: backMouse.containsMouse
                            extraVisibleCondition: false
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.full
                        color: root.autoconnect
                            ? (autoconnectMouse.containsPress ? Appearance.colors.colPrimaryActive
                                : autoconnectMouse.containsMouse ? Appearance.colors.colPrimaryHover
                                : Appearance.colors.colPrimary)
                            : (autoconnectMouse.containsPress ? Appearance.colors.colLayer3Active
                                : autoconnectMouse.containsMouse ? Appearance.colors.colLayer3Hover
                                : Appearance.colors.colLayer3)

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        MouseArea {
                            id: autoconnectMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: root.wiredDevice !== null
                            onClicked: root.wiredDevice.autoconnect = !root.autoconnect
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: root.autoconnect ? "sync" : "sync_disabled"
                                iconSize: 18
                                color: root.autoconnect ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnLayer3
                            }

                            StyledText {
                                text: Translation.tr("Auto")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: true
                                color: root.autoconnect ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnLayer3
                            }
                        }

                        StyledToolTip {
                            text: root.autoconnect
                                ? Translation.tr("Connect automatically")
                                : Translation.tr("Do not connect automatically")
                            alternativeVisibleCondition: autoconnectMouse.containsMouse
                            extraVisibleCondition: false
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.full
                        color: root.managed
                            ? (managedMouse.containsPress ? Appearance.colors.colPrimaryActive
                                : managedMouse.containsMouse ? Appearance.colors.colPrimaryHover
                                : Appearance.colors.colPrimary)
                            : (managedMouse.containsPress ? Appearance.colors.colLayer3Active
                                : managedMouse.containsMouse ? Appearance.colors.colLayer3Hover
                                : Appearance.colors.colLayer3)

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        MouseArea {
                            id: managedMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: root.wiredDevice !== null
                            onClicked: root.wiredDevice.nmManaged = !root.managed
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: root.managed ? "settings_ethernet" : "block"
                                iconSize: 18
                                color: root.managed ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnLayer3
                            }

                            StyledText {
                                text: Translation.tr("Managed")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: true
                                color: root.managed ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnLayer3
                            }
                        }

                        StyledToolTip {
                            text: root.managed
                                ? Translation.tr("Managed by NetworkManager")
                                : Translation.tr("Not managed by NetworkManager")
                            alternativeVisibleCondition: managedMouse.containsMouse
                            extraVisibleCondition: false
                        }
                    }
                }
            }
        }
    }
}
