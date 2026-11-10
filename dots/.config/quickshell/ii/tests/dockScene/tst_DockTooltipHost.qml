import QtQuick
import QtTest
import "dock/widgets"

// The dock's one tooltip (DockTooltipHost). Items ask for it through
// DockTooltip requests; the host slides a single bubble between them inside
// one resident surface instead of each item fading its own window in and out.
//
// Run with scripts/tests/run_dock_preview_popup_tests.py --test tests/dockScene/tst_DockTooltipHost.qml
TestCase {
    id: testCase
    name: "DockTooltipHost"
    when: windowShown
    width: 600
    height: 200

    Item {
        id: fakeWindow
        width: 600
        height: 120

        Item {
            id: fakeDock
            anchors.fill: parent
            property string dockPos: "bottom"
            Item { id: iconA; x: 40; y: 60; width: 48; height: 48 }
            Item { id: iconB; x: 300; y: 60; width: 48; height: 48 }
        }
    }

    Component {
        id: hostComponent
        DockTooltipHost {
            dockContent: fakeDock
            dockWindow: fakeWindow
        }
    }

    function spec(item, text) {
        return { parentItem: item, text: text };
    }

    function test_firstTooltipWaitsTheDwellThenAppears() {
        const host = createTemporaryObject(hostComponent, testCase);
        verify(host);
        host.requestShow(spec(iconA, "Files"));
        // Inside the dwell: nothing yet.
        compare(host.wanted, false);
        tryCompare(host, "wanted", true, 500);
        compare(host.label, "Files");
        tryCompare(host, "reveal", 1, 1000);
        tryCompare(host, "grow", 1, 1000);
        // It never takes a click.
        verify(host.mask !== null);
    }

    function test_movingToTheNextItemSlidesAndSwapsTheText() {
        const host = createTemporaryObject(hostComponent, testCase);
        const a = spec(iconA, "Files");
        host.requestShow(a);
        tryCompare(host, "reveal", 1, 1000);
        host.release(a);
        const b = spec(iconB, "Terminal");
        host.requestShow(b);
        // No dwell once one is up, no fade out: the same bubble travels.
        compare(host.wanted, true);
        compare(host.target, iconB);
        compare(host.label, "Terminal");
        compare(host.outgoing, "Files");
        // Same frame as the switch: the base is already B and the offset
        // puts the drawn bubble exactly where it was, over A — never the old
        // base plus the new offset (a flash an item-distance away).
        fuzzyCompare(host.pointMain, iconB.x + iconB.width / 2, 0.5);
        fuzzyCompare(host.pointMain + host.slideOffset, iconA.x + iconA.width / 2, 0.5);
        // Then it glides over to B.
        verify(host.slideOffset < 0);
        tryCompare(host, "slideOffset", 0, 1000);
        tryCompare(host, "outgoing", "", 1000);
        compare(host.reveal, 1);
    }

    function test_leavingHidesAfterTheGrace() {
        const host = createTemporaryObject(hostComponent, testCase);
        const a = spec(iconA, "Files");
        host.requestShow(a);
        tryCompare(host, "reveal", 1, 1000);
        host.release(a);
        // Within the grace the bubble is still up.
        wait(40);
        compare(host.wanted, true);
        tryCompare(host, "wanted", false, 500);
        tryCompare(host, "reveal", 0, 1000);
    }

    function test_textChangeWhileShownCrossesOver() {
        const host = createTemporaryObject(hostComponent, testCase);
        const a = spec(iconA, "Files");
        host.requestShow(a);
        tryCompare(host, "reveal", 1, 1000);
        a.text = "Files · 3 new";
        host.updateText(a);
        compare(host.label, "Files · 3 new");
        compare(host.outgoing, "Files");
        tryCompare(host, "outgoing", "", 1000);
    }

    // Switching again mid-slide continues from where the bubble is drawn.
    function test_retargetMidSlideStartsFromTheDrawnPosition() {
        const host = createTemporaryObject(hostComponent, testCase);
        const a = spec(iconA, "Files");
        host.requestShow(a);
        tryCompare(host, "reveal", 1, 1000);
        host.release(a);
        const b = spec(iconB, "Terminal");
        host.requestShow(b);
        wait(10);
        const drawn = host.pointMain + host.slideOffset;
        host.release(b);
        host.requestShow(a);
        fuzzyCompare(host.pointMain + host.slideOffset, drawn, 2);
        tryCompare(host, "slideOffset", 0, 1000);
    }
}
