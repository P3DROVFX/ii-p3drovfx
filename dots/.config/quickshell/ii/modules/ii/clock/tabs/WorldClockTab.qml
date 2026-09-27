pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * World clock: the local time on a pane of its own — digital on top, the dial that
 * carries every city under it — and the cities beside it as a grid that takes as many
 * columns as the window allows. Stacked on a narrow window.
 */
Item {
    id: root

    property date now: new Date()
    property bool compact: false
    property bool wide: false
    property bool showSeconds: true
    property ClockSidePanel panels: null
    property real layoutWidth: root.width

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property bool sideBySide: root.layoutWidth >= ClockStyle.mediumMax - 80
    readonly property bool showDial: Config.options.clockApp?.analogWorldClock ?? true
    readonly property real heroWidth: root.sideBySide
        ? Math.round(Math.max(300, Math.min(root.layoutWidth * 0.36, ClockStyle.worldHeroMaxWidth)))
        : root.width
    readonly property real gridGap: ClockStyle.gap
    readonly property real listWidth: root.sideBySide ? root.width - root.heroWidth - ClockStyle.paneGap : root.width
    readonly property real listLayoutWidth: root.sideBySide ? root.layoutWidth - root.heroWidth - ClockStyle.paneGap : root.layoutWidth
    // One city per row: the room beside the dial goes to bigger rows, not more of them.
    readonly property int columns: 1
    readonly property real cardWidth: Math.floor((root.listWidth - root.gridGap * (root.columns - 1)) / root.columns)

    readonly property int cityCount: WorldClockService.clocks.length
    readonly property string pageSubtitle: WorldClockService.localZone.length > 0
        ? WorldClockService.localZone.replace(/_/g, " ") + " · " + WorldClockService.utcOffsetLabel(-root.now.getTimezoneOffset())
        : WorldClockService.utcOffsetLabel(-root.now.getTimezoneOffset())

    function primaryAction(): void {
        root.panels?.show(pickerSheet, { now: root.now });
    }

    function rename(index: int): void {
        const entry = WorldClockService.clocks[index];
        root.panels?.show(renameSheet, {
            cityIndex: index,
            initialText: entry?.name ?? "",
            placeholder: WorldClockService.cityFromZone(entry?.tz ?? "")
        });
    }

    Component.onCompleted: WorldClockService.retain()
    Component.onDestruction: WorldClockService.release()

    Component {
        id: pickerSheet
        TimezonePickerSheet {}
    }

    Component {
        id: renameSheet
        ClockTextPromptSheet {
            property int cityIndex: -1
            title: Translation.tr("Rename city")
            caption: Translation.tr("Name")
            symbol: "location_on"
            onSubmitted: text => WorldClockService.renameClock(cityIndex, text)
        }
    }

    // ── Local time ──────────────────────────────────────────────────────
    component Hero: Rectangle {
        id: hero
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colPane

        readonly property real digitSize: Math.max(ClockStyle.displayDigitMin, Math.min(hero.width * 0.24, ClockStyle.displayDigitMax * 0.9))
        readonly property real dialSize: Math.max(ClockStyle.worldDialMin,
            Math.min(hero.width - ClockStyle.gapHuge * 2, hero.height - heroHeader.implicitHeight - ClockStyle.gapHuge * 3))

        ColumnLayout {
            anchors {
                fill: parent
                margins: ClockStyle.gapHuge
            }
            spacing: ClockStyle.gapLarge

            ColumnLayout {
                id: heroHeader
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 0

                    StyledText {
                        text: ClockFormat.use12Hour
                            ? ClockFormat.pad(root.now.getHours() % 12 || 12) + ":" + ClockFormat.pad(root.now.getMinutes())
                            : ClockFormat.pad(root.now.getHours()) + ":" + ClockFormat.pad(root.now.getMinutes())
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigitsBold
                        font.pixelSize: hero.digitSize
                        color: ClockStyle.colOnSurface
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: hero.digitSize * 0.14
                        Layout.leftMargin: ClockStyle.gapSmall
                        spacing: 0

                        StyledText {
                            visible: ClockFormat.use12Hour
                            text: root.now.getHours() >= 12 ? Qt.locale().pmText : Qt.locale().amText
                            font.pixelSize: hero.digitSize * 0.22
                            color: ClockStyle.colSubtext
                        }

                        StyledText {
                            visible: root.showSeconds
                            text: ClockFormat.pad(root.now.getSeconds())
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDigits
                            font.pixelSize: hero.digitSize * 0.34
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
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.showDial

                WorldAnalogClock {
                    anchors.centerIn: parent
                    width: hero.dialSize
                    height: hero.dialSize
                    now: root.now
                    showSeconds: root.showSeconds

                    StaggeredEntrance {
                        index: 1
                        active: !ClockStyle.reducedMotion
                        fromScale: 0.92
                    }
                }
            }
        }
    }

    // ── Cities ──────────────────────────────────────────────────────────
    component Cities: Flow {
        spacing: root.gridGap

        // Tiles keep their settled size and the flow animates where they land, so a
        // sheet opening or the rail folding re-deals the tiles instead of
        // stretching them frame by frame.
        move: Transition {
            enabled: !ClockStyle.reducedMotion
            NumberAnimation {
                properties: "x,y"
                duration: ClockStyle.motionDefault.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
            }
        }

        Repeater {
            model: root.cityCount

            WorldClockCard {
                id: card
                required property int index
                width: Math.floor((root.listLayoutWidth - root.gridGap * (root.columns - 1)) / root.columns)
                Behavior on width {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }
                clockIndex: card.index
                count: root.cityCount
                now: root.now
                showSeconds: root.showSeconds
                onRenameRequested: root.rename(card.index)

                StaggeredEntrance {
                    index: card.index + 1
                    step: ClockStyle.staggerStep
                    active: !ClockStyle.reducedMotion
                }
            }
        }
    }

    component Empty: ColumnLayout {
        spacing: ClockStyle.gapLarge

        ClockEmptyState {
            Layout.alignment: Qt.AlignHCenter
            symbol: "travel_explore"
            shape: "Clover4Leaf"
            shapeSize: ClockStyle.emptyShapeSmall
            title: Translation.tr("No cities yet")
            subtitle: Translation.tr("Add a city to see its time next to yours.")
        }

        ClockButton {
            Layout.alignment: Qt.AlignHCenter
            variant: "filled"
            symbol: "add_location_alt"
            label: Translation.tr("Add city")
            onClicked: root.primaryAction()
        }
    }

    Loader {
        anchors.fill: parent
        active: root.sideBySide
        sourceComponent: RowLayout {
            spacing: ClockStyle.paneGap

            Hero {
                Layout.fillHeight: true
                Layout.preferredWidth: root.heroWidth
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledFlickable {
                    id: sideFlick
                    anchors.fill: parent
                    visible: root.cityCount > 0
                    contentWidth: width
                    contentHeight: sideCities.implicitHeight + ClockStyle.fabClearance
                    clip: true

                    Cities {
                        id: sideCities
                        width: Math.max(root.listWidth, root.listLayoutWidth)
                    }
                }

                Empty {
                    anchors.centerIn: parent
                    visible: root.cityCount === 0
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
            contentHeight: stack.implicitHeight + ClockStyle.fabClearance
            clip: true

            ColumnLayout {
                id: stack
                width: stackFlick.width
                spacing: ClockStyle.paneGap

                Hero {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.showDial ? Math.min(560, stackFlick.width + 120) : 200
                }

                Cities {
                    Layout.preferredWidth: Math.max(root.listWidth, root.listLayoutWidth)
                    visible: root.cityCount > 0
                }

                Empty {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: ClockStyle.gapHuge
                    visible: root.cityCount === 0
                }
            }
        }
    }
}
