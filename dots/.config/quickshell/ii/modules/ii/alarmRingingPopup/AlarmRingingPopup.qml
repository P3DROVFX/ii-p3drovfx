import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    PanelWindow {
        id: popupWindow
        color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35)
        visible: AlarmService.ringingAlarmIndex !== -1 && Config.options.time.alarms.useFullscreenPopup
            && !GlobalStates.islandOwnsAlarm
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

        WlrLayershell.namespace: "quickshell:alarmRingingPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Center card container
        Rectangle {
            id: centerCard
            anchors.centerIn: parent
            width: 400
            height: 350
            radius: Appearance.rounding.large
            color: ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHigh, 0.15)
            focus: popupWindow.visible

            // Catch dismiss keys
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape || event.key === Qt.Key_Space || event.key === Qt.Key_Return) {
                    AlarmService.stopRinging();
                    event.accepted = true;
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 16

                // Static Icon Badge Container
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 76
                    height: 76
                    radius: 38
                    color: Appearance.colors.colErrorContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "alarm"
                        iconSize: 38
                        color: Appearance.colors.colOnErrorContainer
                    }
                }

                // Time Display
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: AlarmService.ringingAlarm ? AlarmService.ringingAlarm.time : "--:--"
                    font.pixelSize: 56
                    font.family: Appearance.font.family.title
                    font.weight: Font.ExtraBold
                    color: Appearance.colors.colOnSurface
                }

                // Alarm Label Pill
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    color: Appearance.colors.colLayer3
                    radius: 12
                    implicitWidth: labelText.implicitWidth + 24
                    implicitHeight: labelText.implicitHeight + 8

                    StyledText {
                        id: labelText
                        anchors.centerIn: parent
                        text: AlarmService.ringingAlarm ? (AlarmService.ringingAlarm.label || Translation.tr("Alarm")) : Translation.tr("Alarm")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colSubtext
                    }
                }

                Item { Layout.fillHeight: true }

                // Stop Button
                RippleButton {
                    colBackground: Appearance.colors.colError
                    colBackgroundHover: Appearance.colors.colErrorHover
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    buttonRadius: 26

                    contentItem: RowLayout {
                        spacing: 6
                        RowLayout {
                            Layout.alignment: Qt.AlignCenter
                            spacing: 8
                            MaterialSymbol {
                                text: "alarm_off"
                                iconSize: 22
                                color: Appearance.colors.colOnError
                            }
                            StyledText {
                                text: Translation.tr("STOP ALARM")
                                font.weight: Font.Bold
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnError
                            }
                        }
                    }

                    onClicked: {
                        AlarmService.stopRinging();
                    }
                }
            }
        }
    }
}
