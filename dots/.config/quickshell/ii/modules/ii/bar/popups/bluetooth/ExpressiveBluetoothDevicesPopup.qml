import qs.modules.ii.bar.shared
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.bluetooth
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

StyledPopup {
    id: root
    stickyHover: true
    readonly property bool notifIsLeft: (Config.options.notifications.position ?? "top_right").endsWith("left")
    readonly property bool notifIsRight: (Config.options.notifications.position ?? "top_right").endsWith("right")
    readonly property bool sidebarOccludesPopup:
        (root.notifIsLeft && GlobalStates.effectiveLeftOpen)
        || (root.notifIsRight && GlobalStates.effectiveRightOpen)

    active: !sidebarOccludesPopup && (_computedActive || _isClosing)

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

    function getDeviceImageSource(device) {
        if (!device)
            return "";
        
        if (Config.options && Config.options.bluetoothDeviceImages) {
            let custom = Config.options.bluetoothDeviceImages.find(d => d.mac === device.address);
            if (custom && custom.image) {
                return "file://" + Directories.shellConfig + "/bluetooth_images/" + custom.image;
            }
        }

        const mac = (device.address || "").replace(/:/g, "_").toUpperCase();
        const name = (device.name || device.alias || "").toLowerCase();
        const basePath = Directories.assetsPath ? ("file://" + Directories.assetsPath + "/images/devices/") : "";

        if (mac === "E8_EE_CC_96_31_3A" || name.includes("q30") || name.includes("soundcore life q30") || name.includes("soundcore")) {
            return basePath + "anker_q30_.png";
        }
        if (mac === "68_7D_6B_94_0B_C2" || name.includes("buds 3 pro") || name.includes("buds3 pro") || name.includes("galaxy buds 3 pro")) {
            return basePath + "galaxy_buds_3_pro.png";
        }
        if (name.includes("galaxy buds 3") || name.includes("buds 3") || name.includes("buds3")) {
            return basePath + "galaxy_buds_3.png";
        }
        if (mac === "64_1B_2F_9B_95_CE" || name.includes("s23")) {
            return basePath + "samsung_s23.png";
        }
        if (name.includes("s24")) {
            return basePath + "samsung_s24_ultra.png";
        }
        if (name.includes("pixel buds") || name.includes("buds pro") || name.includes("buds fe") || name.includes("buds")) {
            return basePath + "pixel_buds.png";
        }
        if (name.includes("xbox") || name.includes("elite")) {
            return basePath + "xbox_elite_series_2.png";
        }

        return "";
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 12

        // Empty state placeholder
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 140
            Layout.minimumWidth: 320
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
            Layout.minimumWidth: 320
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
                    implicitHeight: (deviceCard.hasNoise && !deviceCard.isPhone) ? 220 : root.cardHeight
                    radius: Appearance.rounding.large
                    color: root.colCard
                    clip: true

                    readonly property var devBattery: EarbudsControlService.batteryInfo(modelData)
                    readonly property var devNoise: EarbudsControlService.noiseControl(modelData)
                    readonly property var leftComp: devBattery ? devBattery.left : null
                    readonly property var rightComp: devBattery ? devBattery.right : null
                    readonly property var caseComp: devBattery ? devBattery.case : null
                    readonly property bool hasIndividualBatteries: devBattery && devBattery.available && (leftComp !== null && leftComp.available) && (rightComp !== null && rightComp.available)
                    readonly property int aggregatePercent: EarbudsControlService.primaryBatteryPercent(modelData) ?? Math.round((modelData.battery ?? 0) * 100)
                    readonly property bool hasNoise: devNoise && devNoise.available && devNoise.modes.length > 0
                    readonly property string customDeviceImg: root.getDeviceImageSource(modelData)
                    readonly property bool hasCustomImg: customDeviceImg !== ""

                    readonly property bool isEarbud: {
                        if (hasIndividualBatteries) return true;
                        let name = (modelData.name || "").toLowerCase();
                        if (name.includes("q30") || name.includes("soundcore") || name.includes("wh-") || name.includes("headphones") || name.includes("headset"))
                            return false;
                        return name.includes("buds") || name.includes("airpods") || name.includes("ear") || name.includes("linkbuds") || name.includes("wf-");
                    }

                    readonly property bool isPhone: {
                        if (isEarbud) return false;
                        let icon = (modelData.icon || "").toLowerCase();
                        let name = (modelData.name || "").toLowerCase();
                        return icon.includes("phone") || name.includes("phone") || name.includes("pixel") || name.includes("galaxy s") || name.includes("iphone") || name.includes("moto") || name.includes("xperia");
                    }

                    readonly property bool isHeadphone: !isEarbud && !isPhone && (
                        (modelData.icon || "").toLowerCase().includes("headphone") ||
                        (modelData.icon || "").toLowerCase().includes("headset") ||
                        (modelData.icon || "").toLowerCase().includes("audio") ||
                        (modelData.name || "").toLowerCase().includes("q30") ||
                        (modelData.name || "").toLowerCase().includes("soundcore") ||
                        (modelData.name || "").toLowerCase().includes("wh-")
                    )

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

                    Connections {
                        target: root
                        function onPopupOpenProgressChanged() {
                            if (root && root.popupOpenProgress === 0.0) {
                                deviceCardAnim.stop();
                                earbud1Anim.stop();
                                earbud2Anim.stop();
                                phoneContainerAnim.stop();

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
                            }
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
                        anchors.margins: 16
                        visible: deviceCard.isEarbud

                        RowLayout {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 8

                            StyledText {
                                text: modelData.name || Translation.tr("Unknown device")
                                font.pixelSize: root.nameSize
                                font.weight: Font.Medium
                                font.family: Appearance.font.family.title
                                color: root.colName
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            // Case battery badge if reported
                            RowLayout {
                                visible: deviceCard.caseComp !== null && deviceCard.caseComp.available
                                spacing: 4

                                Rectangle {
                                    implicitWidth: caseBadgeRow.implicitWidth + 10
                                    implicitHeight: 20
                                    radius: Appearance.rounding.full
                                    color: (deviceCard.caseComp && deviceCard.caseComp.charging) ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest

                                    RowLayout {
                                        id: caseBadgeRow
                                        anchors.centerIn: parent
                                        spacing: 2

                                        MaterialSymbol {
                                            visible: Boolean(deviceCard.caseComp && deviceCard.caseComp.charging)
                                            text: "bolt"
                                            iconSize: 12
                                            color: Appearance.colors.colPrimary
                                        }

                                        StyledText {
                                            text: "Case " + (deviceCard.caseComp ? deviceCard.caseComp.level : 0) + "%"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: (deviceCard.caseComp && deviceCard.caseComp.charging) ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            anchors.top: parent.top
                            anchors.topMargin: 38
                            anchors.bottom: deviceCard.hasNoise ? noiseSelectorEarbuds.top : parent.bottom
                            anchors.bottomMargin: deviceCard.hasNoise ? 8 : 0
                            anchors.left: parent.left
                            anchors.right: parent.right

                            Item {
                                id: earbud1
                                width: 48
                                height: 76
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.leftMargin: 8

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

                            // Left bud badge (cleanly positioned above earbud 1)
                            Rectangle {
                                id: leftBadge
                                visible: deviceCard.hasIndividualBatteries
                                anchors.bottom: earbud1.top
                                anchors.bottomMargin: 4
                                anchors.horizontalCenter: earbud1.horizontalCenter
                                implicitWidth: leftBadgeRow.implicitWidth + 10
                                implicitHeight: 20
                                radius: Appearance.rounding.full
                                color: (deviceCard.leftComp && deviceCard.leftComp.charging) ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest

                                RowLayout {
                                    id: leftBadgeRow
                                    anchors.centerIn: parent
                                    spacing: 3

                                    MaterialSymbol {
                                        visible: Boolean(deviceCard.leftComp && deviceCard.leftComp.charging)
                                        text: "bolt"
                                        iconSize: 11
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        text: "L " + (deviceCard.leftComp ? deviceCard.leftComp.level : 0) + "%"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: (deviceCard.leftComp && deviceCard.leftComp.charging) ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                    }
                                }
                            }

                            Item {
                                id: earbud2
                                width: 48
                                height: 76
                                anchors.bottom: earbud1.top
                                anchors.left: earbud1.right
                                anchors.leftMargin: 4
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

                            // Right bud badge (cleanly positioned under elevated earbud 2)
                            Rectangle {
                                id: rightBadge
                                visible: deviceCard.hasIndividualBatteries
                                anchors.top: earbud2.bottom
                                anchors.topMargin: 4
                                anchors.horizontalCenter: earbud2.horizontalCenter
                                implicitWidth: rightBadgeRow.implicitWidth + 10
                                implicitHeight: 20
                                radius: Appearance.rounding.full
                                color: (deviceCard.rightComp && deviceCard.rightComp.charging) ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest

                                RowLayout {
                                    id: rightBadgeRow
                                    anchors.centerIn: parent
                                    spacing: 3

                                    MaterialSymbol {
                                        visible: Boolean(deviceCard.rightComp && deviceCard.rightComp.charging)
                                        text: "bolt"
                                        iconSize: 11
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        text: "R " + (deviceCard.rightComp ? deviceCard.rightComp.level : 0) + "%"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: (deviceCard.rightComp && deviceCard.rightComp.charging) ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                    }
                                }
                            }

                            // Primary battery percentage text
                            StyledText {
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                anchors.bottomMargin: 4
                                text: deviceCard.aggregatePercent + "%"
                                font.pixelSize: root.batterySize
                                font.weight: Font.Black
                                font.family: Appearance.font.family.main
                                color: (deviceCard.aggregatePercent <= 15) ? Appearance.m3colors.m3error : root.colBattery
                            }
                        }

                        // Noise modes selector inside earbud card
                        EarbudsNoiseControlSelector {
                            id: noiseSelectorEarbuds
                            visible: deviceCard.hasNoise
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            compact: true
                            modes: deviceCard.devNoise ? deviceCard.devNoise.modes : []
                            currentMode: deviceCard.devNoise ? deviceCard.devNoise.currentMode : "off"
                            onModeRequested: modeKey => {
                                EarbudsControlService.setNoiseMode(modelData, modeKey);
                            }
                        }
                    }

                    // Layout for Headphones
                    Item {
                        anchors.fill: parent
                        anchors.margins: 16
                        visible: deviceCard.isHeadphone

                        RowLayout {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 8

                            StyledText {
                                text: modelData.name || Translation.tr("Unknown device")
                                font.pixelSize: root.nameSize
                                font.weight: Font.Medium
                                font.family: Appearance.font.family.title
                                color: root.colName
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: Translation.tr("Connected")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }

                        Item {
                            anchors.top: parent.top
                            anchors.topMargin: 35
                            anchors.bottom: deviceCard.hasNoise ? noiseSelectorHeadphone.top : parent.bottom
                            anchors.bottomMargin: deviceCard.hasNoise ? 8 : 0
                            anchors.left: parent.left
                            anchors.right: parent.right

                            Item {
                                width: 84
                                height: 84
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter

                                MaterialShape {
                                    anchors.centerIn: parent
                                    implicitSize: 80
                                    shapeString: "Cookie6Sided"
                                    color: Appearance.colors.colPrimaryContainer

                                    RotationAnimation on rotation {
                                        from: 0; to: 360
                                        duration: 15000
                                        loops: Animation.Infinite
                                        running: root.active
                                    }
                                }

                                Loader {
                                    anchors.centerIn: parent
                                    active: deviceCard.hasCustomImg
                                    sourceComponent: Image {
                                        source: deviceCard.customDeviceImg
                                        width: 64
                                        height: 64
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        mipmap: true
                                    }
                                }

                                Loader {
                                    anchors.centerIn: parent
                                    active: !deviceCard.hasCustomImg
                                    sourceComponent: MaterialSymbol {
                                        text: Icons.getBluetoothDeviceMaterialSymbol(modelData.icon || "headphones")
                                        iconSize: 42
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }
                                }
                            }

                            StyledText {
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                anchors.bottomMargin: 4
                                text: deviceCard.aggregatePercent + "%"
                                font.pixelSize: root.batterySize
                                font.weight: Font.Black
                                font.family: Appearance.font.family.main
                                color: (deviceCard.aggregatePercent <= 15) ? Appearance.m3colors.m3error : root.colBattery
                            }
                        }

                        EarbudsNoiseControlSelector {
                            id: noiseSelectorHeadphone
                            visible: deviceCard.hasNoise
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            compact: true
                            modes: deviceCard.devNoise ? deviceCard.devNoise.modes : []
                            currentMode: deviceCard.devNoise ? deviceCard.devNoise.currentMode : "off"
                            onModeRequested: modeKey => {
                                EarbudsControlService.setNoiseMode(modelData, modeKey);
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
                        visible: !deviceCard.isEarbud && !deviceCard.isPhone && !deviceCard.isHeadphone

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
