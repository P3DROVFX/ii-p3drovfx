import QtQuick
import QtTest
import "dock"

TestCase {
    id: testCase
    name: "DockWidgetStack"
    when: windowShown
    visible: true
    width: 600
    height: 200

    QtObject {
        id: fakeDock
        property real dotMargin: 9
        property real dotMarginV: 9
        property bool dockWidgetsActive: true
        property bool dockRevealed: true
        property bool dockWindowVisible: true
        property int magnificationTransformOrigin: Item.Bottom
        function _getSlotMagScale(item) { return 1.0; }
    }

    Component {
        id: stackComponent
        DockWidgetStack {
            width: 200
            height: 66
            dockContent: fakeDock
            members: ["weather", "tasks", "media"]
            onCurrentTypeRequested: type => currentType = type
        }
    }

    function loadedPages(stack) {
        const pages = [];
        function walk(item) {
            if (item.objectName && item.objectName.startsWith("Dock"))
                pages.push(item.objectName);
            for (const child of item.children ?? [])
                walk(child);
        }
        walk(stack);
        return pages;
    }

    // At rest only the page on show exists: a stack of three widgets costs
    // one widget.
    function test_onlyThePageOnShowIsLoaded() {
        const stack = createTemporaryObject(stackComponent, testCase);
        verify(stack);
        compare(stack.shownType, "weather");
        compare(loadedPages(stack), ["DockWeatherWidget"]);
    }

    // A turn slides the next page in; while it slides both pages exist, and
    // once it ends the page that left is unloaded.
    function test_turnSlidesAndUnloadsTheLeavingPage() {
        const stack = createTemporaryObject(stackComponent, testCase);
        verify(stack.turn(1));
        compare(stack.currentType, "tasks");
        verify(stack.sliding);
        compare(stack.slideDirection, 1);
        compare(loadedPages(stack).sort(), ["DockTasksWidget", "DockWeatherWidget"]);
        // Nothing turns while a slide is running.
        verify(!stack.turn(1));
        tryCompare(stack, "sliding", false);
        compare(loadedPages(stack), ["DockTasksWidget"]);
        compare(stack.slideProgress, 0);
    }

    // Turning back from the first page wraps to the last, sliding downward.
    function test_turnBackWraps() {
        const stack = createTemporaryObject(stackComponent, testCase);
        verify(stack.turn(-1));
        compare(stack.currentType, "media");
        compare(stack.slideDirection, -1);
        tryCompare(stack, "sliding", false);
        compare(loadedPages(stack), ["DockMediaWidget"]);
    }

    // Touchpad deltas add up to one notch before a page turns.
    function test_wheelNeedsAFullNotch() {
        const stack = createTemporaryObject(stackComponent, testCase);
        const center = stack.mapToItem(testCase, stack.width / 2, stack.height / 2);
        mouseWheel(testCase, center.x, center.y, 0, -40);
        mouseWheel(testCase, center.x, center.y, 0, -40);
        compare(stack.currentType, "");
        mouseWheel(testCase, center.x, center.y, 0, -40);
        compare(stack.currentType, "tasks");
    }

    // A member leaving the stack while it is on show hands the slot to the
    // first remaining member.
    function test_memberLeavingFallsBack() {
        const stack = createTemporaryObject(stackComponent, testCase);
        stack.turn(1);
        tryCompare(stack, "sliding", false);
        stack.members = ["weather", "media"];
        compare(stack.shownType, "weather");
        tryCompare(stack, "sliding", false);
        compare(loadedPages(stack), ["DockWeatherWidget"]);
    }

    // A single member shows no indicator and takes no wheel.
    function test_singleMemberIsStatic() {
        const stack = createTemporaryObject(stackComponent, testCase, { members: ["tasks"] });
        compare(stack.pageCount, 1);
        verify(!stack.turn(1));
        compare(loadedPages(stack), ["DockTasksWidget"]);
    }
}
