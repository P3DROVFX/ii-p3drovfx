import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Activity Notches")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "notifications_active"
            title: Translation.tr("Activity Notches")
            tooltip: Translation.tr("Interactive overlays and notifications inside the dynamic island.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                NotchCard {
                    buttonIcon: "music_note"
                    text: Translation.tr("Media Notch")
                    tooltip: Translation.tr("Toggle the Media Player status notch")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableMedia
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableMedia = !enabled;
                    }
                    heightLabel: Translation.tr("Media contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightMedia
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightMedia = value;
                    }
                }

                NotchCard {
                    buttonIcon: "notifications"
                    text: Translation.tr("Notification Notch")
                    tooltip: Translation.tr("Toggle the notification popups inside the notch")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableNotification
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableNotification = !enabled;
                    }
                    heightLabel: Translation.tr("Notification contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightNotification
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightNotification = value;
                    }
                }

                NotchCard {
                    buttonIcon: "volume_up"
                    text: Translation.tr("OSD Notch")
                    tooltip: Translation.tr("Toggle the volume/brightness OSD inside the notch")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableOsd
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableOsd = !enabled;
                    }
                    hasHeight: false
                }

                NotchCard {
                    buttonIcon: "screen_record"
                    text: Translation.tr("Screen Recording Notch")
                    tooltip: Translation.tr("Toggle the screen recording indicator notch")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableRecording
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableRecording = !enabled;
                    }
                    heightLabel: Translation.tr("Screen Recording contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightRecording
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightRecording = value;
                    }
                }

                NotchCard {
                    buttonIcon: "mic"
                    text: Translation.tr("Dictation Notch")
                    tooltip: Translation.tr("Toggle the dictation waveform notch")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableDictation
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableDictation = !enabled;
                    }
                    heightLabel: Translation.tr("Dictation contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightDictation
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightDictation = value;
                    }
                }

                NotchCard {
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("AI Status Notch")
                    tooltip: Translation.tr("Toggle the AI agent status indicator notch")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableAiStatus
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableAiStatus = !enabled;
                    }
                    heightLabel: Translation.tr("AI Status contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightAiStatus
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightAiStatus = value;
                    }
                }

                NotchCard {
                    buttonIcon: "timer"
                    text: Translation.tr("Timer/Stopwatch Notch")
                    tooltip: Translation.tr("Toggle the Pomodoro/Stopwatch timer notch")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableTimer
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableTimer = !enabled;
                    }
                    heightLabel: Translation.tr("Timer/Stopwatch contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightTimer
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightTimer = value;
                    }
                }

                NotchCard {
                    buttonIcon: "content_paste"
                    text: Translation.tr("Clipboard Notch")
                    tooltip: Translation.tr("Toggle the clipboard history notch")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableClipboard
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableClipboard = !enabled;
                    }
                    heightLabel: Translation.tr("Clipboard contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightClipboard
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightClipboard = value;
                    }
                }

                NotchCard {
                    buttonIcon: "share"
                    text: Translation.tr("LocalSend Share Notch")
                    tooltip: Translation.tr("Toggle the LocalSend files sharing and receiving notch")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableLocalSend
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableLocalSend = !enabled;
                    }
                    heightLabel: Translation.tr("LocalSend contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightLocalSend
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightLocalSend = value;
                    }
                }

                NotchCard {
                    buttonIcon: "playlist_add_check"
                    text: Translation.tr("Checklist Notch")
                    tooltip: Translation.tr("Toggle the checklist notch")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableChecklist
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableChecklist = !enabled;
                    }
                    heightLabel: Translation.tr("Checklist contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightChecklist
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightChecklist = value;
                    }

                    ConfigSwitch {
                        buttonIcon: "visibility"
                        text: Translation.tr("Checklist always visible (Contracted)")
                        visible: !Config.options.bar.floatingNotch.disableChecklist
                        checked: Config.options.bar.floatingNotch.checklistAlwaysVisible
                        onCheckedChanged: {
                            Config.options.bar.floatingNotch.checklistAlwaysVisible = checked;
                            if (checked)
                                Config.options.bar.floatingNotch.checklistOnlyExpanded = false;
                        }
                        StyledToolTip {
                            text: Translation.tr("Make checklist always visible on the dynamic island, even when contracted and idle")
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "open_in_full"
                        text: Translation.tr("Checklist always visible (Expanded Only)")
                        visible: !Config.options.bar.floatingNotch.disableChecklist
                        checked: Config.options.bar.floatingNotch.checklistOnlyExpanded
                        onCheckedChanged: {
                            Config.options.bar.floatingNotch.checklistOnlyExpanded = checked;
                            if (checked)
                                Config.options.bar.floatingNotch.checklistAlwaysVisible = false;
                        }
                        StyledToolTip {
                            text: Translation.tr("Make checklist always show when the dynamic island is expanded, but not when contracted")
                        }
                    }
                }

                NotchCard {
                    buttonIcon: "calendar_month"
                    text: Translation.tr("Calendar Notch")
                    tooltip: Translation.tr("Toggle the calendar notch")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableCalendar
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableCalendar = !enabled;
                    }
                    heightLabel: Translation.tr("Calendar contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightCalendar
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightCalendar = value;
                    }
                }

                NotchCard {
                    buttonIcon: "speaker"
                    text: Translation.tr("Audio Output Notch")
                    tooltip: Translation.tr("Toggle the audio output switcher notch")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableAudio
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableAudio = !enabled;
                    }
                    heightLabel: Translation.tr("Audio contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightAudio
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightAudio = value;
                    }
                }

                NotchCard {
                    buttonIcon: "progress_activity"
                    text: Translation.tr("Live Progress Notch")
                    tooltip: Translation.tr("Toggle the live transfer/build progress notch")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableProgress
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableProgress = !enabled;
                    }
                    heightLabel: Translation.tr("Progress contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightProgress
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightProgress = value;
                    }
                }
            }
        }

        ContentSection {
            icon: "more_horiz"
            title: Translation.tr("Dimensions & Options")
            tooltip: Translation.tr("Notch idle dimensions and panel drag columns.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSpinBox {
                    icon: "height"
                    text: Translation.tr("Idle/Home contracted height")
                    value: Config.options.bar.floatingNotch.heightHome
                    from: 24
                    to: 60
                    stepSize: 1
                    onValueChanged: {
                        Config.options.bar.floatingNotch.heightHome = value;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "smartphone"
                    text: Translation.tr("KDE Connect column in drag panel")
                    visible: !Config.options.bar.floatingNotch.disableLocalSend
                    checked: !Config.options.bar.floatingNotch.disableKdeConnectInLocalSend
                    onCheckedChanged: {
                        Config.options.bar.floatingNotch.disableKdeConnectInLocalSend = !checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Show the KDE Connect drop column alongside LocalSend when dragging files into the notch")
                    }
                }
            }
        }
    }
}
