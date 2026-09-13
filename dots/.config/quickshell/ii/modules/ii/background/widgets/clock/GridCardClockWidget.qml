import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "grid_card_clock"

    visibleWhenLocked: root.lockBehavior === "keep"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "grid_card_clock")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property real contentScale: (Config.options.background.widgets.grid_card_clock.widgetSize ?? 100) / 100.0
    implicitWidth: 240 * contentScale
    implicitHeight: 240 * contentScale

    // -- Colors (WidgetColorScheme) --
    property color colCardBg: WidgetColorScheme.cardBgColor
    property color colText: WidgetColorScheme.textColorOnBg
    property color colTextSecondary: WidgetColorScheme.subtextColorOnBg
    property color colPillBg: WidgetColorScheme.innerShapeColor

    StyledDropShadow {
        target: clockBgShape
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Item {
        anchors.centerIn: parent
        width: 240
        height: 240
        scale: root.contentScale

        Rectangle {
            id: clockBgShape
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: WidgetColorScheme.tintBackground(root.colCardBg)

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 4

                // Hours
                StyledText {
                    text: DateTime.time.split(":")[0].padStart(2, "0")
                    color: root.colText
                    font.family: Appearance.font.family.main
                    font.pixelSize: 210
                    font.weight: Font.Normal
                    font.variableAxes: ({ "wdth": 25 })
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillHeight: true
                    verticalAlignment: Text.AlignVCenter
                }

                // Minutes & AM/PM Column
                ColumnLayout {
                    spacing: 4
                    Layout.fillHeight: true
                    Layout.fillWidth: true

                    // Minutes
                    StyledText {
                        text: DateTime.time.split(":")[1].split(" ")[0].padStart(2, "0")
                        color: root.colTextSecondary
                        font.family: Appearance.font.family.main
                        font.pixelSize: 100
                        font.weight: Font.Normal
                        font.variableAxes: ({ "wdth": 25 })
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                    }

                    // AM/PM Pill
                    Rectangle {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        Layout.maximumWidth: 64
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignBottom
                        color: root.colPillBg
                        radius: Appearance.rounding.normal

                        StyledText {
                            anchors.centerIn: parent
                            text: DateTime.time.includes("PM") ? "PM" : "AM"
                            color: root.colText
                            font.family: Appearance.font.family.main
                            font.pixelSize: 32
                            font.variableAxes: ({ "wdth": 25, "wght": 600 })
                        }
                    }
                }
            }
        }
    }
}
