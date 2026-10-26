pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.media

/**
 * AOD face: a Material 3 Expressive clock laid out in one line. Heavy rounded hours
 * in primary, two shaped dots, lighter minutes, then a column with the date and what
 * is playing (cover cut to a cookie, title and artist). Only whites on the black:
 * weight and three tones carry the hierarchy, the cover is drained of colour too.
 */
Item {
    id: root

    property bool running: true

    readonly property color brightColor: "#f2f2f2"
    readonly property color midColor: "#9a9a9a"
    readonly property color lineColor: "#262626"

    readonly property real digitSize: Math.min(root.height * 0.30, root.width * 0.17)
    readonly property real sideWidth: Math.min(root.width * 0.30, root.digitSize * 2.4)

    readonly property var player: MprisController.activePlayer
    readonly property bool hasMedia: !!root.player && (root.player.trackTitle ?? "") !== ""

    Row {
        anchors.centerIn: parent
        spacing: root.digitSize * 0.22

        Row {
            id: clockRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.digitSize * 0.08

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: DateTime.hours
                color: root.brightColor
                font.family: Appearance.font.family.main
                font.variableAxes: ({ "wght": 800, "wdth": 112, "ROND": 100 })
                font.pixelSize: Math.round(root.digitSize)
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.digitSize * 0.12
                MaterialShape {
                    implicitSize: root.digitSize * 0.15
                    shape: MaterialShape.Shape.Cookie4Sided
                    color: root.midColor
                }
                MaterialShape {
                    implicitSize: root.digitSize * 0.15
                    shape: MaterialShape.Shape.Cookie4Sided
                    color: root.midColor
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: DateTime.minutes
                color: root.brightColor
                font.family: Appearance.font.family.main
                font.variableAxes: ({ "wght": 350, "wdth": 112, "ROND": 100 })
                font.pixelSize: Math.round(root.digitSize)
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(2, root.digitSize * 0.015)
            height: root.digitSize * 0.8
            radius: width / 2
            color: root.lineColor
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: root.sideWidth
            spacing: root.digitSize * 0.12

            Column {
                width: parent.width
                spacing: root.digitSize * 0.01

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: DateTime.dayNameLong
                    color: root.brightColor
                    font.family: Appearance.font.family.main
                    font.variableAxes: ({ "wght": 700, "wdth": 100, "ROND": 100 })
                    font.pixelSize: Math.round(root.digitSize * 0.2)
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: DateTime.dayOfMonth + " " + DateTime.monthNameLong + (DateTime.use12HourClock ? "  ·  " + DateTime.meridiem.toUpperCase() : "")
                    color: root.midColor
                    font.family: Appearance.font.family.main
                    font.variableAxes: ({ "wght": 450, "wdth": 100, "ROND": 100 })
                    font.pixelSize: Math.round(root.digitSize * 0.13)
                }
            }

            // Now playing.
            Row {
                visible: root.hasMedia
                width: parent.width
                spacing: root.digitSize * 0.08

                MediaShapedArt {
                    id: art
                    width: root.digitSize * 0.42
                    height: width
                    anchors.verticalCenter: parent.verticalCenter
                    source: root.hasMedia ? CoverArt.source(MprisController.artUrl) : ""
                    shape: root.player?.isPlaying ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Circle
                    placeholderColor: root.lineColor
                    placeholderIconColor: root.midColor
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        saturation: -1
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - art.width - parent.spacing
                    spacing: root.digitSize * 0.015

                    Row {
                        width: parent.width
                        spacing: root.digitSize * 0.03
                        MaterialSymbol {
                            id: playState
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.player?.isPlaying ? "graphic_eq" : "pause"
                            fill: 1
                            iconSize: Math.round(root.digitSize * 0.11)
                            color: root.midColor
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - playState.width - parent.spacing
                            elide: Text.ElideRight
                            text: root.player?.trackTitle ?? ""
                            color: root.brightColor
                            font.family: Appearance.font.family.main
                            font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                            font.pixelSize: Math.round(root.digitSize * 0.12)
                        }
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        visible: text !== ""
                        text: root.player?.trackArtist ?? ""
                        color: root.midColor
                        font.family: Appearance.font.family.main
                        font.variableAxes: ({ "wght": 450, "wdth": 100, "ROND": 100 })
                        font.pixelSize: Math.round(root.digitSize * 0.1)
                    }
                }
            }
        }
    }
}
