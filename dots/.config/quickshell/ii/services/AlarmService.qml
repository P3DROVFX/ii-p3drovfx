pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property list<var> alarms: Persistent.ready ? Persistent.states.alarms : []
    property int ringingAlarmIndex: -1
    property var ringingAlarm: (ringingAlarmIndex >= 0 && alarms && ringingAlarmIndex < alarms.length) ? alarms[ringingAlarmIndex] : null

    property string lastTriggeredMinute: ""

    function saveAlarms(newAlarms) {
        Persistent.states.alarms = newAlarms;
        root.alarms = Persistent.states.alarms;
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready) {
                root.alarms = Persistent.states.alarms;
            }
        }
    }

    function toggleAlarm(index) {
        if (!Persistent.ready) return;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
        if (index >= 0 && index < cloned.length) {
            cloned[index].enabled = !cloned[index].enabled;
            if (!cloned[index].enabled && ringingAlarmIndex === index) {
                stopRinging();
            }
            saveAlarms(cloned);
        }
    }

    function addAlarm(time, label, days) {
        if (!Persistent.ready) return;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms || []));
        cloned.push({
            time: time || "08:00",
            label: label || Translation.tr("Alarm"),
            days: days || [false, false, false, false, false, false, false],
            enabled: true
        });
        cloned.sort((a, b) => a.time.localeCompare(b.time));
        saveAlarms(cloned);
    }

    function editAlarm(index, time, label, days) {
        if (!Persistent.ready) return;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
        if (index >= 0 && index < cloned.length) {
            cloned[index].time = time;
            cloned[index].label = label;
            cloned[index].days = days;
            cloned[index].enabled = true;
            cloned.sort((a, b) => a.time.localeCompare(b.time));
            saveAlarms(cloned);
        }
    }

    function deleteAlarm(index) {
        if (!Persistent.ready) return;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
        if (index >= 0 && index < cloned.length) {
            if (ringingAlarmIndex === index) {
                stopRinging();
            }
            cloned.splice(index, 1);
            saveAlarms(cloned);
        }
    }

    function triggerAlarm(index) {
        if (index < 0 || index >= alarms.length) return;

        let now = new Date();
        let currentHour = now.getHours().toString().padStart(2, '0');
        let currentMin = now.getMinutes().toString().padStart(2, '0');
        lastTriggeredMinute = currentHour + ":" + currentMin;

        ringingAlarmIndex = index;
        let alarm = alarms[index];

        // Play sound in loop if enabled
        SoundService.stopLoop();
        if (Config.options.sounds.alarm) {
            SoundService.startLoop("alarm-clock-elapsed");
        }

        // Send a system notification if the fullscreen popup is disabled
        if (!Config.options.time.alarms.useFullscreenPopup) {
            let labelStr = alarm.label ? alarm.label : Translation.tr("Alarm");
            Quickshell.execDetached(["notify-send", labelStr, alarm.time, "-a", "Alarm", "-i", "alarm", "--urgency=critical", "--hint=boolean:suppress-sound:true"]);
        }

        GlobalStates.alarmRinging = true;
    }

    function stopRinging() {
        if (ringingAlarmIndex === -1) return;

        let alarm = alarms[ringingAlarmIndex];
        if (alarm && !alarm.days.includes(true)) {
            let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
            for (let i = 0; i < cloned.length; i++) {
                if (cloned[i].time === alarm.time && cloned[i].label === alarm.label) {
                    cloned[i].enabled = false;
                    break;
                }
            }
            saveAlarms(cloned);
        }

        ringingAlarmIndex = -1;
        SoundService.stopLoop();
        GlobalStates.alarmRinging = false;
    }

    function checkAlarms() {
        if (!Persistent.ready || !alarms || alarms.length === 0) return;
        
        let now = new Date();
        let currentHour = now.getHours().toString().padStart(2, '0');
        let currentMin = now.getMinutes().toString().padStart(2, '0');
        let timeStr = currentHour + ":" + currentMin;
        
        if (timeStr === lastTriggeredMinute) {
            return;
        }

        if (ringingAlarmIndex !== -1) {
            return;
        }

        let dayOfWeek = now.getDay(); // 0 = Sunday, 1 = Monday, ..., 6 = Saturday

        for (let i = 0; i < alarms.length; i++) {
            let alarm = alarms[i];
            if (alarm.enabled && alarm.time === timeStr) {
                let hasRepeatDays = alarm.days.includes(true);
                let dayMatches = !hasRepeatDays || alarm.days[dayOfWeek];

                if (dayMatches) {
                    triggerAlarm(i);
                    break;
                }
            }
        }
    }

    Timer {
        id: alarmCheckTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: checkAlarms()
    }

    Timer {
        id: autoStopTimer
        interval: 300000 // 5 minutes
        running: ringingAlarmIndex !== -1
        repeat: false
        onTriggered: stopRinging()
    }

    IpcHandler {
        target: "alarmService"
        function trigger(index: int): void {
            root.triggerAlarm(index);
        }
        function add(time: string, label: string): void {
            root.addAlarm(time, label, [true, true, true, true, true, true, true]);
        }
        function stop(): void {
            root.stopRinging();
        }
    }

    Component.onCompleted: {
        if (Persistent.ready) {
            root.alarms = Persistent.states.alarms;
        }
    }
}
