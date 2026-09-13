pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.services

// Projects contact BDAY values into read-only, all-day timetable entries.
// They are computed from the contact snapshot and deliberately never touch
// khal/ICS, so disabling the feature immediately removes every projection.
Singleton {
    id: root

    readonly property bool enabled: Config.ready
        && (Config.options.calendar.timetable.birthdays?.enable ?? false)

    function observedDate(birthday, year) {
        const month = Number(birthday?.month ?? 0);
        const day = Number(birthday?.day ?? 0);
        if (month < 1 || month > 12 || day < 1 || day > 31)
            return null;
        // Non-leap years observe a Feb 29 birthday on Feb 28.
        const leapDay = month === 2 && day === 29;
        const leapYear = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
        return new Date(year, month - 1, leapDay && !leapYear ? 28 : day);
    }

    function ageOn(birthday, date) {
        const year = Number(birthday?.year ?? 0);
        return year > 0 ? date.getFullYear() - year : -1;
    }

    function birthdaysForDate(date) {
        if (!root.enabled || !(date instanceof Date) || isNaN(date.getTime()))
            return [];
        const events = [];
        for (const contact of (PhoneContactsService.contacts ?? [])) {
            if (!contact?.birthday || contact.nameless === true)
                continue;
            const observed = root.observedDate(contact.birthday, date.getFullYear());
            if (!observed || observed.getMonth() !== date.getMonth() || observed.getDate() !== date.getDate())
                continue;
            const age = root.ageOn(contact.birthday, observed);
            const name = String(contact.displayName ?? Translation.tr("Contact"));
            events.push({
                id: "birthday:" + String(contact.id ?? name) + ":" + String(date.getFullYear()),
                birthdayEvent: true,
                readOnly: true,
                allDay: true,
                startDate: observed,
                endDate: new Date(observed.getFullYear(), observed.getMonth(), observed.getDate() + 1),
                content: age >= 0
                    ? Translation.tr("%1 turns %2").arg(name).arg(String(age))
                    : Translation.tr("%1's birthday").arg(name),
                description: Translation.tr("Birthday from contacts"),
                contactId: String(contact.id ?? ""),
                contactName: name,
                birthday: contact.birthday,
                age: age
            });
        }
        return events;
    }
}
