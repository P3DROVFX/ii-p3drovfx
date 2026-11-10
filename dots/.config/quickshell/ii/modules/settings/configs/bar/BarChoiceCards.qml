pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A choice as expressive cards: an icon in a shape, the name in the title face and one
 * short line under it. At rest the shape is a circle on secondary container; the chosen
 * card fills secondary container, opens its corners and its shape morphs into the
 * option's own one in primary. Columns are balanced over the rows the set needs and the
 * last row shares the full width, so no row ends with a straggler. Pointing at a card
 * reports it (`tried`, after a short rest) for a preview to wear; locked cards fade and
 * carry a lock.
 *
 * options: [{ value, label, description, icon, shape, enabled }]
 */
Item {
    id: root

    readonly property real gap: 8
    readonly property real minCard: 140
    readonly property real cardHeight: 132
    readonly property real cardPadding: 16
    readonly property real dwell: 140

    property var options: []
    property var currentValue: null
    /// The value under the pointer once it has rested there, or null.
    property var tried: null
    signal selected(var value)

    readonly property int count: root.options.length
    readonly property int maxCols: Math.max(1, Math.min(root.count, Math.floor((width + root.gap) / (root.minCard + root.gap))))
    readonly property int rows: Math.ceil(root.count / root.maxCols)
    readonly property int cols: Math.ceil(root.count / Math.max(1, root.rows))
    readonly property int lastRowCount: root.count - root.cols * (root.rows - 1)

    implicitHeight: root.rows * root.cardHeight + Math.max(0, root.rows - 1) * root.gap

    property var pointed: null
    onPointedChanged: {
        if (root.pointed === null) {
            dwellTimer.stop();
            root.tried = null;
        } else {
            dwellTimer.restart();
        }
    }
    Timer {
        id: dwellTimer
        interval: root.dwell
        onTriggered: root.tried = root.pointed
    }

    Repeater {
        model: root.options

        delegate: RippleButton {
            id: card
            required property var modelData
            required property int index
            readonly property int row: Math.floor(card.index / root.cols)
            readonly property int column: card.index % root.cols
            readonly property int rowCount: card.row === root.rows - 1 ? root.lastRowCount : root.cols
            readonly property real cellWidth: (root.width - root.gap * (card.rowCount - 1)) / card.rowCount
            readonly property bool chosen: card.modelData.value === root.currentValue
            readonly property bool available: card.modelData.enabled !== false
            readonly property color colContent: card.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1

            x: card.column * (card.cellWidth + root.gap)
            y: card.row * (root.cardHeight + root.gap)
            width: card.cellWidth
            height: root.cardHeight
            padding: 0
            enabled: card.available
            opacity: card.available || card.chosen ? 1 : 0.45
            buttonRadius: card.chosen ? Appearance.rounding.verylarge : Appearance.rounding.large
            buttonRadiusPressed: Appearance.rounding.normal
            colBackground: card.chosen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
            colBackgroundHover: card.chosen ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
            colRipple: card.chosen ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer1Active
            onClicked: if (!card.chosen) root.selected(card.modelData.value)
            onHoveredChanged: {
                if (card.hovered)
                    root.pointed = card.modelData.value;
                else if (root.pointed === card.modelData.value)
                    root.pointed = null;
            }

            contentItem: Item {
                MaterialShapeWrappedMaterialSymbol {
                    x: root.cardPadding
                    y: root.cardPadding
                    text: card.modelData.icon
                    iconSize: 22
                    padding: 10
                    fill: 1
                    shape: card.chosen ? (card.modelData.shape ?? MaterialShape.Shape.Cookie9Sided)
                        : card.hovered ? MaterialShape.Shape.Cookie7Sided : MaterialShape.Shape.Circle
                    color: card.chosen ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    colSymbol: card.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }

                MaterialSymbol {
                    visible: !card.available
                    anchors {
                        right: parent.right
                        top: parent.top
                        margins: root.cardPadding + 4
                    }
                    text: "lock"
                    iconSize: 16
                    fill: 1
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Column {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        margins: root.cardPadding
                        leftMargin: root.cardPadding + 2
                    }
                    spacing: 1

                    StyledText {
                        width: parent.width
                        text: card.modelData.label
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: card.colContent
                        elide: Text.ElideRight
                    }
                    StyledText {
                        width: parent.width
                        visible: text.length > 0
                        text: card.modelData.description ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: card.colContent
                        opacity: 0.75
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
