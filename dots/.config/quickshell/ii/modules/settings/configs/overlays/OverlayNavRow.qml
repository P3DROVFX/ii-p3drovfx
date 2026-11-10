import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A row of the grouped overlays list (rail vocabulary: outer corners large, joins very
 * small, the engaged row rounds into a pill). The way in is a big trailing button that
 * morphs from a circle to a cookie and fills with primary on hover, so "there is more
 * behind this" reads at a glance; an optional inline switch sits before it.
 */
Rectangle {
    id: root

    property string symbol: ""
    property var shape: MaterialShape.Shape.Cookie7Sided
    property string title: ""
    property string summary: ""
    property bool first: false
    property bool last: false
    property bool hasSwitch: false
    property bool checked: false
    // Without a page behind it the row is just a switch: the arrow goes and a tap toggles.
    property bool hasOpen: true

    signal toggled(bool value)
    signal openRequested()

    readonly property bool engaged: rowHover.hovered || rowTap.pressed
    readonly property real outer: Appearance.rounding.large
    readonly property real join: Appearance.rounding.verysmall
    property real pill: root.engaged ? 1 : 0
    Behavior on pill { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }

    Layout.fillWidth: true
    implicitHeight: 80
    topLeftRadius: root.first ? root.outer : root.join + (root.outer - root.join) * root.pill
    topRightRadius: topLeftRadius
    bottomLeftRadius: root.last ? root.outer : root.join + (root.outer - root.join) * root.pill
    bottomRightRadius: bottomLeftRadius
    color: root.engaged ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

    HoverHandler {
        id: rowHover
        cursorShape: Qt.PointingHandCursor
    }
    // Under the content, so the switch keeps its own clicks
    TapHandler {
        id: rowTap
        onTapped: {
            if (root.hasOpen)
                root.openRequested();
            else if (root.hasSwitch)
                root.toggled(!root.checked);
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 14

        MaterialShapeWrappedMaterialSymbol {
            text: root.symbol
            iconSize: 22
            padding: 11
            shape: root.shape
            color: Appearance.colors.colSecondaryContainer
            colSymbol: Appearance.colors.colOnSecondaryContainer
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: root.summary
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        StyledSwitch {
            visible: root.hasSwitch
            sizeScale: 0.85
            checked: root.checked
            onToggled: root.toggled(checked)
        }

        // the way in
        Item {
            visible: root.hasOpen
            implicitWidth: 52
            implicitHeight: 52
            MaterialShapeWrappedMaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_forward"
                iconSize: 22
                padding: 13
                shape: root.engaged ? MaterialShape.Shape.Cookie4Sided : MaterialShape.Shape.Circle
                color: root.engaged ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                colSymbol: root.engaged ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
        }
    }
}
