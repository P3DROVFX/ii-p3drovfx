pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Favorite People (1x2): the contacts starred in the phone sidebar, six at
 * most, as big round faces with their first name. A click on a face opens
 * the phone's dialer with their number (KDE Connect + ADB); under the
 * pointer the face shrinks a little and a message key rises beside it.
 * Whoever has a birthday today wears the accent around the name.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "people_favorites"
    designWidth: 240
    designHeight: 492

    readonly property real padding: 16
    readonly property var favoriteIds: Array.from(Config.options?.phone?.contacts?.favoriteIds ?? [])
    readonly property var people: (PhoneContactsService.contacts ?? [])
        .filter(contact => root.favoriteIds.includes(String(contact.id)))
        .slice(0, 6)
    readonly property var birthdayIds: source.upcoming.filter(person => person.days === 0).map(person => person.id)

    BirthdaySource {
        id: source
        today: DateTime.clock.date
    }

    function numberOf(contact) {
        const phones = Array.from(contact?.phones ?? []);
        return String((phones.find(phone => phone.primary) ?? phones[0])?.value ?? "");
    }

    onCardTapped: at => {
        const person = faces.childAt(at.x - faces.x, at.y - faces.y);
        if (person && person.number !== undefined && person.number.length > 0)
            PhoneContactsService.openDialer(person.number);
    }

    StyledText {
        id: title
        x: root.padding
        y: root.padding - 2
        text: Translation.tr("People")
        color: WidgetColorScheme.textColorOnBg
        font.family: Appearance.font.family.title
        font.pixelSize: Appearance.font.pixelSize.huge
        font.variableAxes: Appearance.font.variableAxes.titleRounded
    }

    Grid {
        id: faces
        x: root.padding
        anchors.top: title.bottom
        anchors.topMargin: 10
        columns: 2
        columnSpacing: 8
        rowSpacing: 6

        readonly property real cellWidth: (root.designWidth - root.padding * 2 - faces.columnSpacing) / 2
        readonly property real cellHeight: (root.designHeight - faces.y - root.padding - faces.rowSpacing * 2) / 3

        Repeater {
            model: root.people

            delegate: Item {
                id: person
                required property var modelData
                readonly property string number: root.numberOf(person.modelData)
                readonly property bool birthday: root.birthdayIds.includes(String(person.modelData.id))
                readonly property bool hovered: faceHover.hovered && root.actionsEnabled
                width: faces.cellWidth
                height: faces.cellHeight

                HoverHandler {
                    id: faceHover
                    cursorShape: Qt.PointingHandCursor
                }

                PersonAvatar {
                    id: face
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: person.hovered ? -12 : 0
                    y: 4
                    width: Math.min(parent.width - 8, parent.height - nameChip.height - 14) * (person.hovered ? 0.84 : 1)
                    height: width
                    name: String(person.modelData.displayName ?? "")
                    source: String(person.modelData.avatarPath ?? "")
                    Behavior on width {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on anchors.horizontalCenterOffset {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                WidgetButton {
                    anchors.left: face.right
                    anchors.leftMargin: -6
                    anchors.bottom: face.bottom
                    width: 34
                    height: 34
                    opacity: person.hovered && person.number.length > 0 ? 1 : 0
                    visible: opacity > 0
                    symbol: "chat"
                    symbolSize: 16
                    colFill: WidgetColorScheme.pillFillColor
                    colContent: WidgetColorScheme.textColorOnPillFill
                    onClicked: PhoneContactsService.composeSms(person.number)
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                Rectangle {
                    id: nameChip
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: face.bottom
                    anchors.topMargin: 6
                    width: Math.min(parent.width, nameText.implicitWidth + (person.birthday ? 34 : 14))
                    height: 24
                    radius: root.pill(height)
                    color: person.birthday ? WidgetColorScheme.accentColor : "transparent"

                    Row {
                        anchors.centerIn: parent
                        spacing: 3
                        MaterialSymbol {
                            visible: person.birthday
                            anchors.verticalCenter: parent.verticalCenter
                            text: "cake"
                            iconSize: 14
                            fill: 1
                            color: WidgetColorScheme.onAccentColor
                        }
                        StyledText {
                            id: nameText
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(person.modelData.givenName || person.modelData.displayName || "").split(" ")[0]
                            color: person.birthday ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg
                            font.family: Appearance.font.family.main
                            font.pixelSize: 13
                            font.variableAxes: ({ "wght": 650, "wdth": 95, "ROND": 100 })
                        }
                    }
                }
            }
        }
    }

    Column {
        visible: root.people.length === 0
        anchors.centerIn: parent
        width: root.designWidth - root.padding * 2
        spacing: 8

        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "star"
            iconSize: 40
            color: WidgetColorScheme.subtextColorOnBg
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: Translation.tr("Star contacts in the phone sidebar to see them here")
            color: WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }
}
