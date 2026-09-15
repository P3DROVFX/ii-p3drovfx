pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../../../ii/bar/shared/cards"

// Shelf-hosted popup body for the mode/routines chip. Content mirrors the bar's
// mode popup (hero + running routines + manage/turn-off), but is positioned by
// the shelf's own chip popup container inside a ShelfPopupSurface card, exactly
// like the other chip popups.
Item {
    id: root

    property var shelf

    readonly property var mode: Modes.activeMode
    readonly property string colorKey: root.mode?.color ?? ""

    implicitWidth: 344
    implicitHeight: {
        let h = 125 + 22 + 12;
        if (Modes.routineRuns.length > 0)
            h += 30 + 12;
        h += 38 + 16;
        return h;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        HeroCard {
            Layout.fillWidth: true
            compactMode: true
            implicitHeight: 125
            titleSize: Appearance.font.pixelSize.larger
            subtitleSize: Appearance.font.pixelSize.small
            shapeColor: ModeUi.accent(root.colorKey)
            icon: root.mode?.icon ?? "tune"
            title: root.mode?.name ?? ""
            subtitle: {
                if (!Modes.active)
                    return Translation.tr("No mode active");
                let line = Translation.tr("Started %1 · %2")
                    .arg(Modes.sourceText(Modes.activeSource)).arg(ModeUi.clock(Modes.activeSince));
                if (Modes.activeEndsAt > 0)
                    line += " · " + Translation.tr("ends %1").arg(ModeUi.clock(Modes.activeEndsAt));
                return line;
            }
            pillText: Modes.active ? Translation.tr("ON") : ""
            pillIcon: Modes.active ? "check" : ""
            pillColor: ModeUi.accent(root.colorKey)
            pillTextColor: ModeUi.onAccent(root.colorKey)
            pillIconColor: ModeUi.onAccent(root.colorKey)
        }

        // Routines running alongside the mode; × stops one.
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
                    color: ModeUi.container(runChip.routine?.color ?? "")

                    RowLayout {
                        id: runRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialSymbol {
                            text: runChip.routine?.icon ?? "bolt"
                            iconSize: 16
                            color: ModeUi.onContainer(runChip.routine?.color ?? "")
                        }
                        StyledText {
                            text: runChip.routine?.name ?? runChip.modelData.id
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: ModeUi.onContainer(runChip.routine?.color ?? "")
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
                                color: ModeUi.onContainer(runChip.routine?.color ?? "")
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                onClicked: {
                    root.shelf?.closeChipPopup();
                    GlobalStates.modesOpen = true;
                }
                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        text: "tune"
                        iconSize: 18
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        text: Translation.tr("Manage")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                onClicked: {
                    root.shelf?.closeChipPopup();
                    Modes.deactivate("manual");
                }
                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        text: "stop"
                        iconSize: 18
                        color: Appearance.colors.colOnErrorContainer
                    }
                    StyledText {
                        text: Translation.tr("Turn off")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnErrorContainer
                    }
                }
            }
        }
    }
}