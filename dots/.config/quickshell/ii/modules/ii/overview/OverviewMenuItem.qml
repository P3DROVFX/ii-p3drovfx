import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * One row of a window menu: icon, label and, for a state the window is in,
 * a filled check at the end.
 *
 * Rows of a group share one shape — outer corners large, joins small — and
 * the row under the pointer becomes a pill. `danger` rows speak in the error
 * colour and fill with its container.
 */
RippleButton {
    id: root

    property string symbol
    property string label
    property bool danger: false
    property bool first: false
    property bool last: false
    property bool animationsEnabledHere: true
    // The compact context menu style: shorter rows, smaller glyphs.
    property bool dense: false
    readonly property real itemPadding: root.dense ? 10 : OverviewStyle.menuItemPadding
    readonly property real iconSize: root.dense ? 18 : OverviewStyle.menuIconSize
    readonly property real toggleSize: root.dense ? 20 : OverviewStyle.menuToggleSize

    readonly property bool engaged: root.hovered || root.down
    readonly property color colContent: root.danger ? (root.engaged ? OverviewStyle.colOnMenuDangerHover : OverviewStyle.colMenuDanger)
        : root.engaged ? OverviewStyle.colOnMenuItemHover : OverviewStyle.colOnMenu

    implicitHeight: root.dense ? 32 : OverviewStyle.menuItemHeight
    padding: 0
    animationsEnabled: root.animationsEnabledHere
    topLeftRadius: OverviewStyle.menuItemRadius(height, root.first, root.last, true, root.engaged)
    topRightRadius: OverviewStyle.menuItemRadius(height, root.first, root.last, true, root.engaged)
    bottomLeftRadius: OverviewStyle.menuItemRadius(height, root.first, root.last, false, root.engaged)
    bottomRightRadius: OverviewStyle.menuItemRadius(height, root.first, root.last, false, root.engaged)

    colBackground: OverviewStyle.colMenu
    colBackgroundHover: root.danger ? OverviewStyle.colMenuDangerHover : OverviewStyle.colMenuItemHover
    colBackgroundActive: root.danger ? OverviewStyle.colMenuDangerActive : OverviewStyle.colMenuItemActive
    colBackgroundToggled: root.colBackground
    colBackgroundToggledHover: root.colBackgroundHover
    colBackgroundToggledActive: root.colBackgroundActive
    colRipple: root.colBackgroundActive
    colRippleToggled: root.colBackgroundActive

    contentItem: Item {
        MaterialSymbol {
            id: icon
            x: root.itemPadding
            anchors.verticalCenter: parent.verticalCenter
            text: root.symbol
            iconSize: root.iconSize
            fill: root.engaged ? 1 : 0
            color: root.colContent
            Behavior on fill {
                enabled: root.animationsEnabledHere
                animation: OverviewStyle.motionFast.numberAnimation.createObject(this)
            }
            Behavior on color {
                enabled: root.animationsEnabledHere
                animation: OverviewStyle.motionFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            anchors {
                left: icon.right
                leftMargin: root.dense ? 10 : OverviewStyle.menuItemSpacing
                right: toggleMark.visible ? toggleMark.left : parent.right
                rightMargin: root.itemPadding
                verticalCenter: parent.verticalCenter
            }
            text: root.label
            elide: Text.ElideRight
            color: root.colContent
            font.family: Appearance.font.family.main
            font.pixelSize: root.dense ? Appearance.font.pixelSize.smallie + 1 : OverviewStyle.menuLabelSize
            font.variableAxes: root.engaged ? OverviewStyle.menuLabelAxesHover : OverviewStyle.menuLabelAxes
            Behavior on color {
                enabled: root.animationsEnabledHere
                animation: OverviewStyle.motionFast.colorAnimation.createObject(this)
            }
        }

        Rectangle {
            id: toggleMark
            visible: root.toggled
            anchors {
                right: parent.right
                rightMargin: root.itemPadding - (root.toggleSize - root.iconSize) / 2
                verticalCenter: parent.verticalCenter
            }
            width: root.toggleSize
            height: root.toggleSize
            radius: OverviewStyle.radiusFor(height)
            color: OverviewStyle.colMenuToggled

            MaterialSymbol {
                anchors.centerIn: parent
                text: "check"
                iconSize: root.dense ? 14 : OverviewStyle.menuToggleIconSize
                fill: 1
                color: OverviewStyle.colOnMenuToggled
            }
        }
    }
}
