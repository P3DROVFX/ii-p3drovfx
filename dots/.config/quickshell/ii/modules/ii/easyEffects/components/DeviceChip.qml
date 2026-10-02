import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One connected device in the strip over the Presets page: its glyph, its name, and the
 * preset it starts with under it. The one being looked at is a secondary container, the
 * others dashed; a dot marks the one the system is playing through right now.
 */
Rectangle {
    id: root

    property string symbol: "speaker"
    property string label: ""
    property string preset: ""
    property bool selected: false
    property bool playing: false
    property real maxWidth: EasyEffectsStyle.sheetWidth

    signal triggered()

    implicitWidth: Math.min(root.maxWidth, chipRow.implicitWidth + EasyEffectsStyle.gapLarge * 2 - EasyEffectsStyle.gapSmall)
    implicitHeight: EasyEffectsStyle.railRowHeight - EasyEffectsStyle.gapSmall
    radius: EasyEffectsStyle.radiusChip
    color: root.selected ? EasyEffectsStyle.colSecondaryContainer
        : pointer.containsMouse ? EasyEffectsStyle.tint(EasyEffectsStyle.colPrimary, EasyEffectsStyle.tintIdle) : "transparent"

    Behavior on color {
        animation: EasyEffectsStyle.motionFast.colorAnimation.createObject(this)
    }

    DashedBorder {
        anchors.fill: parent
        visible: !root.selected
        color: EasyEffectsStyle.tint(EasyEffectsStyle.colSubtext, EasyEffectsStyle.tintDash)
        borderWidth: 1
        dashLength: 4
        gapLength: 3
        radius: root.radius
    }

    RowLayout {
        id: chipRow
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            leftMargin: EasyEffectsStyle.gapSmall
            right: parent.right
            rightMargin: EasyEffectsStyle.gapLarge - 2
        }
        spacing: EasyEffectsStyle.gapSmall + 2

        EasyEffectsBadge {
            size: EasyEffectsStyle.pillHeight + EasyEffectsStyle.gapSmall / 2
            text: root.symbol
            shape: root.selected ? EasyEffectsStyle.morphOf(MaterialShape.Shape.Cookie9Sided) : MaterialShape.Shape.Cookie9Sided
            color: root.selected ? EasyEffectsStyle.colPrimary : EasyEffectsStyle.colSecondaryContainer
            colSymbol: root.selected ? EasyEffectsStyle.colOnPrimary : EasyEffectsStyle.colOnSecondaryContainer
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.label
                elide: Text.ElideRight
                font.variableAxes: EasyEffectsStyle.axesName
                font.pixelSize: EasyEffectsStyle.textNormal
                color: root.selected ? EasyEffectsStyle.colOnSecondaryContainer : EasyEffectsStyle.colOnSurface
            }

            StyledText {
                Layout.fillWidth: true
                text: root.preset.length > 0 ? root.preset : Translation.tr("No default preset")
                elide: Text.ElideRight
                font.pixelSize: EasyEffectsStyle.textCaption
                color: root.selected ? EasyEffectsStyle.tint(EasyEffectsStyle.colOnSecondaryContainer, EasyEffectsStyle.tintSubtext) : EasyEffectsStyle.colSubtext
            }
        }

        // The device in use: a dot, with the word on hover.
        Rectangle {
            visible: root.playing
            implicitWidth: EasyEffectsStyle.gapSmall
            implicitHeight: EasyEffectsStyle.gapSmall
            radius: width / 2
            color: EasyEffectsStyle.colPrimary
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.triggered()
    }

    StyledToolTip {
        text: root.playing ? Translation.tr("In use right now") : root.label
        extraVisibleCondition: pointer.containsMouse
    }
}
