pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.island
import "WorkspaceShapes.js" as Shapes

/**
 * What marks the workspace you are on. The three booleans behind it (material shape,
 * random shape, direction arrow) are mutually exclusive in the widget, so the page
 * shows them as one choice of four; the track under it plays the chosen behaviour.
 */
WorkspacesPane {
    id: root

    readonly property real hintSpacing: 4

    readonly property var cfg: Config.options.bar.workspaces
    readonly property string mode: root.cfg.useDirectionArrowForActiveIndicator ? "arrow"
        : root.cfg.useRandomShapeForActiveIndicator ? "random"
        : root.cfg.useMaterialShapeForActiveIndicator ? "shape" : "pill"
    readonly property bool shapePicking: root.mode === "shape"
    property string hoveredShape: ""

    readonly property var modes: [
        { "value": "pill", "label": Translation.tr("Pill"), "icon": "horizontal_rule", "shape": "Pill",
          "line": Translation.tr("A rounded pill that stretches toward the next workspace") },
        { "value": "shape", "label": Translation.tr("Shape"), "icon": "interests", "shape": "Cookie7Sided",
          "line": Translation.tr("One Material shape of your choice slides along") },
        { "value": "random", "label": Translation.tr("Random"), "icon": "shuffle", "shape": "Sunny",
          "line": Translation.tr("A new shape every time you switch") },
        { "value": "arrow", "label": Translation.tr("Arrow"), "icon": "arrow_forward", "shape": "Triangle",
          "line": Translation.tr("Turns into a triangle aimed at where you went, then back") }
    ]
    readonly property var modeEntry: root.modes.find(entry => entry.value === root.mode) ?? root.modes[0]

    function setMode(value) {
        root.cfg.useMaterialShapeForActiveIndicator = value === "shape";
        root.cfg.useRandomShapeForActiveIndicator = value === "random";
        root.cfg.useDirectionArrowForActiveIndicator = value === "arrow";
    }

    symbol: "adjust"
    title: Translation.tr("Active indicator")
    engaged: root.hoveredShape.length > 0
    subtitle: root.hoveredShape.length > 0 ? Shapes.label(root.hoveredShape)
        : root.shapePicking ? root.modeEntry.label + " · " + Shapes.label(root.cfg.activeIndicatorShape)
        : root.modeEntry.label

    IslandSegmentedToggle {
        Layout.fillWidth: true
        options: root.modes
        currentValue: root.mode
        onSelected: value => root.setMode(value)
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: demoColumn.implicitHeight + root.padding
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: demoColumn
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: root.padding / 2
            }
            spacing: root.hintSpacing

            WorkspacesIndicatorDemo {
                Layout.alignment: Qt.AlignHCenter
                mode: root.mode
                shapeName: root.cfg.activeIndicatorShape
                colorMode: root.cfg.colorMode
                indicatorOpacity: root.cfg.activeIndicatorOpacity / 100
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.modeEntry.line
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Tap a workspace to try it")
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: Appearance.colors.colSubtext
                opacity: 0.7
            }
        }
    }

    WorkspacesReveal {
        Layout.fillWidth: true
        open: root.shapePicking
        sourceComponent: WorkspacesShapeGrid {
            currentValue: root.cfg.activeIndicatorShape
            onSelected: value => root.cfg.activeIndicatorShape = value
            onHoveredShapeChanged: root.hoveredShape = hoveredShape
        }
    }
}
