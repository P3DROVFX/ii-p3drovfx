import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.lockscreen

/**
 * How the app icons on the workspaces look: a tint whose zero is off, and a mask
 * that crops them to a Material shape picked from the grid.
 */
Rectangle {
    id: root

    readonly property var cfg: Config.options.bar.workspaces
    readonly property var icons: Config.options.appearance.icons
    readonly property real tintStrength: root.cfg.monochromeIcons ? 1 - (Config.options.appearance.iconTintPercentage ?? 0.6) : 0
    readonly property alias triedShape: shapes.tried

    readonly property real padding: 20
    readonly property real tintStep: 0.05

    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.padding
        spacing: 16

        LockSliderRow {
            Layout.fillWidth: true
            symbol: "humidity_percentage"
            label: Translation.tr("Tint workspaces icons")
            activeShape: MaterialShape.Shape.Flower
            from: 0
            to: 1
            stepSize: root.tintStep
            value: root.tintStrength
            onMoved: v => {
                if (v <= 0.0001) {
                    root.cfg.monochromeIcons = false;
                    return;
                }
                Config.options.appearance.iconTintPercentage = 1 - v;
                root.cfg.monochromeIcons = true;
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            MaterialShapeWrappedMaterialSymbol {
                text: "interests"
                iconSize: 18
                padding: 5
                fill: root.icons.enableShapeMask ? 1 : 0
                shape: root.icons.enableShapeMask ? MaterialShape.Shape.Clover4Leaf : MaterialShape.Shape.Circle
                color: root.icons.enableShapeMask ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                colSymbol: root.icons.enableShapeMask ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Apply shape mask to icons")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Crops the icons using the selected material shape")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
            StyledSwitch {
                id: maskSwitch
                checked: root.icons.enableShapeMask
                onToggled: {
                    root.icons.enableShapeMask = maskSwitch.checked;
                    maskSwitch.checked = Qt.binding(() => root.icons.enableShapeMask);
                }
            }
        }

        WorkspacesShapeGrid {
            id: shapes
            Layout.fillWidth: true
            visible: root.icons.enableShapeMask
            currentValue: root.icons.shapeMask
            onSelected: value => root.icons.shapeMask = value
        }
    }
}
