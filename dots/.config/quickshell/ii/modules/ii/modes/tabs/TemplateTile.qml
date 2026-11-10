pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.modes

/**
 * A ready-made routine in Discover (Samsung's Discover tab): its shape in its colour, the
 * name, what it does in one or two lines, and Add. A click previews it in the side sheet;
 * Add copies it straight into the list. Once a copy exists the button says so and still
 * adds another.
 */
Rectangle {
    id: root

    required property var template
    property bool previewing: false

    signal previewRequested()
    signal addRequested()

    readonly property string key: root.template?.template ?? ""
    readonly property string colorKey: root.template?.color ?? ""
    readonly property bool copied: Modes.routines.some(r => r.template === root.key)

    radius: ClockStyle.radiusCard
    color: root.previewing ? ClockStyle.colSecondaryContainer
        : tileHover.hovered ? ClockStyle.colIdleCardHover : ClockStyle.colPane

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: tileHover
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.previewRequested()
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: ClockStyle.gapLarge + 2
        }
        spacing: ClockStyle.gapSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gap

            MaterialShapeWrappedMaterialSymbol {
                text: root.template?.icon ?? "bolt"
                iconSize: 20
                padding: 10
                // Hover doubles the leaves: the shape morphs instead of turning.
                shape: tileHover.hovered || root.previewing ? MaterialShape.Shape.Clover8Leaf : MaterialShape.Shape.Clover4Leaf
                color: ModeUi.container(root.colorKey)
                colSymbol: ModeUi.onContainer(root.colorKey)
            }

            StyledText {
                id: nameText
                Layout.fillWidth: true
                text: root.template?.name ?? ""
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textNormal + 1
                font.weight: Font.DemiBold
                color: root.previewing ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface

                HoverHandler {
                    id: nameHover
                }
                StyledToolTip {
                    extraVisibleCondition: nameHover.hovered && nameText.truncated
                    text: nameText.text
                }
            }
        }

        StyledText {
            id: description
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: ModeUi.templateText(root.template)
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
            font.pixelSize: ClockStyle.textSmall + 1
            color: root.previewing ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant

            HoverHandler {
                id: descriptionHover
            }
            StyledToolTip {
                extraVisibleCondition: descriptionHover.hovered && description.truncated
                text: description.text
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            StyledText {
                Layout.fillWidth: true
                text: ModeUi.routineKindText(root.template?.kind ?? "while")
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textSmall
                color: root.previewing ? ClockStyle.colOnSecondaryContainer : ClockStyle.colSubtext
            }

            ClockChip {
                height_: 34
                symbol: root.copied ? "check" : "add"
                label: root.copied ? Translation.tr("Added") : Translation.tr("Add")
                selected: !root.copied && !root.previewing
                onClicked: root.addRequested()

                StyledToolTip {
                    text: root.copied ? Translation.tr("Already in the list — add another copy") : Translation.tr("Add to the list")
                }
            }
        }
    }
}
