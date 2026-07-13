import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var device
    property bool isFirst: false
    property bool isLast: false
    property bool isPairedSection: true
    property int index: 0
    property int totalCount: 0
    property bool isProcessing: false

    Connections {
        target: root.device
        function onConnectedChanged() {
            root.isProcessing = false;
        }
    }

    property bool isActive: root.device?.connected ?? false

    implicitHeight: 56
    height: implicitHeight

    readonly property real rFull: height / 2
    readonly property real rOuter: Appearance?.rounding?.large ?? 23
    readonly property real rInner: Appearance?.rounding?.normal ?? 17

    // Sliding Flickable for Connected/Paired devices
    Flickable {
        id: flick
        visible: root.isPairedSection
        anchors.fill: parent
        contentWidth: flick.width * 2 + 8
        contentHeight: flick.height
        interactive: false
        clip: true

        property bool showActions: false
        contentX: showActions ? (flick.width + 8) : 0

        Behavior on contentX {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutExpo
            }
        }

        Row {
            height: flick.height
            spacing: 8

            // PAGE 1: Main Connected Info & Toggle button
            RowLayout {
                width: flick.width
                height: flick.height
                spacing: 8

                // Device Info Card
                Rectangle {
                    id: mainInfoCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: rFull
                    
                    color: {
                        if (isActive) {
                            return cardMouse.containsPress ? Appearance.colors.colPrimaryActive
                                   : cardMouse.containsMouse ? Appearance.colors.colPrimaryHover
                                   : Appearance.colors.colPrimary;
                        } else {
                            return cardMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                                   : cardMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
                                   : Appearance.colors.colSurfaceContainerHighest;
                        }
                    }

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root.isProcessing ? Qt.WaitCursor : Qt.PointingHandCursor
                        enabled: !root.isProcessing
                        onClicked: {
                            if (isActive) {
                                flick.showActions = true;
                            } else {
                                root.isProcessing = true;
                                root.device?.connect();
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 12

                        // Left Device Icon (Always static and clean)
                        Item {
                            width: 24
                            height: 24

                            MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 24
                                text: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon || "")
                                color: isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                            }
                        }

                        // Name
                        StyledText {
                            Layout.fillWidth: true
                            text: root.device?.name || Translation.tr("Unknown device")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: true
                            color: isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }

                        // Battery
                        StyledText {
                            visible: root.device?.connected && (root.device?.batteryAvailable ?? false)
                            text: Math.round((root.device?.battery ?? 0) * 100) + "%"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: true
                            color: isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                        }
                    }
                }

                // Action Button (Slide to Quick Settings / Cancel Connection)
                Rectangle {
                    id: actionBtn
                    Layout.preferredWidth: 56
                    Layout.fillHeight: true
                    radius: rFull
                    color: actionBtnMouse.containsPress ? (isActive ? Appearance.colors.colPrimaryActive : Appearance.colors.colSurfaceContainerHighestActive)
                            : actionBtnMouse.containsMouse ? (isActive ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover)
                            : (isActive ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest)

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }

                    MouseArea {
                        id: actionBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.isProcessing) {
                                root.isProcessing = false;
                                root.device?.disconnect();
                            } else {
                                flick.showActions = true;
                            }
                        }
                    }

                    Item {
                        anchors.centerIn: parent
                        width: 24
                        height: 24

                        // Checkmark/Bluetooth Icon
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: isActive ? "check" : "bluetooth"
                            iconSize: 24
                            color: isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                            visible: !root.isProcessing
                            opacity: actionBtnMouse.containsMouse ? 0 : 1
                            scale: actionBtnMouse.containsMouse ? 0.5 : 1
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                        }

                        // Arrow Back
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            iconSize: 24
                            color: isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                            visible: !root.isProcessing
                            opacity: actionBtnMouse.containsMouse ? 1 : 0
                            scale: actionBtnMouse.containsMouse ? 1 : 0.5
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                        }

                        // Rotating Cookie Loading shape
                        MaterialShape {
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            shape: MaterialShape.Shape.Cookie7Sided
                            color: isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                            visible: root.isProcessing
                            opacity: actionBtnMouse.containsMouse ? 0 : 1
                            scale: actionBtnMouse.containsMouse ? 0.5 : 1
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                            RotationAnimator on rotation {
                                from: 0
                                to: 360
                                duration: 2000
                                loops: Animation.Infinite
                                running: root.isProcessing
                            }
                        }

                        // Close symbol to abort connection
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 24
                            color: isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                            visible: root.isProcessing
                            opacity: actionBtnMouse.containsMouse ? 1 : 0
                            scale: actionBtnMouse.containsMouse ? 1 : 0.5
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                        }
                    }
                }
            }

            // PAGE 2: Quick Settings buttons
            RowLayout {
                width: flick.width
                height: flick.height
                spacing: 8

                // Back Button (arrow_forward)
                Rectangle {
                    id: backBtn
                    Layout.preferredWidth: 56
                    Layout.fillHeight: true
                    radius: rFull
                    color: backBtnMouse.containsPress ? (isActive ? Appearance.colors.colPrimaryActive : Appearance.colors.colSurfaceContainerHighestActive)
                            : backBtnMouse.containsMouse ? (isActive ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover)
                            : (isActive ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest)

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }

                    MouseArea {
                        id: backBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: flick.showActions = false
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "arrow_forward"
                        iconSize: 24
                        color: isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                    }
                }

                // Connect/Disconnect Button (outline / border and no fill)
                Rectangle {
                    id: disconnectBtn
                    Layout.fillWidth: true
                    Layout.preferredWidth: disconnectRow.implicitWidth + 32
                    Layout.fillHeight: true
                    radius: rFull
                    color: "transparent"
                    
                    border.width: 2
                    border.color: disconnectBtnMouse.containsMouse ? Appearance.colors.colOnSurface : Appearance.colors.colOutline

                    Behavior on border.color {
                        ColorAnimation { duration: 150 }
                    }

                    MouseArea {
                        id: disconnectBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root.isProcessing ? Qt.WaitCursor : Qt.PointingHandCursor
                        onClicked: {
                            root.isProcessing = true;
                            if (isActive) {
                                root.device?.disconnect();
                            } else {
                                root.device?.connect();
                            }
                            flick.showActions = false;
                        }
                    }

                    RowLayout {
                        id: disconnectRow
                        anchors.centerIn: parent
                        spacing: 6
                        
                        MaterialSymbol {
                            text: isActive ? "bluetooth_disabled" : "bluetooth"
                            iconSize: 18
                            color: disconnectBtnMouse.containsMouse ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        
                        StyledText {
                            text: isActive ? Translation.tr("Disconnect") : Translation.tr("Connect")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            color: disconnectBtnMouse.containsMouse ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }
                }

                // Forget Button (filled red error color)
                Rectangle {
                    id: forgetBtn
                    Layout.fillWidth: true
                    Layout.preferredWidth: forgetRow.implicitWidth + 32
                    Layout.fillHeight: true
                    radius: rFull
                    color: forgetBtnMouse.containsPress ? Appearance.colors.colErrorContainerActive
                            : forgetBtnMouse.containsMouse ? Appearance.colors.colErrorContainerHover
                            : Appearance.colors.colErrorContainer

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }

                    MouseArea {
                        id: forgetBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.device?.forget();
                            flick.showActions = false;
                        }
                    }

                    RowLayout {
                        id: forgetRow
                        anchors.centerIn: parent
                        spacing: 6
                        
                        MaterialSymbol {
                            text: "delete"
                            iconSize: 18
                            color: Appearance.colors.colOnErrorContainer
                        }
                        
                        StyledText {
                            text: Translation.tr("Forget")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            color: Appearance.colors.colOnErrorContainer
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    // Available devices list view card with dynamic corner radius
    Rectangle {
        id: availableCard
        visible: !root.isPairedSection
        anchors.fill: parent

        topLeftRadius: root.isFirst ? rOuter : rInner
        topRightRadius: root.isFirst ? rOuter : rInner
        bottomLeftRadius: root.isLast ? rOuter : rInner
        bottomRightRadius: root.isLast ? rOuter : rInner

        color: availMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
               : availMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
               : Appearance.colors.colSurfaceContainerHighest

        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        MouseArea {
            id: availMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.isProcessing ? Qt.WaitCursor : Qt.PointingHandCursor
            enabled: !root.isProcessing
            onClicked: {
                root.isProcessing = true;
                root.device?.connect();
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 12

            // Left icon or Loading cookie
            Item {
                width: 24
                height: 24

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 24
                    text: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon || "")
                    color: Appearance.colors.colOnSurface
                    opacity: root.isProcessing ? 0 : 1
                    scale: root.isProcessing ? 0.5 : 1
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                }

                MaterialShape {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    shape: MaterialShape.Shape.Cookie7Sided
                    color: Appearance.colors.colOnSurface
                    opacity: root.isProcessing ? 1 : 0
                    scale: root.isProcessing ? 1 : 0.5
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                    RotationAnimator on rotation {
                        from: 0
                        to: 360
                        duration: 2000
                        loops: Animation.Infinite
                        running: root.isProcessing
                    }
                }
            }

            // Name
            StyledText {
                Layout.fillWidth: true
                text: root.device?.name || Translation.tr("Unknown device")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.bold: true
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }

            // Chevron on the right
            MaterialSymbol {
                text: "chevron_right"
                iconSize: 24
                color: Appearance.colors.colSubtext
                opacity: root.isProcessing ? 0 : 0.7
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }
    }
}
