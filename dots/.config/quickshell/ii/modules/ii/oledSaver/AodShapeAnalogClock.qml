pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * AOD face: a minimal analogue clock whose face is a Material shape drawn as an
 * outline. The shape is the hour's: it morphs into the next one when the hour
 * turns (shape is state, never spun), and the hands move on the shortest arc.
 * No seconds hand - the face changes once a minute.
 */
Item {
    id: root

    property bool running: true

    readonly property color handColor: "#ededed"
    readonly property color outlineColor: "#3a3a3a"
    readonly property color markColor: "#6a6a6a"
    readonly property color captionColor: "#8c8c8c"

    readonly property real faceSize: Math.min(root.height * 0.62, root.width * 0.5)
    readonly property real ring: Math.max(3, Math.round(root.faceSize * 0.012))

    // One shape per hour of the dial, so the face reads the hour at a glance too.
    readonly property var hourShapes: [
        MaterialShape.Shape.Cookie12Sided, MaterialShape.Shape.Cookie4Sided, MaterialShape.Shape.Cookie6Sided,
        MaterialShape.Shape.Cookie7Sided, MaterialShape.Shape.Cookie9Sided, MaterialShape.Shape.Sunny,
        MaterialShape.Shape.SoftBurst, MaterialShape.Shape.Flower, MaterialShape.Shape.Clover4Leaf,
        MaterialShape.Shape.Cookie9Sided, MaterialShape.Shape.Cookie6Sided, MaterialShape.Shape.Cookie4Sided
    ]
    readonly property var faceShape: root.hourShapes[DateTime.clock.date.getHours() % 12]

    Column {
        anchors.centerIn: parent
        spacing: root.faceSize * 0.08

        Item {
            id: face
            width: root.faceSize
            height: root.faceSize

            // The outline: the shape, and the same shape a ring smaller in black on it.
            MaterialShape {
                anchors.fill: parent
                shape: root.faceShape
                color: root.outlineColor
            }
            MaterialShape {
                anchors.centerIn: parent
                width: parent.width - root.ring * 2
                height: width
                shape: root.faceShape
                color: "black"
            }

            // Quarter marks.
            Repeater {
                model: 4
                delegate: Rectangle {
                    required property int index
                    readonly property real angle: index * Math.PI / 2
                    readonly property real reach: root.faceSize * 0.34
                    width: root.ring * 2.2
                    height: width
                    radius: width / 2
                    color: root.markColor
                    x: face.width / 2 + Math.sin(angle) * reach - width / 2
                    y: face.height / 2 - Math.cos(angle) * reach - height / 2
                }
            }

            Hand {
                length: root.faceSize * 0.24
                thickness: root.ring * 3.2
                angle: DateTime.hourProgress * 360
            }
            Hand {
                length: root.faceSize * 0.36
                thickness: root.ring * 1.6
                angle: DateTime.minuteProgress * 360
            }

            Rectangle {
                anchors.centerIn: parent
                width: root.ring * 4
                height: width
                radius: width / 2
                color: root.handColor
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: DateTime.dayNameLong + "  ·  " + DateTime.dayOfMonth + " " + DateTime.monthNameShort
            color: root.captionColor
            font.family: Appearance.font.family.main
            font.variableAxes: ({ "wght": 500, "wdth": 100, "ROND": 100 })
            font.pixelSize: Math.round(root.faceSize * 0.055)
        }
    }

    // A hand pinned at the centre, pointing up at angle 0.
    component Hand: Rectangle {
        id: hand
        property real length: 100
        property real thickness: 6
        property real angle: 0

        width: hand.thickness
        height: hand.length
        radius: hand.thickness / 2
        color: root.handColor
        x: face.width / 2 - width / 2
        y: face.height / 2 - hand.length
        // Turns about its bottom edge, which sits on the pivot (the cap covers the
        // rounded end).
        transformOrigin: Item.Bottom
        rotation: hand.angle
        Behavior on rotation {
            enabled: root.running && !Appearance.reducedMotion
            RotationAnimation {
                direction: RotationAnimation.Shortest
                duration: Appearance.animation.elementMove.duration
                easing.type: Easing.OutCubic
            }
        }
    }
}
