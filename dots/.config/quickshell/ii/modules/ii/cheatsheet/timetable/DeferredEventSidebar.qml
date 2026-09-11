import QtQuick

/**
 * Lazy host for the timetable's EventSidebar.
 *
 * The rail is ~2.6k lines (day / details / editor / sources / scope pages, all
 * inline) and used to be built in full the instant the timetable tab opened,
 * even though it starts closed (mode ""). A clean-restart A/B measured the
 * timetable tab at ~148 MiB, most of it retained for the whole session because
 * `keepLastTabLoaded` never lets the tab go. Most timetable visits only glance
 * at the grid and never touch the rail.
 *
 * This wrapper presents the exact same interface WeekView/MonthView already use
 * (same id, same `open`/`mode`/`day`/`sportsListOnly`, same methods and
 * signals) but builds the real EventSidebar on first use and releases it a beat
 * after it closes. Same idiom as DeferredKeybindEditor. Methods forward with
 * `.apply(item, arguments)` so their arity can never drift from the real ones.
 */
Item {
    id: root

    // ── Read state (safe defaults while the rail is not built) ──
    readonly property bool open: loader.item ? loader.item.open : false
    readonly property string mode: loader.item ? loader.item.mode : ""
    readonly property var day: loader.item ? loader.item.day : new Date()

    // Set by the views right before a show* call, and read back by them; the
    // wrapper is the source of truth and forwards it into the item.
    property bool sportsListOnly: false

    // ── Signals (mirror EventSidebar's exactly) ──
    signal saveRequested(var payload)
    signal taskCreateRequested(var task)
    signal taskCompletionRequested(var task)
    signal deleteRequested(var eventData, string scope)
    signal eventFieldsMutationRequested(var eventData, var fields, string scope)
    signal moveRequested(var eventData, var newDate, string scope)
    signal closeRequested
    signal timePickerRequested(string which, int startHour, int startMinute)
    signal datePickerRequested(string purpose, var date)

    function ensure() {
        if (!loader.active)
            loader.active = true;
        // Guarantee the flag is in place before any forwarded method runs,
        // without relying on the Binding below having settled this same tick.
        if (loader.item)
            loader.item.sportsListOnly = root.sportsListOnly;
        return loader.item;
    }

    // ── Methods that may need to open the rail: build, then delegate ──
    function showDay() { const it = ensure(); return it.showDay.apply(it, arguments); }
    function showSportsDay() { const it = ensure(); return it.showSportsDay.apply(it, arguments); }
    function showEvent() { const it = ensure(); return it.showEvent.apply(it, arguments); }
    function showSources() { const it = ensure(); return it.showSources.apply(it, arguments); }
    function showUndatedTasks() { const it = ensure(); return it.showUndatedTasks.apply(it, arguments); }
    function startCreate() { const it = ensure(); return it.startCreate.apply(it, arguments); }
    function startCreateAt() { const it = ensure(); return it.startCreateAt.apply(it, arguments); }
    function startEdit() { const it = ensure(); return it.startEdit.apply(it, arguments); }
    function requestDelete() { const it = ensure(); return it.requestDelete.apply(it, arguments); }
    function requestTimedMutation() { const it = ensure(); return it.requestTimedMutation.apply(it, arguments); }
    function requestMove() { const it = ensure(); return it.requestMove.apply(it, arguments); }

    // ── Methods only meaningful while already open: no build ──
    function applyPickedTime() { if (loader.item) return loader.item.applyPickedTime.apply(loader.item, arguments); }
    function applyPickedDate() { if (loader.item) return loader.item.applyPickedDate.apply(loader.item, arguments); }
    function close() { if (loader.item) return loader.item.close.apply(loader.item, arguments); }

    Binding {
        target: loader.item
        property: "sportsListOnly"
        value: root.sportsListOnly
        when: loader.item !== null
    }

    Loader {
        id: loader
        anchors.fill: parent
        active: false
        sourceComponent: EventSidebar {
            onSaveRequested: payload => root.saveRequested(payload)
            onTaskCreateRequested: task => root.taskCreateRequested(task)
            onTaskCompletionRequested: task => root.taskCompletionRequested(task)
            onDeleteRequested: (eventData, scope) => root.deleteRequested(eventData, scope)
            onEventFieldsMutationRequested: (eventData, fields, scope) => root.eventFieldsMutationRequested(eventData, fields, scope)
            onMoveRequested: (eventData, newDate, scope) => root.moveRequested(eventData, newDate, scope)
            onCloseRequested: root.closeRequested()
            onTimePickerRequested: (which, startHour, startMinute) => root.timePickerRequested(which, startHour, startMinute)
            onDatePickerRequested: (purpose, date) => root.datePickerRequested(purpose, date)
        }
    }

    // Free the rail a beat after it closes so the container's width animation
    // can collapse first; reopening within the grace period keeps it.
    onOpenChanged: {
        if (root.open)
            releaseTimer.stop();
        else
            releaseTimer.restart();
    }

    Timer {
        id: releaseTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (!root.open)
                loader.active = false;
        }
    }
}
