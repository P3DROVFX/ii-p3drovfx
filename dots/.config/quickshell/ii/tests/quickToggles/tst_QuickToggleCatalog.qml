import QtQuick
import QtTest
import "../../modules/ii/sidebarDashboard/quickToggles/androidStyle/QuickToggleCatalog.js" as Catalog

TestCase {
    name: "QuickToggleCatalog"

    function test_catalog_contains_current_types() {
        var types = Catalog.allTypes();
        compare(types.length, Object.keys(Catalog.TOGGLE_TYPES).length);
        verify(Catalog.hasType("network"));
        verify(Catalog.hasType("volumeSlider"));
        verify(Catalog.hasType("mediaWidget"));
        verify(!Catalog.hasType("doesNotExist"));
    }

    function test_defaults_are_centralized() {
        compare(Catalog.defaultSize("network"), [1, 1]);
        compare(Catalog.defaultSize("volumeSlider"), [4, 1]);
        compare(Catalog.defaultSize("mediaWidget"), [2, 2]);
        compare(Catalog.kind("mediaWidget"), "media");
        compare(Catalog.kind("unknown"), "unknown");
    }

    function test_slider_vertical_and_horizontal_sizes() {
        compare(Catalog.normalizeSize("volumeSlider", 1, 2, 4), [1, 2]);
        compare(Catalog.normalizeSize("volumeSlider", 1, 3, 4), [1, 3]);
        compare(Catalog.normalizeSize("volumeSlider", 4, 1, 4), [4, 1]);
        verify(Catalog.isSizeAllowed("volumeSlider", 1, 2, 4));
        verify(Catalog.isSizeAllowed("volumeSlider", 4, 1, 4));
    }

    function test_media_allowed_sizes_and_column_clamp() {
        compare(Catalog.normalizeSize("mediaWidget", 4, 1, 4), [4, 2]);
        compare(Catalog.normalizeSize("mediaWidget", 2, 1, 4), [2, 1]);
        compare(Catalog.normalizeSize("mediaWidget", 4, 2, 3), [2, 2]);
        compare(Catalog.normalizeSize("mediaWidget", 2, 2, 1), [1, 1]);
        verify(Catalog.isSizeAllowed("mediaWidget", 4, 2, 4));
        verify(!Catalog.isSizeAllowed("mediaWidget", 4, 1, 4));
    }

    function test_normalize_pages_migrates_legacy_shape() {
        var warnings = [];
        var raw = [{ type: "network", size: 2 }, { type: "mediaWidget", size: 4, sizeH: 1 }];
        var pages = Catalog.normalizePages(raw, 4, { warn: function(message) { warnings.push(message); } });
        compare(pages.length, 1);
        compare(pages[0].length, 2);
        compare(JSON.stringify(pages[0][0]), JSON.stringify({ id: "network", type: "network", sizeW: 2, sizeH: 1 }));
        compare(JSON.stringify(pages[0][1]), JSON.stringify({ id: "mediaWidget", type: "mediaWidget", sizeW: 4, sizeH: 2 }));
        compare(warnings.length, 0);
    }

    function test_normalize_pages_removes_duplicate_ids_deterministically() {
        var warnings = [];
        var pages = Catalog.normalizePages([
            [{ id: "same", type: "network" }],
            [{ id: "same", type: "bluetooth" }, { type: "vpn" }]
        ], 4, { warn: function(message) { warnings.push(message); } });
        compare(pages.length, 2);
        compare(pages[0].length, 1);
        compare(pages[1].length, 1);
        compare(pages[1][0].id, "vpn");
        compare(warnings.length, 1);
    }
}
