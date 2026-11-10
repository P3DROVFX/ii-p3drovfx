import QtQuick
import "TimetableGestureMath.js" as G

/**
 * The one pointer state machine behind the timed grid (day, 3-day and week).
 *
 * Views feed it press / move / release / cancel in the events row's own
 * coordinates, so a gesture keeps its meaning while the grid auto-scrolls. The
 * gesture never mutates the calendar: release() returns a result and the view
 * decides what to write. It also owns the draft block the editor is building,
 * so the grid has a single source for "what is on screen while I drag".
 */
QtObject {
    id: gesture

    // ── Geometry, bound by the host grid ──
    property int dayCount: 1
    property real dayStride: 1
    property real pixelsPerMinute: 1
    property int gridStart: 0
    property int gridEnd: 24 * 60
    property int step: 15
    property int threshold: 5

    // ── Interaction ──
    // "" | "click" | "move" | "resizeStart" | "resizeEnd" | "create"
    // | "draftMove" | "draftResizeStart" | "draftResizeEnd"
    property string kind: ""
    // Set once the pointer travels past the threshold; before that a press is
    // still a click.
    property bool active: false
    // The event DTO being moved or resized.
    property var target: null
    readonly property bool busy: kind !== ""

    // Grid coordinates. pointerY follows scrolling so the pointer keeps its
    // place on the content.
    property real pressX: 0
    property real pressY: 0
    property real pointerX: 0
    property real pointerY: 0
    property int originDay: -1
    property int originStart: 0
    property int originEnd: 0
    property real grabMinutes: 0

    // Live range. Before activation it equals the origin, so release() can
    // read it unconditionally.
    property int previewDay: -1
    property int previewStart: 0
    property int previewEnd: 0

    // The draft block the editor is building.
    property int draftDay: -1
    property int draftStart: 0
    property int draftEnd: 0
    readonly property bool hasDraft: draftDay >= 0

    function minutesAt(y) {
        return G.minutesAtY(y, gesture.gridStart, gesture.pixelsPerMinute);
    }

    function press(nextKind, nextTarget, day, x, y, start, end) {
        gesture.kind = nextKind;
        gesture.target = nextTarget;
        gesture.active = false;
        gesture.pressX = x;
        gesture.pressY = y;
        gesture.pointerX = x;
        gesture.pointerY = y;
        gesture.originDay = day;
        gesture.originStart = start;
        gesture.originEnd = end;
        gesture.grabMinutes = gesture.minutesAt(y) - start;
        gesture.previewDay = day;
        gesture.previewStart = start;
        gesture.previewEnd = end;
    }

    function move(x, y) {
        if (gesture.kind === "" || gesture.kind === "click")
            return;
        gesture.pointerX = x;
        gesture.pointerY = y;
        if (!gesture.active) {
            if (!G.crossedThreshold(x - gesture.pressX, y - gesture.pressY, gesture.threshold))
                return;
            gesture.active = true;
        }
        gesture.recompute();
    }

    // The view auto-scrolls the grid during a drag; the pointer stays put on
    // screen, so its grid coordinate moves by the same amount.
    function scrollBy(dy) {
        if (gesture.kind === "")
            return;
        gesture.pointerY += dy;
        if (gesture.active)
            gesture.recompute();
    }

    function recompute() {
        const pointerMinutes = gesture.minutesAt(gesture.pointerY);
        switch (gesture.kind) {
        case "move":
        case "draftMove": {
            const range = G.movedRange(pointerMinutes, gesture.grabMinutes, gesture.originEnd - gesture.originStart, gesture.gridStart, gesture.gridEnd, gesture.step);
            const day = G.dayIndexAt(gesture.pointerX, gesture.dayStride, gesture.dayCount);
            gesture.previewDay = day >= 0 ? day : gesture.originDay;
            gesture.previewStart = range.start;
            gesture.previewEnd = range.end;
            break;
        }
        case "resizeEnd":
        case "draftResizeEnd":
            gesture.previewStart = gesture.originStart;
            gesture.previewEnd = G.resizedEnd(pointerMinutes, gesture.originStart, gesture.gridEnd, gesture.step);
            break;
        case "resizeStart":
        case "draftResizeStart":
            gesture.previewEnd = gesture.originEnd;
            gesture.previewStart = G.resizedStart(pointerMinutes, gesture.originEnd, gesture.gridStart, gesture.step);
            break;
        case "create": {
            const range = G.createdRange(gesture.minutesAt(gesture.pressY), pointerMinutes, gesture.gridStart, gesture.gridEnd, gesture.step);
            gesture.previewStart = range.start;
            gesture.previewEnd = range.end;
            break;
        }
        }
    }

    /**
     * Ends the gesture and returns what it meant, or null when there is nothing
     * to do. Kinds: "click" (open the event), "create" / "draft" (a range for
     * the editor), "move" / "resize" (a new time for the event, which the view
     * writes after checking it actually changed).
     */
    function release(x, y) {
        const current = gesture.kind;
        if (current === "")
            return null;
        gesture.pointerX = x;
        gesture.pointerY = y;
        let result = null;
        if (current === "click" || (current === "move" && !gesture.active)) {
            result = { kind: "click", target: gesture.target };
        } else if (current === "create") {
            const range = gesture.active
                ? { start: gesture.previewStart, end: gesture.previewEnd }
                : G.clickedRange(gesture.minutesAt(gesture.pressY), gesture.gridStart, gesture.gridEnd, gesture.step, 60);
            result = {
                kind: "create",
                day: gesture.active ? gesture.previewDay : gesture.originDay,
                start: range.start,
                end: range.end
            };
        } else if (current === "move" || current.indexOf("resize") === 0) {
            // Resizing without travelling is not a click on the event.
            if (current !== "move" && !gesture.active)
                result = null;
            else
                result = {
                    kind: current === "move" ? "move" : "resize",
                    target: gesture.target,
                    day: gesture.previewDay,
                    start: gesture.previewStart,
                    end: gesture.previewEnd,
                    originDay: gesture.originDay,
                    originStart: gesture.originStart,
                    originEnd: gesture.originEnd
                };
        } else {
            result = { kind: "draft", day: gesture.previewDay, start: gesture.previewStart, end: gesture.previewEnd };
        }
        gesture.reset();
        return result;
    }

    function cancel() {
        gesture.reset();
    }

    function reset() {
        gesture.kind = "";
        gesture.active = false;
        gesture.target = null;
    }

    function setDraft(day, start, end) {
        gesture.draftDay = day;
        gesture.draftStart = start;
        gesture.draftEnd = end;
    }

    function clearDraft() {
        gesture.draftDay = -1;
    }
}
