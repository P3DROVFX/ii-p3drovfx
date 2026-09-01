import QtQuick
import QtTest
import "../../modules/ii/sidebarDashboard/quickToggles/androidStyle" as QuickToggleStyle

TestCase {
    name: "QuickToggleEditController"

    property var sourcePages: [[
        { id: "a", type: "network", sizeW: 1, sizeH: 1 },
        { id: "b", type: "bluetooth", sizeW: 1, sizeH: 1 },
        { id: "c", type: "vpn", sizeW: 1, sizeH: 1 }
    ]]
    property var fakeConfig: ({ pages: sourcePages, layoutVersion: 2 })

    QuickToggleStyle.QuickToggleEditController {
        id: controller
        config: fakeConfig
        persistedPages: sourcePages
        columns: 4
    }

    function ids(page) {
        return page.map(function(value) { return value.id; });
    }

    function test_reorder_stays_in_draft_until_commit() {
        verify(controller.beginReorder("b", 0));
        verify(controller.active);
        compare(ids(controller.draftPages[0]), ["a", "b", "c"]);
        verify(controller.previewReorder(0, 3));
        compare(ids(controller.draftPages[0]), ["a", "c", "b"]);
        compare(ids(fakeConfig.pages[0]), ["a", "b", "c"]);
        verify(controller.commitReorder());
        verify(!controller.active);
        compare(ids(fakeConfig.pages[0]), ["a", "c", "b"]);
    }

    function test_cancel_discards_draft() {
        fakeConfig.pages = sourcePages;
        controller.persistedPages = sourcePages;
        verify(controller.beginReorder("a", 0));
        verify(controller.previewReorder(0, 2));
        verify(controller.cancelReorder());
        verify(!controller.active);
        compare(ids(fakeConfig.pages[0]), ["a", "b", "c"]);
    }

    function test_pointer_reorder_uses_packed_row_major_position() {
        fakeConfig.pages = sourcePages;
        controller.persistedPages = sourcePages;
        verify(controller.beginReorder("b", 0));
        verify(controller.previewReorderAt(0, 0, 100, 50, 56, 6));
        compare(ids(controller.draftPages[0]), ["a", "c", "b"]);
        compare(ids(fakeConfig.pages[0]), ["a", "b", "c"]);
        verify(controller.cancelReorder());
    }

    function test_reorder_same_slot_is_a_noop() {
        fakeConfig.pages = sourcePages;
        controller.persistedPages = sourcePages;
        verify(controller.beginReorder("b", 0));
        var before = JSON.stringify(controller.draftPages);
        verify(!controller.previewReorder(0, 1));
        compare(JSON.stringify(controller.draftPages), before);
        verify(controller.cancelReorder());
    }

    function test_adjacent_toggles_swap_in_both_drag_directions() {
        var pages = [[
            { id: "tailscale", type: "tailscale", sizeW: 1, sizeH: 1 },
            { id: "darkMode", type: "darkMode", sizeW: 1, sizeH: 1 }
        ]];
        fakeConfig.pages = pages;
        controller.persistedPages = pages;

        verify(controller.beginReorder("darkMode", 0));
        verify(controller.previewReorderAt(0, 25, 28, 50, 56, 6));
        compare(ids(controller.draftPages[0]), ["darkMode", "tailscale"]);
        compare(controller.draftPages[0][0].sizeW, 1);
        verify(controller.cancelReorder());

        verify(controller.beginReorder("tailscale", 0));
        verify(controller.previewReorderAt(0, 75, 28, 50, 56, 6));
        compare(ids(controller.draftPages[0]), ["darkMode", "tailscale"]);
        compare(controller.draftPages[0][0].sizeW, 1);
        verify(controller.cancelReorder());
    }

    function test_reorder_never_transfers_slider_size() {
        var pages = [[
            { id: "tailscale", type: "tailscale", sizeW: 1, sizeH: 1 },
            { id: "volumeSlider", type: "volumeSlider", sizeW: 4, sizeH: 1 }
        ]];
        fakeConfig.pages = pages;
        controller.persistedPages = pages;

        verify(controller.beginReorder("volumeSlider", 0));
        verify(controller.previewReorderAt(0, 25, 28, 50, 56, 6));
        compare(ids(controller.draftPages[0]), ["volumeSlider", "tailscale"]);
        compare(controller.draftPages[0][0].sizeW, 4);
        compare(controller.draftPages[0][0].sizeH, 1);
        compare(controller.draftPages[0][1].sizeW, 1);
        compare(controller.draftPages[0][1].sizeH, 1);
        verify(controller.cancelReorder());
    }

    function test_full_width_slider_swaps_with_an_entire_row() {
        var sliderLast = [[
            { id: "a", type: "network", sizeW: 1, sizeH: 1 },
            { id: "b", type: "bluetooth", sizeW: 1, sizeH: 1 },
            { id: "c", type: "vpn", sizeW: 1, sizeH: 1 },
            { id: "d", type: "darkMode", sizeW: 1, sizeH: 1 },
            { id: "slider", type: "volumeSlider", sizeW: 4, sizeH: 1 }
        ]];
        fakeConfig.pages = sliderLast;
        controller.persistedPages = sliderLast;
        verify(controller.beginReorder("slider", 0));
        verify(controller.previewReorderAt(0, 109, 28, 50, 56, 6));
        compare(ids(controller.draftPages[0]), ["slider", "a", "b", "c", "d"]);
        compare(controller.draftPages[0][0].sizeW, 4);
        verify(controller.commitReorder());
        compare(ids(fakeConfig.pages[0]), ["slider", "a", "b", "c", "d"]);

        var sliderFirst = [[
            { id: "slider", type: "volumeSlider", sizeW: 4, sizeH: 1 },
            { id: "a", type: "network", sizeW: 1, sizeH: 1 },
            { id: "b", type: "bluetooth", sizeW: 1, sizeH: 1 },
            { id: "c", type: "vpn", sizeW: 1, sizeH: 1 },
            { id: "d", type: "darkMode", sizeW: 1, sizeH: 1 }
        ]];
        fakeConfig.pages = sliderFirst;
        controller.persistedPages = sliderFirst;
        verify(controller.beginReorder("slider", 0));
        verify(controller.previewReorderAt(0, 109, 90, 50, 56, 6));
        compare(ids(controller.draftPages[0]), ["a", "b", "c", "d", "slider"]);
        compare(controller.draftPages[0][4].sizeW, 4);
        verify(controller.commitReorder());
        compare(ids(fakeConfig.pages[0]), ["a", "b", "c", "d", "slider"]);
    }

    function test_cross_page_reorder_commits_from_controller_target() {
        var pages = [
            [{ id: "a", type: "network", sizeW: 1, sizeH: 1 }, { id: "b", type: "bluetooth", sizeW: 1, sizeH: 1 }],
            [{ id: "c", type: "vpn", sizeW: 1, sizeH: 1 }]
        ];
        fakeConfig.pages = pages;
        controller.persistedPages = pages;
        verify(controller.beginReorder("b", 0));
        verify(controller.setTargetPage(1));
        verify(controller.commitReorder());
        compare(ids(fakeConfig.pages[0]), ["a"]);
        compare(ids(fakeConfig.pages[1]), ["c", "b"]);
    }

    // Regression: a pointer resting on the seam between two toggles used to
    // re-round to a different column on every mouse sample, and each rounding
    // swapped the pair again — the grid shivered instead of settling.
    function test_pointer_parked_between_two_toggles_does_not_oscillate() {
        fakeConfig.pages = sourcePages;
        controller.persistedPages = sourcePages;
        controller.reorderSettleMs = 0;
        verify(controller.beginReorder("b", 0));
        // First sample of a real drag: the item's own cell.
        controller.previewReorderAt(0, 81, 28, 50, 56, 6);
        compare(ids(controller.draftPages[0]), ["a", "b", "c"]);

        var seenOrders = {};
        for (var i = 0; i < 40; i++) {
            controller.previewReorderAt(0, 53 + ((i % 2 === 0) ? -2 : 2), 28 + (i % 3) - 1, 50, 56, 6);
            seenOrders[ids(controller.draftPages[0]).join(",")] = true;
        }
        compare(Object.keys(seenOrders).length, 1);
        compare(ids(controller.draftPages[0]), ["a", "b", "c"]);

        // Carried through, the very same gesture still swaps.
        verify(controller.previewReorderAt(0, 25, 28, 50, 56, 6));
        compare(ids(controller.draftPages[0]), ["b", "a", "c"]);
        verify(controller.cancelReorder());
    }

    function test_settle_lock_defers_a_hesitant_second_swap() {
        fakeConfig.pages = sourcePages;
        controller.persistedPages = sourcePages;
        controller.reorderSettleMs = 150;
        verify(controller.beginReorder("b", 0));
        controller.previewReorderAt(0, 81, 28, 50, 56, 6);
        verify(controller.previewReorderAt(0, 25, 28, 50, 56, 6));
        compare(ids(controller.draftPages[0]), ["b", "a", "c"]);

        // Past the dead band but under a cell of travel, while the delegates
        // are still sliding: the placement holds.
        verify(!controller.previewReorderAt(0, 70, 28, 50, 56, 6));
        compare(ids(controller.draftPages[0]), ["b", "a", "c"]);

        wait(200);
        verify(controller.previewReorderAt(0, 70, 28, 50, 56, 6));
        compare(ids(controller.draftPages[0]), ["a", "b", "c"]);
        verify(controller.cancelReorder());
        controller.reorderSettleMs = 0;
    }

    function test_release_during_the_settle_lock_still_lands_the_last_aim() {
        var pages = [[
            { id: "a", type: "network", sizeW: 1, sizeH: 1 },
            { id: "b", type: "bluetooth", sizeW: 1, sizeH: 1 },
            { id: "c", type: "vpn", sizeW: 1, sizeH: 1 },
            { id: "d", type: "nightLight", sizeW: 1, sizeH: 1 }
        ]];
        fakeConfig.pages = pages;
        controller.persistedPages = pages;
        controller.reorderSettleMs = 500;
        verify(controller.beginReorder("c", 0));
        controller.previewReorderAt(0, 137, 28, 50, 56, 6);
        verify(controller.previewReorderAt(0, 81, 28, 50, 56, 6));
        compare(ids(controller.draftPages[0]), ["a", "c", "b", "d"]);

        // Crosses one more seam, is held by the lock, and the button comes up
        // straight away: the commit has to honour the crossing anyway.
        verify(!controller.previewReorderAt(0, 39, 28, 50, 56, 6));
        compare(ids(controller.draftPages[0]), ["a", "c", "b", "d"]);
        verify(controller.commitReorder());
        compare(ids(fakeConfig.pages[0]), ["c", "a", "b", "d"]);
        controller.reorderSettleMs = 0;
    }

    function test_a_new_gesture_starts_without_the_previous_anchor() {
        fakeConfig.pages = sourcePages;
        controller.persistedPages = sourcePages;
        controller.reorderSettleMs = 0;
        verify(controller.beginReorder("b", 0));
        controller.previewReorderAt(0, 81, 28, 50, 56, 6);
        verify(controller.dragCellState.valid);
        verify(controller.cancelReorder());
        verify(!controller.dragCellState.valid);

        verify(controller.beginReorder("c", 0));
        verify(!controller.dragCellState.valid);
        verify(controller.cancelReorder());
    }

    function test_resize_changes_only_target_item() {
        controller.persistedPages = [[
            { id: "a", type: "network", sizeW: 1, sizeH: 1 },
            { id: "slider", type: "volumeSlider", sizeW: 4, sizeH: 1 }
        ]];
        verify(controller.beginResize("a", 0));
        verify(controller.previewResize(2, 2));
        compare(controller.draftPages[0][0].sizeW, 2);
        compare(controller.draftPages[0][0].sizeH, 2);
        compare(controller.draftPages[0][1].sizeW, 4);
        compare(controller.draftPages[0][1].sizeH, 1);
        verify(controller.cancelResize());
    }

    function test_add_and_remove_use_stable_ids() {
        fakeConfig.pages = sourcePages;
        controller.persistedPages = sourcePages;
        verify(controller.addToggle("mediaWidget", 0));
        compare(ids(fakeConfig.pages[0]), ["a", "b", "c", "mediaWidget"]);
        verify(controller.removeToggle("mediaWidget"));
        compare(ids(fakeConfig.pages[0]), ["a", "b", "c"]);
    }

    function test_resize_respects_catalog_constraints() {
        var pages = [[{ id: "volume", type: "volumeSlider", sizeW: 4, sizeH: 1 }]];
        fakeConfig.pages = pages;
        controller.persistedPages = pages;
        verify(controller.beginResize("volume", 0));
        verify(controller.previewResize(1, 2));
        compare(controller.draftPages[0][0].sizeW, 1);
        compare(controller.draftPages[0][0].sizeH, 2);
        verify(controller.commitResize());
        compare(fakeConfig.pages[0][0].sizeW, 1);
        compare(fakeConfig.pages[0][0].sizeH, 2);
    }

    function test_page_management_uses_single_persist_boundary() {
        fakeConfig.pages = sourcePages;
        controller.persistedPages = sourcePages;
        verify(controller.addPage());
        compare(fakeConfig.pages.length, 2);
        compare(fakeConfig.pages[1].length, 0);
        verify(controller.removePage(1));
        compare(fakeConfig.pages.length, 1);
    }
}
