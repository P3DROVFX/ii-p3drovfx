.pragma library

function dateKey(year, month, day) {
    return String(year) + "-" + String(month) + "-" + String(day);
}

function groupEvents(events, enabled) {
    const grouped = {};
    if (!enabled)
        return grouped;

    const source = events ?? [];
    for (let i = 0; i < source.length; i++) {
        const taskDate = new Date(source[i].startDate);
        if (isNaN(taskDate.getTime()))
            continue;
        const key = dateKey(taskDate.getFullYear(), taskDate.getMonth(), taskDate.getDate());
        if (!grouped[key])
            grouped[key] = [];
        grouped[key].push(source[i]);
    }
    return grouped;
}

function tasksForDate(grouped, year, month, day) {
    return grouped[dateKey(year, month, day)] ?? [];
}
