import qs.services
import qs.modules.common
import qs.modules.common.animations
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: stopwatchTab

    property int sizeW: 0
    property int sizeH: 0

    readonly property bool isWide: sizeW >= 4 || (sizeW === 0 && stopwatchTab.width > 320 && stopwatchTab.height < 200)
    readonly property bool isTall: sizeH >= 4 || (sizeH === 0 && stopwatchTab.height > 220 && stopwatchTab.width < 260)
    readonly property bool isCompact: (sizeW === 2 && sizeH === 2) || (sizeW === 0 && stopwatchTab.width < 260 && stopwatchTab.height < 180)

    readonly property bool dense: (stopwatchTab.isCompact || (stopwatchTab.width > 0 && stopwatchTab.width < 260))
    Layout.fillWidth: true
    Layout.fillHeight: true
    property int entranceTrigger: -1
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations

    property bool showShortcutHints: false
    function finishEntrance() {
        entranceStarter.stop();
        stopwatchTab.opacity = 1;
        elapsedEntranceTranslate.y = 0;
    }

    function beginEntrance() {
        if (!entranceAnimationsEnabled || entranceTrigger < 0) {
            finishEntrance();
            return;
        }
        stopwatchTab.opacity = 0;
        elapsedEntranceTranslate.y = 30;
        entranceStarter.requestStart();
    }

    onEntranceTriggerChanged: beginEntrance()
    onEntranceAnimationsEnabledChanged: entranceAnimationsEnabled ? beginEntrance() : finishEntrance()
    Component.onCompleted: beginEntrance()

    Loader {
        id: entranceController
        active: stopwatchTab.entranceAnimationsEnabled
        sourceComponent: Item {
            function restart() { animation.restart(); }
            function stop() { animation.stop(); }
            SequentialAnimation {
                id: animation
                PauseAnimation { duration: Math.round(Appearance.animation.elementMove.duration * 0.1) }
                ParallelAnimation {
                    SidebarGroupAnimation { target: stopwatchTab; property: "opacity"; from: 0; to: 1; animationSpec: Appearance.animation.elementMove }
                    SidebarGroupAnimation { target: elapsedEntranceTranslate; property: "y"; from: 30; to: 0; animationSpec: Appearance.animation.elementMove }
                }
            }
        }
    }

    DeferredAnimationStarter {
        id: entranceStarter
        controller: entranceController
        enabled: stopwatchTab.entranceAnimationsEnabled
    }

    Component {
        id: lapItemDelegate

        Rectangle {
            id: lapItem
            required property int index
            required property var modelData
            property var horizontalPadding: (stopwatchTab.dense || stopwatchTab.isCompact) ? 6 : 10
            property var verticalPadding: (stopwatchTab.dense || stopwatchTab.isCompact) ? 3 : 6
            property real _entranceOffset: 0
            property bool _entranceDone: true

            opacity: _entranceDone ? 1 : 0
            transform: Translate { y: lapItem._entranceDone ? 0 : lapItem._entranceOffset }

            function finishEntrance() {
                lapEntranceStarter.stop();
                _entranceDone = true;
                _entranceOffset = 0;
            }

            function beginEntrance() {
                if (!stopwatchTab.entranceAnimationsEnabled || stopwatchTab.entranceTrigger < 0) {
                    finishEntrance();
                    return;
                }
                _entranceDone = false;
                _entranceOffset = -20;
                lapEntranceStarter.requestStart();
            }

            Component.onCompleted: beginEntrance()

            Connections {
                target: stopwatchTab
                function onEntranceTriggerChanged() { lapItem.beginEntrance(); }
                function onEntranceAnimationsEnabledChanged() {
                    if (!stopwatchTab.entranceAnimationsEnabled)
                        lapItem.finishEntrance();
                }
            }

            Loader {
                id: lapEntranceController
                active: stopwatchTab.entranceAnimationsEnabled
                sourceComponent: Item {
                    function restart() { animation.restart(); }
                    function stop() { animation.stop(); }
                    SequentialAnimation {
                        id: animation
                        PauseAnimation {
                            duration: Math.round(Math.min(lapItem.index, 15)
                                * Appearance.animation.elementMove.duration * 0.08)
                        }
                        ParallelAnimation {
                            SidebarGroupAnimation { target: lapItem; property: "opacity"; from: 0; to: 1; animationSpec: Appearance.animation.elementMove }
                            SidebarGroupAnimation { target: lapItem; property: "_entranceOffset"; from: -20; to: 0; animationSpec: Appearance.animation.elementMove }
                        }
                        ScriptAction { script: lapItem._entranceDone = true }
                    }
                }
            }

            DeferredAnimationStarter {
                id: lapEntranceStarter
                controller: lapEntranceController
                enabled: stopwatchTab.entranceAnimationsEnabled
            }

            width: ListView.view ? ListView.view.width : parent.width
            implicitHeight: lapRow.implicitHeight + verticalPadding * 2
            implicitWidth: lapRow.implicitWidth + horizontalPadding * 2
            color: Appearance.colors.colLayer2
            radius: Appearance.rounding.small

            RowLayout {
                id: lapRow
                anchors {
                    fill: parent
                    leftMargin: lapItem.horizontalPadding
                    rightMargin: lapItem.horizontalPadding
                    topMargin: lapItem.verticalPadding
                    bottomMargin: lapItem.verticalPadding
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: `${TimerService.stopwatchLaps.length - lapItem.index}.`
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: {
                        const lapTime = lapItem.modelData
                        const _10ms = (Math.floor(lapTime) % 100).toString().padStart(2, '0')
                        const totalSeconds = Math.floor(lapTime) / 100
                        const minutes = Math.floor(totalSeconds / 60).toString().padStart(2, '0')
                        const seconds = Math.floor(totalSeconds % 60).toString().padStart(2, '0')
                        return `${minutes}:${seconds}.${_10ms}`
                    }
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colPrimary
                    text: {
                        const originalIndex = TimerService.stopwatchLaps.length - lapItem.index - 1
                        const lastTime = originalIndex > 0 ? TimerService.stopwatchLaps[originalIndex - 1] : 0
                        const lapTime = lapItem.modelData - lastTime
                        const _10ms = (Math.floor(lapTime) % 100).toString().padStart(2, '0')
                        const totalSeconds = Math.floor(lapTime) / 100
                        const minutes = Math.floor(totalSeconds / 60).toString().padStart(2, '0')
                        const seconds = Math.floor(totalSeconds % 60).toString().padStart(2, '0')
                        return `+${minutes == "00" ? "" : minutes + ":"}${seconds}.${_10ms}`
                    }
                }
            }
        }
    }

    // ── Wide 4x2 Layout ──────────────────────────────────────────────────
    RowLayout {
        id: wideContent
        visible: stopwatchTab.isWide
        anchors.fill: parent
        anchors.margins: 4
        spacing: 10

        Item {
            Layout.preferredWidth: Math.round(parent.width * 0.46)
            Layout.fillHeight: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 0

                    StyledText {
                        font.pixelSize: 32
                        font.weight: Font.DemiBold
                        color: Appearance.m3colors.m3onSurface
                        text: {
                            let totalSeconds = Math.floor(TimerService.stopwatchTime) / 100;
                            let minutes = Math.floor(totalSeconds / 60).toString().padStart(2, '0');
                            let seconds = Math.floor(totalSeconds % 60).toString().padStart(2, '0');
                            return `${minutes}:${seconds}`;
                        }
                    }

                    StyledText {
                        font.pixelSize: 26
                        color: Appearance.colors.colSubtext
                        text: `:<sub>${(Math.floor(TimerService.stopwatchTime) % 100).toString().padStart(2, '0')}</sub>`
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6

                    RippleButton {
                        implicitHeight: 30
                        implicitWidth: 66
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        onClicked: TimerService.toggleStopwatch()
                        colBackground: TimerService.stopwatchRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary 
                        colBackgroundHover: TimerService.stopwatchRunning ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colPrimaryHover 
                        colRipple: TimerService.stopwatchRunning ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colPrimaryActive 

                        contentItem: TaskShortcutContent {
                            labelText: TimerService.stopwatchRunning ? Translation.tr("Pause") : TimerService.stopwatchTime === 0 ? Translation.tr("Start") : Translation.tr("Resume")
                            shortcut: "Ctrl + ↵"
                            showHint: stopwatchTab.showShortcutHints
                            labelPixelSize: Appearance.font.pixelSize.smaller
                            color: TimerService.stopwatchRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                        }
                    }

                    RippleButton {
                        implicitHeight: 30
                        implicitWidth: 66
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        onClicked: {
                            if (TimerService.stopwatchRunning) 
                                TimerService.stopwatchRecordLap()
                            else 
                                TimerService.stopwatchReset()
                        }
                        enabled: TimerService.stopwatchTime > 0 || Persistent.states.timer.stopwatch.laps.length > 0
                        colBackground: TimerService.stopwatchRunning ? Appearance.colors.colLayer2 : Appearance.colors.colErrorContainer
                        colBackgroundHover: TimerService.stopwatchRunning ? Appearance.colors.colLayer2Hover : Appearance.colors.colErrorContainerHover
                        colRipple: TimerService.stopwatchRunning ? Appearance.colors.colLayer2Active : Appearance.colors.colErrorContainerActive

                        contentItem: TaskShortcutContent {
                            labelText: TimerService.stopwatchRunning ? Translation.tr("Lap") : Translation.tr("Reset")
                            shortcut: TimerService.stopwatchRunning ? "L" : "R"
                            showHint: stopwatchTab.showShortcutHints
                            labelPixelSize: Appearance.font.pixelSize.smaller
                            color: TimerService.stopwatchRunning ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnErrorContainer
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                anchors.fill: parent
                visible: TimerService.stopwatchLaps.length > 0
                spacing: 3
                clip: true
                popin: true

                model: ScriptModel {
                    values: TimerService.stopwatchLaps.map((v, i, arr) => arr[arr.length - 1 - i])
                }

                delegate: lapItemDelegate
            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: TimerService.stopwatchLaps.length === 0
                spacing: 4

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "timer"
                    iconSize: 26
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No laps recorded yet")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // ── Standard / Compact / Tall Layout ─────────────────────────────────
    Item {
        id: standardContent
        visible: !stopwatchTab.isWide
        anchors {
            fill: parent
            topMargin: stopwatchTab.isCompact ? 4 : 8
            leftMargin: (stopwatchTab.dense || stopwatchTab.isCompact) ? 6 : 16
            rightMargin: (stopwatchTab.dense || stopwatchTab.isCompact) ? 6 : 16
            bottomMargin: stopwatchTab.isCompact ? 2 : 0
        }

        RowLayout { // Elapsed
            id: elapsedIndicator
            transform: Translate { id: elapsedEntranceTranslate; y: 0 }

            anchors {
                top: (stopwatchTab.isCompact && TimerService.stopwatchLaps.length > 0) ? parent.top : undefined
                verticalCenter: (stopwatchTab.isCompact && TimerService.stopwatchLaps.length > 0) ? undefined : parent.verticalCenter
                verticalCenterOffset: stopwatchTab.isCompact ? -((controlButtons.height || 28) + 16) / 2 : -(controlButtons.height + 6) / 2
                horizontalCenter: stopwatchTab.isCompact ? parent.horizontalCenter : undefined
                left: stopwatchTab.isCompact ? undefined : controlButtons.left
                leftMargin: stopwatchTab.isCompact ? 0 : 6
            }

            states: State {
                name: "hasLaps"
                when: !stopwatchTab.isCompact && TimerService.stopwatchLaps.length > 0
                AnchorChanges {
                    target: elapsedIndicator
                    anchors.top: parent.top
                    anchors.verticalCenter: undefined
                    anchors.left: controlButtons.left
                }
            }

            transitions: Transition {
                AnchorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            spacing: 0
            StyledText {
                font.pixelSize: stopwatchTab.isCompact
                    ? 26
                    : (stopwatchTab.dense ? Math.round(Appearance.font.pixelSize.huge * 1.18) : 40)
                color: Appearance.m3colors.m3onSurface
                text: {
                    let totalSeconds = Math.floor(TimerService.stopwatchTime) / 100
                    let minutes = Math.floor(totalSeconds / 60).toString().padStart(2, '0')
                    let seconds = Math.floor(totalSeconds % 60).toString().padStart(2, '0')
                    return `${minutes}:${seconds}`
                }
            }
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: stopwatchTab.isCompact
                    ? 26
                    : (stopwatchTab.dense ? Math.round(Appearance.font.pixelSize.huge * 1.18) : 40)
                color: Appearance.colors.colSubtext
                text: `:<sub>${(Math.floor(TimerService.stopwatchTime) % 100).toString().padStart(2, '0')}</sub>`
            }
        }

        // Laps
        StyledListView {
            id: lapsList
            anchors {
                top: elapsedIndicator.bottom
                bottom: controlButtons.top
                left: parent.left
                right: parent.right
                topMargin: stopwatchTab.isCompact ? 4 : 16
                bottomMargin: stopwatchTab.isCompact ? 4 : 16
            }
            spacing: stopwatchTab.isCompact ? 2 : 4
            clip: true
            popin: true

            model: ScriptModel {
                values: TimerService.stopwatchLaps.map((v, i, arr) => arr[arr.length - 1 - i])
            }

            delegate: lapItemDelegate
        }

        RowLayout {
            id: controlButtons
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: stopwatchTab.isCompact ? 10 : 6
            }
            spacing: 4

            RippleButton {
                buttonRadius: Appearance.rounding.full
                implicitHeight: stopwatchTab.isCompact ? 28 : (stopwatchTab.dense ? 40 : 35)
                implicitWidth: stopwatchTab.isCompact ? 60 : (stopwatchTab.dense ? 76 : 90)
                font.pixelSize: stopwatchTab.isCompact
                    ? Appearance.font.pixelSize.smaller
                    : (stopwatchTab.dense ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger)

                onClicked: {
                    TimerService.toggleStopwatch()
                }

                colBackground: TimerService.stopwatchRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary 
                colBackgroundHover: TimerService.stopwatchRunning ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colPrimaryHover 
                colRipple: TimerService.stopwatchRunning ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colPrimaryActive 

                contentItem: TaskShortcutContent {
                    labelText: TimerService.stopwatchRunning ? Translation.tr("Pause") : TimerService.stopwatchTime === 0 ? Translation.tr("Start") : Translation.tr("Resume")
                    shortcut: "Ctrl + ↵"
                    showHint: stopwatchTab.showShortcutHints
                    labelPixelSize: stopwatchTab.isCompact ? Appearance.font.pixelSize.smaller : (stopwatchTab.dense ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger)
                    color: TimerService.stopwatchRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                }
            }

            RippleButton {
                buttonRadius: Appearance.rounding.full
                implicitHeight: stopwatchTab.isCompact ? 28 : (stopwatchTab.dense ? 40 : 35)
                implicitWidth: stopwatchTab.isCompact ? 60 : (stopwatchTab.dense ? 76 : 90)
                font.pixelSize: stopwatchTab.isCompact
                    ? Appearance.font.pixelSize.smaller
                    : (stopwatchTab.dense ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger)

                onClicked: {
                    if (TimerService.stopwatchRunning) 
                        TimerService.stopwatchRecordLap()
                    else 
                        TimerService.stopwatchReset()
                }
                enabled: TimerService.stopwatchTime > 0 || Persistent.states.timer.stopwatch.laps.length > 0
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colErrorContainerActive

                contentItem: TaskShortcutContent {
                    labelText: TimerService.stopwatchRunning ? Translation.tr("Lap") : Translation.tr("Reset")
                    shortcut: TimerService.stopwatchRunning ? "L" : "R"
                    showHint: stopwatchTab.showShortcutHints
                    labelPixelSize: stopwatchTab.isCompact ? Appearance.font.pixelSize.smaller : (stopwatchTab.dense ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger)
                    color: Appearance.colors.colOnErrorContainer
                }
            }
        }
    }
}
