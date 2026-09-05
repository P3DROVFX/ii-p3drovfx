import qs.modules.common
import qs.modules.common.widgets

/**
 * One Android navigation button: back, home or recents.
 *
 * Each target is a deliberately visible circular touch plate. The parent pill groups the
 * three controls as one system-navigation surface while the generous spacing keeps adjacent
 * targets distinct for a finger.
 */
RippleButton {
    id: root

    property string symbol: ""
    property real symbolSize: 22
    property real symbolRotation: 0
    property real buttonSize: Appearance.sizes.minimumTouchTarget

    signal activated

    implicitWidth: root.buttonSize
    implicitHeight: root.buttonSize
    buttonRadius: Appearance.rounding.full
    buttonRadiusPressed: Appearance.rounding.large
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colBackgroundActive: Appearance.colors.colLayer2Active
    colRipple: Appearance.colors.colLayer2Active
    releaseAction: () => root.activated()

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        text: root.symbol
        iconSize: root.symbolSize
        rotation: root.symbolRotation
        fill: 0
        color: Appearance.colors.colOnLayer2
    }
}
