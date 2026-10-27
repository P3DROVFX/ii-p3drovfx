pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Next Birthday (1x1): whose birthday comes next, from the phone's contacts.
 * Their photo (or initials) beside the days to go in tall condensed digits;
 * their name in the title face and the age they turn under it. On the day the
 * count gives way to "Today" and three small shapes burst around the photo.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "people_birthday"

    readonly property real padding: 18
    readonly property var next: source.upcoming.length > 0 ? source.upcoming[0] : null
    readonly property bool today: root.next?.days === 0

    BirthdaySource {
        id: source
        today: DateTime.clock.date
    }

    Item {
        id: photo
        x: root.padding
        y: root.padding
        width: 92
        height: 92

        PersonAvatar {
            anchors.fill: parent
            visible: root.next !== null
            name: root.next?.name ?? ""
            source: root.next?.avatar ?? ""
        }
        Rectangle {
            anchors.fill: parent
            visible: root.next === null
            radius: width / 2
            color: WidgetColorScheme.pillBgColor

            MaterialSymbol {
                anchors.centerIn: parent
                text: "cake"
                iconSize: 40
                color: WidgetColorScheme.subtextColorOnBg
            }
        }

        // The day itself: three shapes thrown around the photo.
        Repeater {
            model: [
                { shape: "Sunny", size: 30, x: 70, y: -8 },
                { shape: "Clover4Leaf", size: 22, x: -8, y: 66 },
                { shape: "Pill", size: 18, x: 78, y: 74 }
            ]

            delegate: MaterialShape {
                required property var modelData
                required property int index
                x: modelData.x
                y: modelData.y
                width: modelData.size
                height: modelData.size
                shapeString: modelData.shape
                color: index === 0 ? WidgetColorScheme.accentColor : index === 1 ? WidgetColorScheme.pillFillColor : WidgetColorScheme.highlightCircleColor
                scale: root.today ? 1 : 0
                Behavior on scale {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }
        }
    }

    // ── How long ──
    Column {
        anchors.left: photo.right
        anchors.leftMargin: 14
        anchors.verticalCenter: photo.verticalCenter
        spacing: -8
        visible: root.next !== null

        StyledText {
            text: root.today ? Translation.tr("Today") : String(root.next?.days ?? "")
            color: root.today ? WidgetColorScheme.accentColor : WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: root.today ? 30 : 64
            font.variableAxes: root.today ? ({ "wght": 800, "wdth": 90, "ROND": 100 })
                                          : ({ "wght": 820, "wdth": 45, "ROND": 100 })
        }
        StyledText {
            visible: !root.today
            text: root.next?.days === 1 ? Translation.tr("day") : Translation.tr("days")
            color: WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: 14
            font.variableAxes: ({ "wght": 500, "wdth": 110, "slnt": -10, "ROND": 100 })
        }
    }

    // ── Who ──
    StyledText {
        id: nameText
        x: root.padding
        anchors.bottom: detailText.top
        width: root.designWidth - root.padding * 2
        elide: Text.ElideRight
        text: root.next?.name ?? Translation.tr("No birthdays")
        color: WidgetColorScheme.textColorOnBg
        font.family: Appearance.font.family.title
        font.pixelSize: Appearance.font.pixelSize.huge
        font.variableAxes: Appearance.font.variableAxes.titleRounded
    }
    StyledText {
        id: detailText
        x: root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        width: root.designWidth - root.padding * 2
        elide: Text.ElideRight
        text: root.next === null
            ? Translation.tr("Add birthdays to your phone's contacts")
            : (root.next.age > 0 ? Translation.tr("Turns %1").arg(root.next.age) + " · " : "")
              + Qt.locale().toString(root.next.date, "d MMMM")
        color: WidgetColorScheme.subtextColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.small
        font.variableAxes: ({ "wght": 550, "wdth": 100, "ROND": 100 })
    }
}
