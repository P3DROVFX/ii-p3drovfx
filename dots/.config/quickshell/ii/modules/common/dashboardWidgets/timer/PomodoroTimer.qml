import qs.services
import qs.modules.common
import qs.modules.common.animations
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    property int sizeW: 0
    property int sizeH: 0

    readonly property bool isWide: sizeW >= 4 || (sizeW === 0 && root.width > 320 && root.height < 200)
    readonly property bool isTall: sizeH >= 4 || (sizeH === 0 && root.height > 220 && root.width < 260)
    readonly property bool isCompact: (sizeW === 2 && sizeH === 2) || (sizeW === 0 && root.width < 260 && root.height < 180)

    readonly property bool dense: root.isCompact || (root.width > 0 && root.width < 260)

    implicitHeight: root.isWide ? wideLayout.implicitHeight : contentColumn.implicitHeight
    property bool showShortcutHints: false

    implicitWidth: root.isWide ? wideLayout.implicitWidth : contentColumn.implicitWidth

    readonly property real ringGap: root.isCompact ? 4 : (root.dense ? 6 : 10)
    readonly property real ringInset: root.isCompact ? 4 : (root.dense ? 8 : 0)
    readonly property real ringSize: {
        if (root.height <= 0)
            return 200;
        if (root.isWide)
            return Math.max(90, Math.min(130, root.height - 20));
        if (root.isCompact)
            return Math.max(68, Math.min(76, root.height * 0.52));
        return Math.max(root.dense ? 82 : 110,
            Math.min(200, root.height - (buttonsRow ? buttonsRow.implicitHeight : 35) - root.ringGap - root.ringInset,
                root.width - (root.dense ? 20 : 0)));
    }

    readonly property real _realRingValue: TimerService.pomodoroLapDuration > 0 ? (TimerService.pomodoroSecondsLeft / TimerService.pomodoroLapDuration) : 0
    property real _ringAnimValue: _realRingValue
    property int entranceTrigger: -1
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations

    function finishEntrance() {
        entranceStarter.stop();
        contentTranslate.y = 0;
        _ringAnimValue = Qt.binding(function() { return root._realRingValue; });
    }

    function beginEntrance() {
        if (!entranceAnimationsEnabled || entranceTrigger < 0) {
            finishEntrance();
            return;
        }
        _ringAnimValue = 0;
        contentTranslate.y = 20;
        entranceStarter.requestStart();
    }

    onEntranceTriggerChanged: beginEntrance()
    onEntranceAnimationsEnabledChanged: entranceAnimationsEnabled ? beginEntrance() : finishEntrance()
    Component.onCompleted: beginEntrance()

    Loader {
        id: entranceController
        active: root.entranceAnimationsEnabled
        sourceComponent: Item {
            function restart() { animation.restart(); }
            function stop() { animation.stop(); }
            SequentialAnimation {
                id: animation
                PauseAnimation { duration: Math.round(Appearance.animation.elementMove.duration * 0.1) }
                ParallelAnimation {
                    SidebarGroupAnimation { target: contentTranslate; property: "y"; from: 20; to: 0; animationSpec: Appearance.animation.elementMove }
                    SidebarGroupAnimation { target: root; property: "_ringAnimValue"; from: 0; to: root._realRingValue; animationSpec: Appearance.animation.elementMove }
                }
                ScriptAction {
                    script: root._ringAnimValue = Qt.binding(function() { return root._realRingValue; })
                }
            }
        }
    }

    DeferredAnimationStarter {
        id: entranceStarter
        controller: entranceController
        enabled: root.entranceAnimationsEnabled
    }

    component PomodoroControlButtons: RowLayout {
        id: ctrlRow
        property bool isCompactLayout: root.isCompact
        spacing: (root.dense || isCompactLayout || root.isWide) ? 6 : 8

        RippleButton {
            buttonRadius: Appearance.rounding.full
            contentItem: TaskShortcutContent {
                labelText: TimerService.pomodoroRunning ? Translation.tr("Pause") : (TimerService.pomodoroSecondsLeft === TimerService.pomodoroLapDuration) ? Translation.tr("Start") : Translation.tr("Resume")
                shortcut: "Ctrl + ↵"
                showHint: root.showShortcutHints
                labelPixelSize: (isCompactLayout || root.isWide) ? Appearance.font.pixelSize.smaller : (root.dense ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger)
                color: TimerService.pomodoroRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
            }
            implicitHeight: (isCompactLayout || root.isWide) ? 28 : (root.dense ? 38 : 35)
            implicitWidth: isCompactLayout ? 58 : (root.isWide ? 64 : (root.dense ? 68 : 84))
            font.pixelSize: (isCompactLayout || root.isWide)
                ? Appearance.font.pixelSize.smaller
                : (root.dense ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger)
            onClicked: TimerService.togglePomodoro()
            colBackground: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
            colBackgroundHover: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colPrimaryHover
            colRipple: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colPrimaryActive
        }

        RippleButton {
            buttonRadius: Appearance.rounding.full
            implicitHeight: (isCompactLayout || root.isWide) ? 28 : (root.dense ? 38 : 35)
            implicitWidth: isCompactLayout ? 58 : (root.isWide ? 64 : (root.dense ? 68 : 84))

            onClicked: TimerService.resetPomodoro()
            enabled: (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration) || TimerService.pomodoroCycle > 0 || TimerService.pomodoroBreak

            font.pixelSize: (isCompactLayout || root.isWide)
                ? Appearance.font.pixelSize.smaller
                : (root.dense ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger)
            colBackground: Appearance.colors.colErrorContainer
            colBackgroundHover: Appearance.colors.colErrorContainerHover
            colRipple: Appearance.colors.colErrorContainerActive

            contentItem: TaskShortcutContent {
                labelText: Translation.tr("Reset")
                shortcut: "R"
                showHint: root.showShortcutHints
                labelPixelSize: (isCompactLayout || root.isWide) ? Appearance.font.pixelSize.smaller : (root.dense ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger)
                color: Appearance.colors.colOnErrorContainer
            }
        }

        RippleButton {
            id: editTimeButton
            visible: !isCompactLayout && !root.isWide
            implicitHeight: isCompactLayout ? 32 : (root.dense ? 38 : 35)
            implicitWidth: isCompactLayout ? 32 : (root.dense ? 34 : 35)
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: TimerService.requestCustomTime()

            contentItem: TaskShortcutContent {
                symbol: "edit"
                shortcut: "E"
                showHint: root.showShortcutHints
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnSecondaryContainer
            }

            StyledToolTip {
                extraVisibleCondition: editTimeButton.hovered
                text: Translation.tr("Set custom time")
            }
        }
    }

    // ── Wide 4x2 Layout ──────────────────────────────────────────────────
    Item {
        id: wideLayout
        visible: root.isWide
        anchors.fill: parent
        anchors.margins: 4

        readonly property real leftPaneWidth: Math.min(width * 0.44, height + 10)

        Item {
            id: wideLeftPane
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: wideLayout.leftPaneWidth

            CircularProgress {
                anchors.centerIn: parent
                lineWidth: Math.max(4, Math.round(root.ringSize / 22))
                value: root._ringAnimValue
                implicitSize: Math.min(parent.width - 4, parent.height - 4, root.ringSize)
                enableAnimation: false

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0

                    Item {
                        implicitWidth: wideTimeText.implicitWidth + 12
                        implicitHeight: wideTimeText.implicitHeight + 4

                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            color: wideTimeMouse.containsMouse ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.12) : "transparent"
                        }

                        StyledText {
                            id: wideTimeText
                            anchors.centerIn: parent
                            text: {
                                let totalSecs = Math.max(0, TimerService.pomodoroSecondsLeft);
                                let hours = Math.floor(totalSecs / 3600);
                                let minutes = Math.floor((totalSecs % 3600) / 60).toString().padStart(2, '0');
                                let seconds = Math.floor(totalSecs % 60).toString().padStart(2, '0');
                                if (hours > 0) return `${hours.toString().padStart(2, '0')}:${minutes}:${seconds}`;
                                return `${minutes}:${seconds}`;
                            }
                            font.pixelSize: Math.round(Math.max(18, Math.min(26, root.ringSize * 0.24)))
                            font.weight: Font.Bold
                            color: wideTimeMouse.containsMouse ? Appearance.colors.colPrimary : Appearance.m3colors.m3onSurface
                        }

                        MouseArea {
                            id: wideTimeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                let currentSeconds = TimerService.pomodoroSecondsLeft > 0 ? TimerService.pomodoroSecondsLeft : TimerService.pomodoroLapDuration;
                                let startHour = Math.floor(currentSeconds / 3600);
                                let startMinute = Math.floor((currentSeconds % 3600) / 60);
                                let title = TimerService.pomodoroLongBreak ? Translation.tr("Long break time") : TimerService.pomodoroBreak ? Translation.tr("Break time") : Translation.tr("Focus time");
                                TimerService.requestCustomTime(startHour, startMinute, title);
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: wideTimeMouse.containsMouse
                            text: Translation.tr("Click to set custom time")
                        }
                    }
                }
            }
        }

        Item {
            id: wideRightPane
            anchors {
                left: wideLeftPane.right
                right: parent.right
                top: parent.top
                bottom: parent.bottom
                leftMargin: 8
                rightMargin: 4
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                RowLayout {
                    spacing: 6

                    StyledText {
                        text: TimerService.pomodoroLongBreak ? Translation.tr("Long break") : TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus")
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }

                    RippleButton {
                        implicitWidth: 22
                        implicitHeight: 22
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: TimerService.requestCustomTime()

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "edit"
                            iconSize: 13
                            color: Appearance.colors.colSubtext
                        }

                        StyledToolTip {
                            extraVisibleCondition: parent.hovered
                            text: Translation.tr("Set custom time")
                        }
                    }
                }

                RowLayout {
                    spacing: 6

                    Repeater {
                        model: 4
                        Rectangle {
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: Appearance.rounding.full
                            color: index <= TimerService.pomodoroCycle
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer2Hover
                        }
                    }

                    StyledText {
                        text: Translation.tr("Cycle %1 of %2").arg(String(TimerService.pomodoroCycle + 1)).arg("4")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                PomodoroControlButtons {
                    isCompactLayout: false
                }
            }
        }
    }

    // ── Standard / Compact / Tall Layout ─────────────────────────────────
    ColumnLayout {
        id: contentColumn
        visible: !root.isWide
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.isCompact ? -6 : 0
        spacing: root.isCompact ? 4 : root.ringGap
        transform: Translate { id: contentTranslate; y: 0 }

        // The Pomodoro timer circle
        CircularProgress {
            id: circularProgress
            Layout.alignment: Qt.AlignHCenter
            lineWidth: Math.max(4, Math.round(root.ringSize / 25))
            value: root._ringAnimValue
            implicitSize: root.ringSize
            enableAnimation: false

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                Item {
                    id: timeClickableArea
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: timeText.implicitWidth + (root.isCompact ? 10 : 16)
                    implicitHeight: timeText.implicitHeight + (root.isCompact ? 4 : 6)

                    Rectangle {
                        id: timeHoverBg
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: timeMouseArea.containsMouse ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.12) : "transparent"
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(timeHoverBg)
                        }
                    }

                    StyledText {
                        id: timeText
                        anchors.centerIn: parent
                        text: {
                            let totalSecs = Math.max(0, TimerService.pomodoroSecondsLeft);
                            let hours = Math.floor(totalSecs / 3600);
                            let minutes = Math.floor((totalSecs % 3600) / 60).toString().padStart(2, '0');
                            let seconds = Math.floor(totalSecs % 60).toString().padStart(2, '0');
                            if (hours > 0) {
                                return `${hours.toString().padStart(2, '0')}:${minutes}:${seconds}`;
                            }
                            return `${minutes}:${seconds}`;
                        }
                        font.pixelSize: {
                            let totalSecs = Math.max(0, TimerService.pomodoroSecondsLeft);
                            let hours = Math.floor(totalSecs / 3600);
                            return Math.round(Math.max(17, Math.min(hours > 0 ? 30 : 40, root.ringSize * (hours > 0 ? 0.19 : 0.25))));
                        }
                        font.weight: Font.Bold
                        color: timeMouseArea.containsMouse ? Appearance.colors.colPrimary : Appearance.m3colors.m3onSurface
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(timeText)
                        }
                    }

                    MouseArea {
                        id: timeMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            let currentSeconds = TimerService.pomodoroSecondsLeft > 0 ? TimerService.pomodoroSecondsLeft : TimerService.pomodoroLapDuration;
                            let startHour = Math.floor(currentSeconds / 3600);
                            let startMinute = Math.floor((currentSeconds % 3600) / 60);
                            let title = TimerService.pomodoroLongBreak ? Translation.tr("Long break time") : TimerService.pomodoroBreak ? Translation.tr("Break time") : Translation.tr("Focus time");
                            TimerService.requestCustomTime(startHour, startMinute, title);
                        }
                    }

                    StyledToolTip {
                        extraVisibleCondition: timeMouseArea.containsMouse
                        text: Translation.tr("Click to set custom time")
                    }
                }

                StyledText {
                    id: modeLabel
                    Layout.alignment: Qt.AlignHCenter
                    text: TimerService.pomodoroLongBreak ? Translation.tr("Long break") : TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus")
                    font.pixelSize: root.isCompact ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext

                    property string _lastMode: ""
                    readonly property string _currentMode: TimerService.pomodoroLongBreak ? "long" : TimerService.pomodoroBreak ? "break" : "focus"

                    transform: Scale {
                        id: modeScale
                        origin.y: modeLabel.height / 2
                        yScale: 1.0
                    }

                    on_CurrentModeChanged: {
                        if (_lastMode !== "" && _lastMode !== _currentMode) {
                            modeFlip.restart();
                        }
                        _lastMode = _currentMode;
                    }

                    SequentialAnimation {
                        id: modeFlip
                        NumberAnimation { target: modeScale; property: "yScale"; from: 1.0; to: 0.0; duration: 120; easing.type: Easing.InCubic }
                        NumberAnimation { target: modeScale; property: "yScale"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutBack }
                    }
                }
            }

            Rectangle {
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                }
                implicitWidth: Math.round(Math.max(22, Math.min(36, root.ringSize * 0.18)))
                implicitHeight: implicitWidth

                StyledText {
                    id: cycleText
                    anchors.centerIn: parent
                    color: Appearance.colors.colOnLayer2
                    text: TimerService.pomodoroCycle + 1
                    font.pixelSize: root.isCompact ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.normal
                }
            }
        }

        // The Start/Stop, Reset and Edit buttons
        PomodoroControlButtons {
            id: buttonsRow
            Layout.alignment: Qt.AlignHCenter
            isCompactLayout: root.isCompact
        }
    }
}
