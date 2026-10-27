pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Birthdays (2x1): the next birthdays on a line that is time itself. Today
 * is the left end; each person's photo sits as far along as their birthday
 * is away, hanging above or below the line in turn so close ones never
 * cover each other, with their name and date beside it. The scale stretches
 * to the furthest of the five, so a crowded month spreads out.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "people_birthdays"
    designWidth: 492
    designHeight: 240

    readonly property real padding: 18
    readonly property var people: source.upcoming.slice(0, 5)
    readonly property real span: Math.max(14, ...root.people.map(person => person.days))

    BirthdaySource {
        id: source
        today: DateTime.clock.date
    }

    StyledText {
        x: root.padding
        y: root.padding - 4
        text: Translation.tr("Birthdays")
        color: WidgetColorScheme.textColorOnBg
        font.family: Appearance.font.family.title
        font.pixelSize: Appearance.font.pixelSize.larger
        font.variableAxes: Appearance.font.variableAxes.titleRounded
    }
    StyledText {
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        y: root.padding
        text: Translation.tr("next %1 days").arg(Math.round(root.span))
        color: WidgetColorScheme.subtextColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: 12
        font.variableAxes: ({ "wght": 500, "wdth": 100, "slnt": -10, "ROND": 100 })
    }

    Item {
        id: lane
        visible: root.people.length > 0
        x: root.padding + 6
        y: 50
        width: root.designWidth - root.padding * 2 - 60
        height: root.designHeight - lane.y - root.padding

        readonly property real lineY: lane.height / 2
        readonly property real photo: 52

        // The line: today at the left end.
        Rectangle {
            x: 0
            y: lane.lineY - 2
            width: lane.width + 50
            height: 4
            radius: 2
            color: WidgetColorScheme.pillBgColor
        }
        Rectangle {
            x: -4
            y: lane.lineY - 8
            width: 16
            height: 16
            radius: 8
            color: WidgetColorScheme.accentColor
        }

        Repeater {
            model: root.people

            delegate: Item {
                id: person
                required property var modelData
                required property int index
                readonly property bool above: person.index % 2 === 0
                x: lane.width * person.modelData.days / root.span
                width: lane.photo
                height: lane.height

                // A short stem from the line to the photo.
                Rectangle {
                    x: lane.photo / 2 - 1.5
                    y: person.above ? lane.lineY - 14 : lane.lineY
                    width: 3
                    height: 14
                    color: WidgetColorScheme.pillBgColor
                }

                PersonAvatar {
                    id: face
                    y: person.above ? lane.lineY - 14 - lane.photo : lane.lineY + 14
                    width: lane.photo
                    height: lane.photo
                    name: person.modelData.name
                    source: person.modelData.avatar
                }

                Column {
                    anchors.left: face.right
                    anchors.leftMargin: 6
                    anchors.verticalCenter: face.verticalCenter
                    spacing: -2

                    StyledText {
                        text: person.modelData.name.split(" ")[0]
                        color: WidgetColorScheme.textColorOnBg
                        font.family: Appearance.font.family.main
                        font.pixelSize: 13
                        font.variableAxes: ({ "wght": 700, "wdth": 90, "ROND": 100 })
                    }
                    StyledText {
                        text: person.modelData.days === 0 ? Translation.tr("Today")
                            : Qt.locale().toString(person.modelData.date, "d MMM")
                        color: person.modelData.days === 0 ? WidgetColorScheme.accentColor : WidgetColorScheme.subtextColorOnBg
                        font.family: Appearance.font.family.main
                        font.pixelSize: 11
                        font.variableAxes: ({ "wght": 500, "wdth": 100, "ROND": 100 })
                    }
                }
            }
        }
    }

    StyledText {
        visible: root.people.length === 0
        anchors.centerIn: parent
        text: Translation.tr("Add birthdays to your phone's contacts")
        color: WidgetColorScheme.subtextColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.normal
    }
}
