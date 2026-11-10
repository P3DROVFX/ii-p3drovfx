pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * `fill` variant of Sculpt timer — the capsule is the progress bar.
 *
 * Each readout is a soft capsule that the vivid tone fills from the leading
 * end as the time goes (the stopwatch fills once a minute, the next alarm as it
 * comes closer). The readout is drawn twice, once per tone, and the vivid copy
 * is cut to the fill: the digits change colour exactly where the fill's edge
 * crosses them. Each second glides over its whole second, so the edge moves
 * continuously instead of stepping; a reset takes the spatial curve back.
 */
Item {
    id: root

    property real thickness: 32
    property BarWidgetPalette tones
    property var keys: []
    property var entryFor: function (key) { return null; }

    signal triggered(string key)

    readonly property real radius: Appearance.rounding.scale === 0 ? 0 : root.thickness / 2

    implicitWidth: row.implicitWidth
    implicitHeight: root.thickness

    component Face: Row {
        id: face
        property var e: ({})
        property color ink: "white"
        spacing: 5

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: face.e.icon ?? "timer"
            fill: face.e.paused ? 0 : 1
            iconSize: Math.round(root.thickness * 0.5)
            color: face.ink
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: (face.e.text ?? "") + (face.e.minor ?? "")
            color: face.ink
            font.family: Appearance.font.family.title
            font.pixelSize: Math.round(root.thickness * 0.5)
            font.variableAxes: ({
                "wght": face.e.paused ? 450 : 760,
                "ROND": 100
            })
            font.features: ({
                "tnum": 1
            })
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5

        Repeater {
            model: root.keys

            delegate: Item {
                id: readout
                required property string modelData
                readonly property var e: root.entryFor(readout.modelData) ?? ({})
                readonly property bool hovered: press.containsMouse

                property real shown: readout.e.elapsed ?? 0
                property real target: readout.e.elapsed ?? 0
                onTargetChanged: {
                    glide.stop();
                    const delta = Math.abs(readout.target - readout.shown);
                    if (Appearance.reducedMotion || !readout.visible) {
                        readout.shown = readout.target;
                        return;
                    }
                    glide.from = readout.shown;
                    glide.to = readout.target;
                    glide.duration = delta < 0.05 ? 1000 : Appearance.animation.elementMove.duration;
                    glide.easing.type = delta < 0.05 ? Easing.Linear : Easing.OutCubic;
                    glide.start();
                }
                NumberAnimation {
                    id: glide
                    target: readout
                    property: "shown"
                }

                implicitWidth: bottomFace.implicitWidth + 24
                implicitHeight: root.thickness

                Rectangle {
                    anchors.fill: parent
                    radius: root.radius
                    color: readout.hovered ? root.tones.colBackgroundVariantHover : root.tones.colBackgroundVariant
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(parent)
                    }
                }

                Face {
                    id: bottomFace
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    e: readout.e
                    ink: root.tones.colOnBackgroundVariant
                }

                // The fill, and the readout again in the fill's own ink.
                Item {
                    width: Math.round(readout.width * Math.max(0, Math.min(1, readout.shown)))
                    height: parent.height
                    clip: true

                    Rectangle {
                        width: readout.width
                        height: readout.height
                        radius: root.radius
                        color: readout.hovered ? root.tones.colBackgroundHover : root.tones.colBackground
                    }

                    Face {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        e: readout.e
                        ink: root.tones.colOnBackground
                    }
                }

                MouseArea {
                    id: press
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.triggered(readout.modelData)
                }

                StyledToolTip {
                    text: readout.e.label ?? ""
                    alternativeVisibleCondition: readout.hovered
                    extraVisibleCondition: false
                    requireOverlay: false
                }
            }
        }
    }
}
