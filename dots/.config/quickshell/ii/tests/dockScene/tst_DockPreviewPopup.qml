import QtQuick
import QtTest
import "dock/widgets"
import qs.services

TestCase {
    id: testCase
    name: "DockPreviewPopup"
    when: windowShown
    visible: true
    width: 900
    height: 700

    // Stand-in for the dock: only the surface the popup reads.
    QtObject {
        id: fakeDock
        property string dockPos: "bottom"
        property bool isVertical: false
        property bool buttonHovered: false
        property bool anyContextMenuOpen: false
        property bool dragging: false
        property bool popupIsResizing: false
        property var lastHoveredButton: null
        property point hoveredButtonCenter: Qt.point(450, 660)
        property real maxWindowPreviewWidth: 300
        property real maxWindowPreviewHeight: 200
        property real windowControlsHeight: 30
        property real magCrossExtra: 0
        function _getSlotMagScale() { return 1.0 }
    }

    Component {
        id: popupComponent
        DockPreviewPopup {
            dockRoot: fakeDock
            dockWindow: testCase
            appTopLevel: null
        }
    }

    // Fake window identity with a unique object identity per instance.
    Component {
        id: toplevelFactory
        QtObject { property string appId: "" }
    }
    function makeToplevel(appId) {
        return toplevelFactory.createObject(testCase, { appId: appId })
    }

    function addToplevel(toplevel) {
        const values = ToplevelManager.toplevels.values.slice()
        values.push(toplevel)
        ToplevelManager.toplevels.values = values
    }

    function clearToplevels() {
        ToplevelManager.toplevels.values = []
    }

    function init() {
        clearToplevels()
        fakeDock.buttonHovered = false
        fakeDock.anyContextMenuOpen = false
        fakeDock.dragging = false
    }

    function cleanup() {
        clearToplevels()
    }

    function findChild(item, predicate) {
        if (predicate(item))
            return item
        for (let child of item.children ?? []) {
            const found = findChild(child, predicate)
            if (found)
                return found
        }
        return null
    }

    function makeApp(appId) {
        const app = { appId: appId, toplevels: [makeToplevel(appId)] }
        app.toplevels.forEach(addToplevel)
        return app
    }

    // A sweep does not open the popup and does not build the row: the open
    // dwell (70 ms) keeps the surface unmapped while the cursor crosses, and
    // a closed popup never adopts a target (no row, no capture). Resting on
    // one icon opens the popup, which then adopts that icon's app; crossing
    // further swaps the row only after its own dwell confirms the new target.
    function test_sweepDoesNotOpenRestingHoverDoes() {
        const popup = createTemporaryObject(popupComponent, testCase)
        verify(popup)
        const browser = makeApp("browser")
        popup.appTopLevel = browser
        fakeDock.buttonHovered = true
        // 40 ms: inside the open dwell — nothing mapped, nothing built.
        wait(40)
        compare(popup.show, false)
        compare(popup.visible, false)
        compare(popup.displayedApp, null)

        // Rest long enough and the popup opens with the hovered app.
        wait(200)
        compare(popup.show, true)
        compare(popup.visible, true)
        compare(popup.displayedApp, browser)

        // Crossing to another app holds the row until the dwell confirms.
        const terminal = makeApp("terminal")
        popup.appTopLevel = terminal
        // 60 ms: still inside the 80 ms commit dwell, so the row holds the
        // previous app — but only for the time it takes to cross, not to rest.
        wait(60)
        compare(popup.displayedApp, browser)
        // Commit lands at ~130 ms (dwell + dip) and the rise is done by 200.
        wait(400)
        compare(popup.displayedApp, terminal)
        compare(popup.swapOpacity, 1)
    }

    // Crossing further before the open dwell expires restarts it: a pass over
    // three icons opens once, on the one the cursor rested on.
    function test_repeatedCrossingRestartsTheDwell() {
        const popup = createTemporaryObject(popupComponent, testCase)
        verify(popup)
        const browser = makeApp("browser")
        popup.appTopLevel = browser
        fakeDock.buttonHovered = true
        wait(200)
        compare(popup.displayedApp, browser)

        for (const name of ["terminal", "files"]) {
            popup.appTopLevel = makeApp(name)
            // 60 ms between crosses — under the 80 ms dwell each time.
            wait(60)
            compare(popup.displayedApp, browser)
        }
        wait(400)
        compare(popup.displayedApp?.appId, "files")
    }

    function test_geometryFixedBeforeFirstFrame() {
        const popup = createTemporaryObject(popupComponent, testCase)
        verify(popup)
        popup.appTopLevel = makeApp("browser")
        fakeDock.buttonHovered = true
        // Past the 70 ms open dwell the popup is mapped.
        wait(250)
        compare(popup.show, true)

        const background = findChild(popup, item => item.objectName === "popupBackground")
        verify(background)
        const slot = findChild(background, item => item.objectName === "previewSlot")
        verify(slot)
        // Slot exists at the configured size even with no captured frame:
        // popup geometry never chases sourceSize.
        compare(slot.width, 300)
        compare(slot.height, 200)
        compare(background.implicitWidth, 300 + 2 * background.padding)
        verify(background.implicitHeight > 200)
    }

    function test_blurLayerDisablesAtRest() {
        const popup = createTemporaryObject(popupComponent, testCase)
        verify(popup)
        popup.appTopLevel = makeApp("browser")
        fakeDock.buttonHovered = true
        // Past the open dwell: mapped, and the blur only lives in the
        // transition.
        wait(200)
        compare(popup.show, true)
        const background = findChild(popup, item => item.objectName === "popupBackground")
        verify(background)
        tryCompare(background, "blurRadius", 0)
        compare(background.layer.enabled, false)

        // Leaving closes; while the hide animation runs the layer is back on.
        popup.appTopLevel = null
        fakeDock.buttonHovered = false
        // Hide dwell (150 ms) + hide fade (40 ms): the blur is fully back.
        wait(400)
        tryCompare(background, "blurRadius", 16)
        compare(background.layer.enabled, true)
    }

    // A closed popup is inert: it does not adopt the hovered app, so a sweep
    // across icons while it is hidden builds no row and arms no capture. It
    // adopts the moment the open dwell finishes (onShowChanged).
    function test_closedPopupStaysInert() {
        const popup = createTemporaryObject(popupComponent, testCase)
        verify(popup)
        const browser = makeApp("browser")
        popup.appTopLevel = browser
        compare(popup.displayedApp, null)
        compare(popup.show, false)
        // No crossfade to stop, nothing pending — the swap state is pristine.
        compare(popup.swapOpacity, 1)
    }
}
