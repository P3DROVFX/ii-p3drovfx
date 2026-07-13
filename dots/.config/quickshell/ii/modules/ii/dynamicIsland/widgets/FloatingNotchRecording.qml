import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import Quickshell

Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property bool active: (Persistent.states.screenRecord && Persistent.states.screenRecord.active) || false
    readonly property bool paused: (Persistent.states.screenRecord && Persistent.states.screenRecord.paused) || false
    readonly property bool isLoading: (Persistent.states.screenRecord && Persistent.states.screenRecord.loading) || false
    readonly property int elapsedSeconds: (Persistent.states.screenRecord && Persistent.states.screenRecord.seconds) || 0

    onActiveChanged: {
        if (!active) {
            elapsedSeconds = 0;
        }
    }

    readonly property string timeText: {
        const mins = Math.floor(elapsedSeconds / 60);
        const secs = elapsedSeconds % 60;
        return String(mins).padStart(2, '0') + ":" + String(secs).padStart(2, '0');
    }

    // ==========================================
    // 1. CONTRACTED MODE
    // ==========================================
    RowLayout {
        id: contractedLayout
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8
        visible: !root.isExpanded

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            width: 10
            height: 10
            radius: 5
            color: root.paused ? Appearance.colors.colWarning : Appearance.colors.colError

            SequentialAnimation on opacity {
                running: root.active && !root.paused
                loops: Animation.Infinite
                NumberAnimation {
                    from: 1.0
                    to: 0.3
                    duration: 600
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    from: 0.3
                    to: 1.0
                    duration: 600
                    easing.type: Easing.InOutSine
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.bold: true
            font.features: ({
                    "tnum": 1
                })
            color: Appearance.colors.colOnSurface
            text: root.paused ? Translation.tr("PAUSED") : root.timeText
        }
    }

    // ==========================================
    // 2. EXPANDED MODE
    // ==========================================
    ColumnLayout {
        id: expandedLayout
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 12
        visible: root.isExpanded

        // Header Row: Icon/Title + Timer
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Static badge for recording state
            Rectangle {
                width: 36
                height: 36
                radius: 18
                color: Appearance.colors.colError

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.paused ? "pause" : "videocam"
                    iconSize: Appearance.font.pixelSize.medium
                    color: Appearance.colors.colOnError
                }
            }

            // Title and Status
            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                    text: Translation.tr("Screen Record")
                }

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.paused ? Appearance.colors.colWarning : Appearance.colors.colError
                    text: root.paused ? Translation.tr("Paused") : Translation.tr("Recording...")
                }
            }

            // High-contrast digital timer
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.numbers
                font.weight: Font.Bold
                font.features: ({
                        "tnum": 1
                    })
                color: Appearance.colors.colOnSurface
                text: root.timeText
            }
        }

        // Live Audio/Activity soundwave visualization
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            clip: true

            Row {
                id: waveRow
                spacing: 4
                anchors.centerIn: parent

                property var heights: [6, 12, 18, 14, 8, 16, 10, 14, 6]

                Repeater {
                    model: 9
                    delegate: Rectangle {
                        width: 3
                        height: root.paused ? 4 : waveRow.heights[index]
                        radius: 1.5
                        color: root.paused ? Appearance.colors.colWarning : Appearance.colors.colError
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on height {
                            NumberAnimation {
                                duration: 80
                            }
                        }
                    }
                }

                Timer {
                    interval: 80
                    running: root.active && !root.paused && root.isExpanded
                    repeat: true
                    onTriggered: {
                        let newH = [];
                        for (let i = 0; i < 9; i++) {
                            newH.push(Math.floor(Math.random() * 16) + 4);
                        }
                        waveRow.heights = newH;
                    }
                }
            }
        }

        // Sleek circular action buttons
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 36
            spacing: 20

            RippleButton {
                id: stopBtn
                width: 36
                height: 36
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                buttonRadius: 18
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colErrorContainerActive

                onClicked: Quickshell.execDetached([Directories.recordScriptPath])

                contentItem: Item {
                    implicitWidth: 36
                    implicitHeight: 36
                    MaterialSymbol {
                        text: "stop"
                        iconSize: Appearance.font.pixelSize.medium
                        color: Appearance.colors.colOnErrorContainer
                        fill: 1
                        anchors.centerIn: parent
                    }
                }
            }

            RippleButton {
                id: pauseBtn
                width: 36
                height: 36
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                buttonRadius: 18
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive

                onClicked: Quickshell.execDetached([Directories.recordScriptPath, "--pause"])

                contentItem: Item {
                    implicitWidth: 36
                    implicitHeight: 36
                    MaterialSymbol {
                        text: root.paused ? "play_arrow" : "pause"
                        iconSize: Appearance.font.pixelSize.medium
                        color: Appearance.colors.colOnSecondaryContainer
                        fill: 1
                        anchors.centerIn: parent
                    }
                }
            }
        }
    }
}
