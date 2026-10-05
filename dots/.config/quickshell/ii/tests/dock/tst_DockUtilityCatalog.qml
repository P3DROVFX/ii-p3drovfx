import QtQuick
import QtTest
import "../../modules/ii/dock/utilities/DockUtilityCatalog.js" as Catalog

TestCase {
    name: "DockUtilityCatalog"

    function test_orderKeysRoundTrip() {
        compare(Catalog.orderKey("stopwatch"), "util:stopwatch");
        verify(Catalog.isOrderKey("util:stopwatch"));
        verify(!Catalog.isOrderKey("weather"));
        compare(Catalog.kindFromOrderKey("util:stopwatch"), "stopwatch");
        compare(Catalog.kindFromOrderKey("app:kitty"), "");
    }

    function test_normalizeDropsUnknownAndDuplicates() {
        const out = Catalog.normalize([
            { kind: "stopwatch", wide: 1 },
            { kind: "stopwatch", wide: false },
            { kind: "nope" },
            null
        ]);
        compare(out.length, 1);
        compare(out[0].kind, "stopwatch");
        compare(out[0].wide, true);
    }

    function test_plainStringsReadAsSquare() {
        const out = Catalog.normalize(["stopwatch"]);
        compare(out.length, 1);
        compare(out[0].wide, false);
    }

    function test_slots() {
        compare(Catalog.slotsFor({ kind: "stopwatch", wide: true }, false), Catalog.WIDE_SLOTS);
        compare(Catalog.slotsFor({ kind: "stopwatch", wide: true }, true), 1);
        compare(Catalog.slotsFor({ kind: "stopwatch", wide: false }, false), 1);
        compare(Catalog.slotsFor(null, false), 1);
    }

    function test_withAndWithout() {
        let list = Catalog.withKind([], "stopwatch", false);
        compare(list.length, 1);
        list = Catalog.withKind(list, "stopwatch", true);
        compare(list.length, 1);
        compare(list[0].wide, true);
        compare(Catalog.withoutKind(list, "stopwatch").length, 0);
        compare(Catalog.withKind([], "unknown", true).length, 0);
    }

    function test_everyKindIsComplete() {
        const groups = Catalog.groups.map(g => g.id);
        for (const entry of Catalog.kinds) {
            verify(entry.file.length > 0, entry.kind);
            verify(entry.title.length > 0, entry.kind);
            verify(entry.symbol.length > 0, entry.kind);
            verify(groups.indexOf(entry.group) >= 0, entry.kind);
        }
    }

    function test_renamedKindKeepsItsPlace() {
        const out = Catalog.normalize([{ kind: "claudeUsage", wide: true }]);
        compare(out.length, 1);
        compare(out[0].kind, "aiUsage");
        compare(Catalog.kindFromOrderKey("util:claudeUsage"), "aiUsage");
        verify(Catalog.find("claudeUsage") !== null);
    }

    function test_kindsCanAskForTheirWideWidth() {
        compare(Catalog.wideSlotsFor("clock"), 2);
        compare(Catalog.wideSlotsFor("stopwatch"), Catalog.WIDE_SLOTS);
        compare(Catalog.slotsFor({ kind: "clock", wide: true }, false), 2);
        compare(Catalog.slotsFor({ kind: "clock", wide: true }, true), 1);
    }
}
