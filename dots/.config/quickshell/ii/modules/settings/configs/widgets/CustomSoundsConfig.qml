import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property var customizableEvents: [
        { key: "notifications", icon: "notifications", label: Translation.tr("Notifications") },
        { key: "volumeChange", icon: "volume_up", label: Translation.tr("Volume change") },
        { key: "battery", icon: "battery_alert", label: Translation.tr("Battery & power") },
        { key: "screenshot", icon: "photo_camera", label: Translation.tr("Screenshot shutter") },
        { key: "pomodoro", icon: "av_timer", label: Translation.tr("Pomodoro") },
        { key: "timer", icon: "hourglass_top", label: Translation.tr("Timer finished") },
        { key: "alarm", icon: "alarm", label: Translation.tr("Alarm ring") },
        { key: "session", icon: "login", label: Translation.tr("Login") },
        { key: "devices", icon: "bluetooth_connected", label: Translation.tr("Device connections") },
        { key: "lock", icon: "lock", label: Translation.tr("Screen lock") }
    ]

    property string fileDialogTarget: ""

    FileDialog {
        id: fileDialog
        currentFolder: "file:///usr/share/sounds"
        nameFilters: [
            Translation.tr("Audio files (*.oga *.ogg *.wav *.mp3 *.flac *.opus)"),
            Translation.tr("All files (*)")
        ]
        onAccepted: {
            const path = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""));
            if (subPageRoot.fileDialogTarget !== "")
                Config.options.sounds.custom[subPageRoot.fileDialogTarget] = path;
        }
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Custom sounds")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "tune"
            title: Translation.tr("Custom sounds")

            NoticeBox {
                Layout.fillWidth: true
                text: Translation.tr("Override the sound theme for individual events with a local audio file.")
            }

            Repeater {
                model: subPageRoot.customizableEvents

                delegate: Rectangle {
                    id: customRow
                    required property var modelData
                    readonly property string customPath: Config.options.sounds.custom[modelData.key] ?? ""
                    readonly property bool hasCustom: customPath !== ""

                    Layout.fillWidth: true
                    implicitHeight: rowLayout.implicitHeight + 16
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colLayer2Base

                    RowLayout {
                        id: rowLayout
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 12
                            rightMargin: 8
                        }
                        spacing: 10

                        MaterialSymbol {
                            text: customRow.modelData.icon
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: customRow.modelData.label
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            visible: customRow.hasCustom
                            Layout.maximumWidth: 320
                            text: customRow.customPath
                            elide: Text.ElideMiddle
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        RippleButton {
                            visible: customRow.hasCustom
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: SoundService.previewFile(customRow.customPath)

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "play_arrow"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledToolTip { text: Translation.tr("Play custom sound") }
                        }

                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: {
                                subPageRoot.fileDialogTarget = customRow.modelData.key;
                                fileDialog.open();
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "folder_open"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledToolTip { text: Translation.tr("Choose a custom sound file") }
                        }

                        RippleButton {
                            visible: customRow.hasCustom
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: Config.options.sounds.custom[customRow.modelData.key] = ""

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledToolTip { text: Translation.tr("Reset to theme sound") }
                        }
                    }
                }
            }
        }
    }
}
