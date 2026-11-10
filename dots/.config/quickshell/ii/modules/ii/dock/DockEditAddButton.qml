import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Edit Mode's (+) at the end of the dock: the slot that is not filled yet, in
 * the dashed outline the shell uses for one, opening the catalogue. While the
 * catalogue is open the dashes fill in and the plus turns into the shape of
 * an added tile - the morph says where the sheet came from.
 */
Item {
    id: root

    property Item dockContent: null
    property Item anchorTarget: root

    readonly property real size: Appearance.sizes.dockButtonSize
    readonly property bool open: (root.dockContent?.editMenuOpen ?? false)
        && root.dockContent.editMenuTarget?.type === "editAdd"

    width: root.size
    height: root.size

    DashedBorder {
        anchors.fill: parent
        visible: !root.open
        radius: Appearance.rounding.normal
        borderWidth: 2
        dashLength: 5
        gapLength: 4
        color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, hover.hovered ? 0.25 : 0.5)
    }

    MaterialShapeWrappedMaterialSymbol {
        anchors.centerIn: parent
        implicitSize: root.size * (hover.hovered || root.open ? 0.78 : 0.66)
        iconSize: Math.round(root.size * 0.42)
        padding: 0
        text: "add"
        shape: root.open ? MaterialShape.Shape.Cookie7Sided : MaterialShape.Shape.Circle
        color: root.open || hover.hovered ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
        colSymbol: root.open || hover.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

        Behavior on implicitSize {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: {
            if (root.open)
                return;
            root.dockContent?.openEditMenu(root.anchorTarget, { "type": "editAdd", "orderKey": root.dockContent.editAddKey });
        }
    }
}
