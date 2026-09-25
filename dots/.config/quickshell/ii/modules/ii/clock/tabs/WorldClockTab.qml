pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * World clock: the local time, digital and on a dial that carries every city, and the
 * list of cities. Side by side on a wide window, stacked on a narrow one.
 */
Item {
    id: root

    property date now: new Date()
    property bool compact: false
    property bool wide: false
    property bool showSeconds: true

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
    readonly property bool sideBySide: root.width >= ClockStyle.mediumMax
    readonly property bool showDial: Config.options.clockApp?.analogWorldClock ?? true
    readonly property real heroWidth: root.sideBySide ? Math.min(root.width * 0.44, ClockStyle.worldHeroMaxWidth) : root.width - root.padding * 2
    readonly property real dialSize: Math.max(ClockStyle.worldDialMin, Math.min(root.heroWidth * 0.8, root.sideBySide ? root.height * 0.5 : root.height * 0.36))
    readonly property real digitalSize: Math.max(ClockStyle.displayDigitMin, Math.min(root.heroWidth * 0.26, ClockStyle.displayDigitMax))

    readonly property int cityCount: WorldClockService.clocks.length
    readonly property string pageSubtitle: WorldClockService.localZone.length > 0
        ? WorldClockService.localZone.replace(/_/g, " ") + " · " + WorldClockService.utcOffsetLabel(-root.now.getTimezoneOffset())
        : WorldClockService.utcOffsetLabel(-root.now.getTimezoneOffset())

    property int renameIndex: -1

    Component.onCompleted: WorldClockService.retain()
    Component.onDestruction: WorldClockService.release()

    component Hero: ColumnLayout {
        spacing: ClockStyle.gap

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 0

            StyledText {
                text: ClockFormat.use12Hour
                    ? ClockFormat.pad(root.now.getHours() % 12 || 12) + ":" + ClockFormat.pad(root.now.getMinutes())
                    : ClockFormat.pad(root.now.getHours()) + ":" + ClockFormat.pad(root.now.getMinutes())
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigitsBold
                font.pixelSize: root.digitalSize
                color: ClockStyle.colOnBackground
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignBottom
                Layout.bottomMargin: root.digitalSize * 0.14
                Layout.leftMargin: ClockStyle.gapSmall
                spacing: 0

                StyledText {
                    visible: ClockFormat.use12Hour
                    text: root.now.getHours() >= 12 ? Qt.locale().pmText : Qt.locale().amText
                    font.pixelSize: root.digitalSize * 0.22
                    color: ClockStyle.colSubtext
                }

                StyledText {
                    visible: root.showSeconds
                    text: ClockFormat.pad(root.now.getSeconds())
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigits
                    font.pixelSize: root.digitalSize * 0.32
                    color: ClockStyle.colPrimary
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.locale().toString(root.now, "dddd, d MMMM")
            font.pixelSize: ClockStyle.textLarge
            color: ClockStyle.colSubtext
        }

        WorldAnalogClock {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: ClockStyle.gapSmall
            visible: root.showDial
            Layout.preferredWidth: root.dialSize
            Layout.preferredHeight: root.dialSize
            now: root.now
            showSeconds: root.showSeconds

            StaggeredEntrance {
                index: 1
                active: !ClockStyle.reducedMotion
                fromScale: 0.9
            }
        }
    }

    component CityList: ColumnLayout {
        spacing: ClockStyle.gapSmall

        Repeater {
            model: root.cityCount

            WorldClockCard {
                id: card
                required property int index
                Layout.fillWidth: true
                clockIndex: card.index
                count: root.cityCount
                now: root.now
                showSeconds: root.showSeconds
                onRenameRequested: {
                    root.renameIndex = card.index;
                    renameLoader.active = true;
                    renameLoader.item.openWith(WorldClockService.clocks[card.index]?.name ?? "");
                }

                StaggeredEntrance {
                    index: card.index + 2
                    step: ClockStyle.staggerStep
                    active: !ClockStyle.reducedMotion
                }
            }
        }

        ClockEmptyState {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: ClockStyle.gapHuge
            visible: root.cityCount === 0
            symbol: "travel_explore"
            shape: "Clover4Leaf"
            shapeSize: ClockStyle.emptyShapeSmall
            title: Translation.tr("No cities yet")
            subtitle: Translation.tr("Add a city to see its time next to yours.")
        }
    }

    Loader {
        anchors.fill: parent
        active: root.sideBySide
        sourceComponent: RowLayout {
            spacing: ClockStyle.gapHuge

            Item {
                Layout.fillHeight: true
                Layout.preferredWidth: root.heroWidth
                Layout.leftMargin: root.padding

                Hero {
                    anchors.centerIn: parent
                    width: parent.width
                }
            }

            StyledFlickable {
                id: sideFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: sideList.implicitHeight + ClockStyle.fabSize + ClockStyle.gapHuge * 3
                clip: true

                CityList {
                    id: sideList
                    y: ClockStyle.gapSmall
                    width: sideFlick.width - root.padding
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: !root.sideBySide
        sourceComponent: StyledFlickable {
            id: stackFlick
            contentWidth: width
            contentHeight: stack.implicitHeight + ClockStyle.fabSize + ClockStyle.gapHuge * 3
            clip: true

            ColumnLayout {
                id: stack
                x: root.padding
                y: ClockStyle.gapSmall
                width: stackFlick.width - root.padding * 2
                spacing: ClockStyle.gapHuge

                Hero {
                    Layout.fillWidth: true
                }

                CityList {
                    Layout.fillWidth: true
                }
            }
        }
    }

    ClockFab {
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: ClockStyle.gapHuge
        }
        symbol: "add_location_alt"
        label: root.wide ? Translation.tr("Add city") : ""
        onClicked: {
            pickerLoader.active = true;
            pickerLoader.item.open();
        }
    }

    Loader {
        id: pickerLoader
        anchors.fill: parent
        active: false
        sourceComponent: TimezonePickerSheet {
            now: root.now
            onFullyClosed: pickerLoader.active = false
        }
    }

    Loader {
        id: renameLoader
        anchors.fill: parent
        active: false
        sourceComponent: ClockTextPromptSheet {
            title: Translation.tr("Rename city")
            placeholder: WorldClockService.cityFromZone(WorldClockService.clocks[root.renameIndex]?.tz ?? "")
            onSubmitted: text => WorldClockService.renameClock(root.renameIndex, text)
            onFullyClosed: renameLoader.active = false
        }
    }
}
