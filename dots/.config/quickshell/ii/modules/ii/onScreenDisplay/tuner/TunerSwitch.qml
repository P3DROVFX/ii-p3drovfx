pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The Tuner's on/off body: OFF and ON as two detents on a ruler that slides under the beam
 * (`ruler`, Config osd.tuner.toggleRuler), or the two words alone: the active one in the
 * middle, and a flip slides them across while colour, size and weight cross-fade.
 * Sized to its words and label.
 */
Item {
    id: root

    required property string label
    required property bool on
    property bool ruler: true

    readonly property int labelY: 8
    // Both words sit on it, so the selected, larger one grows upward. With the ruler, the words
    // sit above the ticks; without it, they're centred in the space under the label.
    readonly property int wordBaseline: root.ruler ? 39 : 54
    readonly property int tickMidY: 52      // below the words' baseline, clear of them
    readonly property int edgeFade: 14
    readonly property int maxWidth: 320

    // Distance between the two detents, and the viewport that holds both with room around.
    readonly property int gap: Math.round((offSelected.implicitWidth + onSelected.implicitWidth) / 2 + 22)
    readonly property real idleWordWidth: Math.max(offIdle.implicitWidth, onIdle.implicitWidth)
    readonly property int viewWidth: Math.min(root.maxWidth,
        Math.round(Math.max(2 * (root.gap + root.idleWordWidth / 2 + 18), labelMeasure.implicitWidth + 24)))

    // Strip offset under the beam: 0 on OFF, `gap` on ON. Animates only on a flip.
    property real shown: root.on ? root.gap : 0
    Behavior on shown {
        NumberAnimation {
            duration: 550
            easing.type: Easing.OutQuart
        }
    }

    readonly property var tickXs: {
        const out = [];
        const start = -Math.ceil(root.viewWidth / 16) * 8;
        for (let x = start; x <= root.gap + root.viewWidth / 2; x += 8)
            out.push(x);
        if (root.gap % 8)
            out.push(root.gap);
        return out;
    }

    implicitWidth: root.viewWidth
    implicitHeight: 72

    component Word: StyledText {
        property bool selected: false
        property real size: root.ruler ? (selected ? 18 : 14) : (selected ? 22 : 15)
        property real weightAxis: (root.ruler || selected) ? 700 : 500
        font.pixelSize: size
        font.weight: Math.round(weightAxis)
        font.variableAxes: root.ruler ? Appearance.font.variableAxes.main
            : Object.assign({}, Appearance.font.variableAxes.main, { "wght": weightAxis })
        font.letterSpacing: size * 0.08
        color: selected ? Appearance.colors.colPrimary : Appearance.colors.colOutline
    }

    // Width probes for the layout; never shown.
    Word { id: offSelected; visible: false; selected: true; text: Translation.tr("Off").toUpperCase() }
    Word { id: onSelected; visible: false; selected: true; text: Translation.tr("On").toUpperCase() }
    Word { id: offIdle; visible: false; text: Translation.tr("Off").toUpperCase() }
    Word { id: onIdle; visible: false; text: Translation.tr("On").toUpperCase() }
    StyledText {
        id: labelMeasure
        visible: false
        text: labelText.text
        font.pixelSize: labelText.font.pixelSize
        font.letterSpacing: labelText.font.letterSpacing
        font.capitalization: labelText.font.capitalization
    }

    Item {
        id: viewport
        width: root.viewWidth
        height: parent.height
        clip: true

        StyledText {
            id: labelText
            y: root.labelY
            width: root.viewWidth - 24
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.label
            color: Appearance.colors.colOutline
            font.pixelSize: 10
            font.letterSpacing: 1.6
            font.capitalization: Font.AllUppercase
        }

        Item {
            id: strip
            x: root.viewWidth / 2 - root.shown
            width: 1
            height: parent.height

            Repeater {
                model: [Translation.tr("Off"), Translation.tr("On")]

                Word {
                    required property string modelData
                    required property int index

                    x: index * root.gap - width / 2
                    y: root.wordBaseline - baselineOffset
                    text: modelData.toUpperCase()
                    selected: index === (root.on ? 1 : 0)

                    Behavior on size {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on weightAxis {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: 300
                        }
                    }
                }
            }

            Repeater {
                model: root.ruler ? root.tickXs : []

                TunerTick {
                    required property real modelData

                    distance: modelData - root.shown
                    x: modelData - 1
                    midY: root.tickMidY
                    baseHeight: (modelData === 0 || modelData === root.gap) ? 10 : 5
                    edgeOpacity: {
                        const xv = root.viewWidth / 2 + distance;
                        return Math.max(0, Math.min(1, Math.min(xv, root.viewWidth - xv) / root.edgeFade));
                    }
                }
            }
        }

        TunerBeam {
            visible: root.ruler
            x: root.viewWidth / 2 - width / 2
            y: root.tickMidY - height / 2
            width: 28
            height: 22
            color: Appearance.colors.colPrimary
        }
    }
}
