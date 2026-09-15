pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono

Item {
    id: root

    property int currMonth: new Date().getMonth()
    property int currYear: new Date().getFullYear()

    readonly property bool isCurrentMonth: {
        const now = new Date();
        return root.currMonth === now.getMonth() && root.currYear === now.getFullYear();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            RippleButton {
                implicitWidth: 24; implicitHeight: 24
                buttonRadius: 9
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    iconSize: 18
                    text: "chevron_left"
                    color: Appearance.m3colors.m3tertiary
                }
                onClicked: {
                    if (root.currMonth === 0) {
                        root.currMonth = 11;
                        root.currYear -= 1;
                    } else {
                        root.currMonth -= 1;
                    }
                }
            }

            RippleButton {
                id: monthBtn
                Layout.fillWidth: true
                implicitHeight: 24
                implicitWidth: monthBtnText.implicitWidth + 20
                Behavior on implicitWidth {
                    SmoothedAnimation {
                        velocity: Appearance.animation.elementMove.velocity
                    }
                }
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: {
                    if (!root.isCurrentMonth) {
                        const now = new Date();
                        root.currMonth = now.getMonth();
                        root.currYear = now.getFullYear();
                    }
                }
                contentItem: StyledText {
                    id: monthBtnText
                    horizontalAlignment: Text.AlignHCenter
                    text: `${root.isCurrentMonth ? "" : "• "}${grid.title}`
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                }
            }

            RippleButton {
                implicitWidth: 24; implicitHeight: 24
                buttonRadius: 9
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    iconSize: 18
                    text: "chevron_right"
                    color: Appearance.m3colors.m3tertiary
                }
                onClicked: {
                    if (root.currMonth === 11) {
                        root.currMonth = 0;
                        root.currYear += 1;
                    } else {
                        root.currMonth += 1;
                    }
                }
            }
        }

        DayOfWeekRow {
            Layout.fillWidth: true
            locale: grid.locale

            delegate: StyledText {
                required property var model

                horizontalAlignment: Text.AlignHCenter
                text: model.shortName
                font.pixelSize: Appearance.font.pixelSize.small
                color: (model.day === 0 || model.day === 6) ? Appearance.m3colors.m3secondary : Appearance.colors.colOnLayer1
            }
        }

        MonthGrid {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true

            month: root.currMonth
            year: root.currYear
            locale: Qt.locale()
            spacing: 2

            delegate: Item {
                id: dayItem
                required property var model

                readonly property bool isToday: model.today
                readonly property bool isCurrentMonth: model.month === grid.month

                Squircle {
                    anchors.centerIn: parent
                    width: Math.min(dayItem.width, dayItem.height) * 0.72
                    height: width
                    radius: width * 0.34
                    color: Appearance.colors.colPrimary
                    visible: dayItem.isToday
                }

                StyledText {
                    anchors.centerIn: parent
                    text: dayItem.model.day
                    font.pixelSize: Appearance.font.pixelSize.small
                    opacity: dayItem.isToday || dayItem.isCurrentMonth ? 1 : 0.4
                    color: {
                        if (dayItem.isToday)
                            return Appearance.m3colors.m3onPrimary;
                        const dow = dayItem.model.date.getUTCDay();
                        if (dow === 0 || dow === 6)
                            return Appearance.m3colors.m3secondary;
                        return Appearance.colors.colOnLayer1;
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton
        onClicked: {
            const now = new Date();
            root.currMonth = now.getMonth();
            root.currYear = now.getFullYear();
        }
        onWheel: event => {
            if (event.angleDelta.y < 0) {
                if (root.currMonth === 11) {
                    root.currMonth = 0;
                    root.currYear += 1;
                } else {
                    root.currMonth += 1;
                }
            } else {
                if (root.currMonth === 0) {
                    root.currMonth = 11;
                    root.currYear -= 1;
                } else {
                    root.currMonth -= 1;
                }
            }
        }
    }
}
