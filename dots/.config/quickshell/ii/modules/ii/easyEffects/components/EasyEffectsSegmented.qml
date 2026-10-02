import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Two or three exclusive choices drawn as one joined group (Output / Input): the chosen
 * segment is a full primary pill, the others secondary containers that keep a small
 * corner where they meet, so the choice reads as a notch pressed into the group. Collapses
 * to icons only when `compact`.
 */
RowLayout {
    id: root

    /// [{ id, icon, label }]
    property var options: []
    property string current: ""
    property bool compact: false

    signal chosen(string id)

    spacing: EasyEffectsStyle.gapTiny - 1

    Repeater {
        model: root.options

        RippleButton {
            id: segment
            required property var modelData
            required property int index
            readonly property bool picked: root.current === segment.modelData.id
            readonly property bool first: segment.index === 0
            readonly property bool last: segment.index === root.options.length - 1
            readonly property real full: EasyEffectsStyle.pill(EasyEffectsStyle.buttonHeight)

            implicitHeight: EasyEffectsStyle.buttonHeight
            implicitWidth: root.compact ? EasyEffectsStyle.buttonHeight + EasyEffectsStyle.gapSmall : segmentRow.implicitWidth + EasyEffectsStyle.gapHuge * 2 - EasyEffectsStyle.gapSmall
            toggled: segment.picked
            colBackground: EasyEffectsStyle.colSecondaryContainer
            colBackgroundHover: EasyEffectsStyle.colSecondaryContainerHover
            colBackgroundActive: EasyEffectsStyle.colSecondaryContainerActive
            colBackgroundToggled: EasyEffectsStyle.colPrimary
            colBackgroundToggledHover: EasyEffectsStyle.colPrimaryHover
            colBackgroundToggledActive: EasyEffectsStyle.colPrimaryActive
            colRipple: EasyEffectsStyle.colPrimaryActive
            topLeftRadius: segment.picked || segment.first ? segment.full : EasyEffectsStyle.radiusJoin
            bottomLeftRadius: segment.topLeftRadius
            topRightRadius: segment.picked || segment.last ? segment.full : EasyEffectsStyle.radiusJoin
            bottomRightRadius: segment.topRightRadius
            onClicked: root.chosen(segment.modelData.id)

            Behavior on topLeftRadius {
                animation: EasyEffectsStyle.motionFast.numberAnimation.createObject(this)
            }
            Behavior on topRightRadius {
                animation: EasyEffectsStyle.motionFast.numberAnimation.createObject(this)
            }

            contentItem: Item {
                RowLayout {
                    id: segmentRow
                    anchors.centerIn: parent
                    spacing: EasyEffectsStyle.gapSmall

                    MaterialSymbol {
                        text: segment.modelData.icon
                        iconSize: EasyEffectsStyle.iconSmall + 2
                        fill: segment.picked ? 1 : 0
                        color: segment.picked ? EasyEffectsStyle.colOnPrimary : EasyEffectsStyle.colOnSecondaryContainer
                    }

                    StyledText {
                        visible: !root.compact
                        text: segment.modelData.label
                        font.pixelSize: EasyEffectsStyle.textNormal
                        font.weight: Font.DemiBold
                        color: segment.picked ? EasyEffectsStyle.colOnPrimary : EasyEffectsStyle.colOnSecondaryContainer
                    }
                }
            }

            StyledToolTip {
                text: segment.modelData.label
                extraVisibleCondition: root.compact
            }
        }
    }
}
