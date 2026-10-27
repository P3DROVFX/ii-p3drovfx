import QtQuick
import qs.services

/*
 * The contacts' birthdays, soonest first: [{ id, name, avatar, date, days, age }]
 * where `date` is the next time it comes (today included), `days` how far that
 * is and `age` the age then (-1 when the year is unknown). Read straight from
 * the phone's contacts, so it works whether or not the timetable shows them.
 */
QtObject {
    id: source

    property date today: new Date()

    readonly property var upcoming: {
        const start = new Date(source.today.getFullYear(), source.today.getMonth(), source.today.getDate());
        const out = [];
        for (const contact of (PhoneContactsService.contacts ?? [])) {
            if (!contact?.birthday || contact.nameless === true)
                continue;
            let next = BirthdaysService.observedDate(contact.birthday, start.getFullYear());
            if (next && next < start)
                next = BirthdaysService.observedDate(contact.birthday, start.getFullYear() + 1);
            if (!next)
                continue;
            out.push({
                id: String(contact.id ?? ""),
                name: String(contact.displayName ?? ""),
                avatar: String(contact.avatarPath ?? ""),
                date: next,
                days: Math.round((next.getTime() - start.getTime()) / 86400000),
                age: BirthdaysService.ageOn(contact.birthday, next)
            });
        }
        return out.sort((a, b) => a.days - b.days);
    }
}
