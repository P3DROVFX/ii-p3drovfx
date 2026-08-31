function text(value) {
    return String(value ?? "").trim();
}

function arrayOf(value) {
    if (Array.isArray(value))
        return value;
    if (!value || typeof value.length !== "number")
        return [];
    const result = [];
    for (let i = 0; i < value.length; i++)
        result.push(value[i]);
    return result;
}

function teamName(value) {
    return text(value?.team?.displayName || value?.team?.name || value?.homeAway);
}

function rosterText(roster, starters) {
    const values = arrayOf(roster?.roster);
    const lines = [];
    for (let i = 0; i < values.length; i++) {
        const item = values[i] ?? ({});
        if ((item.starter === true) !== starters)
            continue;
        const athlete = item.athlete ?? ({});
        const jersey = text(item.jersey || athlete.jersey);
        const name = text(athlete.displayName || athlete.fullName || athlete.shortName);
        const position = text(item.position?.abbreviation || item.position?.displayName);
        if (name.length === 0)
            continue;
        const prefix = jersey.length > 0 ? jersey + " · " : "";
        const suffix = position.length > 0 ? " · " + position : "";
        lines.push(prefix + name + suffix);
    }
    return lines.join("\n");
}

function lineupRows(rosters) {
    const values = arrayOf(rosters);
    const rows = [];
    for (let i = 0; i < values.length; i++) {
        const roster = values[i] ?? ({});
        const team = teamName(roster);
        const starters = rosterText(roster, true);
        const substitutes = rosterText(roster, false);
        if (starters.length > 0)
            rows.push({ team: team, group: "starters", value: starters });
        if (substitutes.length > 0)
            rows.push({ team: team, group: "substitutes", value: substitutes });
    }
    return rows;
}

function statisticsText(team) {
    const values = arrayOf(team?.statistics);
    const lines = [];
    for (let i = 0; i < values.length; i++) {
        const item = values[i] ?? ({});
        const label = text(item.label || item.displayName || item.name);
        const value = text(item.displayValue ?? item.value);
        if (label.length > 0 && value.length > 0)
            lines.push(label + ": " + value);
    }
    return lines.join("\n");
}

function statisticsRows(teams) {
    const values = arrayOf(teams);
    const rows = [];
    for (let i = 0; i < values.length; i++) {
        const team = values[i] ?? ({});
        const value = statisticsText(team);
        if (value.length > 0)
            rows.push({ team: teamName(team), value: value });
    }
    return rows;
}

function leadersText(group) {
    const categories = arrayOf(group?.leaders);
    const lines = [];
    for (let i = 0; i < categories.length; i++) {
        const category = categories[i] ?? ({});
        const values = arrayOf(category.leaders);
        if (values.length === 0)
            continue;
        const leader = values[0] ?? ({});
        const label = text(category.displayName || category.name);
        const athlete = text(leader.athlete?.displayName || leader.athlete?.fullName);
        const value = text(leader.displayValue || leader.mainStat?.value || leader.summary);
        const parts = [label, athlete, value].filter(part => part.length > 0);
        if (parts.length > 0)
            lines.push(parts.join(" · "));
    }
    return lines.join("\n");
}

function leaderRows(groups) {
    const values = arrayOf(groups);
    const rows = [];
    for (let i = 0; i < values.length; i++) {
        const group = values[i] ?? ({});
        const value = leadersText(group);
        if (value.length > 0)
            rows.push({ team: teamName(group), value: value });
    }
    return rows;
}

function keyEventRows(events) {
    const values = arrayOf(events);
    const rows = [];
    for (let i = 0; i < values.length; i++) {
        const item = values[i] ?? ({});
        const time = text(item.clock?.displayValue || item.time?.displayValue);
        const kind = text(item.type?.text || item.type?.description);
        const description = text(item.text || item.shortText);
        const participants = arrayOf(item.participants)
            .map(participant => text(participant?.athlete?.displayName))
            .filter(value => value.length > 0)
            .join(", ");
        const body = description || (participants.length > 0 ? [kind, participants].filter(value => value.length > 0).join(" · ") : kind);
        if (body.length > 0)
            rows.push({ time: time, kind: kind, text: body });
    }
    return rows;
}

if (typeof module !== "undefined") {
    module.exports = {
        lineupRows,
        statisticsRows,
        leaderRows,
        keyEventRows
    };
}
