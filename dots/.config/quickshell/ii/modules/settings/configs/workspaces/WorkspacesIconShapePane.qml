import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "WorkspaceShapes.js" as Shapes

/**
 * Crops every app icon in the shell with one Material shape. The switch in the header
 * unfolds the shape grid; the subtitle names the shape under the pointer.
 */
WorkspacesPane {
    id: root

    readonly property var icons: Config.options.appearance.icons
    property string hoveredShape: ""

    symbol: "interests"
    title: Translation.tr("App icon shape")
    engaged: root.hoveredShape.length > 0
    subtitle: root.hoveredShape.length > 0 ? Shapes.label(root.hoveredShape)
        : root.icons.enableShapeMask ? Shapes.label(root.icons.shapeMask)
        : Translation.tr("Icons keep their own shape")

    headerExtra: StyledSwitch {
        checked: root.icons.enableShapeMask
        onToggled: root.icons.enableShapeMask = checked
        StyledToolTip {
            text: Translation.tr("Crops the icons using the selected material shape")
        }
    }

    WorkspacesReveal {
        Layout.fillWidth: true
        open: root.icons.enableShapeMask
        sourceComponent: WorkspacesShapeGrid {
            currentValue: root.icons.shapeMask
            onSelected: value => root.icons.shapeMask = value
            onHoveredShapeChanged: root.hoveredShape = hoveredShape
        }
    }
}
