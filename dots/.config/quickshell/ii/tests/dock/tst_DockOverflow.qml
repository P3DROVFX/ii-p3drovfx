import QtQuick
import QtTest
import "../../modules/ii/dock/DockOverflow.js" as DockOverflow

TestCase {
    name: "DockOverflow"

    function app(id, pinned, windows) {
        return { type: "app", appId: id, orderKey: (pinned ? "app:" : "runningApp:") + id,
                 appData: { appId: id, pinned: pinned, toplevels: windows ? [{}] : [] } };
    }

    function widget(key) {
        return { type: "weather", orderKey: key };
    }

    // Every item is one 10px slot, except widgets (30px); no spacing.
    function measure(items) {
        return items.reduce(function (sum, item) { return sum + (item.type === "weather" ? 30 : 10); }, 0);
    }

    function options(budget, recency) {
        return {
            budget: budget,
            measure: measure,
            recencyOf: function (item) { return (recency || {})[item.appId] || 0; },
            makeGroup: function (members) {
                return { type: "appGroup", autoGroup: true, orderKey: "group:__overflow",
                         memberKeys: members.map(function (m) { return m.orderKey; }) };
            }
        };
    }

    function keys(items) {
        return items.map(function (item) { return item.orderKey; });
    }

    function test_fits_untouched() {
        var items = [app("a", true, false), app("b", false, true), widget("w")];
        var out = DockOverflow.fold(items, options(50));
        compare(out.items, items);
        compare(out.foldedKeys, []);
    }

    function test_unknown_budget_never_folds() {
        var items = [app("a", false, true), app("b", false, true), app("c", false, true)];
        compare(DockOverflow.fold(items, options(0)).foldedKeys, []);
    }

    function test_least_recent_running_apps_fold_first() {
        // 6 slots + 30px widget = 90; budget 70 folds three (the group takes a slot back).
        var items = [app("pin", true, false), app("a", false, true), app("b", false, true),
                     app("c", false, true), app("d", false, true), app("e", false, true), widget("w")];
        var out = DockOverflow.fold(items, options(70, { a: 5, b: 1, c: 4, d: 2, e: 3 }));
        compare(out.foldedKeys, ["runningApp:b", "runningApp:d", "runningApp:e"]);
        verify(measure(out.items) <= 70);
        compare(keys(out.items), ["app:pin", "runningApp:a", "runningApp:c", "group:__overflow", "w"]);
        // Members keep dock order.
        compare(out.items[3].memberKeys, ["runningApp:b", "runningApp:d", "runningApp:e"]);
    }

    function test_idle_pins_fold_before_pinned_running() {
        var items = [app("p1", true, true), app("p2", true, false), app("p3", true, false), widget("w")];
        var out = DockOverflow.fold(items, options(50));
        compare(out.foldedKeys, ["app:p3", "app:p2"]);
        compare(keys(out.items), ["app:p1", "group:__overflow", "w"]);
    }

    function test_needs_two_candidates() {
        var items = [app("a", false, true), widget("w"), widget("x")];
        compare(DockOverflow.fold(items, options(40)).foldedKeys, []);
    }

    function test_folds_everything_when_nothing_else_fits() {
        var items = [app("a", false, true), app("b", false, true), app("c", false, true), widget("w")];
        var out = DockOverflow.fold(items, options(5));
        compare(out.foldedKeys.length, 3);
        compare(keys(out.items), ["group:__overflow", "w"]);
    }

    function test_ties_keep_the_later_app() {
        var items = [app("a", false, true), app("b", false, true), app("c", false, true), widget("w")];
        var out = DockOverflow.fold(items, options(50));
        compare(out.foldedKeys, ["runningApp:a", "runningApp:b"]);
        compare(keys(out.items), ["runningApp:c", "group:__overflow", "w"]);
    }
}
