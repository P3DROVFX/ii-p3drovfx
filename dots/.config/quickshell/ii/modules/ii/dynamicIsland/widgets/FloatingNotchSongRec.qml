pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Music recognition on the island.
 *
 * Listening: a breathing glyph and Cancel. The breathing is the only motion and it runs
 * only while this face is on screen and listening, which SongRec caps at its timeout.
 * Result: title and artist, with Open (the Shazam page) and YouTube. Failure: one line.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property var source: {
        let node = root.parent;
        while (node && !node.hasOwnProperty("controller"))
            node = node.parent;
        return node && node.controller ? node.controller.sources.songRec : null;
    }
    readonly property string phase: root.source ? root.source.phase : (SongRec.running ? "listening" : "")
    readonly property bool listening: root.phase === "listening"
    readonly property bool hasResult: root.phase === "result"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: 10

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.max(26, Math.min(34, root.height - 10))
            implicitHeight: implicitWidth
            radius: width / 2
            color: root.phase === "failed" ? Appearance.colors.colLayer2 : Appearance.colors.colPrimary

            MaterialSymbol {
                id: glyph
                anchors.centerIn: parent
                text: root.phase === "failed" ? "music_off" : (root.hasResult ? "music_note" : "graphic_eq")
                fill: 1
                iconSize: Math.round(parent.width * 0.6)
                color: root.phase === "failed" ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnPrimary

                SequentialAnimation on opacity {
                    running: root.listening && root.visible && root.Window.window !== null
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: -2

            StyledText {
                Layout.fillWidth: true
                text: root.listening ? Translation.tr("Listening…")
                    : (root.hasResult ? SongRec.recognizedTrack.title
                        : (root.source ? root.source.failureMessage : ""))
                elide: Text.ElideRight
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
            }

            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.listening ? (SongRec.monitorSourceString === "monitor"
                        ? Translation.tr("What's playing on this computer")
                        : Translation.tr("Through the microphone"))
                    : (root.hasResult ? SongRec.recognizedTrack.subtitle : "")
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }

        PillButton {
            visible: root.listening
            label: Translation.tr("Cancel")
            onTriggered: SongRec.toggleRunning(false)
        }

        PillButton {
            visible: root.hasResult && SongRec.recognizedTrack.url !== ""
            label: Translation.tr("Open")
            primary: true
            onTriggered: {
                Qt.openUrlExternally(SongRec.recognizedTrack.url);
                if (root.source)
                    root.source.dismiss();
            }
        }

        PillButton {
            visible: root.hasResult
            label: "YouTube"
            onTriggered: {
                SongRec.openOnYouTube();
                if (root.source)
                    root.source.dismiss();
            }
        }
    }

    component PillButton: RippleButton {
        id: pill
        required property string label
        property bool primary: false
        signal triggered()

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: pillLabel.implicitWidth + 24
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackground: pill.primary ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
        colBackgroundHover: pill.primary ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
        colRipple: pill.primary ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active
        onClicked: pill.triggered()

        contentItem: StyledText {
            id: pillLabel
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: pill.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: pill.primary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        }
    }
}
