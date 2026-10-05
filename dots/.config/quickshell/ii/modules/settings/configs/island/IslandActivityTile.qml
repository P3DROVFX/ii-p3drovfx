import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One activity: its glyph, name, where it shows right now, and its switch.
 *
 * On or off is the switch and the glyph's shape (a circle while off, the activity's
 * own shape once on); being the one on the stage is the tile's fill. Pressing the
 * tile puts the activity on the stage, the switch only switches. A sub-option (the
 * workspace bubble, one-line notifications) rides on the tile as a chip.
 */
RippleButton {
    id: root

    property var entry: ({})
    property bool activityOn: false
    property bool selected: false
    /** Where the activity shows, said in a few words; replaced by "Off" while off. */
    property string whereText: ""
    property string chipLabel: ""
    property bool chipChosen: false

    signal toggledByUser(bool value)
    signal chipToggled(bool value)

    readonly property color colContent: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1

    implicitHeight: 124
    buttonRadius: Appearance.rounding.large
    buttonRadiusPressed: Appearance.rounding.normal
    colBackground: root.selected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
    colBackgroundHover: root.selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
    colRipple: root.selected ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer1Active

    contentItem: Item {
        MaterialShapeWrappedMaterialSymbol {
            id: glyph
            x: 16
            y: 16
            text: root.entry.icon ?? ""
            iconSize: 20
            padding: 10
            fill: root.activityOn ? 1 : 0
            shape: root.activityOn ? glyph.getShape(root.entry.shape ?? "Cookie9Sided") : MaterialShape.Shape.Circle
            color: root.activityOn ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
            colSymbol: root.activityOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledSwitch {
            id: toggle
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: glyph.verticalCenter
            sizeScale: 0.8
            checked: root.activityOn
            onToggled: {
                root.toggledByUser(toggle.checked);
                // The click broke the binding; the config is the truth again.
                toggle.checked = Qt.binding(() => root.activityOn);
            }
        }

        StyledText {
            id: title
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 18
            anchors.rightMargin: 16
            y: glyph.y + glyph.height + 10
            text: Translation.tr(root.entry.label ?? "")
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            font.pixelSize: Appearance.font.pixelSize.large
            color: root.colContent
            opacity: root.activityOn ? 1 : 0.62
            elide: Text.ElideRight
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 18
            anchors.rightMargin: 12
            anchors.top: title.bottom
            anchors.topMargin: 2
            spacing: 6

            MaterialSymbol {
                visible: root.activityOn
                text: "arrow_outward"
                iconSize: Appearance.font.pixelSize.small
                color: root.colContent
                opacity: 0.65
            }

            StyledText {
                Layout.fillWidth: true
                text: root.activityOn ? root.whereText : Translation.tr("Off")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.colContent
                opacity: 0.72
                elide: Text.ElideRight
            }

            RippleButton {
                id: chip
                visible: root.chipLabel !== "" && root.activityOn
                implicitHeight: 26
                implicitWidth: chipRow.implicitWidth + 18
                buttonRadius: height / 2
                buttonRadiusPressed: Appearance.rounding.verysmall
                colBackground: root.chipChosen ? Appearance.colors.colPrimary : ColorUtils.applyAlpha(root.colContent, 0.08)
                colBackgroundHover: root.chipChosen ? Appearance.colors.colPrimaryHover : ColorUtils.applyAlpha(root.colContent, 0.16)
                colRipple: root.chipChosen ? Appearance.colors.colPrimaryActive : ColorUtils.applyAlpha(root.colContent, 0.24)
                onClicked: root.chipToggled(!root.chipChosen)

                contentItem: Item {
                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: root.chipChosen ? "check" : "add"
                            iconSize: Appearance.font.pixelSize.small
                            color: root.chipChosen ? Appearance.colors.colOnPrimary : root.colContent
                        }
                        StyledText {
                            text: root.chipLabel
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: root.chipChosen ? Appearance.colors.colOnPrimary : root.colContent
                        }
                    }
                }
            }
        }
    }
}
