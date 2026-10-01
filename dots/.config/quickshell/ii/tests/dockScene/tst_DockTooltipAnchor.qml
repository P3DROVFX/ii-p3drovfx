import QtQuick
import QtTest
import "dock/widgets"

// DockTooltip anchors by mapping its parent item into scene coordinates. The
// dock has one tooltip per app icon, group and file, and mapToItem() reads the
// item's position in C++ — out of sight of the QML binding engine — so the
// anchor used to be recomputed on every frame the icon moved, for every popup,
// magnified or not. The tooltip is therefore only anchored while it is shown,
// which is what these tests pin down:
//   - a hidden tooltip never maps (nothing to follow),
//   - a shown one is placed above its icon and keeps following it while the
//     dock moves and magnifies that icon,
//   - hiding it again drops the anchor.
//
// Run with scripts/tests/run_dock_preview_popup_tests.py --test tests/dockScene/tst_DockTooltipAnchor.qml
TestCase {
    id: testCase
    name: "DockTooltipAnchor"
    when: windowShown
    width: 400
    height: 200

    Item {
        id: host
        width: 400
        height: 200

        Item {
            id: anchorItem
            x: 40
            y: 60
            width: 48
            height: 48
        }
    }

    Component {
        id: tooltipComponent
        DockTooltip {
            parentItem: anchorItem
            text: "Firefox"
            dockPosition: "bottom"
        }
    }

    function test_hidden_tooltip_never_maps_its_parent() {
        const tip = createTemporaryObject(tooltipComponent, testCase)
        verify(tip)
        compare(tip.showTooltip, false)
        compare(tip.anchor.rect.x, 0)
        compare(tip.anchor.rect.y, 0)

        // The icon moving under a hidden tooltip must not compute anything.
        anchorItem.x = 100
        compare(tip.anchor.rect.x, 0)
        anchorItem.x = 40
    }

    function test_shown_tooltip_sits_above_the_icon_and_follows_it() {
        const tip = createTemporaryObject(tooltipComponent, testCase)
        verify(tip)
        tip.showTooltip = true
        // The hover intent is gated by a 70 ms dwell; tryCompare waits it
        // out instead of pinning the exact timer.
        tryCompare(tip, "tooltipShown", true)

        // Above the icon, centred on it.
        compare(tip.anchor.rect.y, 60 - tip.height - 8)
        compare(tip.anchor.rect.x, 40 + 48 / 2 - tip.width / 2)

        // Magnifying the icon (scale around its centre) lifts its top edge, and
        // the tooltip has to follow that instead of staying where it first
        // mapped.
        anchorItem.scale = 1.5
        wait(1)
        compare(tip.anchor.rect.y, 60 - 12 - tip.height - 8)
        cancelMagnification()

        // Reflowing the dock moves the icon sideways.
        anchorItem.x = 120
        wait(1)
        compare(tip.anchor.rect.x, 120 + 48 / 2 - tip.width / 2)
    }

    function test_hiding_drops_the_anchor() {
        const tip = createTemporaryObject(tooltipComponent, testCase)
        verify(tip)
        tip.showTooltip = true
        tryCompare(tip, "tooltipShown", true)
        verify(tip.anchor.rect.x !== 0)

        tip.showTooltip = false
        compare(tip.tooltipShown, false)
        // The window keeps tracking while it fades out, then drops.
        tryCompare(tip, "visible", false)
        compare(tip.anchor.rect.x, 0)
        compare(tip.anchor.rect.y, 0)
    }

    function cancelMagnification() {
        anchorItem.scale = 1
    }
}
