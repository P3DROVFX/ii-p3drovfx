import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property var timezoneOffsets: ({})

    // Functions mapped from parent ClockWidgetPopup
    property var getTimezoneOffsetString
    property var getUtcTimeForTz
    property var getFormattedTime
    property var getFormattedDate
    
    // Internal animation control
    property bool startAnim: false

    onStartAnimChanged: {
        if (startAnim) {
            // Reset all cards
            for (var i = 0; i < listView.count; i++) {
                var item = listView.itemAtIndex(i);
                if (item) {
                    item.cardOpacity = 0.0;
                    item.cardTranslateX = 50;
                    item.iconScale = 0.8;
                    item.iconRotation = -15;
                    item.offsetOpacity = 0.0;
                    item.offsetTranslateX = -30;
                    item.timeOpacity = 0.0;
                    item.timeScale = 0.9;
                }
            }
            
            // Start staggered animations
            Qt.callLater(function() {
                for (var j = 0; j < listView.count; j++) {
                    var cardItem = listView.itemAtIndex(j);
                    if (cardItem) {
                        cardItem.cardAnimDelay = 200 + (j * 120);
                        cardItem.startCardAnim();
                    }
                }
            });
        }
    }

    Connections {
        target: root
        function onPopupOpenProgressChanged() {
            if (root && root.popupOpenProgress === 0.0) {
                for (var k = 0; k < listView.count; k++) {
                    var resetItem = listView.itemAtIndex(k);
                    if (resetItem) {
                        resetItem.stopCardAnim();
                        resetItem.cardOpacity = 0.0;
                        resetItem.cardTranslateX = 50;
                        resetItem.iconScale = 0.8;
                        resetItem.iconRotation = -15;
                        resetItem.offsetOpacity = 0.0;
                        resetItem.offsetTranslateX = -30;
                        resetItem.timeOpacity = 0.0;
                        resetItem.timeScale = 0.9;
                    }
                }
            }
        }
    }

    Layout.fillWidth: true
    Layout.preferredHeight: 96
    implicitHeight: 96

    ListView {
        id: listView
        anchors.fill: parent
        orientation: ListView.Horizontal
        spacing: 12
        clip: true
        interactive: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        model: Config.options.time.worldClocks

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                let delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                listView.contentX = Math.max(0, Math.min(listView.contentWidth - listView.width, listView.contentX - delta));
            }
        }

        delegate: Rectangle {
            id: card
            width: listView.count >= 2 ? (listView.width > 0 ? listView.width * 0.85 : 320) : (listView.width > 0 ? listView.width : 380)
            height: 96
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2
            clip: true

            layer.enabled: true
            layer.smooth: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: card.width
                    height: card.height
                    radius: card.radius
                    antialiasing: true
                }
            }

            required property var modelData
            required property int index
            
            // Animation properties
            property real cardOpacity: 1.0
            property real cardTranslateX: 0
            property real iconScale: 1.0
            property real iconRotation: 0
            property real offsetOpacity: 1.0
            property real offsetTranslateX: 0
            property real timeOpacity: 1.0
            property real timeScale: 1.0
            property int cardAnimDelay: 0
            
            function startCardAnim() {
                cardAnim.start();
            }

            SequentialAnimation {
                id: cardAnim
                PauseAnimation { duration: card.cardAnimDelay }
                ParallelAnimation {
                    NumberAnimation { target: card; property: "cardOpacity"; from: 0.0; to: 1.0; duration: 400 }
                    NumberAnimation { target: card; property: "cardTranslateX"; from: 50; to: 0; duration: 500; easing.type: Easing.OutCubic }
                    NumberAnimation { target: card; property: "iconScale"; from: 0.8; to: 1.0; duration: 450; easing.type: Easing.OutBack }
                    NumberAnimation { target: card; property: "iconRotation"; from: -15; to: 0; duration: 450; easing.type: Easing.OutCubic }
                    NumberAnimation { target: card; property: "offsetOpacity"; from: 0.0; to: 1.0; duration: 350 }
                    NumberAnimation { target: card; property: "offsetTranslateX"; from: -30; to: 0; duration: 400; easing.type: Easing.OutCubic }
                    NumberAnimation { target: card; property: "timeOpacity"; from: 0.0; to: 1.0; duration: 350 }
                    NumberAnimation { target: card; property: "timeScale"; from: 0.9; to: 1.0; duration: 400; easing.type: Easing.OutBack }
                }
            }

            opacity: card.cardOpacity
            transform: Translate {
                x: card.cardTranslateX
            }

            // Decorative background circle on the right side
            Rectangle {
                width: parent.height * 1.66
                height: width
                radius: width / 2
                color: Appearance.colors.colLayer3
                anchors {
                    right: parent.right
                    rightMargin: -width * 0.2
                    top: parent.top
                    topMargin: -width * 0.2
                }
            }

            // Right side weather/day-night info inside the circle
            ColumnLayout {
                anchors {
                    horizontalCenter: parent.right
                    horizontalCenterOffset: -card.height * 0.66
                    verticalCenter: parent.verticalCenter
                }
                spacing: 2

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        try {
                            const targetUtc = root.getUtcTimeForTz(card.modelData.tz, DateTime.clock.date);
                            if (isNaN(targetUtc)) return "question_mark";
                            const targetDate = new Date(targetUtc);
                            const hour = targetDate.getUTCHours();
                            return (hour < 6 || hour >= 18) ? "dark_mode" : "light_mode";
                        } catch (e) {
                            return "question_mark";
                        }
                    }
                    iconSize: card.height * 0.58
                    fill: 1
                    color: text === "light_mode" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    scale: card.iconScale
                    rotation: card.iconRotation
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "18°" // Mock placeholder temperature
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurface
                }
            }

            // Left side time zone info
            ColumnLayout {
                anchors {
                    left: parent.left
                    leftMargin: 20
                    verticalCenter: parent.verticalCenter
                }
                spacing: 6

                RowLayout {
                    spacing: 8

                    // Offset pill badge
                    Rectangle {
                        implicitWidth: offsetText.implicitWidth + 18
                        implicitHeight: 20
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSurfaceContainerHighest
                        opacity: card.offsetOpacity
                        transform: Translate { x: card.offsetTranslateX }

                        StyledText {
                            id: offsetText
                            anchors.centerIn: parent
                            text: {
                                let offset = root.getTimezoneOffsetString(card.modelData.tz, DateTime.clock.date);
                                return offset === "" ? "+0h" : offset;
                            }
                            font.pixelSize: 14
                            font.weight: Font.Thin
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    StyledText {
                        text: card.modelData.name || card.modelData.tz || Translation.tr("Unnamed")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }
                }

                StyledText {
                    text: root.getFormattedTime(card.modelData.tz, DateTime.clock.date)
                    font.pixelSize: Math.min(42, card.width * 0.11)
                    font.family: Appearance.font.family.title
                    font.weight: 1000
                    color: Appearance.colors.colOnSurface
                    opacity: card.timeOpacity
                    scale: card.timeScale
                }
            }
        }
    }
}
