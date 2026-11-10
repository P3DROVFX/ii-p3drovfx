pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * `stamp` variant of Sculpt weather — the condition as a word, the
 * temperature as a stamp.
 *
 * The card carries one display word for the sky — SUN, CLOUD, RAIN, STORM —
 * set black, wide and slanted. The temperature is stamped over the card's end
 * inside a shape that is the weather itself, so the outline already says it
 * before the number does; when the weather changes, the stamp morphs.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property BarWidgetPalette tones
    property bool hovered: false
    property string condition: "sun"
    property string word: ""
    property string digits: "--"

    readonly property int stampShape: ({
        "sun": MaterialShape.Shape.Sunny,
        "clear": MaterialShape.Shape.Cookie12Sided,
        "cloud": MaterialShape.Shape.Puffy,
        "fog": MaterialShape.Shape.Pill,
        "rain": MaterialShape.Shape.Ghostish,
        "snow": MaterialShape.Shape.Flower,
        "storm": MaterialShape.Shape.Burst
    })[root.condition] ?? MaterialShape.Shape.Circle
    readonly property real stampSize: root.thickness + 2
    readonly property real overlap: Math.round(root.thickness * 0.3)
    readonly property real cardLength: (root.vertical ? wordText.implicitWidth : wordText.implicitWidth) + 20 + root.overlap

    implicitWidth: root.vertical ? root.thickness : root.cardLength + root.stampSize - root.overlap
    implicitHeight: root.vertical ? root.cardLength + root.stampSize - root.overlap : root.thickness

    Rectangle {
        id: card
        width: root.vertical ? root.thickness : root.cardLength
        height: root.vertical ? root.cardLength : root.thickness
        radius: Appearance.rounding.scale === 0 ? 0 : Math.round(root.thickness * 0.3)
        color: root.hovered ? root.tones.colBackgroundHover : root.tones.colBackground
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(card)
        }

        StyledText {
            id: wordText
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.vertical ? 0 : -Math.round(root.overlap / 2)
            anchors.verticalCenterOffset: root.vertical ? -Math.round(root.overlap / 2) : 0
            rotation: root.vertical ? (Config.options.bar.bottom ? 90 : -90) : 0
            text: root.word.toUpperCase()
            color: root.tones.colOnBackground
            font.family: Appearance.font.family.main
            font.pixelSize: Math.round(root.thickness * 0.5)
            font.letterSpacing: -0.4
            font.variableAxes: ({
                "wght": 900,
                "wdth": 125,
                "slnt": -10,
                "ROND": 0
            })
        }
    }

    MaterialShape {
        id: stamp
        x: root.vertical ? Math.round((root.thickness - root.stampSize) / 2) : card.width - root.overlap
        y: root.vertical ? card.height - root.overlap : Math.round((root.thickness - root.stampSize) / 2)
        implicitSize: root.stampSize
        shape: root.stampShape
        color: root.tones.colBackgroundVariant

        StyledText {
            anchors.centerIn: parent
            text: root.digits + "°"
            color: root.tones.colOnBackgroundVariant
            font.family: Appearance.font.family.title
            font.pixelSize: Math.round(root.thickness * (root.digits.length > 2 ? 0.32 : 0.38))
            font.variableAxes: ({
                "wght": 800,
                "ROND": 100
            })
            font.features: ({
                "tnum": 1
            })
        }
    }
}
