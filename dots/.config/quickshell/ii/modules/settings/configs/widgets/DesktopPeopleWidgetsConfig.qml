pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.people
import qs.modules.settings.configs.widgets

/*
 * One page for the People & dates widgets. Birthdays, photos and favorites
 * come from the phone's contacts (KDE Connect), holidays from Calendar; the
 * countdowns' dates are the one thing kept here, in the editor below.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var widgets: Config.options.background.widgets
    readonly property var events: Array.from(root.widgets.people_countdowns.events ?? [])

    function saveEvents(list) {
        root.widgets.people_countdowns.events = list;
    }
    function editEvent(index, changes) {
        const list = root.events.map(entry => Object.assign({}, entry));
        Object.assign(list[index], changes);
        root.saveEvents(list);
    }

    WidgetPageHeader {
        title: Translation.tr("People & Dates Options")
        onBack: root.goBack()
    }

    // [ Favorites ][ Birthdays      ][ Next    ]
    // [           ][ Countdowns     ][ Holiday ]
    WidgetPreviewStage {
        columns: 4
        rows: 2

        WidgetPreviewSlot {
            rowSpan: 2
            FavoritePeopleWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.height / Math.max(1, implicitHeight)
            }
        }
        WidgetPreviewSlot {
            column: 1
            columnSpan: 2
            BirthdayTimelineWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 3
            NextBirthdayWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 1
            row: 1
            columnSpan: 2
            CountdownsWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 3
            row: 1
            HolidayWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
    }

    ContentSection {
        title: Translation.tr("Countdowns")
        icon: "event_upcoming"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Dates as YYYY-MM-DD. A yearly date comes back every year (only its day and month count).")
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }

        Repeater {
            model: root.events

            delegate: RowLayout {
                id: eventRow
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 8

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Title")
                    text: eventRow.modelData.title ?? ""
                    onEditingFinished: root.editEvent(eventRow.index, { title: text.trim() })
                }
                MaterialTextField {
                    Layout.preferredWidth: 140
                    placeholderText: "2026-12-25"
                    text: eventRow.modelData.date ?? ""
                    onEditingFinished: root.editEvent(eventRow.index, { date: text.trim() })
                }
                RippleButtonWithIcon {
                    materialIcon: eventRow.modelData.yearly ? "event_repeat" : "event"
                    mainText: eventRow.modelData.yearly ? Translation.tr("Yearly") : Translation.tr("Once")
                    onClicked: root.editEvent(eventRow.index, { yearly: !eventRow.modelData.yearly })
                }
                RippleButtonWithIcon {
                    materialIcon: "delete"
                    mainText: ""
                    onClicked: {
                        const list = root.events.slice();
                        list.splice(eventRow.index, 1);
                        root.saveEvents(list);
                    }
                }
            }
        }

        RippleButtonWithIcon {
            materialIcon: "add"
            mainText: Translation.tr("Add a date")
            onClicked: {
                const d = new Date();
                d.setDate(d.getDate() + 30);
                root.saveEvents(root.events.concat([{ title: Translation.tr("New date"), date: Qt.formatDate(d, "yyyy-MM-dd"), yearly: false }]));
            }
        }
    }

    ContentSection {
        title: Translation.tr("Where the data comes from")
        icon: "contacts"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Birthdays, photos and favorites come from your phone's contacts through KDE Connect; star people in the phone sidebar. Calling and messaging open on the phone and need ADB. Holidays follow Settings → Calendar.")
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }
    }

    component SizeSection: ContentSection {
        id: section
        property string widgetId
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: section.widgetId }
            WidgetSizeSlider { options: root.widgets[section.widgetId] }
        }
    }

    SizeSection { title: Translation.tr("Next Birthday (1x1)"); icon: "cake"; widgetId: "people_birthday" }
    SizeSection { title: Translation.tr("Birthdays (2x1)"); icon: "timeline"; widgetId: "people_birthdays" }
    SizeSection { title: Translation.tr("Next Holiday (1x1)"); icon: "celebration"; widgetId: "people_holiday" }
    SizeSection { title: Translation.tr("Countdowns (2x1)"); icon: "event_upcoming"; widgetId: "people_countdowns" }
    SizeSection { title: Translation.tr("Favorite People (1x2)"); icon: "group"; widgetId: "people_favorites" }

    ContentSection {
        title: Translation.tr("Shared")
        icon: "tune"

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }
}
