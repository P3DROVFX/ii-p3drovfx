import QtQuick
import QtTest
import "../../modules/tablet/appDrawer/TabletAppGridLayout.js" as AppGridLayout

TestCase {
    name: "TabletAppGridLayout"

    // A 1920px screen: the drawer's outer margin leaves 1808 for the body, the A–Z rail
    // reserves 76 of it, and a tile is 200 wide.
    readonly property real body: 1808
    readonly property real rail: 76
    readonly property real cell: 200

    function test_only_whole_columns_are_shown() {
        const available = body - rail;             // 1732
        compare(AppGridLayout.columnCount(available, cell), 8);
        // 1600, not 1732: the 132px remainder is what used to sit as dead space on the
        // right and make the whole grid look left-aligned.
        compare(AppGridLayout.gridWidth(available, cell), 1600);
    }

    function test_the_block_is_centred_on_the_screen_not_on_what_the_rail_leaves() {
        const available = body - rail;
        const width = AppGridLayout.gridWidth(available, cell);
        const x = AppGridLayout.originX(body, available, width);
        // Centred against the body: the rail is a thin overlay, and the eye centres the
        // icons against the screen rather than against the region beside it.
        compare(x, Math.round((body - width) / 2));
        // And it still clears the rail.
        verify(x + width <= available);
    }

    function test_a_side_column_pushes_the_grid_left_rather_than_under_it() {
        // Clipboard and file results open a 520px column; the grid loses columns and the
        // centred position would now overlap it, so the clamp takes over.
        const available = body - (520 + 24);       // 1264
        const width = AppGridLayout.gridWidth(available, cell);
        compare(width, 1200);
        const x = AppGridLayout.originX(body, available, width);
        compare(x, available - width);             // hard against the reserve, not under it
        verify(x < Math.round((body - width) / 2));
    }

    function test_a_grid_that_exactly_fills_its_space_sits_at_the_left_edge() {
        compare(AppGridLayout.originX(1600, 1600, 1600), 0);
        compare(AppGridLayout.gridWidth(1600, 200), 1600);
    }

    function test_a_screen_too_narrow_for_one_tile_still_shows_one_column() {
        // Never zero columns: a grid with no columns renders nothing at all, which is a
        // worse answer than a clipped tile.
        compare(AppGridLayout.columnCount(120, 200), 1);
        compare(AppGridLayout.gridWidth(120, 200), 120);
        compare(AppGridLayout.originX(120, 120, 120), 0);
    }

    function test_the_first_frame_does_not_divide_by_zero() {
        // Sizes are all zero before the drawer has been laid out once.
        compare(AppGridLayout.columnCount(0, 0), 1);
        compare(AppGridLayout.gridWidth(0, 0), 0);
        compare(AppGridLayout.originX(0, 0, 0), 0);
    }
}
