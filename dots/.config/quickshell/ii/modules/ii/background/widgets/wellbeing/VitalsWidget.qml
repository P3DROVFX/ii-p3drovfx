pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Vitals (2x1): today from the phone's health data. On the left today's steps in
 * tall condensed digits over a wavy line that runs to the phone's step goal; on the
 * right, on one plate, last night (how long, its score in a scalloped badge) and the
 * newest heart rate with the time it was taken. Only what has data shows: without
 * steps the plate takes the card, without a night or a reading the plate drops that
 * row. Off, or with nothing synced yet, a single line says why.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "wellbeing_vitals"
    designWidth: 492
    designHeight: 240

    readonly property real padding: 18
    readonly property string today: Qt.formatDate(DateTime.clock.date, "yyyy-MM-dd")
    readonly property bool vitalsOn: VitalsService.enabled
    readonly property var day: {
        void VitalsService.dataVersion;
        return root.vitalsOn ? VitalsService.summary(root.today) : null;
    }
    readonly property var steps: root.day?.t?.steps ?? null
    readonly property int goal: VitalsService.meta?.goals?.steps ?? 0
    readonly property var night: root.day?.sleep ?? null
    readonly property var heart: {
        void VitalsService.dataVersion;
        return root.vitalsOn ? VitalsService.latest("heartRate") : null;
    }
    readonly property bool hasSteps: root.steps !== null
    readonly property bool hasPlate: root.night !== null || root.heart !== null
    readonly property bool empty: !root.hasSteps && !root.hasPlate

    onCardTapped: GlobalStates.openVitalsApp("")

    // ── Nothing to show ──
    Column {
        anchors.centerIn: parent
        visible: root.empty
        spacing: 6

        MaterialShape {
            anchors.horizontalCenter: parent.horizontalCenter
            implicitSize: 64
            shape: MaterialShape.Shape.Cookie9Sided
            color: WidgetColorScheme.innerShapeColor

            MaterialSymbol {
                anchors.centerIn: parent
                text: "ecg_heart"
                iconSize: 32
                color: WidgetColorScheme.textColorOnBg
            }
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Translation.tr("Vitals")
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.larger
            font.variableAxes: Appearance.font.variableAxes.titleRounded
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !root.vitalsOn ? Translation.tr("Vitals is off") : Translation.tr("No health data yet")
            color: WidgetColorScheme.subtextColorOnBg
            font.pixelSize: Appearance.font.pixelSize.normal
        }
    }

    // ── Steps ──
    Item {
        id: stepsBlock
        visible: root.hasSteps
        x: root.padding + 4
        y: root.padding
        width: root.hasPlate ? 206 : root.designWidth - x - root.padding - 4
        height: root.designHeight - root.padding * 2

        Row {
            spacing: 6
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: "directions_walk"
                iconSize: 20
                fill: 1
                color: WidgetColorScheme.accentColor
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Translation.tr("Steps today")
                color: WidgetColorScheme.subtextColorOnBg
                font.pixelSize: Appearance.font.pixelSize.normal
                font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
            }
        }

        StyledText {
            id: stepsText
            y: 22
            width: parent.width
            elide: Text.ElideRight
            text: VitalsTypes.format("steps", root.steps ?? 0)
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: 96
            font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
        }

        StyledText {
            anchors.bottom: stepsBar.top
            anchors.bottomMargin: 10
            text: root.goal <= 0 ? ""
                : root.steps >= root.goal ? Translation.tr("Goal reached")
                : Translation.tr("%1 to go").arg(VitalsTypes.format("steps", root.goal - root.steps))
            color: root.steps >= root.goal ? WidgetColorScheme.accentColor : WidgetColorScheme.subtextColorOnBg
            font.pixelSize: Appearance.font.pixelSize.normal
            font.variableAxes: ({ "wght": 620, "wdth": 92, "ROND": 100 })
        }

        StyledProgressBar {
            id: stepsBar
            visible: root.goal > 0
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            width: parent.width
            valueBarWidth: parent.width
            valueBarHeight: 6
            value: root.goal > 0 ? Math.min(1, (root.steps ?? 0) / root.goal) : 0
            wavy: true
            highlightColor: WidgetColorScheme.accentColor
            trackColor: WidgetColorScheme.pillBgColor
        }
    }

    // ── Last night and the heart ──
    Rectangle {
        id: plate
        visible: root.hasPlate
        x: root.hasSteps ? 250 : root.padding
        y: root.padding
        width: root.designWidth - plate.x - root.padding
        height: root.designHeight - root.padding * 2
        radius: Appearance.rounding.large
        color: WidgetColorScheme.pillBgColor

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 16
            spacing: 14

            // Last night
            Item {
                visible: root.night !== null
                width: parent.width
                height: 64

                Column {
                    anchors.left: parent.left
                    anchors.right: scoreBadge.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Row {
                        spacing: 4
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "bedtime"
                            iconSize: 18
                            fill: 1
                            color: WidgetColorScheme.subtextColorOnBg
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Last night")
                            color: WidgetColorScheme.subtextColorOnBg
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                        }
                    }
                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: root.night ? VitalsTypes.duration(root.night.min) : ""
                        color: WidgetColorScheme.textColorOnBg
                        font.family: Appearance.font.family.main
                        font.pixelSize: 28
                        font.variableAxes: ({ "wght": 560, "wdth": 80, "ROND": 100 })
                    }
                }

                MaterialShape {
                    id: scoreBadge
                    visible: (root.night?.score ?? null) !== null
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 58
                    shape: MaterialShape.Shape.Cookie12Sided
                    color: WidgetColorScheme.accentColor

                    StyledText {
                        anchors.centerIn: parent
                        text: String(root.night?.score ?? "")
                        color: WidgetColorScheme.onAccentColor
                        font.family: Appearance.font.family.main
                        font.pixelSize: 24
                        font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
                    }
                }
            }

            // Newest heart rate
            Row {
                visible: root.heart !== null
                spacing: 8

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "favorite"
                    iconSize: 26
                    fill: 1
                    color: WidgetColorScheme.accentColor
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    StyledText {
                        text: root.heart ? VitalsTypes.format("heartRate", root.heart.value) : ""
                        color: WidgetColorScheme.textColorOnBg
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.variableAxes: ({ "wght": 700, "wdth": 100, "ROND": 100 })
                    }
                    StyledText {
                        // Today's reading by its time; an older one with its day too.
                        text: !root.heart?.time ? ""
                            : Translation.tr("as of %1").arg(Qt.locale().toString(new Date(root.heart.time),
                                root.heart.date === root.today ? (Config.options?.time?.format ?? "hh:mm")
                                    : "ddd " + (Config.options?.time?.format ?? "hh:mm")))
                        color: WidgetColorScheme.subtextColorOnBg
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }
    }
}
