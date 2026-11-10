// Run with node scripts/tests/test_reminders_logic.cjs
//
// Contract for services/reminders/RemindersLogic.js: the repeat rules (Samsung
// Reminder's "the next occurrence only arrives once this one is done"), when each
// alert fires, the smart lists, search, sort and the recycle-bin clean-up.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const strict = require('node:assert/strict');

// Values built inside the vm context carry its own Array/Object prototypes; compare
// them as plain JSON so deepEqual looks at the data, not the realm.
const plain = value => (value === undefined ? value : JSON.parse(JSON.stringify(value)));
const assert = Object.assign((...args) => strict(...args), strict, {
    deepEqual: (actual, expected, message) => strict.deepEqual(plain(actual), plain(expected), message)
});

const root = path.resolve(__dirname, '../..');
const context = vm.createContext({ Math, Number, JSON, isFinite, Date, String, Array, Object, Boolean, isNaN });
vm.runInContext(
    fs.readFileSync(path.join(root, 'services/reminders/RemindersLogic.js'), 'utf8')
        .replace(/^\.pragma library\s*/, ''),
    context);
const L = context;

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
}

const NOW = new Date(2026, 9, 1, 12, 0).getTime(); // Thu 1 Oct 2026, 12:00
const MONDAY = 1;

function make(fields) {
    return L.normalizeReminder(Object.assign({ id: 'x', title: 'Test', createdAt: NOW }, fields), NOW);
}

function schedule(date, time, repeat) {
    return L.normalizeSchedule({ date, time, repeat });
}

test('store normalisation always has the default category first', () => {
    const store = L.normalizeStore({ categories: [{ id: 'b', name: 'B', order: 2 }, { id: 'a', name: 'A', order: 1, pinned: true }] }, NOW, 'Mine');
    assert.deepEqual(store.categories.map(c => c.id), ['default', 'a', 'b']);
    assert.equal(store.categories[0].name, 'Mine');
});

test('a reminder in a deleted category falls back to the default one', () => {
    const store = L.normalizeStore({ reminders: [{ id: 'r', title: 'T', categoryId: 'gone' }] }, NOW);
    assert.equal(store.reminders[0].categoryId, 'default');
});

test('garbage fields are dropped, not kept', () => {
    const r = make({ alert: 'deafening', schedule: { date: 'nope' }, early: { kind: 'custom' }, attachments: [{ kind: 'link' }] });
    assert.equal(r.alert, 'default');
    assert.equal(r.schedule, null);
    assert.equal(r.early, null);
    assert.equal(r.attachments.length, 0);
});

test('repeat rules take their anchor from the first date', () => {
    const s = schedule('2026-10-05', '08:00', { unit: 'week', interval: 2 });
    assert.equal(s.repeat.anchor, '2026-10-05');
});

test('daily every 3 days', () => {
    const next = L.nextOccurrence(schedule('2026-10-01', '09:00', { unit: 'day', interval: 3 }), MONDAY);
    assert.deepEqual({ ...next }, { date: '2026-10-04', time: '09:00' });
});

test('hourly crosses midnight', () => {
    const next = L.nextOccurrence(schedule('2026-10-01', '23:30', { unit: 'hour', interval: 2 }), MONDAY);
    assert.deepEqual({ ...next }, { date: '2026-10-02', time: '01:30' });
});

test('weekly on Tue and Thu walks to the next listed weekday', () => {
    const days = [false, false, true, false, true, false, false];
    const tue = L.nextOccurrence(schedule('2026-09-29', '18:00', { unit: 'week', interval: 1, weekdays: days }), MONDAY);
    assert.equal(tue.date, '2026-10-01');
    const thu = L.nextOccurrence(schedule('2026-10-01', '18:00', { unit: 'week', interval: 1, weekdays: days }), MONDAY);
    assert.equal(thu.date, '2026-10-06');
});

test('every 2 weeks skips the odd week', () => {
    const s = L.normalizeSchedule({ date: '2026-10-05', time: '08:00', repeat: { unit: 'week', interval: 2, anchor: '2026-10-05' } });
    assert.equal(L.nextOccurrence(s, MONDAY).date, '2026-10-19');
});

test('monthly on the 31st lands on the last day of short months', () => {
    const s = L.normalizeSchedule({ date: '2026-01-31', time: '', repeat: { unit: 'month', interval: 1, monthDays: [31], anchor: '2026-01-31' } });
    const feb = L.nextOccurrence(s, MONDAY);
    assert.equal(feb.date, '2026-02-28');
    const mar = L.nextOccurrence(Object.assign({}, s, { date: feb.date }), MONDAY);
    assert.equal(mar.date, '2026-03-31');
});

test('monthly with several days picks the next one in the same month', () => {
    const s = schedule('2026-10-01', '10:00', { unit: 'month', interval: 1, monthDays: [1, 15] });
    assert.equal(L.nextOccurrence(s, MONDAY).date, '2026-10-15');
});

test('yearly with several dates', () => {
    const s = schedule('2026-10-01', '10:00', { unit: 'year', interval: 1, yearDates: ['03-01', '10-01'] });
    assert.equal(L.nextOccurrence(s, MONDAY).date, '2027-03-01');
});

test('a count end stops after N occurrences', () => {
    const s = L.normalizeSchedule({ date: '2026-10-01', time: '09:00', occurrence: 1, repeat: { unit: 'day', interval: 1, end: { kind: 'count', count: 2 } } });
    assert.equal(L.nextOccurrence(s, MONDAY), null);
});

test('an until end stops past its date', () => {
    const s = schedule('2026-10-01', '09:00', { unit: 'day', interval: 1, end: { kind: 'until', until: '2026-10-01' } });
    assert.equal(L.nextOccurrence(s, MONDAY), null);
});

test('completing a repeat moves it on and unticks the checklist', () => {
    const r = make({
        schedule: { date: '2026-10-01', time: '09:00', repeat: { unit: 'day', interval: 1 } },
        checklist: [{ id: 'a', text: 'milk', done: true }],
        firedFor: '2026-10-01T09:00'
    });
    const done = L.complete(r, NOW, MONDAY);
    assert.equal(done.completed, false);
    assert.equal(done.schedule.date, '2026-10-02');
    assert.equal(done.schedule.occurrence, 1);
    assert.equal(done.firedFor, '');
    assert.equal(done.checklist[0].done, false);
});

test('completing a one-off marks it completed', () => {
    const done = L.complete(make({ schedule: { date: '2026-10-01', time: '09:00' } }), NOW, MONDAY);
    assert.equal(done.completed, true);
    assert.equal(done.completedAt, NOW);
});

test('an all-day reminder alerts at the all-day time', () => {
    const r = make({ schedule: { date: '2026-10-02', time: '' } });
    assert.equal(L.dueAt(r, '08:30').getTime(), new Date(2026, 9, 2, 8, 30).getTime());
});

test('alerts: main, early, snooze and already-fired', () => {
    const r = make({ schedule: { date: '2026-10-08', time: '09:00' }, early: { kind: 'day' } });
    const alerts = L.pendingAlerts(r, '09:00');
    assert.deepEqual(alerts.map(a => a.kind).sort(), ['early', 'main']);
    assert.equal(alerts.find(a => a.kind === 'early').at, new Date(2026, 9, 7, 9, 0).getTime());

    const fired = make({ schedule: { date: '2026-10-08', time: '09:00' }, firedFor: '2026-10-08T09:00' });
    assert.equal(L.pendingAlerts(fired, '09:00').length, 0);

    const snoozed = make({ schedule: { date: '2026-10-08', time: '09:00' }, firedFor: '2026-10-08T09:00', snoozedUntil: NOW + 5 });
    assert.deepEqual(L.pendingAlerts(snoozed, '09:00').map(a => a.at), [NOW + 5]);

    assert.equal(L.pendingAlerts(make({ completed: true, schedule: { date: '2026-10-08', time: '09:00' } }), '09:00').length, 0);
});

test('nextAlert and dueAlerts order by time', () => {
    const a = make({ id: 'a', schedule: { date: '2026-10-01', time: '11:00' } });
    const b = make({ id: 'b', schedule: { date: '2026-10-01', time: '10:00' } });
    const c = make({ id: 'c', schedule: { date: '2026-10-03', time: '10:00' } });
    assert.equal(L.nextAlert([a, b, c], '09:00').id, 'b');
    assert.deepEqual(L.dueAlerts([a, b, c], NOW, '09:00').map(x => x.id), ['b', 'a']);
});

test('smart lists: today keeps overdue, completed and deleted are apart', () => {
    const overdue = make({ id: 'o', schedule: { date: '2026-09-29', time: '09:00' } });
    const later = make({ id: 'l', schedule: { date: '2026-10-09', time: '09:00' } });
    const plain = make({ id: 'p', important: true });
    const done = make({ id: 'd', completed: true, completedAt: NOW });
    const binned = make({ id: 'b', deletedAt: NOW });
    const counts = L.smartCounts([overdue, later, plain, done, binned], new Date(NOW));
    assert.equal(counts.today, 1);
    assert.equal(counts.scheduled, 2);
    assert.equal(counts.important, 1);
    assert.equal(counts.noAlert, 1);
    assert.equal(counts.completed, 1);
    assert.equal(counts.all, 3);
});

test('search needs every word and honours the filters', () => {
    const a = make({ id: 'a', title: 'Buy milk', checklist: [{ text: 'oat' }] });
    const b = make({ id: 'b', title: 'Buy bread', attachments: [{ kind: 'link', url: 'https://bakery.example' }] });
    assert.deepEqual(L.search([a, b], 'buy oat', {}).map(r => r.id), ['a']);
    assert.deepEqual(L.search([a, b], 'bakery', {}).map(r => r.id), ['b']);
    assert.deepEqual(L.search([a, b], '', { links: true }).map(r => r.id), ['b']);
    assert.deepEqual(L.search([a, b], '', {}).map(r => r.id), []);
});

test('suggestions put prefixes first and skip exact matches', () => {
    const out = L.suggestions(['Call mum', 'Recall the order', 'call'], [], 'call', 5);
    assert.deepEqual(Array.from(out), ['Call mum', 'Recall the order']);
});

test('sort by alert time puts unscheduled last; pinImportant floats stars', () => {
    const a = make({ id: 'a', schedule: { date: '2026-10-03', time: '09:00' } });
    const b = make({ id: 'b', schedule: { date: '2026-10-02', time: '09:00' } });
    const c = make({ id: 'c', important: true });
    assert.deepEqual(L.sortReminders([a, c, b], 'alertTime', false, {}, '09:00').map(r => r.id), ['b', 'a', 'c']);
    assert.deepEqual(L.sortReminders([a, c, b], 'alertTime', true, {}, '09:00').map(r => r.id), ['c', 'b', 'a']);
});

test('groupByDay buckets overdue, today, tomorrow and later', () => {
    const now = new Date(NOW);
    const list = [
        make({ id: 'o', schedule: { date: '2026-10-01', time: '08:00' } }),
        make({ id: 't', schedule: { date: '2026-10-01', time: '18:00' } }),
        make({ id: 'm', schedule: { date: '2026-10-02', time: '08:00' } }),
        make({ id: 'x', schedule: { date: '2026-12-02', time: '08:00' } }),
        make({ id: 'n' })
    ];
    const groups = L.groupByDay(list, now, '09:00');
    assert.deepEqual(groups.map(g => g.key), ['overdue', 'today', 'tomorrow', 'later', 'none']);
});

test('expired honours both retention windows', () => {
    const day = 86400000;
    const old = make({ id: 'old', deletedAt: NOW - 31 * day });
    const fresh = make({ id: 'fresh', deletedAt: NOW - day });
    const doneOld = make({ id: 'done', completed: true, completedAt: NOW - 8 * day });
    assert.deepEqual(Array.from(L.expired([old, fresh, doneOld], NOW, 30, 7)), ['old', 'done']);
    assert.deepEqual(Array.from(L.expired([old, fresh, doneOld], NOW, 30, 0)), ['old']);
});

test('templates build valid drafts', () => {
    for (const id of ['workout', 'payment', 'pickup', 'home', 'grocery']) {
        const draft = L.templateDraft(id, new Date(NOW), { groceryItems: ['Milk', 'Eggs'] });
        const r = make(draft);
        assert.ok(r.title.length > 0, id);
        if (id === 'grocery')
            assert.equal(r.checklist.length, 2);
        else
            assert.ok(r.schedule, id);
    }
    const workout = make(L.templateDraft('workout', new Date(NOW), {}));
    assert.ok([2, 4].includes(L.parseDay(workout.schedule.date).getDay()));
});

console.log(`reminders logic: ${passed} passed`);
