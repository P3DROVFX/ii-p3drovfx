pragma Singleton
import Quickshell
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    // Qt uses a 12h clock when the format contains an unquoted am/pm field (a, A, ap or AP).
    // Text inside single quotes is fixed text, so it must not count.
    function is12HourTimeFormat(format) {
        if (!format)
            return false;

        return /[aA]/.test(String(format).replace(/'[^']*'/g, ""));
    }

    // Returns "" when the format is usable, otherwise an error code the UI turns into
    // a translated message. A code rather than a string keeps this file free of a
    // qs.services dependency (Translation lives there, and services import common).
    function dateTimeFormatError(format) {
        const trimmed = String(format ?? "").trim();
        if (trimmed.length === 0)
            return "empty";

        if ((trimmed.match(/'/g) ?? []).length % 2 !== 0)
            return "unclosedQuote";

        // Qt echoes characters it doesn't recognize verbatim, so an unchanged result means
        // the string contains no actual date/time fields and would render as dead text.
        if (Qt.locale().toString(new Date(), trimmed) === trimmed)
            return "noFields";

        return "";
    }

    function isValidDateTimeFormat(format) {
        return root.dateTimeFormatError(format).length === 0;
    }

    function syncHyprlockTimeFormat(format) {
        const configPath = FileUtils.trimFileProtocol(Directories.config) + "/hypr/hyprlock.conf";
        const twelveHour = root.is12HourTimeFormat(format);
        const from = twelveHour ? "TIME" : "TIME12";
        const to = twelveHour ? "TIME12" : "TIME";
        // --follow-symlinks keeps dotfile symlinks intact; anchoring on $ avoids mangling
        // unrelated words such as MYTIME.
        const script = `[ -f '${configPath}' ] || exit 0; sed -i --follow-symlinks 's/\\$${from}\\b/$${to}/g' '${configPath}'`;
        Quickshell.execDetached(["bash", "-c", script]);
    }

    function getFirstDayOfWeek(date, firstDay = 1) {
        const d = new Date(date); // Copy
        const day = d.getDay();   // 0 = Sunday, 1 = Monday, ..., 6 = Saturday

        // Calculate difference to firstDay
        const diff = (day - firstDay + 7) % 7;
        d.setDate(d.getDate() - diff);
        return d;
    }

    function sameDate(d1, d2) {
        return (d1.getFullYear() === d2.getFullYear() && d1.getMonth() === d2.getMonth() && d1.getDate() === d2.getDate());
    }

    function getIthDayDateOfSameWeek(date, i, firstDay = 1) {
        const firstDayDate = root.getFirstDayOfWeek(date, firstDay);
        const targetDate = new Date(firstDayDate);
        targetDate.setDate(firstDayDate.getDate() + i);
        return targetDate;
    }

    // A deliberately small, local-first parser for the Calendar quick-create
    // surface. It only claims a time when it can preserve the user's text as
    // a valid event title; callers can still show the regular blank form.
    function parseNaturalEvent(value, locale = "pt-BR") {
        let text = String(value ?? "").trim();
        if (text.length === 0)
            return null;
        const now = new Date();
        let day = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        let consumed = false;
        if (/\b(amanh[ãa]|tomorrow)\b/i.test(text)) {
            day.setDate(day.getDate() + 1);
            text = text.replace(/\b(amanh[ãa]|tomorrow)\b/ig, " ");
            consumed = true;
        } else if (/\b(hoje|today)\b/i.test(text)) {
            text = text.replace(/\b(hoje|today)\b/ig, " ");
            consumed = true;
        }
        const timeMatch = text.match(/(?:\b[àa]s?\s*)?(\d{1,2})(?::|h)(\d{2})?\b/i);
        if (!timeMatch && !consumed)
            return null;
        const hours = timeMatch ? Math.max(0, Math.min(23, Number(timeMatch[1]))) : 9;
        const minutes = timeMatch ? Math.max(0, Math.min(59, Number(timeMatch[2] ?? 0))) : 0;
        if (timeMatch)
            text = text.replace(timeMatch[0], " ");
        const durationMatch = text.match(/\b(?:por|for)\s+(\d+)\s*(m|min|mins|minuto|minutos|minute|minutes)\b/i);
        const duration = durationMatch ? Math.max(5, Number(durationMatch[1])) : 30;
        if (durationMatch)
            text = text.replace(durationMatch[0], " ");
        const calendarMatch = text.match(/#([^\s#]+)/);
        const calendar = calendarMatch ? String(calendarMatch[1]) : "";
        if (calendarMatch)
            text = text.replace(calendarMatch[0], " ");
        const title = text.replace(/\s+/g, " ").trim();
        if (title.length === 0)
            return null;
        const start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hours, minutes);
        return {
            title: title,
            calendar: calendar,
            start: start,
            end: new Date(start.getTime() + duration * 60000),
            durationMinutes: duration,
            locale: String(locale)
        };
    }
}
