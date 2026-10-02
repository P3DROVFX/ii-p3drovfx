import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * One setting, as a row on its section's pane: a shape badge with the glyph, what it is,
 * what it does, and its control on the right (a switch, chips, a button — whatever is put
 * inside). A switch row (`toggle`) fills with the secondary container while it is on and
 * its badge morphs, the way the clock's form toggles do; the whole row is the target.
 */
Rectangle {
    id: root

    property string symbol: ""
    property string title: ""
    property string description: ""
    property int shapeKind: MaterialShape.Shape.Cookie9Sided
    /// A switch row: `checked` is its state, `toggled(checked)` asks for the opposite.
    property bool toggle: false
    property bool checked: false
    property bool clickable: root.toggle
    default property alias control: controlHolder.data

    signal toggled(bool checked)
    signal clicked()

    readonly property bool lit: root.toggle && root.checked
    readonly property color colContent: root.lit ? EasyEffectsStyle.colOnSecondaryContainer : EasyEffectsStyle.colOnSurface
    readonly property color colSubContent: root.lit ? EasyEffectsStyle.tint(EasyEffectsStyle.colOnSecondaryContainer, EasyEffectsStyle.tintSubtext) : EasyEffectsStyle.colSubtext

    Layout.fillWidth: true
    implicitHeight: Math.max(EasyEffectsStyle.railRowHeight + EasyEffectsStyle.gapLarge, rowLayout.implicitHeight + EasyEffectsStyle.gapLarge * 2)
    radius: EasyEffectsStyle.radiusRow
    color: root.lit ? EasyEffectsStyle.colSecondaryContainer
        : rowMouse.containsMouse && root.clickable ? EasyEffectsStyle.colRowHover : EasyEffectsStyle.colRow

    Behavior on color {
        animation: EasyEffectsStyle.motionFast.colorAnimation.createObject(this)
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: root.clickable
        enabled: root.clickable
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.toggle)
                root.toggled(!root.checked);
            root.clicked();
        }
    }

    RowLayout {
        id: rowLayout
        anchors {
            fill: parent
            leftMargin: EasyEffectsStyle.gapLarge - 2
            rightMargin: EasyEffectsStyle.gapLarge
        }
        spacing: EasyEffectsStyle.gap + 2

        EasyEffectsBadge {
            size: EasyEffectsStyle.fieldBadge + EasyEffectsStyle.gapTiny
            text: root.symbol
            shape: root.lit ? EasyEffectsStyle.morphOf(root.shapeKind) : root.shapeKind
            color: root.lit ? EasyEffectsStyle.colTertiary : EasyEffectsStyle.colPrimaryContainer
            colSymbol: root.lit ? EasyEffectsStyle.colOnTertiary : EasyEffectsStyle.colOnPrimaryContainer
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.title
                wrapMode: Text.WordWrap
                font.variableAxes: EasyEffectsStyle.axesName
                font.pixelSize: EasyEffectsStyle.textBody
                color: root.colContent
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.description.length > 0
                text: root.description
                wrapMode: Text.WordWrap
                font.pixelSize: EasyEffectsStyle.textSmall
                color: root.colSubContent
            }
        }

        RowLayout {
            id: controlHolder
            Layout.alignment: Qt.AlignVCenter
            spacing: EasyEffectsStyle.gapSmall

            StyledSwitch {
                visible: root.toggle
                checked: root.checked
                checkable: false
                activeColor: EasyEffectsStyle.colOnSecondaryContainer
                activeThumbColor: EasyEffectsStyle.colSecondaryContainer
                onClicked: root.toggled(!root.checked)
            }
        }
    }
}
