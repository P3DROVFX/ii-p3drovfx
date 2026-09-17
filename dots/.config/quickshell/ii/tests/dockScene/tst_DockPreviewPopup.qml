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
    QtObject { id: toplevelFactory }
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

    function test_popupAppearsInstantlyDuringTraversal() {
        const popup = createTemporaryObject(popupComponent, testCase)
        verify(popup)

        // Fast pass-through: hover two apps for 80 ms each — below the 150 ms
        // capture arm interval in both cases.
        popup.appTopLevel = makeApp("browser")
        fakeDock.buttonHovered = true
        wait(80)
        // Popup shell is already visible; capture is NOT armed.
        compare(popup.show, true)
        compare(popup.captureArmed, false)

        popup.appTopLevel = makeApp("terminal")
        wait(80)
        compare(popup.show, true)
        compare(popup.captureArmed, false)
        compare(popup.displayedToplevels.length, 1)
        compare(popup.displayedToplevels[0].appId, "terminal")
    }

    function test_captureArmsAfterSettle() {
        const popup = createTemporaryObject(popupComponent, testCase)
        verify(popup)
        popup.appTopLevel = makeApp("browser")
        fakeDock.buttonHovered = true

        // Shell visible before the stream exists.
        wait(50)
        compare(popup.show, true)
        compare(popup.captureArmed, false)

        // Dwell past the interval arms the stream.
        wait(150)
        compare(popup.captureArmed, true)

        // Crossing to another app disarms until the pointer settles there.
        popup.appTopLevel = makeApp("terminal")
        compare(popup.captureArmed, false)
        wait(200)
        compare(popup.captureArmed, true)
    }

    function test_geometryFixedBeforeFirstFrame() {
        const popup = createTemporaryObject(popupComponent, testCase)
        verify(popup)
        popup.appTopLevel = makeApp("browser")
        fakeDock.buttonHovered = true
        wait(100)
        compare(popup.show, true)

        const slot = findChild(popup.popupBackground, item => item.objectName === "previewSlot")
        verify(slot)
        // Slot exists at the configured size even with no captured frame:
        // popup geometry never chases sourceSize.
        compare(slot.width, 300)
        compare(slot.height, 200)
        compare(popup.popupBackground.implicitWidth, 300 + 2 * popup.popupBackground.padding)
        verify(popup.popupBackground.implicitHeight > 200)
    }

    function test_blurLayerDisablesAtRest() {
        const popup = createTemporaryObject(popupComponent, testCase)
        verify(popup)
        popup.appTopLevel = makeApp("browser")
        fakeDock.buttonHovered = true
        wait(100)
        compare(popup.show, true)
        tryCompare(popup.popupBackground, "blurRadius", 0)
        compare(popup.popupBackground.layer.enabled, false)

        // Leaving closes; while the hide animation runs the layer is back on.
        popup.appTopLevel = null
        fakeDock.buttonHovered = false
        wait(200)
        compare(popup.popupBackground.layer.enabled, true)
        compare(popup.popupBackground.blurRadius, 16)
    }

    function test_captureUnarmsWhenPopupCloses() {
        const popup = createTemporaryObject(popupComponent, testCase)
        verify(popup)
        popup.appTopLevel = makeApp("browser")
        fakeDock.buttonHovered = true
        wait(200)
        compare(popup.captureArmed, true)

        popup.appTopLevel = null
        fakeDock.buttonHovered = false
        wait(200)
        compare(popup.show, false)
        tryCompare(popup, "visible", false)
        compare(popup.captureArmed, false)
    }
}
