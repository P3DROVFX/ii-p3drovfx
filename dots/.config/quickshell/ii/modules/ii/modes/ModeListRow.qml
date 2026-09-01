import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * One mode in the list: icon in the mode's colour, name, and what starts
 * it — or that it is on. The active row is filled with the mode's accent.
 * With `routine`, the same row for a routine: the trailing icon becomes its
 * enable switch and "active" means running.
 */
Item {
    id: root

    required property var mode
    property bool routine: false
    property bool selected: false
    /// The delegate whose copy is being dragged: keeps its slot, shows nothing.
    property bool hidden: false
    /// The copy under the pointer: lifted with a shadow, no interaction.
    property bool ghost: false

    readonly property bool isActive: root.routine ? Modes.isRoutineRunning(root.mode.id) : Modes.activeModeId === root.mode.id
    readonly property bool dimmed: root.routine && !root.mode.enabled && !root.isActive
    readonly property string colorKey: root.mode.color ?? ""

    signal clicked()
    signal dragStarted(real y)
    signal dragMoved(real y)
    signal dragEnded()

    implicitHeight: 62
    opacity: root.hidden ? 0 : 1

    StyledRectangularShadow {
        visible: root.ghost
        target: card
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: {
            if (root.isActive)
                return root.selected ? ModeUi.accent(root.colorKey) : ModeUi.container(root.colorKey);
            if (root.selected)
                return Appearance.colors.colSecondaryContainer;
            if (root.ghost)
                return Appearance.colors.colLayer2;
            return rowArea.containsMouse ? Appearance.colors.colLayer2Hover : "transparent";
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        readonly property color colText: {
            if (root.isActive)
                return root.selected ? ModeUi.onAccent(root.colorKey) : ModeUi.onContainer(root.colorKey);
            if (root.selected)
                return Appearance.colors.colOnSecondaryContainer;
            return Appearance.colors.colOnLayer1;
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 4
            }
            spacing: 10

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 40
                implicitHeight: 40
                radius: Appearance.rounding.full
                opacity: root.dimmed ? 0.55 : 1
                color: root.isActive && root.selected
                    ? ColorUtils.transparentize(ModeUi.onAccent(root.colorKey), 0.85)
                    : ModeUi.container(root.colorKey)

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.mode.icon
                    iconSize: 22
                    fill: root.isActive ? 1 : 0
                    color: root.isActive && root.selected
                        ? ModeUi.onAccent(root.colorKey) : ModeUi.onContainer(root.colorKey)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        Layout.fillWidth: true
                        text: root.mode.name
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: card.colText
                    }

                    // Says the mode may start on its own; a bare trigger does not.
                    MaterialSymbol {
                        visible: !root.routine && root.mode.auto && root.mode.triggers.length > 0
                        text: "autoplay"
                        iconSize: 16
                        color: ColorUtils.transparentize(card.colText, 0.3)
                    }

                    MaterialSymbol {
                        visible: root.routine && root.mode.kind === "once"
                        text: "bolt"
                        iconSize: 16
                        color: ColorUtils.transparentize(card.colText, 0.3)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.routine ? ModeUi.routineStatus(root.mode) : ModeUi.modeStatus(root.mode)
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ColorUtils.transparentize(card.colText, 0.25)
                }
            }

            // Routines: whether it may run on its own. Sits before the handle
            // so the row keeps the same right edge as a mode row.
            StyledSwitch {
                visible: root.routine && root.mode.triggers.length > 0
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: 2
                checked: root.mode.enabled ?? true
                onClicked: Modes.upsertRoutine(Object.assign({}, root.mode, { enabled: checked }))
            }

            MouseArea {
                id: handle
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 28
                implicitHeight: 40
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true
                opacity: rowArea.containsMouse || handle.containsMouse || root.ghost || root.selected ? 1 : 0.35

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                onPressed: mouse => root.dragStarted(handle.mapToItem(root, mouse.x, mouse.y).y)
                onPositionChanged: mouse => {
                    if (handle.pressed)
                        root.dragMoved(handle.mapToItem(root, mouse.x, mouse.y).y);
                }
                onReleased: root.dragEnded()
                onCanceled: root.dragEnded()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "drag_indicator"
                    iconSize: 20
                    color: ColorUtils.transparentize(card.colText, 0.3)
                }
            }
        }
    }
}
