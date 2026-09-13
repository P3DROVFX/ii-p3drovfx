pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * The sidebar's mode picker: every mode as a tile, the active one filled.
 * One tap starts or ends; the full manager is one button away.
 */
WindowDialog {
    id: root
    backgroundWidth: 340

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Modes")
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer1
        }

        StyledText {
            visible: Modes.active
            text: Translation.tr("%1 on").arg(Modes.activeMode?.name ?? "")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    StyledText {
        visible: Modes.modes.length === 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: Translation.tr("No modes yet. Open the manager to create one.")
        color: Appearance.colors.colSubtext
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        rowSpacing: 8
        columnSpacing: 8

        Repeater {
            model: Modes.modes

            delegate: RippleButton {
                id: tile
                required property var modelData
                readonly property bool isActive: Modes.activeModeId === tile.modelData.id
                readonly property string colorKey: tile.modelData.color ?? ""
                readonly property color fg: tile.isActive ? ModeUi.onAccent(tile.colorKey) : Appearance.colors.colOnLayer2

                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 72
                buttonRadius: Appearance.rounding.normal
                colBackground: tile.isActive ? ModeUi.accent(tile.colorKey) : Appearance.colors.colLayer2
                colBackgroundHover: tile.isActive
                    ? ColorUtils.mix(ModeUi.accent(tile.colorKey), ModeUi.onAccent(tile.colorKey), 0.9)
                    : Appearance.colors.colLayer2Hover
                colRipple: tile.isActive
                    ? ColorUtils.mix(ModeUi.accent(tile.colorKey), ModeUi.onAccent(tile.colorKey), 0.8)
                    : Appearance.colors.colLayer2Active
                onClicked: Modes.toggle(tile.modelData.id)

                contentItem: RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 12
                        rightMargin: 10
                    }
                    spacing: 10

                    Rectangle {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: Appearance.rounding.full
                        color: tile.isActive ? ColorUtils.transparentize(tile.fg, 0.85) : ModeUi.container(tile.colorKey)

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: tile.modelData.icon
                            iconSize: 20
                            fill: tile.isActive ? 1 : 0
                            color: tile.isActive ? tile.fg : ModeUi.onContainer(tile.colorKey)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: tile.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: tile.fg
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: ModeUi.modeStatus(tile.modelData)
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: ColorUtils.transparentize(tile.fg, 0.3)
                        }
                    }
                }
            }
        }
    }

    // Running routines, each with its own stop.
    Flow {
        Layout.fillWidth: true
        visible: Modes.routineRuns.length > 0
        spacing: 6

        Repeater {
            model: Modes.routineRuns

            delegate: Rectangle {
                id: runChip
                required property var modelData
                readonly property var routine: Modes.routineById(runChip.modelData.id)

                implicitWidth: runRow.implicitWidth + 20
                implicitHeight: 30
                radius: Appearance.rounding.full
                color: Appearance.colors.colSecondaryContainer

                RowLayout {
                    id: runRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        text: runChip.routine?.icon ?? "bolt"
                        iconSize: 16
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        text: runChip.routine?.name ?? runChip.modelData.id
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    MouseArea {
                        implicitWidth: 18
                        implicitHeight: 18
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Modes.stopRoutine(runChip.modelData.id, "manual")

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 16
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 12

        RippleButton {
            id: manageButton
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
            colRipple: Appearance.colors.colSurfaceContainerHighestActive
            implicitHeight: 36
            implicitWidth: manageText.implicitWidth + 32
            onClicked: {
                root.dismiss();
                GlobalStates.sidebarRightOpen = false;
                GlobalStates.modesOpen = true;
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: manageButton.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                radius: parent.buttonEffectiveRadius
            }

            contentItem: StyledText {
                id: manageText
                text: Translation.tr("Manage…")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                color: manageButton.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
            }
        }

        Item {
            Layout.fillWidth: true
        }

        RippleButton {
            id: doneButton
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            implicitHeight: 36
            implicitWidth: doneText.implicitWidth + 32
            onClicked: root.dismiss()

            contentItem: StyledText {
                id: doneText
                text: Translation.tr("Done")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}
