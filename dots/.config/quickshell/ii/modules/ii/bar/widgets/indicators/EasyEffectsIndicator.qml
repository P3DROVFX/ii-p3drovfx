pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar.shared
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Bar pill for EasyEffects: the preset's glyph and short name while EasyEffects runs,
 * no room at all otherwise. A click (or a scroll) steps to the next preset for the
 * output device, a right click holds the popup open with all of them, a middle click
 * bypasses every effect. Hovering shows the popup; with click-to-show, a click does.
 */
MouseArea {
    id: indicator
    property bool vertical: false

    readonly property bool running: EasyEffects.running
    readonly property string preset: EasyEffects.outputPreset
    readonly property bool clickToShowPopup: BarInteraction.clickToShow
    readonly property bool showHoverState: containsMouse && !clickToShowPopup
    // Edit Mode must be able to reach it while EasyEffects is off.
    readonly property bool shown: indicator.running || GlobalStates.editMode
    property real wheelDelta: 0

    Layout.fillHeight: vertical
    hoverEnabled: !clickToShowPopup
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor

    implicitWidth: shown ? (vertical ? Appearance.sizes.verticalBarWidth : layoutHoriz.implicitWidth) : 0
    implicitHeight: shown ? (vertical ? layoutVert.implicitHeight : Appearance.sizes.baseBarHeight) : 0
    visible: shown

    Component.onCompleted: indicator.updateVisibility()
    onRunningChanged: indicator.updateVisibility()

    function updateVisibility() {
        rootItem.toggleVisible(indicator.running);
        rootItem.toggleHighlight(false);
    }

    readonly property color colFill: EasyEffects.bypassed ? Appearance.colors.colSurfaceContainerHighest
        : showHoverState ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer
    readonly property color colText: EasyEffects.bypassed ? Appearance.colors.colSubtext : Appearance.colors.colOnPrimaryContainer

    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton) {
            EasyEffects.toggleBypass();
            return;
        }
        if (mouse.button === Qt.RightButton || indicator.clickToShowPopup) {
            indicator.togglePopup();
            return;
        }
        EasyEffects.cyclePreset(1);
    }

    // The popup doesn't toggle itself on a press here: it would take every button, so a
    // middle click would open it on top of bypassing and its focus grab would eat the
    // next scroll. In click mode its own toggle keeps the guard against reopening on the
    // press that just dismissed it.
    function togglePopup(): void {
        if (indicator.clickToShowPopup && popupLoader.item) {
            popupLoader.item.toggleFromPress();
            return;
        }
        GlobalStates.toggleBarPopup("easyEffects");
    }

    onWheel: wheel => {
        indicator.wheelDelta += wheel.angleDelta.y;
        if (Math.abs(indicator.wheelDelta) < 120)
            return;
        EasyEffects.cyclePreset(indicator.wheelDelta > 0 ? -1 : 1);
        indicator.wheelDelta = 0;
    }

    PopupLoader {
        id: popupLoader
        active: BarInteraction.enablePopups && (BarInteraction.clickToShow || indicator.containsMouse || held
            || GlobalStates.isBarPopupOpen("easyEffects"))
        sourceComponent: StyledPopup {
            id: popup
            popupId: "easyEffects"
            hoverTarget: indicator
            touchToggle: false
            stickyHover: true
            popupRadius: Appearance.rounding.large

            onActiveChanged: EasyEffects.hold("barPopup", popup.active)
            Component.onDestruction: EasyEffects.hold("barPopup", false)

            contentItem: ColumnLayout {
                spacing: 12
                implicitWidth: 300

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    MaterialShapeWrappedMaterialSymbol {
                        text: EasyEffects.iconFor(indicator.preset)
                        iconSize: 22
                        padding: 10
                        shape: MaterialShape.Shape.Cookie9Sided
                        color: EasyEffects.bypassed ? Appearance.colors.colSurfaceContainerHighest : Appearance.colors.colPrimaryContainer
                        colSymbol: EasyEffects.bypassed ? Appearance.colors.colSubtext : Appearance.colors.colOnPrimaryContainer
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: indicator.preset.length > 0 ? indicator.preset : Translation.tr("No preset")
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: EasyEffects.bypassed ? Translation.tr("Effects bypassed")
                                : Audio.friendlyDeviceName(EasyEffects.outputDevice)
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: EasyEffects.devicePresets

                        RippleButton {
                            id: chip
                            required property string modelData
                            readonly property bool selected: chip.modelData === indicator.preset

                            implicitHeight: 32
                            implicitWidth: chipText.implicitWidth + 24
                            buttonRadius: chip.selected ? Appearance.rounding.small : Appearance.rounding.full
                            colBackground: chip.selected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
                            colBackgroundHover: chip.selected ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighest
                            onClicked: EasyEffects.loadPreset(chip.modelData, "output", true)

                            contentItem: StyledText {
                                id: chipText
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: EasyEffects.shortName(chip.modelData)
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: chip.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
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
                        onClicked: EasyEffects.toggleBypass()

                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            MaterialSymbol {
                                text: EasyEffects.bypassed ? "graphic_eq" : "do_not_disturb_on"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }

                            StyledText {
                                text: EasyEffects.bypassed ? Translation.tr("Turn on") : Translation.tr("Bypass")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }

                    RippleButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        visible: Config.options.easyEffects?.appEnable ?? true
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        onClicked: {
                            popup.close();
                            GlobalStates.openEasyEffectsApp("presets");
                        }

                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            MaterialSymbol {
                                text: "open_in_new"
                                iconSize: 18
                                color: Appearance.colors.colOnPrimary
                            }

                            StyledText {
                                text: Translation.tr("Open app")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
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
                text: EasyEffects.iconFor(indicator.preset)
                iconSize: 16
                fill: EasyEffects.bypassed ? 0 : 1
                color: indicator.colText
            }
        }

        Rectangle {
            visible: indicator.preset.length > 0
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
                text: EasyEffects.shortName(indicator.preset)
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
                text: EasyEffects.iconFor(indicator.preset)
                iconSize: 16
                fill: EasyEffects.bypassed ? 0 : 1
                color: indicator.colText
            }
        }
    }
}
