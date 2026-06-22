.pragma library

function snapToGrid(minutes, snapInterval) {
    return Math.round(minutes / snapInterval) * snapInterval;
}

function yToMinutes(y, startHour, startMinute, pixelsPerMinute) {
    return startHour * 60 + startMinute + (y / pixelsPerMinute);
}

function minutesToY(totalMinutes, startHour, startMinute, pixelsPerMinute) {
    return (totalMinutes - (startHour * 60 + startMinute)) * pixelsPerMinute;
}

function minutesToTimeStr(totalMinutes, format) {
    let clamped = Math.max(0, Math.min(totalMinutes, 24 * 60));
    let hour = Math.floor(clamped / 60);
    let minute = Math.round(clamped % 60);
    let d = new Date();
    d.setHours(hour, minute, 0, 0);
    return Qt.formatTime(d, format || "hh:mm");
}

function minutesToKhalTimeStr(totalMinutes) {
    let clamped = Math.max(0, Math.min(totalMinutes, 24 * 60));
    let hour = Math.floor(clamped / 60);
    let minute = Math.round(clamped % 60);
    return (hour < 10 ? "0" : "") + hour + ":" + (minute < 10 ? "0" : "") + minute;
}

function getDateForDayIndex(dayIndex, firstDayOfWeek, todayFirst) {
    let d = new Date();
    if (todayFirst) {
        d.setDate(d.getDate() + dayIndex);
    } else {
        let currentConfigDayIndex = (d.getDay() - firstDayOfWeek + 6) % 7;
        d.setDate(d.getDate() - currentConfigDayIndex + dayIndex);
    }
    return d;
}

function parseTimeToMinutes(timeStr) {
    if (!timeStr) return null;
    let parts = timeStr.split(":");
    if (parts.length < 2) return null;
    let hour = parseInt(parts[0]);
    let minute = parseInt(parts[1]);
    if (isNaN(hour) || isNaN(minute)) return null;
    return hour * 60 + minute;
}

function withOpacity(colorValue, alpha) {
    if (!colorValue) return Qt.rgba(0, 0, 0, alpha);
    let color = Qt.color(colorValue);
    return Qt.rgba(color.r, color.g, color.b, alpha);
}

function isAllDayEvent(event) {
    if (!event) return false;
    let start = event.start || "";
    let end = event.end || "";
    // Common patterns for all-day events
    return (start === "00:00" && end === "23:59") ||
        (start === "00:00" && end === "00:00") ||
        (start === "00:00" && end === "24:00") ||
        (!event.start && !event.end);
}

function getAllDayEvents(events) {
    if (!events || !events.length) return [];
    return events.filter(evt => isAllDayEvent(evt));
}

function getTimedEvents(events) {
    if (!events || !events.length) return [];
    return events.filter(evt => !isAllDayEvent(evt));
}

function lerpColor(color1, color2, factor) {
    let c1 = Qt.color(color1);
    let c2 = Qt.color(color2);
    let f = Math.max(0, Math.min(1, factor));
    let r = c1.r + (c2.r - c1.r) * f;
    let g = c1.g + (c2.g - c1.g) * f;
    let b = c1.b + (c2.b - c1.b) * f;
    let a = c1.a + (c2.a - c1.a) * f;
    return Qt.rgba(r, g, b, a);
}

function getEventColorRadial(dayIndex, startMinutes, nextEvtData, maxDist, colors) {
    if (!nextEvtData) return colors.colSurfaceContainerHigh;

    let nextDay = nextEvtData.dayIndex;
    let nextStart = nextEvtData.startMinutes;

    let dx = dayIndex - nextDay;
    let dy = (startMinutes - nextStart) / 60.0;

    if (dx === 0 && dy === 0) return colors.colPrimary;

    let distance = Math.sqrt(dx * dx + dy * dy);
    let normalizedDist = Math.min(1.0, distance / maxDist);

    let c1, c2, ratio;
    if (normalizedDist < 0.33) {
        c1 = colors.colPrimary;
        c2 = colors.colSecondary;
        ratio = normalizedDist / 0.33;
    } else if (normalizedDist < 0.66) {
        c1 = colors.colSecondary;
        c2 = colors.colTertiary;
        ratio = (normalizedDist - 0.33) / 0.33;
    } else {
        c1 = colors.colTertiary;
        c2 = colors.colSurfaceContainerHighest;
        ratio = (normalizedDist - 0.66) / 0.34;
    }

    return lerpColor(c1, c2, ratio);
}

function computeEventLayout(events, parseFn) {
    if (!events || events.length === 0) return [];

    // Use internal parse function if not provided
    let parse = parseFn || parseTimeToMinutes;

    // 1. Prepare and sort timed events
    let timedEvents = events.filter(e => !isAllDayEvent(e)).map(e => {
        let start = parse(e.start);
        let end = parse(e.end);
        if (start === null || end === null) return null;

        // Handle midnight wrap
        if (end === 0 && start > 0) end = 24 * 60;

        return {
            event: e,
            start: start,
            end: end,
            colIndex: 0,
            totalCols: 1
        };
    }).filter(e => e !== null)
        .sort((a, b) => a.start - b.start || (b.end - b.start) - (a.end - a.start));

    if (timedEvents.length === 0) return [];

    // 2. Group overlapping events
    let groups = [];
    let currentGroup = [];
    let groupEnd = -1;

    for (let ev of timedEvents) {
        if (ev.start >= groupEnd) {
            if (currentGroup.length > 0) groups.push(currentGroup);
            currentGroup = [ev];
            groupEnd = ev.end;
        } else {
            currentGroup.push(ev);
            groupEnd = Math.max(groupEnd, ev.end);
        }
    }
    if (currentGroup.length > 0) groups.push(currentGroup);

    // 3. Assign columns within each group
    for (let group of groups) {
        let columns = []; // array of end times for each column

        for (let ev of group) {
            let placed = false;
            for (let i = 0; i < columns.length; i++) {
                if (ev.start >= columns[i]) {
                    ev.colIndex = i;
                    columns[i] = ev.end;
                    placed = true;
                    break;
                }
            }
            if (!placed) {
                ev.colIndex = columns.length;
                columns.push(ev.end);
            }
        }

        // 4. Set totalCols for everyone in this group
        for (let ev of group) {
            ev.totalCols = columns.length;
        }
    }

    return timedEvents;
}
