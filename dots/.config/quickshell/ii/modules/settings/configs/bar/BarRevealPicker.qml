pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * How a hidden bar comes back, as four cards that draw their trigger: a strip along the top
 * of a small screen, as thick as the zone the pointer has to touch, and a hold ring when
 * the pointer has to stay there. The chosen preset fills secondary container and its zone
 * turns primary. Values that match no preset leave every card unchosen.
 *
 * presets: [{ value, label, width, delay }]
 */
Item {
    id: root

    readonly property real gap: 8
    readonly property real minCard: 150
    readonly property real cardHeight: 118
    readonly property real stageHeight: 52
    readonly property real cardPadding: 13
    readonly property real zoneScale: 0.75

    property var presets: []
    property int currentWidth: 6
    property int currentDelay: 0
    signal selected(var preset)

    readonly property int columns: (width - root.gap * 3) / 4 >= root.minCard ? 4 : 2
    readonly property real cardWidth: Math.floor((width - root.gap * (root.columns - 1)) / root.columns)
    readonly property int rows: Math.ceil(root.presets.length / root.columns)

    implicitHeight: root.rows * root.cardHeight + (root.rows - 1) * root.gap

    Repeater {
        model: root.presets

        delegate: RippleButton {
            id: card
            required property var modelData
            required property int index
            readonly property bool chosen: card.modelData.width === root.currentWidth && card.modelData.delay === root.currentDelay
            readonly property color colContent: card.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1

            x: (card.index % root.columns) * (root.cardWidth + root.gap)
            y: Math.floor(card.index / root.columns) * (root.cardHeight + root.gap)
            width: root.cardWidth
            height: root.cardHeight
            padding: 0
            buttonRadius: card.chosen ? Appearance.rounding.large : Appearance.rounding.normal
            buttonRadiusPressed: Appearance.rounding.verysmall
            colBackground: card.chosen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
            colBackgroundHover: card.chosen ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
            colRipple: card.chosen ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer1Active
            onClicked: root.selected(card.modelData)

            contentItem: Item {
                // The top of a screen: a ghost of the bar, the zone that wakes it, the hold ring.
                Rectangle {
                    id: stage
                    x: root.cardPadding
                    y: root.cardPadding
                    width: parent.width - root.cardPadding * 2
                    height: root.stageHeight
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer0
                    clip: true

                    Rectangle {
                        id: zone
                        width: parent.width
                        height: Math.max(3, card.modelData.width * root.zoneScale)
                        color: card.chosen ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        opacity: card.chosen ? 0.9 : 0.35
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }

                    // The hidden bar it reveals: a dashed outline would be a border, so a faint plate.
                    Rectangle {
                        x: 8
                        y: 4
                        width: parent.width - 16
                        height: 8
                        radius: 4
                        color: Appearance.colors.colOnSurface
                        opacity: 0.12
                    }

                    // A pointer resting on the zone; a ring around it when it has to hold.
                    Item {
                        width: 22
                        height: 22
                        x: parent.width / 2 - width / 2
                        y: Math.min(parent.height - height - 4, zone.height + 2)

                        Rectangle {
                            anchors.fill: parent
                            visible: card.modelData.delay > 0
                            radius: width / 2
                            color: "transparent"
                            border.width: 2
                            border.color: card.chosen ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: card.modelData.delay > 0 ? "timer" : "arrow_selector_tool"
                            iconSize: 13
                            fill: 1
                            color: card.chosen ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }

                ColumnLayout {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        leftMargin: root.cardPadding + 4
                        rightMargin: root.cardPadding
                        bottomMargin: root.cardPadding
                    }
                    spacing: -1

                    StyledText {
                        Layout.fillWidth: true
                        text: card.modelData.label
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: card.colContent
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("%1 px · %2 ms").arg(card.modelData.width).arg(card.modelData.delay)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.main
                        font.variableAxes: ({ "wght": 560, "wdth": 80 })
                        color: card.colContent
                        opacity: 0.75
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
