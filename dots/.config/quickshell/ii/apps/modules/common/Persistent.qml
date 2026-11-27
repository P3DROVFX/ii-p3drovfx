pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Slim Persistent stand-in for standalone apps (primarily Calendar).
 * Persists only the timetable UI state to `${Directories.appsState}/calendar.json`
 * so the app never races with the shell's `states.json` JsonAdapter.
 */
Singleton {
    id: root

    property bool ready: false
    readonly property string statePath: `${Directories.appsState}/calendar.json`

    property QtObject states: QtObject {
        property QtObject cheatsheet: QtObject {
            property string timetableView: "month"
            property bool timetableShowUpcoming: true
            property string timetableMonthDensity: "compact"
            property bool timetableCollapseRecurring: true
            property var timetableCollapsedUpcomingGroups: []
            property int timetableSlotHeight: 168
            property int timetableSlotHeightVersion: 0
            property bool authBannerDismissed: false

            onTimetableViewChanged: root.scheduleSave()
            onTimetableShowUpcomingChanged: root.scheduleSave()
            onTimetableMonthDensityChanged: root.scheduleSave()
            onTimetableCollapseRecurringChanged: root.scheduleSave()
            onTimetableCollapsedUpcomingGroupsChanged: root.scheduleSave()
            onTimetableSlotHeightChanged: root.scheduleSave()
            onTimetableSlotHeightVersionChanged: root.scheduleSave()
            onAuthBannerDismissedChanged: root.scheduleSave()
        }
        property QtObject overlay: QtObject {
            property QtObject notes: QtObject {
                property int tabIndex: 0
            }
        }
    }

    property bool _loading: false

    function _applyJson(raw: string): void {
        if (!raw || raw.trim().length === 0)
            return;
        let data;
        try {
            data = JSON.parse(raw);
        } catch (e) {
            return;
        }
        const cs = data?.cheatsheet ?? data ?? {};
        root._loading = true;
        if (typeof cs.timetableView === "string" && ["day", "threeDay", "week", "month"].includes(cs.timetableView))
            root.states.cheatsheet.timetableView = cs.timetableView;
        if (typeof cs.timetableShowUpcoming === "boolean")
            root.states.cheatsheet.timetableShowUpcoming = cs.timetableShowUpcoming;
        if (typeof cs.timetableMonthDensity === "string" && ["compact", "comfortable"].includes(cs.timetableMonthDensity))
            root.states.cheatsheet.timetableMonthDensity = cs.timetableMonthDensity;
        if (typeof cs.timetableCollapseRecurring === "boolean")
            root.states.cheatsheet.timetableCollapseRecurring = cs.timetableCollapseRecurring;
        if (Array.isArray(cs.timetableCollapsedUpcomingGroups))
            root.states.cheatsheet.timetableCollapsedUpcomingGroups = cs.timetableCollapsedUpcomingGroups;
        if (typeof cs.timetableSlotHeight === "number" && cs.timetableSlotHeight > 0)
            root.states.cheatsheet.timetableSlotHeight = cs.timetableSlotHeight;
        if (typeof cs.timetableSlotHeightVersion === "number")
            root.states.cheatsheet.timetableSlotHeightVersion = cs.timetableSlotHeightVersion;
        if (typeof cs.authBannerDismissed === "boolean")
            root.states.cheatsheet.authBannerDismissed = cs.authBannerDismissed;
        root._loading = false;
    }

    function scheduleSave(): void {
        if (!root.ready || root._loading)
            return;
        saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: 150
        repeat: false
        onTriggered: {
            const payload = {
                cheatsheet: {
                    timetableView: root.states.cheatsheet.timetableView,
                    timetableShowUpcoming: root.states.cheatsheet.timetableShowUpcoming,
                    timetableMonthDensity: root.states.cheatsheet.timetableMonthDensity,
                    timetableCollapseRecurring: root.states.cheatsheet.timetableCollapseRecurring,
                    timetableCollapsedUpcomingGroups: root.states.cheatsheet.timetableCollapsedUpcomingGroups,
                    timetableSlotHeight: root.states.cheatsheet.timetableSlotHeight,
                    timetableSlotHeightVersion: root.states.cheatsheet.timetableSlotHeightVersion,
                    authBannerDismissed: root.states.cheatsheet.authBannerDismissed
                }
            };
            Quickshell.execDetached(["mkdir", "-p", Directories.appsState]);
            stateFile.setText(JSON.stringify(payload, null, 2));
        }
    }

    FileView {
        id: stateFile
        path: root.statePath
        atomicWrites: true
        blockAllReads: true
        onLoaded: {
            root._applyJson(stateFile.text());
            root.ready = true;
        }
        onLoadFailed: {
            root.ready = true;
        }
    }

    Component.onCompleted: {
        const text = stateFile.text();
        if (text && text.trim().length > 0)
            root._applyJson(text);
        root.ready = true;
    }
}
