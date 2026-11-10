pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * The Tuner's slider body: a ruler that slides under a fixed beam, with the value beside it.
 * Counted in the caller's units: percent, or backlight levels when `stepped`. The ruler keeps
 * a fixed width; only the value readout changes the body's width.
 */
Item {
    id: root

    required property string label
    required property real value
    property real from: 0
    property real to: 100
    property real safeLimit: 0     // above 0: the ruler, value and beam turn red past it
    property bool stepped: false   // hardware levels: a major tick per level, 3 minors between

    signal valueUpdateRequested(real newValue)

    readonly property int rulerWidth: 200
    readonly property int valueGap: 10
    readonly property int edgeFade: 30
    readonly property real unitPx: root.stepped ? 44 : 5
    // Centred in the space under the label, not in the whole height.
    readonly property int tickMidY: 46
    readonly property bool over: root.safeLimit > 0 && root.value > root.safeLimit

    // The value under the beam. Animates only while the value moves; at rest nothing here
    // is re-evaluated.
    property real shown: root.value
    Behavior on shown {
        NumberAnimation {
            duration: 550
            easing.type: Easing.OutQuart
        }
    }

    readonly property var ticks: {
        const out = [];
        if (root.stepped) {
            for (let level = root.from; level <= root.to; level++) {
                out.push({ u: level, major: true });
                if (level < root.to) {
                    for (let k = 1; k < 4; k++)
                        out.push({ u: level + k / 4, major: false });
                }
            }
            return out;
        }
        const first = Math.ceil(root.from / 2) * 2;
        if (first !== root.from)
            out.push({ u: root.from, major: true });
        for (let u = first; u <= root.to; u += 2)
            out.push({ u: u, major: u % 10 === 0 });
        return out;
    }

    // Sized for the widest value this slider can show, so going from 9 to 10 doesn't resize it.
    implicitWidth: root.rulerWidth + root.valueGap + valueMeasure.implicitWidth
    implicitHeight: 72

    Item {
        id: viewport
        width: root.rulerWidth
        height: parent.height
        clip: true

        StyledText {
            y: 9
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Appearance.colors.colOutline
            font.pixelSize: 10
            font.letterSpacing: 1.6
            font.capitalization: Font.AllUppercase
        }

        Repeater {
            model: root.ticks

            TunerTick {
                required property var modelData

                distance: (modelData.u - root.shown) * root.unitPx
                x: root.rulerWidth / 2 + distance - 1
                midY: root.tickMidY
                baseHeight: modelData.major ? 16 : 8
                lit: modelData.u <= root.shown && root.shown > root.from
                over: root.safeLimit > 0 && modelData.u > root.safeLimit
                edgeOpacity: {
                    const xv = root.rulerWidth / 2 + distance;
                    return Math.max(0, Math.min(1, Math.min(xv, root.rulerWidth - xv) / root.edgeFade));
                }
            }
        }

        TunerBeam {
            x: root.rulerWidth / 2 - width / 2
            y: root.tickMidY - height / 2
            width: 28
            height: 36
            color: root.over ? Appearance.colors.colError : Appearance.colors.colPrimary
        }
    }

    // Width probe: as many digits as the largest value has (tabular digits share one width).
    StyledText {
        id: valueMeasure
        visible: false
        text: "0".repeat(String(Math.round(Math.max(Math.abs(root.from), Math.abs(root.to)))).length)
        font.pixelSize: valueText.font.pixelSize
        font.weight: valueText.font.weight
        font.features: { "tnum": 1 }
    }

    StyledText {
        id: valueText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.value)
        color: root.over ? Appearance.colors.colError : Appearance.colors.colOnLayer0
        font.pixelSize: 28
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
        horizontalAlignment: Text.AlignRight

        Behavior on color {
            ColorAnimation {
                duration: 300
            }
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (event.angleDelta.y === 0)
                return;
            const step = (root.stepped ? 1 : 2) * (event.angleDelta.y > 0 ? 1 : -1);
            const next = Math.max(root.from, Math.min(root.to, Math.round(root.value) + step));
            if (next !== Math.round(root.value))
                root.valueUpdateRequested(next);
        }
    }
}
