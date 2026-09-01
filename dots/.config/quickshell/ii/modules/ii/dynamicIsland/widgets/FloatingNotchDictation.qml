pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell

/**
 * The notch while speech is being dictated into another window.
 *
 * The bars are the real thing: `DictationService` reads voxtype's own audio
 * bridge, so what moves here is the audio the daemon is actually transcribing,
 * not a decorative animation. When that sidecar is missing the row falls back to
 * a slow breath rather than pretending to hear something.
 *
 * Nothing here grabs focus or keyboard — the whole point is that the keystrokes
 * voxtype synthesises land in the window the user was already typing in.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property bool recording: DictationService.recording
    readonly property bool transcribing: DictationService.transcribing
    readonly property int elapsedSeconds: Math.floor(DictationService.elapsedMs / 1000)
    readonly property bool hasLevels: DictationService.bridgeInstalled && DictationService.waveform.length > 0

    readonly property string timeText: {
        const minutes = Math.floor(root.elapsedSeconds / 60);
        return String(minutes).padStart(2, '0') + ":" + String(root.elapsedSeconds % 60).padStart(2, '0');
    }
    readonly property color accent: root.transcribing ? Appearance.colors.colSecondary : Appearance.colors.colPrimary

    /** Bar height for slot `index` of `count`, newest sample on the right. */
    function barHeight(index, count, maxHeight) {
        const levels = DictationService.waveform;
        const minHeight = 3;
        if (!root.recording)
            return minHeight;
        if (!root.hasLevels)
            return minHeight + (maxHeight - minHeight) * 0.25 * breath.value;
        const sample = levels[levels.length - count + index];
        if (sample === undefined)
            return minHeight;
        return minHeight + (maxHeight - minHeight) * Math.max(0, Math.min(1, sample));
    }

    QtObject {
        id: breath
        property real value: 0.4

        // Only animates when it is the thing being shown, so a missing audio
        // bridge does not leave a timer running behind a hidden notch.
        NumberAnimation on value {
            running: root.recording && !root.hasLevels
            loops: Animation.Infinite
            from: 0.25
            to: 1.0
            duration: 900
            easing.type: Easing.InOutSine
        }
    }

    component LevelBars: Row {
        id: bars
        property int count: 12
        property real maxHeight: 16
        property real barWidth: 3
        spacing: 3

        Repeater {
            model: bars.count
            delegate: Rectangle {
                required property int index
                width: bars.barWidth
                height: root.barHeight(index, bars.count, bars.maxHeight)
                radius: width / 2
                color: root.accent
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.transcribing ? 0.45 : 1

                Behavior on height {
                    NumberAnimation { duration: 70; easing.type: Easing.OutQuad }
                }
            }
        }
    }

    // ── Contracted ───────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 10
        visible: !root.isExpanded

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.transcribing ? "graphic_eq" : "mic"
            iconSize: Appearance.font.pixelSize.large
            color: root.accent

            SequentialAnimation on opacity {
                running: root.recording
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.45; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
            }
            onTextChanged: if (!root.recording) opacity = 1.0
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: root.transcribing ? Translation.tr("Transcribing…") : Translation.tr("Listening…")
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSurface
        }

        LevelBars {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            count: 12
            maxHeight: 16
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            visible: root.recording
            text: root.timeText
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.features: ({ "tnum": 1 })
            font.weight: Font.Bold
            color: Appearance.colors.colSubtext
        }
    }

    // ── Expanded ─────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 10
        visible: root.isExpanded

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                width: 36
                height: 36
                radius: 18
                color: root.accent

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.transcribing ? "graphic_eq" : "mic"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.transcribing ? Appearance.colors.colOnSecondary : Appearance.colors.colOnPrimary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.transcribing ? Translation.tr("Transcribing…") : Translation.tr("Dictation")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.transcribing
                        ? DictationService.qualityLabel
                        : Translation.tr("Types into the focused window")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            StyledText {
                visible: root.recording
                text: root.timeText
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.numbers
                font.weight: Font.Bold
                font.features: ({ "tnum": 1 })
                color: Appearance.colors.colOnSurface
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 24

            LevelBars {
                anchors.centerIn: parent
                count: 24
                maxHeight: 22
                barWidth: 3
            }
        }

        RippleButtonWithIcon {
            Layout.alignment: Qt.AlignHCenter
            visible: root.recording
            materialIcon: "stop"
            mainText: Translation.tr("Stop and type")
            onClicked: DictationService.stop()
        }
    }
}
