import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/** Keeps SongRec's listening state visible and asks before starting it. */
Rectangle {
    id: root

    property var messageData: null
    property var card: null
    readonly property var preview: root.card?.data?.preview ?? ({})
    readonly property bool listening: SongRec.running

    implicitHeight: content.implicitHeight + Appearance.rounding.normal
    radius: Appearance.rounding.normal
    color: Appearance.colors.colSecondaryContainer

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Appearance.rounding.unsharpenmore
        spacing: Appearance.rounding.unsharpenmore

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.rounding.unsharpenmore

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: root.listening ? "graphic_eq" : "music_note"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.m3colors.m3onSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.listening ? Translation.tr("Listening for a song") : Translation.tr("Identify this song?")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.listening
                        ? Translation.tr("Source: %1 · temporary audio is removed by SongRec").arg(String(root.preview.monitorSource ?? "monitor"))
                        : Translation.tr("Source: %1 · this listens to audio").arg(String(root.preview.monitorSource ?? "monitor"))
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !root.listening && String(SongRec.recognizedTrack?.title ?? "").length > 0
                    text: String(SongRec.recognizedTrack?.title ?? "") + " · " + String(SongRec.recognizedTrack?.subtitle ?? "")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.rounding.unsharpenmore

            Item { Layout.fillWidth: true }

            RippleButton {
                visible: root.listening
                leftPadding: Appearance.rounding.small
                rightPadding: Appearance.rounding.small
                topPadding: Appearance.rounding.unsharpenmore / 2
                bottomPadding: Appearance.rounding.unsharpenmore / 2
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: Ai.stopSongIdentify(root.messageData)
                contentItem: StyledText {
                    text: Translation.tr("Stop")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }

            RippleButton {
                visible: !root.listening && root.messageData?.functionPending === true
                leftPadding: Appearance.rounding.small
                rightPadding: Appearance.rounding.small
                topPadding: Appearance.rounding.unsharpenmore / 2
                bottomPadding: Appearance.rounding.unsharpenmore / 2
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: Ai.rejectSongIdentify(root.messageData)
                contentItem: StyledText {
                    text: Translation.tr("Discard")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }

            RippleButton {
                visible: !root.listening && root.messageData?.functionPending === true
                leftPadding: Appearance.rounding.small
                rightPadding: Appearance.rounding.small
                topPadding: Appearance.rounding.unsharpenmore / 2
                bottomPadding: Appearance.rounding.unsharpenmore / 2
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: Ai.approveSongIdentify(root.messageData)
                contentItem: StyledText {
                    text: Translation.tr("Listen")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onPrimary
                }
            }
        }
    }
}
