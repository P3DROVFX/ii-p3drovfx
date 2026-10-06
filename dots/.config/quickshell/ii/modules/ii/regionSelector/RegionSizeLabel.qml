import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// Selection size in the shell's expressive digits: two tall condensed numbers
// with a light, wide "×" between them and a small "px" unit. The width and the
// height are the one number this overlay is about, so they get the display
// face; everything around them stays quiet.
Item {
    id: root

    property int sizeW: 0
    property int sizeH: 0
    property int digitSize: 22
    property color colDigits: Appearance.colors.colOnPrimaryContainer
    property color colMuted: ColorUtils.transparentize(colDigits, 0.35)
    property bool showUnit: true

    readonly property var axesDigits: ({
            "wght": 760,
            "wdth": 40,
            "ROND": 100
        })
    readonly property var axesSign: ({
            "wght": 350,
            "wdth": 100,
            "ROND": 100
        })

    function group(n) {
        var str = String(Math.max(0, Math.round(n)));
        var out = "";
        for (var i = 0; i < str.length; i++) {
            if (i > 0 && (str.length - i) % 3 === 0)
                out += ",";
            out += str[i];
        }
        return out;
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row

        spacing: Math.round(root.digitSize * 0.18)

        StyledText {
            id: wText

            text: root.group(root.sizeW)
            font.family: Appearance.font.family.main
            font.variableAxes: root.axesDigits
            font.pixelSize: Math.round(root.digitSize)
            color: root.colDigits
        }

        StyledText {
            anchors.baseline: wText.baseline
            text: "×"
            font.family: Appearance.font.family.main
            font.variableAxes: root.axesSign
            font.pixelSize: Math.round(root.digitSize * 0.72)
            color: root.colMuted
        }

        StyledText {
            anchors.baseline: wText.baseline
            text: root.group(root.sizeH)
            font.family: Appearance.font.family.main
            font.variableAxes: root.axesDigits
            font.pixelSize: Math.round(root.digitSize)
            color: root.colDigits
        }

        StyledText {
            visible: root.showUnit
            anchors.baseline: wText.baseline
            leftPadding: 1
            text: "px"
            font.family: Appearance.font.family.main
            font.pixelSize: Math.round(Math.max(Appearance.font.pixelSize.smallest, root.digitSize * 0.48))
            font.weight: Font.Bold
            color: root.colMuted
        }

    }

}
