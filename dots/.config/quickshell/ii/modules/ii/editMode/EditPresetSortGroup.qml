import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The order of the presets, as an M3 Expressive connected button group:
 * three segments sharing one shape, the chosen one swelling into a pill that
 * spends the words (its name and its direction) while the others keep to
 * their icon. Clicking the chosen one again turns the order around - the
 * arrow it carries says which way it reads.
 */
Row {
    id: root

    property string current: "recent"
    property bool reversed: false
    signal picked(string key)

    readonly property var options: [
        { "key": "recent", "icon": "history", "label": Translation.tr("Recent"),
          "hint": Translation.tr("Last applied first") },
        { "key": "name", "icon": "sort_by_alpha", "label": Translation.tr("Name"),
          "hint": Translation.tr("A to Z") },
        { "key": "newest", "icon": "update", "label": Translation.tr("Newest"),
          "hint": Translation.tr("Last saved first") }
    ]
    readonly property real segmentHeight: 36
    readonly property real innerRadius: Math.min(Appearance.rounding.unsharpenmore, root.segmentHeight / 2)
    readonly property real outerRadius: Math.min(Appearance.rounding.full, root.segmentHeight / 2)

    spacing: 2

    Repeater {
        model: root.options

        delegate: Rectangle {
            id: segment
            required property var modelData
            required property int index
            readonly property bool chosen: segment.modelData.key === root.current
            readonly property bool firstSegment: segment.index === 0
            readonly property bool lastSegment: segment.index === root.options.length - 1
            // The chosen segment and the press are pills; the rest keep the
            // group's joined corners.
            readonly property real joinRadius: (segment.chosen || tap.pressed) ? root.outerRadius : root.innerRadius

            height: root.segmentHeight
            width: segment.chosen ? content.implicitWidth + 28 : 40
            topLeftRadius: segment.firstSegment ? root.outerRadius : segment.joinRadius
            bottomLeftRadius: segment.firstSegment ? root.outerRadius : segment.joinRadius
            topRightRadius: segment.lastSegment ? root.outerRadius : segment.joinRadius
            bottomRightRadius: segment.lastSegment ? root.outerRadius : segment.joinRadius
            // The chosen order is THE state of the block: primary, so it reads
            // under a scheme whose containers are all one grey.
            color: segment.chosen
                ? (hover.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
                : (hover.hovered ? Appearance.colors.colSurfaceContainerHighestHover : Appearance.colors.colSurfaceContainerHighest)
            clip: true

            Behavior on width {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(segment)
            }
            Behavior on topLeftRadius {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(segment)
            }
            Behavior on bottomLeftRadius {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(segment)
            }
            Behavior on topRightRadius {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(segment)
            }
            Behavior on bottomRightRadius {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(segment)
            }
            Behavior on color {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(segment)
            }

            Row {
                id: content
                anchors.centerIn: parent
                spacing: 4

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: segment.modelData.icon
                    iconSize: 18
                    fill: segment.chosen ? 1 : 0
                    color: segment.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: segment.chosen
                    text: segment.modelData.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimary
                }
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: segment.chosen
                    text: root.reversed ? "north" : "south"
                    iconSize: 15
                    color: Appearance.colors.colOnPrimary
                }
            }

            HoverHandler {
                id: hover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                id: tap
                onTapped: root.picked(segment.modelData.key)
            }

            StyledToolTip {
                text: segment.chosen
                    ? Translation.tr("%1 · click to reverse").arg(segment.modelData.hint)
                    : segment.modelData.label
                extraVisibleCondition: hover.hovered
            }
        }
    }
}
