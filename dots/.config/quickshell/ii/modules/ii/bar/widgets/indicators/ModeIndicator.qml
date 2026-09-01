pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import qs.modules.ii.bar.shared
import "../../shared/cards"
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Bar pill for the active mode: its icon and name in its colour. Takes no
 * room while nothing is on, like the record indicator. Left-click opens
 * the manager, right-click ends the mode.
 */
MouseArea {
    id: indicator
    property bool vertical: false

    readonly property bool active: Modes.active
    readonly property var mode: Modes.activeMode
    readonly property string colorKey: indicator.mode?.color ?? ""
    readonly property bool clickToShowPopup: Config.options.bar.tooltips.clickToShow
    readonly property bool showHoverState: containsMouse && !clickToShowPopup

    Layout.fillHeight: vertical
    hoverEnabled: !clickToShowPopup
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor

    implicitWidth: active ? (vertical ? Appearance.sizes.verticalBarWidth : layoutHoriz.implicitWidth) : 0
    implicitHeight: active ? (vertical ? layoutVert.implicitHeight : Appearance.sizes.baseBarHeight) : 0
    visible: active

    Component.onCompleted: indicator.updateVisibility()
    onActiveChanged: indicator.updateVisibility()

    function updateVisibility() {
        rootItem.toggleVisible(indicator.active);
        rootItem.toggleHighlight(false);
    }

    readonly property color colFill: showHoverState
        ? ColorUtils.mix(ModeUi.container(colorKey), ModeUi.onContainer(colorKey), 0.9)
        : ModeUi.container(colorKey)
    readonly property color colText: ModeUi.onContainer(colorKey)

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            Modes.deactivate("manual");
            return;
        }
        if (indicator.clickToShowPopup)
            return;
        GlobalStates.modesOpen = !GlobalStates.modesOpen;
    }

    // Hover / click popup, in the bar's own style (click-to-show is honoured
    // by the popup itself).
    StyledPopup {
        id: modePopup
        hoverTarget: indicator
        stickyHover: true
        popupRadius: Appearance.rounding.large

        contentItem: ColumnLayout {
            spacing: 12
            implicitWidth: 320

            HeroCard {
                icon: indicator.mode?.icon ?? "tune"
                compactMode: true
                adaptiveWidth: true
                implicitHeight: 125
                titleSize: Appearance.font.pixelSize.larger
                subtitleSize: Appearance.font.pixelSize.small
                shapeColor: ModeUi.accent(indicator.colorKey)
                title: indicator.mode?.name ?? ""
                subtitle: {
                    let line = Translation.tr("Started %1 · %2")
                        .arg(Modes.sourceText(Modes.activeSource)).arg(ModeUi.clock(Modes.activeSince));
                    if (Modes.activeEndsAt > 0)
                        line += " · " + Translation.tr("ends %1").arg(ModeUi.clock(Modes.activeEndsAt));
                    return line;
                }
                pillText: Translation.tr("ON")
                pillIcon: "check"
                pillColor: ModeUi.accent(indicator.colorKey)
                pillTextColor: ModeUi.onAccent(indicator.colorKey)
                pillIconColor: ModeUi.onAccent(indicator.colorKey)
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
                        modePopup.close();
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
                        modePopup.close();
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

    RowLayout {
        id: layoutHoriz
        visible: !indicator.vertical
        anchors.centerIn: parent
        spacing: 6

        MaterialShape {
            width: 32
            height: 32
            shape: MaterialShape.Shape.Cookie9Sided
            color: indicator.colFill

            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: indicator.mode?.icon ?? "tune"
                iconSize: 16
                fill: 1
                color: indicator.colText
            }
        }

        Rectangle {
            height: 32
            implicitWidth: nameText.implicitWidth + 20
            radius: height / 2
            color: indicator.colFill

            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }

            StyledText {
                id: nameText
                anchors.centerIn: parent
                text: indicator.mode?.name ?? ""
                color: indicator.colText
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Bold
            }
        }
    }

    ColumnLayout {
        id: layoutVert
        visible: indicator.vertical
        anchors.centerIn: parent
        spacing: 6

        MaterialShape {
            Layout.alignment: Qt.AlignHCenter
            width: 32
            height: 32
            shape: MaterialShape.Shape.Cookie9Sided
            color: indicator.colFill

            MaterialSymbol {
                anchors.centerIn: parent
                text: indicator.mode?.icon ?? "tune"
                iconSize: 16
                fill: 1
                color: indicator.colText
            }
        }
    }
}
