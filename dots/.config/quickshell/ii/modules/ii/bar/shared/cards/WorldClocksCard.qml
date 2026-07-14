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
                }
            }
        }
    }
}
