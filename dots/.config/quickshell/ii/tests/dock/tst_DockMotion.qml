import QtQuick
import QtTest
import "../../modules/ii/dock/widgets"

TestCase {
    id: testCase
    name: "DockMotion"
    when: windowShown
    width: 700
    height: 700

    StableDockModel { id: model }
    DockMotion { id: motion; duration: 120 }
    SignalSpy { id: settledSpy; target: motion; signalName: "settled" }
    QtObject { id: liveWindow; property string title: "First window" }

    property bool animate: false
    property real preview: 0
    Component {
        id: horizontalDelegate
        Item {
            id: slot
            required property string entryKey
            required property int index
            width: 80
            height: 80
            readonly property real visualPosition: position.position
            DockItemPosition {
                id: position
                layoutPosition: slot.x
                offset: slot.entryKey === "b" ? testCase.preview : 0
                animate: testCase.animate
            }
            transform: Translate { x: position.position - slot.x }
        }
    }
    Component {
        id: verticalDelegate
        Item {
            id: slot
            required property string entryKey
            required property int index
            width: 80
            height: 80
            readonly property real visualPosition: position.position
            DockItemPosition {
                id: position
                layoutPosition: slot.y
                offset: slot.entryKey === "b" ? testCase.preview : 0
                animate: testCase.animate
            }
            transform: Translate { y: position.position - slot.y }
        }
    }
    Row { Repeater { id: horizontal; model: model; delegate: horizontalDelegate } }
    Column { x: 500; Repeater { id: vertical; model: model; delegate: verticalDelegate } }

    function records(keys) {
        return keys.map(key => ({ orderKey: key, type: "app", appData: { toplevels: [liveWindow] } }));
    }
    function init() {
        model.keyFunction = null;
        animate = false;
        preview = 0;
        model.sourceValues = records(["a", "b", "c"]);
        motion.reset(0);
        settledSpy.clear();
        wait(30);
    }
    function test_identitySurvivesPayloadAndMoves() {
        const a = horizontal.itemAt(0);
        const b = horizontal.itemAt(1);
        const c = horizontal.itemAt(2);
        model.sourceValues = records(["c", "a", "b"]);
        compare(horizontal.itemAt(0), c);
        compare(horizontal.itemAt(1), a);
        compare(horizontal.itemAt(2), b);
        compare(model.itemsByKey.a.appData.toplevels[0], liveWindow);
        liveWindow.title = "Updated";
        compare(model.itemsByKey.a.appData.toplevels[0].title, "Updated");
    }
    function test_pinChangePreservesAppIdentity() {
        model.keyFunction = value => value.appId;
        model.sourceValues = [{orderKey: "runningApp:browser", type: "app", appId: "browser"}];
        const app = horizontal.itemAt(0);
        model.sourceValues = [{orderKey: "app:browser", type: "app", appId: "browser"}];
        compare(horizontal.itemAt(0), app);
        compare(model.itemsByKey.browser.orderKey, "app:browser");
    }
    function test_middleRemovalKeepsOtherDelegates() {
        const a = horizontal.itemAt(0);
        const c = horizontal.itemAt(2);
        model.sourceValues = records(["a", "c"]);
        compare(horizontal.itemAt(0), a);
        compare(horizontal.itemAt(1), c);
        compare(model.count, 2);
        verify(model.itemsByKey.b === undefined);
    }
    function test_commitDuringNeighbourMotion_data() {
        return [{ tag: "horizontal", vertical: false }, { tag: "vertical", vertical: true }];
    }
    function test_commitDuringNeighbourMotion(data) {
        const repeater = data.vertical ? vertical : horizontal;
        const b = repeater.itemAt(1);
        compare(b.visualPosition, 80);
        animate = true;
        preview = -80;
        wait(35);
        const interrupted = b.visualPosition;
        verify(interrupted > 0 && interrupted < 80);
        model.sourceValues = records(["b", "a", "c"]);
        preview = 0;
        compare(repeater.itemAt(0), b);
        verify(Math.abs(b.visualPosition - interrupted) < 1, "Commit must retain the currently rendered position");
        tryCompare(b, "visualPosition", 0);
    }
    function test_reverseMenuWithoutReset() {
        motion.animateTo(1);
        wait(45);
        const opening = motion.progress;
        verify(opening > 0 && opening < 1);
        motion.animateTo(0);
        compare(motion.progress, opening);
        wait(25);
        const closing = motion.progress;
        verify(closing < opening);
        motion.animateTo(1);
        compare(motion.progress, closing);
        tryCompare(motion, "progress", 1);
        compare(settledSpy.count, 1);
        compare(settledSpy.signalArguments[0][0], 1);
    }
    function test_contentSequenceReversesWithSurface() {
        motion.reset(0.45);
        verify(motion.phase(0) > motion.phase(3));
        verify(motion.phase(3) > motion.phase(6));
        motion.reset(1);
        compare(motion.phase(6), 1);
        motion.animateTo(0);
        tryCompare(motion, "progress", 0);
        compare(motion.phase(0), 0);
        compare(settledSpy.count, 1);
    }
    function test_directPointerAndSettle() {
        const item = createTemporaryObject(positionComponent, testCase);
        item.layoutPosition = 20;
        item.offset = 39.75;
        compare(item.position, 59.75);
        item.offset = 75.125;
        compare(item.position, 95.125);
        item.settling = true;
        item.tracking = false;
        item.layoutPosition = 80;
        item.offset = 15.125;
        compare(item.position, 95.125);
        item.offset = 0;
        compare(item.position, 80);
    }
    Component { id: positionComponent; DockItemPosition { animate: true; tracking: true } }
}
