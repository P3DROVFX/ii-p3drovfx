import qs.modules.ii.bar.shared
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

StyledPopup {
    id: root
    stickyHover: true

    readonly property bool hasDevices: BluetoothStatus.connectedDevices.length > 0

    // Design Variables
    readonly property color colCard: Appearance.colors.colSurfaceContainerHigh
    readonly property color colName: Appearance.colors.colOnSurface
    readonly property color colBattery: Appearance.colors.colOnSecondaryContainer
    readonly property color colIconPrimary: Appearance.colors.colOnSecondaryContainer
    readonly property color colIconSecondary: Appearance.colors.colSecondary
    readonly property real cardHeight: 180
    readonly property int nameSize: Appearance.font.pixelSize.normal
    readonly property int batterySize: 42

    // Smartphone Coloring
    readonly property color colPhoneBody: Appearance.colors.colSecondaryContainer
    readonly property color colPhoneCameraFrame: Appearance.colors.colPrimary

    readonly property string iconEarbudsCushion: "../../../../../assets/images/devices/earbuds_cushion.svg"
    readonly property string iconEarbudsStem: "../../../../../assets/images/devices/earbuds_stem.svg"

    // Pixel Folder Assets
    readonly property string pixelPath: "../../../../../assets/images/devices/pixel/"
    readonly property string iconFrameBody: pixelPath + "frame_body.svg"
    readonly property string iconFrameDetails: pixelPath + "frame_details.svg"
    readonly property string iconCameraBase: pixelPath + "camera_base.svg"
    readonly property string iconCameraDetails: pixelPath + "camera_details.svg"

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 12

        // Empty state placeholder
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 140
            Layout.minimumWidth: 280
            visible: !root.hasDevices

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12

                MaterialShape {
                    Layout.alignment: Qt.AlignHCenter
                    shapeString: "Cookie6Sided"
                    implicitSize: 64
                    color: Appearance.colors.colSurfaceContainerHighest

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "bluetooth_disabled"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No devices connected")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        // Scalable list of devices
        Item {
            Layout.fillWidth: true
            Layout.minimumWidth: 280
            visible: root.hasDevices

            implicitHeight: {
                var c = rep.count;
                let h = 0;
                for (let i = 0; i < c; i++) {
                    let child = rep.itemAt(i);
                    if (child) {
                        h += child.implicitHeight;
                    }
                }
                if (c > 0)
                    h += (c - 1) * 12;
                if (h === 0 && c > 0)
                    return c * root.cardHeight + (c - 1) * 12;
                return h;
            }

            Repeater {
                id: rep
                model: BluetoothStatus.connectedDevices
                delegate: Rectangle {
                    id: deviceCard
                    width: parent.width
                    implicitHeight: root.cardHeight
                    radius: Appearance.rounding.large
                    color: root.colCard
                    clip: true

                    readonly property bool isEarbud: {
                        let icon = (modelData.icon || "").toLowerCase();
                        return icon.includes("headset") || icon.includes("headphone") || icon.includes("audio") || modelData.name.toLowerCase().includes("buds");
                    }

                    readonly property bool isPhone: {
                        let icon = (modelData.icon || "").toLowerCase();
                        let name = (modelData.name || "").toLowerCase();
                        return icon.includes("phone") || name.includes("phone") || name.includes("pixel") || name.includes("galaxy") || name.includes("iphone") || name.includes("moto") || name.includes("xperia");
                    }

                    readonly property int totalCount: BluetoothStatus.connectedDevices.length
                    property int vIndex: {
                        if (totalCount === 0)
                            return index;
                        let dIdx = root.hoverTarget ? root.hoverTarget.deviceIndex : 0;
                        return (index - dIdx + totalCount) % totalCount;
                    }

                    y: {
                        var _c = rep.count;
                        let yPos = 0;
                        for (let i = 0; i < _c; i++) {
                            let other = rep.itemAt(i);
                            if (other && other !== deviceCard && other.vIndex < vIndex) {
                                yPos += other.implicitHeight + 12;
                            }
                        }
                        return yPos;
                    }

                    readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6
                    
                    onStartAnimChanged: {
                        if (startAnim) {
                            deviceCard.opacity = 0.0;
                            deviceCard.scale = 0.85;
                            deviceCardTranslate.y = 25;

                            earbud1.opacity = 0.0;
                            earbud1.scale = 0.8;
                            earbud1Trans.y = 30;

                            earbud2.opacity = 0.0;
                            earbud2.scale = 0.8;
                            earbud2Trans.y = 30;

                            phoneContainer.opacity = 0.0;
                            phoneContainer.scale = 0.8;
                            phoneContainerTrans.y = 30;
                            
                            Qt.callLater(function() {
                                deviceCardAnim.start();
                                earbud1Anim.start();
                                earbud2Anim.start();
                                phoneContainerAnim.start();
                            });
                        }
                    }
                    
                    opacity: 0.0
                    scale: 1.0
                    transform: Translate {
                        id: deviceCardTranslate
                        y: (root.opened && root.popupOpenProgress > 0.6) ? 0 : 25
                    }
                    
                    SequentialAnimation {
                        id: deviceCardAnim
                        PauseAnimation { duration: 40 + index * 75 }
                        ParallelAnimation {
                            NumberAnimation { target: deviceCard; property: "opacity"; to: 1.0; duration: 300 }
                            NumberAnimation { target: deviceCard; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                            NumberAnimation { target: deviceCardTranslate; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                        }
                    }

                    Behavior on y {
                        NumberAnimation {
                            duration: 400
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.1
                        }
                    }

                    // Layout for Earbuds
                    Item {
                        anchors.fill: parent
                        anchors.margins: 18
                        visible: deviceCard.isEarbud

                        StyledText {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            text: modelData.name || Translation.tr("Unknown device")
                            font.pixelSize: root.nameSize
                            font.weight: Font.Medium
                            font.family: Appearance.font.family.title
                            color: root.colName
                            elide: Text.ElideRight
                            width: parent.width * 0.7
                        }

                        Item {
                            anchors.top: parent.top
                            anchors.topMargin: 50
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right

                            Item {
                                id: earbud1
                                width: 48
                                height: 76
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.leftMargin: 5

                                opacity: 0.0
                                scale: 0.8
                                transform: Translate {
                                    id: earbud1Trans
                                    y: 30
                                }

                                SequentialAnimation {
                                    id: earbud1Anim
                                    PauseAnimation { duration: 40 + index * 75 + 100 }
                                    ParallelAnimation {
                                        NumberAnimation { target: earbud1; property: "scale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                                        NumberAnimation { target: earbud1; property: "opacity"; from: 0.0; to: 1.0; duration: 350 }
                                        NumberAnimation { target: earbud1Trans; property: "y"; from: 30; to: 0; duration: 350; easing.type: Easing.OutCubic }
                                    }
                                }

                                Image {
                                    anchors.fill: parent
                                    source: root.iconEarbudsCushion
                                    sourceSize: Qt.size(width, height)
                                    layer.enabled: true
                                    layer.effect: ColorOverlay {
                                        color: root.colIconPrimary
                                    }
                                }

                                Image {
                                    anchors.fill: parent
                                    source: root.iconEarbudsStem
                                    sourceSize: Qt.size(width, height)
                                    layer.enabled: true
                                    layer.effect: ColorOverlay {
                                        color: root.colIconSecondary
                                    }
                                }
                            }

                            Item {
                                id: earbud2
                                width: 48
                                height: 76
                                anchors.bottom: earbud1.top
                                anchors.left: earbud1.right
                                anchors.leftMargin: 2
                                anchors.bottomMargin: -35

                                opacity: 0.0
                                scale: 0.8
                                transform: Translate {
                                    id: earbud2Trans
                                    y: 30
                                }

                                SequentialAnimation {
                                    id: earbud2Anim
                                    PauseAnimation { duration: 40 + index * 75 + 160 }
                                    ParallelAnimation {
                                        NumberAnimation { target: earbud2; property: "scale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                                        NumberAnimation { target: earbud2; property: "opacity"; from: 0.0; to: 1.0; duration: 350 }
                                        NumberAnimation { target: earbud2Trans; property: "y"; from: 30; to: 0; duration: 350; easing.type: Easing.OutCubic }
                                    }
                                }

                                Image {
                                    anchors.fill: parent
                                    source: root.iconEarbudsCushion
                                    sourceSize: Qt.size(width, height)
                                    mirror: true
                                    layer.enabled: true
                                    layer.effect: ColorOverlay {
                                        color: root.colIconPrimary
                                    }
                                }

                                Image {
                                    anchors.fill: parent
                                    source: root.iconEarbudsStem
                                    sourceSize: Qt.size(width, height)
                                    mirror: true
                                    layer.enabled: true
                                    layer.effect: ColorOverlay {
                                        color: root.colIconSecondary
                                    }
                                }
                            }

                            StyledText {
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                text: Math.round((modelData.battery ?? 0) * 100) + "%"
                                font.pixelSize: root.batterySize
                                font.weight: Font.Black
                                font.family: Appearance.font.family.main
                                color: (modelData.battery <= 0.15) ? Appearance.m3colors.m3error : root.colBattery
                            }
                        }
                    }

                    // Layout for Smartphone
                    Item {
                        anchors.fill: parent
                        visible: deviceCard.isPhone && !deviceCard.isEarbud

                        StyledText {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.topMargin: 18
                            anchors.leftMargin: 18
                            text: modelData.name || Translation.tr("Unknown device")
                            font.pixelSize: root.nameSize
                            font.weight: Font.Medium
                            font.family: Appearance.font.family.title
                            color: root.colName
                            elide: Text.ElideRight
                            width: parent.width * 0.6
                        }

                        StyledText {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.bottomMargin: 18
                            anchors.leftMargin: 18
                            text: Math.round((modelData.battery ?? 0) * 100) + "%"
                            font.pixelSize: root.batterySize
                            font.weight: Font.Black
                            font.family: Appearance.font.family.main
                            color: (modelData.battery <= 0.15) ? Appearance.m3colors.m3error : root.colBattery
                        }

                        // Smartphone Assembled
                        Item {
                            id: phoneContainer
                            width: 105
                            height: 127
                            anchors.right: parent.right
                            anchors.rightMargin: 15
                            anchors.bottom: parent.bottom

                            opacity: 0.0
                            scale: 0.8
                            transform: Translate {
                                id: phoneContainerTrans
                                y: 30
                            }

                            SequentialAnimation {
                                id: phoneContainerAnim
                                PauseAnimation { duration: 40 + index * 75 + 100 }
                                ParallelAnimation {
                                    NumberAnimation { target: phoneContainer; property: "scale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                                    NumberAnimation { target: phoneContainer; property: "opacity"; from: 0.0; to: 1.0; duration: 350 }
                                    NumberAnimation { target: phoneContainerTrans; property: "y"; from: 30; to: 0; duration: 350; easing.type: Easing.OutCubic }
                                }
                            }

                            // 1. Frame Body (The colorable part)
                            Image {
                                anchors.fill: parent
                                source: root.iconFrameBody
                                sourceSize: Qt.size(width, height)
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: root.colPhoneBody
                                }
                            }

                            // 2. Frame Details (Logo G, Antennas, Buttons - original detail preserved)
                            Image {
                                anchors.fill: parent
                                source: root.iconFrameDetails
                                sourceSize: Qt.size(width, height)
                                opacity: 0.8
                            }

                            // 3. Camera Module
                            Item {
                                width: 96
                                height: 30
                                anchors.top: parent.top
                                anchors.topMargin: 18
                                anchors.horizontalCenter: parent.horizontalCenter

                                // Camera Frame (Colored)
                                Image {
                                    anchors.fill: parent
                                    source: root.iconCameraBase
                                    sourceSize: Qt.size(width, height)
                                    layer.enabled: true
                                    layer.effect: ColorOverlay {
                                        color: root.colPhoneCameraFrame
                                    }
                                }

                                // Camera Details (Original)
                                Image {
                                    anchors.fill: parent
                                    source: root.iconCameraDetails
                                    sourceSize: Qt.size(width, height)
                                }
                            }
                        }
                    }

                    // Default Layout
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 4
                        visible: !deviceCard.isEarbud && !deviceCard.isPhone

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.name || Translation.tr("Unknown device")
                            font.pixelSize: Appearance.font.pixelSize.hugeass
                            font.weight: Font.Black
                            font.family: Appearance.font.family.title
                            color: Appearance.colors.colOnSurface
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        StyledText {
                            visible: modelData.batteryAvailable
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            text: Math.round((modelData.battery ?? 0) * 100) + "%"
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Bold
                            color: (modelData.battery <= 0.15) ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }
}
