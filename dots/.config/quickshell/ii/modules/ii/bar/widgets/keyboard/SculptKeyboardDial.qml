pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * `dial` variant of the Sculpt keyboard layout — the world clock's dial, small.
 *
 * A soft disc with the code at its centre and one tick per configured layout
 * around the rim. A vivid marker sits on the current layout's tick and travels
 * forward round the rim on every switch — rotation that means something: where
 * you are in the cycle. Beside it (horizontal bar, when enabled) the layout's
 * full name, and the next one in a lighter, slanted voice.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property BarWidgetPalette tones
    property bool hovered: false
    property var codes: []
    property int currentIndex: 0
    property bool showName: true
    property string currentName: ""

    readonly property int count: Math.max(1, root.codes.length)
    readonly property bool named: root.showName && !root.vertical
    readonly property real rimRadius: root.thickness / 2 - 4

    // Steps taken, never unwound: the marker always moves forward.
    property int steps: root.currentIndex
    property int lastIndex: root.currentIndex
    onCurrentIndexChanged: {
        const delta = ((root.currentIndex - root.lastIndex) % root.count + root.count) % root.count;
        root.steps += delta;
        root.lastIndex = root.currentIndex;
    }
    property real markerAngle: -90 + root.steps * 360 / root.count
    Behavior on markerAngle {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    implicitWidth: root.vertical ? root.thickness : root.thickness + (root.named ? labels.implicitWidth + 8 : 0)
    implicitHeight: root.thickness

    Rectangle {
        id: dial
        width: root.thickness
        height: root.thickness
        radius: width / 2
        color: root.hovered ? root.tones.colBackgroundVariantHover : root.tones.colBackgroundVariant
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(dial)
        }

        Repeater {
            model: root.codes.length > 1 ? root.count : 0

            delegate: Rectangle {
                required property int index
                readonly property real angle: (-90 + index * 360 / root.count) * Math.PI / 180
                width: 3
                height: 3
                radius: 1.5
                x: dial.width / 2 + root.rimRadius * Math.cos(angle) - width / 2
                y: dial.height / 2 + root.rimRadius * Math.sin(angle) - height / 2
                color: root.tones.colOnBackgroundVariant
                opacity: 0.45
            }
        }

        Rectangle {
            visible: root.codes.length > 1
            readonly property real angle: root.markerAngle * Math.PI / 180
            width: 7
            height: 7
            radius: 3.5
            x: dial.width / 2 + root.rimRadius * Math.cos(angle) - width / 2
            y: dial.height / 2 + root.rimRadius * Math.sin(angle) - height / 2
            color: root.tones.colBackground
        }

        StyledText {
            anchors.centerIn: parent
            text: root.codes[root.currentIndex] ?? ""
            color: root.tones.colOnBackgroundVariant
            font.family: Appearance.font.family.main
            font.pixelSize: Math.round(root.thickness * 0.34)
            font.variableAxes: ({
                "wght": 800,
                "wdth": 80,
                "ROND": 100
            })
        }
    }

    Column {
        id: labels
        visible: root.named
        x: root.thickness + 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: -1

        StyledText {
            width: Math.min(implicitWidth, 120)
            text: root.currentName.length > 0 ? root.currentName : (root.codes[root.currentIndex] ?? "").toUpperCase()
            elide: Text.ElideRight
            color: root.tones.colBare
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        StyledText {
            visible: root.codes.length > 1
            text: Translation.tr("next · %1").arg((root.codes[(root.currentIndex + 1) % root.count] ?? "").toUpperCase())
            color: root.tones.colBare
            opacity: 0.7
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.variableAxes: ({
                "wght": 420,
                "wdth": 100,
                "slnt": -10,
                "ROND": 100
            })
        }
    }
}
