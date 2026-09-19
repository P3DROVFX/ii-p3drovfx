pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.animations
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * Countdown timers. The picker feeds TimerService's shared countdown list, so
 * timers started from search, the calendar or the sports panel show up here
 * too.
 */
Item {
    id: root

    property int sizeW: 0
    property int sizeH: 0

    readonly property bool isWide: sizeW >= 4 || (sizeW === 0 && root.width > 320 && root.height < 200)
    readonly property bool isTall: sizeH >= 4 || (sizeH === 0 && root.height > 220 && root.width < 260)
    readonly property bool isCompact: (sizeW === 2 && sizeH === 2) || (sizeW === 0 && root.width < 260 && root.height < 180)

    property int entranceTrigger: -1
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations
    readonly property bool compact: root.isCompact || (root.height > 0 && root.height < 250)
    readonly property bool dense: root.isCompact || (root.width > 0 && root.width < 260)

    property bool showShortcutHints: false
    readonly property var countdowns: Array.from(TimerService.countdowns ?? [])
    readonly property var draft: Persistent.states.timer.countdownDraft
    readonly property int draftSeconds: TimerService.draftCountdownSeconds()
    // The service stores an absolute end date and exposes the shared display
    // clock used by both this list and the bar widget.
    readonly property int displayTick: TimerService.countdownTick
    readonly property bool dialFocused: hoursDial.activeFocus || minutesDial.activeFocus || secondsDial.activeFocus

    function setDraft(hours, minutes, seconds) {
        if (!root.draft)
            return;
        root.draft.hours = hours;
        root.draft.minutes = minutes;
        root.draft.seconds = seconds;
    }

    function startDraft() {
        if (root.draftSeconds <= 0)
            return;
        TimerService.addCountdownSeconds(root.draftSeconds);
    }

    function toggleCountdown(timer) {
        if (!timer) return;
        if (timer.notified) TimerService.restartCountdown(timer.id);
        else TimerService.toggleCountdown(timer.id);
    }

    function handleKey(event) {
        if (event.modifiers !== Qt.NoModifier && event.modifiers !== Qt.ControlModifier)
            return false;
        let dial = null;
        if (event.key === Qt.Key_H) dial = hoursDial;
        else if (event.key === Qt.Key_M) dial = minutesDial;
        else if (event.key === Qt.Key_S) dial = secondsDial;
        if (dial) {
            dial.forceActiveFocus(Qt.ShortcutFocusReason);
            return true;
        }
        if (event.key === Qt.Key_Escape && root.dialFocused) {
            root.forceActiveFocus(Qt.ShortcutFocusReason);
            return true;
        }
        if (event.key === Qt.Key_Space) {
            if (!event.isAutoRepeat) root.startDraft();
            return true;
        }
        if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) {
            const minutes = Config.options.search.modules.timers.quickPresets[event.key - Qt.Key_F1];
            if (minutes === undefined) return false;
            if (!event.isAutoRepeat) root.setDraft(Math.floor(Number(minutes) / 60), Number(minutes) % 60, 0);
            return true;
        }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down || event.key === Qt.Key_Home || event.key === Qt.Key_End) {
            if (countdownList.count === 0) return false;
            const index = event.key === Qt.Key_Home ? 0 : event.key === Qt.Key_End ? countdownList.count - 1
                : countdownList.currentIndex + (event.key === Qt.Key_Up ? -1 : 1);
            countdownList.currentIndex = Math.max(0, Math.min(countdownList.count - 1, index));
            countdownList.positionViewAtIndex(countdownList.currentIndex, ListView.Contain);
            root.forceActiveFocus(Qt.ShortcutFocusReason);
            return true;
        }
        const selected = root.countdowns[countdownList.currentIndex];
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!event.isAutoRepeat) root.toggleCountdown(selected);
            return true;
        }
        if (event.key === Qt.Key_Delete) {
            if (!event.isAutoRepeat && selected) TimerService.removeCountdown(selected.id);
            return true;
        }
        return false;
    }

    function finishEntrance() {
        entranceStarter.stop();
        root.opacity = 1;
        contentTranslate.y = 0;
    }

    function beginEntrance() {
        if (!entranceAnimationsEnabled || entranceTrigger < 0) {
            finishEntrance();
            return;
        }
        root.opacity = 0;
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
                    SidebarGroupAnimation { target: root; property: "opacity"; from: 0; to: 1; animationSpec: Appearance.animation.elementMove }
                    SidebarGroupAnimation { target: contentTranslate; property: "y"; from: 20; to: 0; animationSpec: Appearance.animation.elementMove }
                }
            }
        }
    }

    DeferredAnimationStarter {
        id: entranceStarter
        controller: entranceController
        enabled: root.entranceAnimationsEnabled
    }

    Component {
        id: countdownItemDelegate

        Rectangle {
            id: countdownItem
            required property var modelData
            required property int index
            readonly property int secondsLeft: {
                root.displayTick; // Re-evaluate while the timer runs
                return TimerService.countdownSecondsLeft(countdownItem.modelData);
            }
            readonly property bool done: countdownItem.modelData?.notified ?? false
            readonly property bool paused: countdownItem.modelData?.paused ?? false
            readonly property real progress: {
                const duration = Number(countdownItem.modelData?.durationSeconds ?? 0);
                if (duration <= 0)
                    return 0;
                return Math.max(0, Math.min(1, countdownItem.secondsLeft / duration));
            }

            width: ListView.view ? ListView.view.width : parent.width
            implicitHeight: root.isCompact ? 36 : (root.dense ? 44 : 38)
            radius: Appearance.rounding.small
            color: countdownItem.done ? Appearance.colors.colErrorContainer
                : (countdownList && countdownList.currentIndex === countdownItem.index) ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

            Rectangle { // Remaining-time fill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: countdownItem.done ? 0 : parent.width * countdownItem.progress
                visible: width > 0
                radius: parent.radius
                color: countdownItem.paused ? Appearance.colors.colLayer2Hover : Appearance.colors.colSecondaryContainer

                Behavior on width {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: root.isCompact ? 6 : 10
                    rightMargin: 4
                }
                spacing: root.isCompact ? 4 : 6

                TaskShortcutContent {
                    symbol: countdownItem.done ? "notifications_active" : countdownItem.paused ? "pause_circle" : "hourglass_top"
                    shortcut: "›"
                    showHint: countdownList && countdownList.currentIndex === countdownItem.index
                    iconSize: root.isCompact ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
                    color: countdownItem.done ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    text: String(countdownItem.modelData?.label ?? Translation.tr("Timer"))
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: countdownItem.done ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
                }
                StyledText {
                    text: countdownItem.done ? Translation.tr("Done") : TimerService.formatCountdownDuration(countdownItem.secondsLeft)
                    font.pixelSize: root.isCompact ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
                    color: countdownItem.done ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer1
                }

                CountdownActionButton {
                    buttonIcon: countdownItem.done ? "restart_alt" : countdownItem.paused ? "play_arrow" : "pause"
                    tooltipText: countdownItem.done ? Translation.tr("Restart") : countdownItem.paused ? Translation.tr("Resume") : Translation.tr("Pause")
                    shortcut: (countdownList && countdownList.currentIndex === countdownItem.index) ? "Enter" : ""
                    iconColour: countdownItem.done ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
                    onClicked: root.toggleCountdown(countdownItem.modelData)
                }
                CountdownActionButton {
                    buttonIcon: "close"
                    tooltipText: Translation.tr("Cancel")
                    shortcut: (countdownList && countdownList.currentIndex === countdownItem.index) ? "Del" : ""
                    iconColour: countdownItem.done ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
                    hoverIconColour: Appearance.colors.colOnErrorContainer
                    colBackgroundHover: countdownItem.done ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer
                    colRipple: Appearance.colors.colErrorContainerActive
                    onClicked: TimerService.removeCountdown(countdownItem.modelData.id)
                }
            }
        }
    }

    // ── Wide 4x2 Layout ──────────────────────────────────────────────────
    Item {
        id: wideLayout
        visible: root.isWide
        anchors.fill: parent
        anchors.margins: 6

        readonly property real paneWidth: Math.floor((width - 9) / 2)

        // Left Pane: Duration Dials + Start Button
        Item {
            id: leftCountdownPane
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: wideLayout.paneWidth
            clip: true

            Column {
                anchors.centerIn: parent
                spacing: 6

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 3

                    DurationDial {
                        shortcut: "H"
                        showShortcutHints: root.showShortcutHints
                        unitLabel: Translation.tr("hours")
                        value: root.draft && root.draft.hours !== undefined && root.draft.hours !== null ? root.draft.hours : 0
                        maxValue: 23
                        implicitWidth: 34
                        implicitHeight: 36
                        numberSize: 16
                        onValueRequested: newValue => { if (root.draft) root.draft.hours = newValue; }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ":"
                        font.pixelSize: 14
                        color: Appearance.colors.colSubtext
                    }
                    DurationDial {
                        shortcut: "M"
                        showShortcutHints: root.showShortcutHints
                        unitLabel: Translation.tr("min")
                        value: root.draft && root.draft.minutes !== undefined && root.draft.minutes !== null ? root.draft.minutes : 0
                        maxValue: 59
                        implicitWidth: 34
                        implicitHeight: 36
                        numberSize: 16
                        onValueRequested: newValue => { if (root.draft) root.draft.minutes = newValue; }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ":"
                        font.pixelSize: 14
                        color: Appearance.colors.colSubtext
                    }
                    DurationDial {
                        shortcut: "S"
                        showShortcutHints: root.showShortcutHints
                        unitLabel: Translation.tr("sec")
                        value: root.draft && root.draft.seconds !== undefined && root.draft.seconds !== null ? root.draft.seconds : 0
                        maxValue: 59
                        implicitWidth: 34
                        implicitHeight: 36
                        numberSize: 16
                        onValueRequested: newValue => { if (root.draft) root.draft.seconds = newValue; }
                    }
                }

                RippleButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitWidth: Math.min(124, leftCountdownPane.width - 8)
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    enabled: root.draftSeconds > 0
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    onClicked: root.startDraft()
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive

                    contentItem: TaskShortcutContent {
                        labelText: Translation.tr("Start %1").arg(TimerService.formatCountdownDuration(root.draftSeconds))
                        shortcut: "Ctrl + ↵"
                        showHint: root.showShortcutHints
                        labelPixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }

        // Divider
        Rectangle {
            id: countdownDivider
            anchors.left: leftCountdownPane.right
            anchors.leftMargin: 4
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.3
        }

        // Right Pane: Active Timers OR 3x2 Presets Grid
        Item {
            id: rightCountdownPane
            anchors.left: countdownDivider.right
            anchors.leftMargin: 4
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            clip: true

            StyledListView {
                anchors.fill: parent
                visible: root.countdowns.length > 0
                spacing: 3
                clip: true
                popin: true
                currentIndex: -1
                model: ScriptModel { values: root.countdowns }
                delegate: countdownItemDelegate
            }

            Column {
                anchors.centerIn: parent
                visible: root.countdowns.length === 0
                spacing: 5
                width: parent.width

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Translation.tr("Quick Presets")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }

                Grid {
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: 3
                    spacing: 4

                    Repeater {
                        model: [5, 10, 15, 25, 45, 60]
                        delegate: RippleButton {
                            required property int modelData
                            implicitHeight: 24
                            implicitWidth: Math.floor((rightCountdownPane.width - 16) / 3)
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: root.setDraft(Math.floor(modelData / 60), modelData % 60, 0)

                            contentItem: StyledText {
                                anchors.centerIn: parent
                                text: `${modelData}m`
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnLayer2
                                font.weight: Font.Medium
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Standard / Compact / Tall Layout ─────────────────────────────────
    ColumnLayout {
        id: standardLayout
        visible: !root.isWide
        anchors {
            fill: parent
            topMargin: root.isCompact ? 4 : (root.dense ? 4 : 2)
            leftMargin: root.isCompact ? 6 : (root.dense ? 6 : 16)
            rightMargin: root.isCompact ? 6 : (root.dense ? 6 : 16)
            bottomMargin: root.isCompact ? 4 : 6
        }
        spacing: root.isCompact ? 3 : (root.compact ? 6 : 10)
        transform: Translate { id: contentTranslate; y: 0 }

        Item {
            visible: root.isCompact && root.countdowns.length === 0
            Layout.fillHeight: true
        }

        RowLayout { // Duration picker
            id: pickerRow
            visible: !root.isCompact || root.countdowns.length === 0
            Layout.alignment: Qt.AlignHCenter
            spacing: root.isCompact ? 2 : 4

            DurationDial {
                id: hoursDial
                shortcut: "H"
                showShortcutHints: root.showShortcutHints
                unitLabel: Translation.tr("hours")
                value: root.draft && root.draft.hours !== undefined && root.draft.hours !== null
                    ? root.draft.hours : 0
                maxValue: 23
                implicitWidth: root.isCompact ? 34 : (root.dense ? 48 : 62)
                implicitHeight: root.isCompact ? 34 : (root.compact ? 50 : 66)
                numberSize: root.isCompact ? 16 : (root.dense ? 22 : (root.compact ? 26 : 32))
                onValueRequested: newValue => {
                    if (root.draft)
                        root.draft.hours = newValue;
                }
            }
            StyledText {
                text: ":"
                font.pixelSize: root.isCompact ? 14 : (root.compact ? 20 : 24)
                color: Appearance.colors.colSubtext
            }
            DurationDial {
                id: minutesDial
                shortcut: "M"
                showShortcutHints: root.showShortcutHints
                unitLabel: Translation.tr("min")
                value: root.draft && root.draft.minutes !== undefined && root.draft.minutes !== null
                    ? root.draft.minutes : 0
                maxValue: 59
                implicitWidth: root.isCompact ? 34 : (root.dense ? 48 : 62)
                implicitHeight: root.isCompact ? 34 : (root.compact ? 50 : 66)
                numberSize: root.isCompact ? 16 : (root.dense ? 22 : (root.compact ? 26 : 32))
                onValueRequested: newValue => {
                    if (root.draft)
                        root.draft.minutes = newValue;
                }
            }
            StyledText {
                text: ":"
                font.pixelSize: root.isCompact ? 14 : (root.compact ? 20 : 24)
                color: Appearance.colors.colSubtext
            }
            DurationDial {
                id: secondsDial
                shortcut: "S"
                showShortcutHints: root.showShortcutHints
                unitLabel: Translation.tr("sec")
                value: root.draft && root.draft.seconds !== undefined && root.draft.seconds !== null
                    ? root.draft.seconds : 0
                maxValue: 59
                implicitWidth: root.isCompact ? 34 : (root.dense ? 48 : 62)
                implicitHeight: root.isCompact ? 34 : (root.compact ? 50 : 66)
                numberSize: root.isCompact ? 16 : (root.dense ? 22 : (root.compact ? 26 : 32))
                onValueRequested: newValue => {
                    if (root.draft)
                        root.draft.seconds = newValue;
                }
            }
        }

        RowLayout { // Compact quick presets row for 2x2
            id: compactPresetsRow
            visible: root.isCompact && root.countdowns.length === 0
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            Repeater {
                model: [1, 5, 10, 15]
                delegate: RippleButton {
                    required property int modelData
                    implicitHeight: 20
                    implicitWidth: 26
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: root.setDraft(Math.floor(modelData / 60), modelData % 60, 0)

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: `${modelData}m`
                        font.pixelSize: Appearance.font.pixelSize.smallest * 0.9
                        color: Appearance.colors.colOnLayer2
                        font.weight: Font.Medium
                    }
                }
            }
        }

        Flow { // Duration presets, wrapping instead of overflowing
            id: presetFlow
            visible: !root.isCompact && root.countdowns.length === 0
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: Config.options.search.modules.timers.quickPresets
                delegate: RippleButton {
                    required property var modelData
                    required property int index
                    implicitHeight: 26
                    implicitWidth: Math.max(42, presetLabel.implicitWidth + 16)
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: root.setDraft(Math.floor(Number(modelData) / 60), Number(modelData) % 60, 0)

                    contentItem: TaskShortcutContent {
                        id: presetLabel
                        labelText: Translation.tr("%1m").arg(String(modelData))
                        labelPixelSize: Appearance.font.pixelSize.smaller
                        shortcut: index < 12 ? "F" + (index + 1) : ""
                        showHint: root.showShortcutHints
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledToolTip {
                        text: Translation.tr("Set %1 minutes").arg(String(modelData))
                    }
                }
            }
        }

        RippleButton { // Start
            id: startBtn
            visible: !root.isCompact || root.countdowns.length === 0
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.isCompact ? 104 : -1
            Layout.fillWidth: !root.isCompact
            implicitHeight: root.isCompact ? 26 : (root.dense ? 40 : 35)
            buttonRadius: Appearance.rounding.full
            enabled: root.draftSeconds > 0
            font.pixelSize: Appearance.font.pixelSize.larger
            onClicked: root.startDraft()

            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive

            contentItem: TaskShortcutContent {
                labelText: Translation.tr("Start %1").arg(TimerService.formatCountdownDuration(root.draftSeconds))
                shortcut: "Ctrl + ↵"
                showHint: root.showShortcutHints
                labelPixelSize: root.isCompact ? Appearance.font.pixelSize.smallest : (root.dense ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger)
                color: Appearance.colors.colOnPrimary
            }
        }

        Item {
            visible: root.isCompact && root.countdowns.length === 0
            Layout.fillHeight: true
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: "↑ / ↓ · Home / End · Enter · Del"
            font.pixelSize: Appearance.font.pixelSize.smallest
            opacity: root.showShortcutHints && !root.dialFocused ? 1 : 0
            visible: opacity > 0 && !root.isCompact
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        Item { // Running timers
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.countdowns.length > 0 || !root.isCompact

            StyledListView {
                id: countdownList
                anchors.fill: parent
                spacing: root.isCompact ? 2 : 4
                clip: true
                popin: true
                currentIndex: -1
                keyNavigationEnabled: false

                model: ScriptModel {
                    values: root.countdowns
                }

                delegate: countdownItemDelegate
            }

            ColumnLayout {
                anchors.centerIn: parent
                // The dials and presets already explain the empty state in a
                // square host; this desktop placeholder otherwise collides
                // with the full-width Start button.
                visible: root.countdowns.length === 0 && !root.dense
                spacing: 0

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "hourglass_disabled"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Drag a dial to set a duration")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    component CountdownActionButton: RippleButton {
        id: actionButton
        property string buttonIcon: ""
        property string tooltipText: ""
        property string shortcut: ""
        property color iconColour: Appearance.colors.colOnLayer2
        property color hoverIconColour: actionButton.iconColour

        implicitHeight: root.dense ? 36 : 30
        implicitWidth: implicitHeight
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active

        contentItem: TaskShortcutContent {
            symbol: actionButton.buttonIcon
            shortcut: actionButton.shortcut
            showHint: root.showShortcutHints
            iconSize: Appearance.font.pixelSize.large
            color: actionButton.hovered ? actionButton.hoverIconColour : actionButton.iconColour
        }

        StyledToolTip {
            text: actionButton.tooltipText
        }
    }
}
