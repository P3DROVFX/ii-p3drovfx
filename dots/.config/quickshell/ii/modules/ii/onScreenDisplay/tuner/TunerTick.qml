import QtQuick
import qs.modules.common
import qs.modules.common.functions

/**
 * One ruler tick under the Tuner's spotlight: it grows, brightens and glows as it nears the
 * centre of the viewport. The parent places it (`x`) and feeds it its distance from the
 * centre; nothing here runs unless that distance changes, i.e. while the ruler slides.
 */
Item {
    id: root

    property real distance: 0      // px from the viewport's centre
    property real midY: 0          // the tick band's vertical centre
    property real baseHeight: 8
    property bool lit: false       // on the filled side of the value
    property bool over: false      // past the safe limit (volume overdrive)
    property real edgeOpacity: 1   // fades it out at the viewport's ends

    // 1 right under the beam, 0 from 44 px out.
    readonly property real spot: Math.pow(Math.max(0, 1 - Math.abs(root.distance) / 44), 1.6)
    readonly property color lightColor: root.over ? Appearance.colors.colError : Appearance.colors.colPrimary
    readonly property color restColor: root.over
        ? ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colOutlineVariant, 0.3)
        : Appearance.colors.colOutlineVariant

    width: 2
    height: root.baseHeight * (1 + 0.9 * root.spot)
    y: root.midY - root.height / 2
    opacity: root.edgeOpacity
    visible: root.edgeOpacity > 0

    // Glow, only on the few ticks right under the beam: three soft rings stand in for a blur.
    Repeater {
        model: root.spot > 0.55 ? 3 : 0

        Rectangle {
            required property int index
            readonly property real grow: (index + 1) * 2 * root.spot

            anchors.centerIn: parent
            width: root.width + 2 * grow
            height: root.height + grow
            radius: width / 2
            color: ColorUtils.applyAlpha(root.lightColor, [0.2, 0.1, 0.05][index] * root.spot)
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 1
        opacity: root.lit ? 0.45 + 0.55 * root.spot : 1
        color: {
            if (root.lit || root.spot <= 0)
                return root.lit ? root.lightColor : root.restColor;
            return ColorUtils.mix(root.lightColor, root.restColor, 0.85 * root.spot);
        }
    }
}
